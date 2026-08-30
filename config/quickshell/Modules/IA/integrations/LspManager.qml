import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "../TextUtils.js" as TU

// LSP: lo que sabe el IDE, lo sabe el agente.
//
// Un pool de servidores de lenguaje vivos, uno por lenguaje y raíz de proyecto,
// hablando LSP a través de un puente de framing que traduce las cabeceras
// Content-Length a líneas NDJSON, que es lo que SplitParser sabe trocear. Antes de
// cada operación el archivo se reabre desde disco, así que el agente siempre
// pregunta sobre lo que hay ahora: editar y pedir diagnósticos a continuación
// funciona.
//
// Expone una sola operación `request({op, path, line, col, ...}, cb)` con ops de
// lectura y el rename, que es escritura y aplica un WorkspaceEdit con copias
// previas, en el puente y con la misma jaula de $HOME.
//
// Los servidores se autodetectan al arrancar: si falta el de un lenguaje, la
// respuesta es el paquete que hay que instalar y no un fallo mudo.
Scope {
    id: lsp

    property var svc
    // Dónde dejar las copias previas de un rename; lo pone el orquestador con la
    // misma carpeta de deshacer del ejecutor.
    property string backupDir: ""

    // Por lenguaje: candidatos en orden de preferencia —el primero instalado gana—
    // y el paquete que lo trae, para poder decirlo.
    readonly property var registry: ({
        qml:    { cands: [["/usr/lib/qt6/bin/qmlls"], ["qmlls"]],
                  pkg: "qt6-declarative (trae qmlls)" },
        python: { cands: [["basedpyright-langserver", "--stdio"],
                          ["pyright-langserver", "--stdio"], ["pylsp"]],
                  pkg: "pyright o python-lsp-server" },
        ts:     { cands: [["typescript-language-server", "--stdio"]],
                  pkg: "typescript-language-server" },
        c:      { cands: [["clangd"]], pkg: "clang" },
        rust:   { cands: [["rust-analyzer"]], pkg: "rust-analyzer" },
        go:     { cands: [["gopls"]], pkg: "gopls" },
        bash:   { cands: [["bash-language-server", "start"]],
                  pkg: "bash-language-server" },
        lua:    { cands: [["lua-language-server"]], pkg: "lua-language-server" }
    })
    readonly property var extMap: ({
        ".qml": "qml", ".py": "python",
        ".ts": "ts", ".tsx": "ts", ".js": "ts", ".jsx": "ts", ".mjs": "ts",
        ".c": "c", ".h": "c", ".cpp": "c", ".hpp": "c", ".cc": "c",
        ".rs": "rust", ".go": "go", ".sh": "bash", ".bash": "bash",
        ".lua": "lua"
    })

    // Autodetección
    property var available: ({})       // binario → true
    property bool detected: false
    property var _bootQueue: []        // peticiones llegadas antes de detectar

    Process {
        running: true
        command: ["sh", "-c",
            'for b in /usr/lib/qt6/bin/qmlls qmlls basedpyright-langserver '
            + 'pyright-langserver pylsp typescript-language-server clangd '
            + 'rust-analyzer gopls bash-language-server lua-language-server; do '
            + 'command -v "$b" >/dev/null 2>&1 && echo "$b"; done']
        stdout: StdioCollector { id: detOut }
        onExited: {
            const m = {}
            for (const b of (detOut.text || "").split("\n"))
                if (b.trim() !== "")
                    m[b.trim()] = true
            lsp.available = m
            lsp.detected = true
            const q = lsp._bootQueue
            lsp._bootQueue = []
            for (const f of q)
                f()
        }
    }

    // El servidor de un lenguaje, ya elegido; null si no hay ninguno instalado.
    function _serverFor(lang) {
        const r = registry[lang]
        if (!r)
            return null
        for (const cand of r.cands)
            if (available[cand[0]])
                return cand
        return null
    }

    // clave (lang|raíz) → { proc, ready, seq, pending, waitReady, diag,
    //                       diagWait, lastUse }
    property var _pool: ({})
    property var _roots: ({})           // carpeta → raíz de proyecto (caché)

    readonly property Component _srvComp: Component {
        Process {
            id: srv
            property string poolKey: ""
            property string lang: ""
            property string root: ""
            property bool ready: false
            property int seq: 0
            property var pending: ({})     // id → {cb, deadline}
            property var waitReady: []     // callbacks esperando el initialize
            property var diag: ({})        // path → diagnósticos ya publicados
            property var diagWait: ({})    // path → {cb, deadline}
            property double lastUse: Date.now()
            // El open y el apply van de uno en uno por servidor: su respuesta llega
            // a un solo hueco, sin id que la case, así que varias peticiones en
            // paralelo se pisarían. Se encolan y se sirven en fila.
            property var openWait: null
            property var applyWait: null
            // Quien espera el resultado de un comando del servidor: si sus cambios
            // llegan por workspace/applyEdit, se le contesta ahí.
            property var pendingApplyCb: null
            property var queue: []         // [{path, args, cb}] esperando turno
            property bool draining: false

            stdinEnabled: true

            function rpc(method, params, cb, timeoutMs) {
                const id = ++seq
                pending[id] = { cb: cb,
                                deadline: Date.now() + (timeoutMs || 10000) }
                srv.write(JSON.stringify({ jsonrpc: "2.0", id: id,
                                           method: method, params: params }) + "\n")
            }
            function notify(method, params) {
                srv.write(JSON.stringify({ jsonrpc: "2.0", method: method,
                                           params: params }) + "\n")
            }
            function send(obj) { srv.write(JSON.stringify(obj) + "\n") }

            stdout: SplitParser {
                onRead: (line) => {
                    const l = line.trim()
                    if (l === "" || l[0] !== "{")
                        return
                    let j = null
                    try { j = JSON.parse(l) } catch (e) { return }
                    lsp._onMessage(srv, j)
                }
            }
            stderr: SplitParser { onRead: () => {} }
            onExited: lsp._dropServer(srv.poolKey)
        }
    }

    function _dropServer(key) {
        const s = _pool[key]
        if (!s)
            return
        const p = Object.assign({}, _pool)
        delete p[key]
        _pool = p
        // Lo que esperaba a este servidor no puede quedarse colgado.
        for (const id in s.pending)
            s.pending[id].cb(null, "el servidor LSP terminó")
        for (const f of s.waitReady)
            f(null)
        s.destroy()
    }

    function _onMessage(srv, j) {
        // Respuesta a una petición nuestra.
        if (j.id !== undefined && srv.pending[j.id]) {
            const cb = srv.pending[j.id].cb
            delete srv.pending[j.id]
            cb(j.result !== undefined ? j.result : null,
               j.error ? (j.error.message || JSON.stringify(j.error)) : "")
            return
        }
        // Diagnósticos publicados: se guardan y se despierta a quien esperara.
        if (j.method === "textDocument/publishDiagnostics") {
            const path = decodeURIComponent(
                String(j.params.uri || "").replace(/^file:\/\//, ""))
            srv.diag[path] = j.params.diagnostics || []
            const w = srv.diagWait[path]
            if (w) {
                delete srv.diagWait[path]
                w.cb(srv.diag[path], "")
            }
            return
        }
        // Peticiones del servidor que piden respuesta (configuración,
        // capacidades dinámicas): se contestan con lo mínimo para que no se
        // quede esperando.
        if (j.id !== undefined && j.method === "workspace/configuration") {
            srv.send({ jsonrpc: "2.0", id: j.id,
                       result: (j.params.items || []).map(() => null) })
            return
        }
        if (j.id !== undefined && j.method === "client/registerCapability") {
            srv.send({ jsonrpc: "2.0", id: j.id, result: null })
            return
        }
        // El servidor pide aplicar cambios él (lo hacen los comandos de code
        // action). Se aplican por el puente —con copias y jaula, como todo— y
        // se le contesta que sí.
        if (j.id !== undefined && j.method === "workspace/applyEdit") {
            const cb = srv.pendingApplyCb
            srv.pendingApplyCb = null
            srv.applyWait = (ap) => {
                if (!cb)
                    return
                let out = "Aplicado por el servidor:"
                for (const f of (ap.files || []))
                    out += "\n- " + f.path + " (" + f.edits + " ediciones)"
                if ((ap.backups || []).length > 0)
                    out += "\nCopias previas en: " + ap.backups.join(", ")
                for (const e of (ap.errors || []))
                    out += "\n[no aplicado] " + e
                cb(out)
            }
            srv.send({ _qs: "apply_edit",
                       edit: (j.params && j.params.edit) || ({}),
                       backupDir: lsp.backupDir })
            srv.send({ jsonrpc: "2.0", id: j.id, result: { applied: true } })
            return
        }
        if (j._qs === "opened" && srv.openWait) {
            const f = srv.openWait
            srv.openWait = null
            f(j)
            return
        }
        if (j._qs === "applied" && srv.applyWait) {
            const f = srv.applyWait
            srv.applyWait = null
            f(j)
        }
    }

    // Barrido de tiempos: peticiones sin respuesta y esperas de diagnósticos
    // caducan con mensaje; servidores sin uso en 10 minutos se apagan.
    Timer {
        interval: 2000
        running: Object.keys(lsp._pool).length > 0
        repeat: true
        onTriggered: {
            const now = Date.now()
            for (const key in lsp._pool) {
                const s = lsp._pool[key]
                for (const id in s.pending)
                    if (now > s.pending[id].deadline) {
                        const cb = s.pending[id].cb
                        delete s.pending[id]
                        cb(null, "el servidor no contestó a tiempo")
                    }
                for (const path in s.diagWait)
                    if (now > s.diagWait[path].deadline) {
                        // Silencio también es respuesta: sin quejas publicadas.
                        const cb = s.diagWait[path].cb
                        delete s.diagWait[path]
                        cb(s.diag[path] || [], "")
                    }
                if (now - s.lastUse > 600000
                        && Object.keys(s.pending).length === 0)
                    _dropServer(key)
            }
        }
    }

    // Arranque de un servidor
    function _ensure(lang, root, cb) {
        const key = lang + "|" + root
        const got = _pool[key]
        if (got) {
            got.lastUse = Date.now()
            if (got.ready)
                cb(got)
            else
                got.waitReady.push(cb)
            return
        }
        const cand = _serverFor(lang)
        const argv = ["python3", svc.iaDir + "/bin/jsonrpc-bridge.py",
                      "stdio", "--"].concat(cand)
        // qmlls necesita saber dónde está el proyecto para resolver imports.
        if (cand[0].indexOf("qmlls") !== -1)
            argv.push("-b", root)
        const s = _srvComp.createObject(lsp, {
            poolKey: key, lang: lang, root: root, command: argv })
        const p = Object.assign({}, _pool)
        p[key] = s
        _pool = p
        s.waitReady.push(cb)
        s.running = true
        const rootUri = "file://" + root
        s.rpc("initialize", {
            processId: null,
            rootUri: rootUri,
            workspaceFolders: [{ uri: rootUri, name: root.split("/").pop() }],
            capabilities: {
                textDocument: {
                    publishDiagnostics: {}, hover: {}, definition: {},
                    references: {}, documentSymbol: {}, rename: {},
                    // Los arreglos rápidos: se anuncia que entendemos las
                    // acciones como objeto (no solo como comando) y que
                    // sabemos resolverlas en dos pasos, que es como las
                    // sirven los servidores modernos.
                    codeAction: {
                        codeActionLiteralSupport: { codeActionKind: {
                            valueSet: ["quickfix", "refactor", "source",
                                       "source.organizeImports"] } },
                        resolveSupport: { properties: ["edit"] }
                    }
                },
                workspace: { applyEdit: true, workspaceEdit: {
                    documentChanges: true } }
            }
        }, (res, err) => {
            if (err !== "") {
                lsp._dropServer(key)
                return
            }
            s.notify("initialized", {})
            s.ready = true
            const q = s.waitReady
            s.waitReady = []
            for (const f of q)
                f(s)
        }, 20000)
    }

    // request({op, path, line, col, name, new_name}, cb) — cb(textoResultado).
    // line y col llegan en base 1 (como los enseña read_file); LSP cuenta en
    // base 0 y la traducción vive solo aquí.
    function request(args, cb) {
        if (!detected) {
            _bootQueue.push(() => request(args, cb))
            return
        }
        const path = svc._safePath(args.path)
        if (path === "") {
            cb("Ruta fuera de la carpeta personal.")
            return
        }
        const dot = path.lastIndexOf(".")
        const lang = extMap[dot >= 0 ? path.slice(dot).toLowerCase() : ""]
        if (!lang) {
            cb("No hay servidor LSP asociado a esta extensión. Cubiertas: "
               + Object.keys(extMap).join(" "))
            return
        }
        if (!_serverFor(lang)) {
            cb("Falta el servidor LSP de " + lang + ". Instálalo: pacman -S "
               + registry[lang].pkg)
            return
        }
        const dir = path.slice(0, path.lastIndexOf("/"))
        if (_roots[dir]) {
            _go(lang, _roots[dir], path, args, cb)
            return
        }
        // Raíz del proyecto: la del repo git si lo hay, la carpeta si no. Las
        // búsquedas se ENCOLAN (un solo rootProc): cuatro peticiones a la vez
        // en un proyecto sin resolver se pisarían el onDone del proceso.
        _rootQueue.push({ dir: dir, lang: lang, path: path, args: args, cb: cb })
        _drainRoots()
    }

    property var _rootQueue: []
    property bool _rootBusy: false
    function _drainRoots() {
        if (_rootBusy || _rootQueue.length === 0)
            return
        // Si mientras esperaba turno otra búsqueda ya resolvió esta carpeta,
        // se salta el proceso y se sirve directa.
        const job = _rootQueue[0]
        if (_roots[job.dir]) {
            _rootQueue.shift()
            _go(job.lang, _roots[job.dir], job.path, job.args, job.cb)
            Qt.callLater(_drainRoots)
            return
        }
        _rootBusy = true
        rootProc.dir = job.dir
        rootProc.running = true
    }
    Process {
        id: rootProc
        property string dir: ""
        command: ["sh", "-c", 'cd "$QS_D" 2>/dev/null && '
                  + '{ git rev-parse --show-toplevel 2>/dev/null || pwd; }']
        environment: ({ QS_D: dir })
        stdout: StdioCollector { id: rootOut }
        onExited: {
            const job = lsp._rootQueue.shift()
            const root = (rootOut.text || "").trim() || rootProc.dir
            const m = Object.assign({}, lsp._roots)
            m[rootProc.dir] = root
            lsp._roots = m
            lsp._rootBusy = false
            if (job)
                lsp._go(job.lang, root, job.path, job.args, job.cb)
            Qt.callLater(lsp._drainRoots)
        }
    }

    function _go(lang, root, path, args, cb) {
        _ensure(lang, root, (s) => {
            if (!s) {
                cb("El servidor LSP de " + lang + " no arrancó.")
                return
            }
            s.lastUse = Date.now()
            s.queue.push({ path: path, args: args, cb: cb })
            _drain(s)
        })
    }

    // Sirve la cola del servidor DE UNA EN UNA: abrir (fresco desde disco) →
    // operar → soltar el turno. Serializar el open es lo que evita que dos
    // aperturas en paralelo se pisen el único hueco de respuesta del puente.
    function _drain(s) {
        if (s.draining || s.queue.length === 0)
            return
        s.draining = true
        const job = s.queue.shift()
        const soltar = (texto) => {
            job.cb(texto)
            s.draining = false
            Qt.callLater(() => lsp._drain(s))
        }
        s.openWait = (j) => {
            if (!j.ok) {
                soltar("No se pudo abrir " + job.path + ": " + (j.error || ""))
                return
            }
            lsp._dispatch(s, job.path, job.args, soltar)
        }
        s.send({ _qs: "open", path: job.path })
    }

    function _dispatch(s, path, args, cb) {
        const uri = "file://" + path
        const doc = { textDocument: { uri: uri } }
        const pos = { line: Math.max(0, (parseInt(args.line) || 1) - 1),
                      character: Math.max(0, (parseInt(args.col) || 1) - 1) }
        switch (String(args.op || "diagnostics")) {
        case "diagnostics":
            // El servidor publica cuando termina de analizar: se espera a la
            // publicación de ESTE archivo (el didOpen fresco la provoca).
            delete s.diag[path]
            s.diagWait[path] = { deadline: Date.now() + 8000,
                cb: (diags) => cb(lsp._fmtDiags(path, diags)) }
            return
        case "hover":
            s.rpc("textDocument/hover", Object.assign({ position: pos }, doc),
                (res, err) => cb(err !== "" ? "Error LSP: " + err
                                            : lsp._fmtHover(res)))
            return
        case "definition":
            s.rpc("textDocument/definition", Object.assign({ position: pos }, doc),
                (res, err) => cb(err !== "" ? "Error LSP: " + err
                                            : lsp._fmtLocs(res, "definición")))
            return
        case "references":
            s.rpc("textDocument/references", Object.assign({
                position: pos, context: { includeDeclaration: true } }, doc),
                (res, err) => cb(err !== "" ? "Error LSP: " + err
                                            : lsp._fmtLocs(res, "referencia")))
            return
        case "symbols":
            s.rpc("textDocument/documentSymbol", doc,
                (res, err) => cb(err !== "" ? "Error LSP: " + err
                                            : lsp._fmtSymbols(res)))
            return
        case "actions":
        case "fix": {
            // Los diagnósticos de ESA línea son el contexto que hace que el
            // servidor ofrezca el arreglo: sin ellos, un quickfix casi nunca
            // aparece. Se usan los ya publicados para este archivo.
            const linea = pos.line
            const enLinea = (s.diag[path] || []).filter(d => {
                const r = d.range
                return r && r.start.line <= linea && r.end.line >= linea
            })
            // Rango: el que pida la llamada, o la línea entera — más generoso
            // que un punto, que es lo que quiere quien pide "arréglame esto".
            const rango = { start: { line: linea, character: 0 },
                            end: { line: linea, character: 4000 } }
            s.rpc("textDocument/codeAction", Object.assign({
                range: rango,
                context: { diagnostics: enLinea,
                           only: args.kind ? [String(args.kind)] : undefined }
            }, doc), (res, err) => {
                if (err !== "") { cb("Error LSP: " + err); return }
                const acciones = (res || []).filter(a => a)
                if (acciones.length === 0) {
                    cb("El servidor no ofrece ningún arreglo en "
                       + path.split("/").pop() + ":" + (linea + 1)
                       + (enLinea.length === 0
                          ? " (no hay diagnósticos en esa línea: pide antes op=diagnostics)"
                          : ""))
                    return
                }
                if (args.op === "actions") {
                    let out = acciones.length + " arreglos disponibles en L"
                            + (linea + 1) + " (aplica con lsp_fix index=N):"
                    for (let i = 0; i < acciones.length; i++) {
                        const a = acciones[i]
                        out += "\n  [" + i + "] " + (a.title || "(sin título)")
                             + (a.kind ? "   (" + a.kind + ")" : "")
                             + (a.isPreferred ? "  ← recomendado" : "")
                    }
                    cb(out)
                    return
                }
                const idx = parseInt(args.index) || 0
                const elegida = acciones[idx]
                if (!elegida) {
                    cb("No existe el arreglo " + idx + ": hay " + acciones.length
                       + " (0.." + (acciones.length - 1) + "). Mira lsp op=actions.")
                    return
                }
                lsp._applyAction(s, elegida, cb)
            }, 15000)
            return
        }
        case "raw": {
            const metodo = String(args.method || "").trim()
            if (metodo === "") { cb("Falta method."); return }
            let params = args.params
            if (typeof params === "string")
                params = TU.repairJson(params) || ({})
            if (!params || typeof params !== "object")
                params = ({})
            // Comodidad: si el método es de textDocument y no trae documento,
            // se le pone este (que ya está abierto y fresco).
            if (metodo.startsWith("textDocument/") && params.textDocument === undefined)
                params.textDocument = { uri: uri }
            s.rpc(metodo, params, (res, err) => {
                if (err !== "") { cb("Error LSP en " + metodo + ": " + err); return }
                const txt = JSON.stringify(res, null, 1)
                cb("Respuesta de " + metodo + ":\n"
                   + (txt === undefined ? "null" : txt.slice(0, 6000)))
            }, 20000)
            return
        }
        case "rename": {
            const nuevo = String(args.new_name || "").trim()
            if (nuevo === "") {
                cb("Falta new_name.")
                return
            }
            s.rpc("textDocument/rename", Object.assign({
                position: pos, newName: nuevo }, doc), (res, err) => {
                if (err !== "") { cb("Error LSP: " + err); return }
                if (!res || (!res.changes && !res.documentChanges)) {
                    cb("El servidor no propuso cambios (¿posición sin símbolo?).")
                    return
                }
                // El puente aplica el WorkspaceEdit con copia previa de cada
                // archivo y la jaula de $HOME.
                s.applyWait = (j) => {
                    let out = "Renombrado aplicado."
                    for (const f of (j.files || []))
                        out += "\n- " + f.path + " (" + f.edits + " ediciones)"
                    if ((j.backups || []).length > 0)
                        out += "\nCopias previas en: " + j.backups.join(", ")
                    for (const e of (j.errors || []))
                        out += "\n[no aplicado] " + e
                    cb(out)
                }
                s.send({ _qs: "apply_edit", edit: res,
                         backupDir: lsp.backupDir })
            }, 15000)
            return
        }
        }
        cb("op debe ser diagnostics, hover, definition, references, symbols, "
           + "actions, fix, raw o rename.")
    }

    // Aplicar un arreglo. Un servidor lo puede servir de tres formas y hay que
    // aguantar las tres: con su WorkspaceEdit dentro; como COMANDO que ejecuta
    // el servidor (y que puede devolver el edit por workspace/applyEdit); o
    // "perezoso", sin edit, esperando un codeAction/resolve que lo rellene.
    function _applyAction(s, accion, cb) {
        const titulo = accion.title || "(sin título)"
        const conEdit = (edit) => {
            s.applyWait = (j) => {
                let out = "Aplicado: " + titulo
                for (const f of (j.files || []))
                    out += "\n- " + f.path + " (" + f.edits + " ediciones)"
                if ((j.backups || []).length > 0)
                    out += "\nCopias previas en: " + j.backups.join(", ")
                for (const e of (j.errors || []))
                    out += "\n[no aplicado] " + e
                if ((j.files || []).length === 0 && (j.errors || []).length === 0)
                    out += "\n(el arreglo no tocó ningún archivo)"
                cb(out)
            }
            s.send({ _qs: "apply_edit", edit: edit, backupDir: lsp.backupDir })
        }
        if (accion.edit) {
            conEdit(accion.edit)
            return
        }
        if (accion.command) {
            // Un comando del servidor: sus cambios llegarán como una petición
            // workspace/applyEdit, que el pool ya sabe atender.
            const c = accion.command
            const cmd = typeof c === "string" ? { command: c } : c
            s.pendingApplyCb = cb
            s.rpc("workspace/executeCommand",
                { command: cmd.command, arguments: cmd.arguments || [] },
                (res, err) => {
                    if (s.pendingApplyCb) {
                        s.pendingApplyCb = null
                        cb(err !== "" ? "El comando del servidor falló: " + err
                                      : "Ejecutado: " + titulo
                                        + " (el servidor no devolvió cambios)")
                    }
                }, 20000)
            return
        }
        // Perezoso: se pide el cuerpo del arreglo y se reintenta.
        s.rpc("codeAction/resolve", accion, (res, err) => {
            if (err !== "") { cb("No se pudo resolver el arreglo: " + err); return }
            if (res && res.edit) {
                conEdit(res.edit)
                return
            }
            if (res && res.command) {
                lsp._applyAction(s, res, cb)
                return
            }
            cb("El servidor no devolvió cambios para «" + titulo + "».")
        }, 15000)
    }

    // Formato de las respuestas
    readonly property var _sev: ({ 1: "error", 2: "aviso", 3: "info", 4: "pista" })
    function _fmtDiags(path, diags) {
        if (!diags || diags.length === 0)
            return "Sin diagnósticos: el servidor no publica ninguna queja de " + path
        let out = diags.length + " diagnósticos de " + path + ":"
        for (const d of diags.slice(0, 40)) {
            const r = d.range && d.range.start
            out += "\n- L" + ((r ? r.line : 0) + 1) + ":C" + ((r ? r.character : 0) + 1)
                 + " [" + (_sev[d.severity] || "aviso") + "] "
                 + String(d.message || "").split("\n")[0].slice(0, 200)
        }
        if (diags.length > 40)
            out += "\n… y " + (diags.length - 40) + " más."
        return out
    }
    function _fmtHover(res) {
        if (!res || !res.contents)
            return "Sin información en esa posición."
        const c = res.contents
        const texto = typeof c === "string" ? c
                    : Array.isArray(c) ? c.map(x => typeof x === "string" ? x : x.value).join("\n")
                    : c.value || ""
        return texto.trim() === "" ? "Sin información en esa posición."
                                   : texto.slice(0, 3000)
    }
    function _fmtLocs(res, tipo) {
        let locs = res
        if (!locs)
            return "Sin resultados."
        if (!Array.isArray(locs))
            locs = [locs]
        if (locs.length === 0)
            return "Sin resultados."
        let out = locs.length + " " + tipo + (locs.length === 1 ? "" : "s") + ":"
        for (const l of locs.slice(0, 30)) {
            const uri = l.uri || l.targetUri || ""
            const r = l.range || l.targetSelectionRange || l.targetRange
            const path = decodeURIComponent(uri.replace(/^file:\/\//, ""))
            out += "\n- " + path + ":" + (r ? r.start.line + 1 : "?")
                 + ":" + (r ? r.start.character + 1 : "?")
        }
        return out
    }
    readonly property var _kinds: ({
        2: "módulo", 5: "clase", 6: "método", 7: "propiedad", 8: "campo",
        9: "constructor", 10: "enum", 11: "interfaz", 12: "función",
        13: "variable", 14: "constante", 23: "struct" })
    function _fmtSymbols(res) {
        if (!res || res.length === 0)
            return "Sin símbolos."
        let out = "Símbolos del documento:"
        let n = 0
        const walk = (list, sangria) => {
            for (const s of list) {
                if (n >= 80)
                    return
                n++
                const r = (s.selectionRange || s.range
                           || (s.location && s.location.range))
                out += "\n" + sangria + "- " + (_kinds[s.kind] || "símbolo")
                     + " " + s.name
                     + (r ? "  L" + (r.start.line + 1) : "")
                if (s.children && s.children.length > 0)
                    walk(s.children, sangria + "  ")
            }
        }
        walk(res, "")
        return out
    }

    // Estado para el panel o para depurar: qué servidores viven.
    readonly property var poolInfo: {
        const out = []
        for (const k in _pool)
            out.push(k + (_pool[k].ready ? "" : " (arrancando)"))
        return out
    }

    function shutdown() {
        for (const k in _pool)
            _dropServer(k)
    }
    Component.onDestruction: shutdown()
}
