import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// EJECUCIÓN PERSISTENTE (la celda de oh-my-pi): un Python que sigue VIVO entre
// llamadas. Definir una función en una celda y usarla tres turnos después
// funciona, cargar un CSV una vez y consultarlo veinte veces no cuesta veinte
// cargas.
//
// Y el cierre del círculo: dentro de la celda existe `tool(nombre, **args)`,
// que llama DE VUELTA a las herramientas del agente por un puente de ida y
// vuelta. El criterio de qué se puede llamar es exactamente el del subagente:
// la familia de SOLO LECTURA (leer, listar, buscar, consultas del sistema y de
// servidores, ast_search) más el lsp de lectura — puede ser autónomo justo
// porque nada de lo que alcanza cambia el equipo. La celda en sí es clase
// exec: la aprobó el usuario, con todo lo que eso significa.
//
// El kernel muere con el hilo (_resetThread) y por inactividad larga: el
// estado pertenece al encargo, no a la máquina.
Scope {
    id: repl

    property var svc
    property var lsp

    property bool alive: false
    property bool _booting: false
    property var _cellCb: null         // callback de la celda en curso
    property var _bootQueue: []        // celdas llegadas antes del ready
    property bool _fresh: true         // primer resultado tras arrancar
    property double _lastUse: 0

    readonly property Process _kernel: Process {
        id: kernel
        stdinEnabled: true
        command: ["python3", repl.svc ? repl.svc.iaDir + "/bin/repl-kernel.py" : ""]
        stdout: SplitParser {
            onRead: (line) => {
                const l = line.trim()
                if (l === "" || l[0] !== "{")
                    return
                let j = null
                try { j = JSON.parse(l) } catch (e) { return }
                repl._onMessage(j)
            }
        }
        stderr: SplitParser { onRead: () => {} }
        onExited: {
            repl.alive = false
            repl._booting = false
            if (repl._cellCb) {
                const cb = repl._cellCb
                repl._cellCb = null
                cb("El kernel de Python murió a mitad de la celda. Vuelve a "
                   + "ejecutarla: arrancará uno nuevo (sin el estado anterior).")
            }
        }
    }

    function _onMessage(j) {
        switch (j.t) {
        case "ready": {
            alive = true
            _booting = false
            prelude = j.prelude || []
            const q = _bootQueue
            _bootQueue = []
            for (const f of q)
                f()
            return
        }
        case "result": {
            const cb = _cellCb
            _cellCb = null
            if (cb)
                cb(_fmtResult(j))
            return
        }
        case "tool":
            _routeTool(j)
            return
        }
    }

    property var prelude: []           // helpers del preludio compartido

    function _fmtResult(r) {
        let out = ""
        if (_fresh) {
            _fresh = false
            out += "(kernel de Python recién arrancado; el estado empieza aquí. "
                 + "Preludio en proceso —sin fork/exec— con jaula $HOME: "
                 + "read/ls/grep/glob/find/stat/write, y tool(nombre,**args) "
                 + "para las herramientas del harness)\n"
        }
        if (r.out && r.out !== "")
            out += r.out
        if (r.value && r.value !== "")
            out += (out.endsWith("\n") || out === "" ? "" : "\n") + "⇒ " + r.value
        if (r.err && r.err.trim() !== "")
            out += (out === "" ? "" : "\n") + "[stderr]\n" + r.err
        if (out.trim() === "")
            out = r.ok ? "(celda ejecutada, sin salida)" : "(falló sin mensaje)"
        return out + "\n[" + (r.ok ? "ok" : "ERROR") + " · " + (r.ms || 0) + " ms"
               + " · el estado persiste para la siguiente celda]"
    }

    // ── La celda ─────────────────────────────────────────────────────────────
    // exec({code, reset, timeout}, cb). Una celda cada vez: el ejecutor ya
    // serializa las herramientas, esto solo lo defiende.
    function exec(args, cb) {
        if (_cellCb) {
            cb("Ya hay una celda ejecutándose; espera su resultado.")
            return
        }
        if (args.reset === true && alive) {
            kernel.running = false
            alive = false
        }
        const code = String(args.code || "")
        if (code.trim() === "") {
            cb("Celda vacía.")
            return
        }
        _lastUse = Date.now()
        const lanzar = () => {
            repl._cellCb = cb
            kernel.write(JSON.stringify({ t: "exec", code: code,
                timeout: Math.max(1, Math.min(120, parseInt(args.timeout) || 30))
            }) + "\n")
        }
        if (alive) {
            lanzar()
            return
        }
        _bootQueue.push(lanzar)
        if (!_booting) {
            _booting = true
            _fresh = true
            kernel.running = true
        }
    }

    // ── El puente de vuelta: tool() dentro de la celda ───────────────────────
    property var _toolReq: null        // la petición en curso (el kernel espera)

    function _routeTool(j) {
        const name = String(j.name || "")
        const args = j.args || ({})
        const responder = (texto) => {
            kernel.write(JSON.stringify({ t: "tool_result", id: j.id,
                result: repl.svc.redactSecrets(String(texto))
                        .slice(0, repl.svc.toolResultCap) }) + "\n")
        }
        // lsp de lectura: útil y sin efectos (rename queda fuera adrede).
        if (name === "lsp") {
            svc.auditRecord({ src: "cell", tool: "lsp",
                              args: JSON.stringify(args), decision: "auto" })
            if (String(args.op || "") === "rename") {
                responder("Desde la celda el lsp es de solo lectura: rename no.")
                return
            }
            lsp.request(args, responder)
            return
        }
        // El resto: la misma familia de solo lectura que hereda el subagente.
        // La celda ya la aprobó el usuario, pero lo que llame DESDE dentro no
        // pasa por ninguna tarjeta: al registro.
        svc.auditRecord({ src: "cell", tool: name,
                          args: JSON.stringify(args), decision: "auto" })
        const built = svc.readOnlyCommand(name, args)
        if (built === null) {
            responder("Desde la celda solo se pueden llamar herramientas de "
                + "solo lectura (read_file, read_files, list_dir, grep_files, "
                + "glob_files, fetch_url, ast_search, consultas del sistema y "
                + "de servidores, lsp). '" + name + "' no lo es.")
            return
        }
        if (built.error !== undefined) {
            responder(built.error)
            return
        }
        loopProc.onDone = responder
        loopProc.command = built.cmd
        loopProc.environment = built.env || ({})
        loopProc.running = true
    }

    Process {
        id: loopProc
        property var onDone: null
        stdout: StdioCollector { id: loopOut }
        stderr: StdioCollector { id: loopErr }
        onExited: (code) => {
            const f = loopProc.onDone
            loopProc.onDone = null
            if (!f)
                return
            let out = (loopOut.text || "")
            if ((loopErr.text || "").trim() !== "")
                out += (out !== "" ? "\n" : "") + "[stderr] " + loopErr.text
            f(out.trim() === "" ? "(sin salida; código " + code + ")" : out)
        }
    }

    // Sin uso en 15 minutos, el kernel se apaga solo: si el estado ya no le
    // importa a nadie, que no quede un Python cargado con quién sabe qué.
    Timer {
        interval: 60000
        running: repl.alive
        repeat: true
        onTriggered: {
            if (Date.now() - repl._lastUse > 900000 && !repl._cellCb)
                kernel.running = false
        }
    }

    function resetThread() {
        if (kernel.running)
            kernel.running = false
        _bootQueue = []
        _cellCb = null
    }
    Component.onDestruction: if (kernel.running) kernel.running = false
}
