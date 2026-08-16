import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "Debuggers.js" as DBG

// DEPURADOR: el agente habla DAP (Debug Adapter Protocol) con los adaptadores
// de verdad, a través del mismo puente de framing que el LSP. Una sesión cada
// vez, como el subagente: el estado de una depuración es demasiado delicado
// para llevar dos a medias.
//
// Qué adaptador para qué lenguaje sale del catálogo (Debuggers.js), no de aquí:
// trece adaptadores que cubren C, C++, Rust, Zig, Swift, Objective-C, Python,
// Go, JavaScript, TypeScript, C#, F#, Ruby, PHP, Kotlin, Dart, Elixir y Bash.
// Añadir un lenguaje es añadir una fila allí, incluida su detección y el "te
// falta esto, instálalo así".
//
// El reparto de herramientas sigue la clase de riesgo del harness:
//   debug_start   exec      arranca TU programa bajo el depurador
//   debug_ctl     external  continuar, pasos, puntos de ruptura, parar
//   debug_view    read      pila, variables, hilos, estado (no toca nada)
//   debug_eval    external  evalúa una expresión en el marco parado
//
// delve no habla DAP por stdio (solo TCP): el puente lo arranca y se conecta
// él, y aquí no se nota la diferencia.
Scope {
    id: dbg

    property var svc

    // ── Estado de la sesión ──────────────────────────────────────────────────
    property string state: "idle"      // idle|starting|running|stopped|exited
    property string adapterName: ""
    property string program: ""
    property int stoppedThread: 0
    property string stopReason: ""
    property string outputBuf: ""      // salida del programa, cola acotada
    property var lastStack: []         // último stackTrace (índice → frame)
    property var breakpoints: ({})     // path → [líneas]
    property int _seq: 0
    property var _pending: ({})        // seq → {cb, deadline}
    property var _stopWait: null       // {cb, deadline} esperando parada
    property int exitCode: -1

    // Detección: qué adaptadores hay. debugpy es un módulo, no un binario.
    property var available: ({})
    property bool detected: false
    Process {
        running: true
        command: ["sh", "-c", DBG.deteccion()]
        stdout: StdioCollector { id: ddet }
        onExited: {
            const m = {}
            for (const b of (ddet.text || "").split("\n"))
                if (b.trim() !== "")
                    m[b.trim()] = true
            dbg.available = m
            dbg.detected = true
        }
    }

    readonly property Process _proc: Process {
        id: proc
        stdinEnabled: true
        stdout: SplitParser {
            onRead: (line) => {
                const l = line.trim()
                if (l === "" || l[0] !== "{")
                    return
                let j = null
                try { j = JSON.parse(l) } catch (e) { return }
                dbg._onMessage(j)
            }
        }
        stderr: SplitParser { onRead: () => {} }
        onExited: {
            if (dbg.state !== "idle" && dbg.state !== "exited") {
                dbg.state = "exited"
                dbg._flushWaiters("el adaptador terminó")
            }
        }
    }

    function _send(obj) { proc.write(JSON.stringify(obj) + "\n") }

    function _request(command, args, cb, timeoutMs) {
        const id = ++_seq
        _pending[id] = { cb: cb || (() => {}),
                         deadline: Date.now() + (timeoutMs || 10000) }
        _send({ seq: id, type: "request", command: command,
                arguments: args || {} })
    }

    function _flushWaiters(motivo) {
        for (const id in _pending) {
            const cb = _pending[id].cb
            delete _pending[id]
            cb(null, motivo)
        }
        if (_stopWait) {
            const w = _stopWait
            _stopWait = null
            w.cb()
        }
    }

    Timer {
        interval: 1500
        running: dbg.state !== "idle"
        repeat: true
        onTriggered: {
            const now = Date.now()
            for (const id in dbg._pending)
                if (now > dbg._pending[id].deadline) {
                    const cb = dbg._pending[id].cb
                    delete dbg._pending[id]
                    cb(null, "el adaptador no contestó a tiempo")
                }
            if (dbg._stopWait && now > dbg._stopWait.deadline) {
                const w = dbg._stopWait
                dbg._stopWait = null
                w.cb()      // sigue corriendo: se informa tal cual
            }
        }
    }

    // ── Mensajes del adaptador ───────────────────────────────────────────────
    property var _onInitialized: null   // qué hacer cuando el adaptador esté listo

    function _onMessage(j) {
        if (j._qs === "up")
            return
        if (j._qs === "down" || j._qs === "fatal") {
            if (dbg.state !== "idle")
                dbg.state = "exited"
            _flushWaiters(j.error || "el adaptador se cerró")
            return
        }
        if (j.type === "response") {
            const p = _pending[j.request_seq]
            if (p) {
                delete _pending[j.request_seq]
                p.cb(j.body || ({}), j.success ? "" : (j.message || "petición rechazada"))
            }
            return
        }
        if (j.type !== "event")
            return
        switch (j.event) {
        case "initialized": {
            const f = _onInitialized
            _onInitialized = null
            if (f) f()
            return
        }
        case "stopped": {
            state = "stopped"
            stoppedThread = (j.body && j.body.threadId) || stoppedThread
            stopReason = (j.body && j.body.reason) || ""
            // La pila del hilo parado se pide ya: es lo primero que se quiere
            // ver, y deja los frameId listos para vars y eval.
            _request("stackTrace", { threadId: stoppedThread, levels: 20 },
                (body) => {
                    dbg.lastStack = (body && body.stackFrames) || []
                    if (dbg._stopWait) {
                        const w = dbg._stopWait
                        dbg._stopWait = null
                        w.cb()
                    }
                })
            return
        }
        case "continued":
            state = "running"
            return
        case "output":
            if (j.body && j.body.output)
                outputBuf = (outputBuf + j.body.output).slice(-8000)
            return
        case "exited":
            exitCode = (j.body && j.body.exitCode !== undefined)
                       ? j.body.exitCode : -1
            state = "exited"
            if (_stopWait) {
                const w = _stopWait
                _stopWait = null
                w.cb()
            }
            return
        case "terminated":
            if (state !== "exited")
                state = "exited"
            if (_stopWait) {
                const w = _stopWait
                _stopWait = null
                w.cb()
            }
            return
        }
    }

    // ── Arrancar ─────────────────────────────────────────────────────────────
    // start({program, args, lang, stop_on_entry, breakpoints}, cb)
    function start(args, cb) {
        if (!detected) {
            cb("Los adaptadores aún se están detectando; vuelve a intentarlo.")
            return
        }
        if (state !== "idle" && state !== "exited") {
            cb("Ya hay una sesión de depuración (" + state + "). Ciérrala con "
               + "debug_ctl action=stop antes de abrir otra.")
            return
        }
        // ENGANCHARSE A UN PROCESO QUE YA CORRE. Es la otra mitad de depurar:
        // un servicio que lleva horas mal, un cuelgue que solo pasa en
        // producción, algo que no se puede relanzar. No hay `program` que valga
        // —el programa ya está en marcha—, así que la jaula de rutas no aplica y
        // lo que se comprueba es que el proceso exista y sea TUYO (ver
        // ToolRunner: engancharse a un proceso ajeno no lo permite el sistema, y
        // pedirlo sin más devolvería un error del adaptador imposible de leer).
        const pid = parseInt(args.attach_pid)
        const esAdjuntar = !isNaN(pid) && pid > 0
        let prog = ""
        if (!esAdjuntar) {
            prog = svc._safePath(args.program)
            if (prog === "") {
                cb("El programa debe estar dentro de la carpeta personal. Si lo "
                   + "que quieres es engancharte a algo que ya corre, pasa "
                   + "attach_pid en vez de program.")
                return
            }
        }

        // Qué adaptador toca: lo dice el catálogo, no este archivo.
        const el = DBG.elige(prog, args.lang, available)
        if (el === null) {
            cb("No sé con qué depurar eso. Lenguajes que conozco: "
               + DBG.lenguajes().join(", ") + ".")
            return
        }
        if (el.falta) {
            cb("Falta el depurador de " + el.lenguaje + ": " + el.falta
               + ". Instálalo con  pacman -S " + el.paquete
               + (el.otros.length > 0
                  ? "  (también valdría: " + el.otros.join(", ") + ")" : ""))
            return
        }
        adapterName = el.id
        const dir = prog !== "" ? prog.slice(0, prog.lastIndexOf("/"))
                                : svc.toolCtx.home
        const progArgs = Array.isArray(args.args) ? args.args.map(String) : []
        // El puerto solo lo usan los de socket (delve). Se saca del reloj para
        // no chocar con una sesión anterior que aún esté soltando el puerto.
        const bridge = DBG.puente(el.def, 38000 + (Date.now() % 1000))
        const launch = esAdjuntar
            ? DBG.peticionAdjuntar(el.def, pid)
            : DBG.peticionLanzar(el.def, prog, progArgs, dir,
                                 args.stop_on_entry === true)

        // Rupturas iniciales. Tres formas, de la más corta a la más completa:
        //   "~/p/main.py:42"
        //   "~/p/main.py:42 if n > 100"       (condición pegada, muy cómoda)
        //   {file, line, condition, hit_condition, log_message}
        breakpoints = ({})
        const bps = Array.isArray(args.breakpoints) ? args.breakpoints : []
        for (const b of bps) {
            const bp = _parseBp(b)
            if (!bp)
                continue
            if (!breakpoints[bp.file])
                breakpoints[bp.file] = []
            breakpoints[bp.file].push(bp)
        }

        state = "starting"
        program = esAdjuntar ? ("(proceso " + pid + ")") : prog
        outputBuf = ""
        lastStack = []
        exitCode = -1
        _pending = ({})
        _seq = 0
        proc.command = ["python3", svc.iaDir + "/bin/jsonrpc-bridge.py"]
                       .concat(bridge)
        proc.running = true

        _request("initialize", {
            clientID: "quickshell-ia", adapterID: adapterName,
            linesStartAt1: true, columnsStartAt1: true, pathFormat: "path",
            supportsRunInTerminalRequest: false
        }, (body, err) => {
            if (err !== "") {
                dbg.stop(() => {})
                cb("El adaptador rechazó el initialize: " + err)
                return
            }
            // Con initialize contestado se lanza; el evento 'initialized'
            // marca el momento de poner puntos de ruptura y cerrar la
            // configuración (el orden que exige el protocolo).
            dbg._onInitialized = () => {
                dbg._sendBreakpoints(() => {
                    dbg._request("configurationDone", {}, () => {})
                })
            }
            // El nombre de la petición es el del propio objeto: lanzar y
            // engancharse son dos verbos distintos del protocolo, no una
            // opción de uno de ellos.
            dbg._request(launch.request, launch, (b2, err2) => {
                if (err2 !== "") {
                    dbg.stop(() => {})
                    cb(esAdjuntar
                       ? ("No se pudo enganchar al proceso " + pid + ": " + err2
                          + ". En muchos sistemas hace falta permiso para mirar "
                          + "dentro de otro proceso aunque sea tuyo: mira "
                          + "/proc/sys/kernel/yama/ptrace_scope.")
                       : ("No se pudo lanzar el programa: " + err2))
                }
            }, 30000)
            // Se contesta cuando el programa pare (ruptura o entrada) o
            // termine — eso es lo que el modelo necesita saber para seguir.
            // Engancharse no siempre para el programa: lldb y gdb sí, debugpy
            // no. Como el "no para" es una respuesta válida y no un fallo, se
            // espera mucho menos: cuatro segundos y se cuenta cómo está, en vez
            // de tener al usuario quince mirando una tarjeta que no va a
            // cambiar. Para pararlo está debug_ctl action=pause.
            dbg._stopWait = { deadline: Date.now() + (esAdjuntar ? 4000 : 15000),
                              cb: () => cb(dbg._sitrep()) }
        }, 15000)
    }

    // Una ruptura desde cualquiera de sus tres formas. null si no se entiende.
    function _parseBp(b) {
        let f = "", l = 0, cond = "", hit = "", log = ""
        if (typeof b === "string") {
            // "archivo:línea" con condición opcional pegada detrás.
            let resto = String(b).trim()
            const mIf = resto.match(/\s+(?:if|si)\s+([\s\S]+)$/i)
            if (mIf) {
                cond = mIf[1].trim()
                resto = resto.slice(0, resto.length - mIf[0].length)
            }
            const c = resto.lastIndexOf(":")
            if (c <= 0)
                return null
            f = resto.slice(0, c)
            l = parseInt(resto.slice(c + 1)) || 0
        } else if (b && b.file) {
            f = String(b.file)
            l = parseInt(b.line) || 0
            cond = String(b.condition || "").trim()
            hit = String(b.hit_condition || b.hitCondition || "").trim()
            log = String(b.log_message || b.logMessage || "").trim()
        } else {
            return null
        }
        const fp = svc._safePath(f)
        if (fp === "" || l <= 0)
            return null
        return { file: fp, line: l, condition: cond,
                 hitCondition: hit, logMessage: log }
    }

    // Las rupturas de un archivo, legibles: "42 si n>100, 87 (x3)".
    function _fmtBps(lista) {
        return (lista || []).map(bp => {
            let s = String(bp.line)
            if (bp.condition && bp.condition !== "")
                s += " si " + bp.condition
            if (bp.hitCondition && bp.hitCondition !== "")
                s += " (paso " + bp.hitCondition + ")"
            if (bp.logMessage && bp.logMessage !== "")
                s += " [registra]"
            return s
        }).join(", ")
    }

    // Lo que viaja al adaptador por cada ruptura. Los campos vacíos NO se
    // mandan: un `condition: ""` hace que algunos adaptadores no paren nunca.
    function _bpWire(bp) {
        const o = { line: bp.line }
        if (bp.condition && bp.condition !== "")
            o.condition = bp.condition
        if (bp.hitCondition && bp.hitCondition !== "")
            o.hitCondition = bp.hitCondition
        if (bp.logMessage && bp.logMessage !== "")
            o.logMessage = bp.logMessage
        return o
    }

    function _sendBreakpoints(done) {
        const files = Object.keys(breakpoints)
        if (files.length === 0) {
            done()
            return
        }
        let quedan = files.length
        for (const f of files)
            _request("setBreakpoints", {
                source: { path: f },
                breakpoints: breakpoints[f].map(bp => dbg._bpWire(bp))
            }, () => { if (--quedan === 0) done() })
    }

    // El parte de situación: es la respuesta de casi todo, porque tras cada
    // paso lo que quiere el modelo es saber dónde está y qué ha salido.
    function _sitrep() {
        let out = "[" + adapterName + "] "
        if (state === "stopped") {
            out += "PARADO (" + (stopReason || "?") + ")"
            if (lastStack.length > 0) {
                const f = lastStack[0]
                out += " en " + (f.source && f.source.path ? f.source.path : f.name)
                     + ":" + f.line
                out += "\nPila:"
                for (let i = 0; i < Math.min(lastStack.length, 8); i++) {
                    const fr = lastStack[i]
                    out += "\n  #" + i + " " + fr.name + "  "
                         + (fr.source && fr.source.path ? fr.source.path : "?")
                         + ":" + fr.line
                }
            }
        } else if (state === "exited") {
            out += "programa TERMINADO"
                 + (exitCode >= 0 ? " (código " + exitCode + ")" : "")
        } else {
            out += "corriendo (usa debug_ctl action=pause para pararlo, o "
                 + "debug_view what=status para mirar la salida)"
        }
        const bpn = Object.keys(breakpoints)
            .map(f => f.split("/").pop() + ":" + _fmtBps(breakpoints[f]))
        if (bpn.length > 0)
            out += "\nRupturas: " + bpn.join("  ")
        if (outputBuf.trim() !== "")
            out += "\nSalida del programa (cola):\n" + outputBuf.slice(-2000)
        return out
    }

    // ── Control ──────────────────────────────────────────────────────────────
    function ctl(args, cb) {
        const action = String(args.action || "")
        if (state === "idle") {
            cb("No hay sesión. Ábrela con debug_start.")
            return
        }
        const resumen = () => {
            dbg._stopWait = { deadline: Date.now() + 10000,
                              cb: () => cb(dbg._sitrep()) }
        }
        switch (action) {
        case "continue":
            state = "running"
            _request("continue", { threadId: stoppedThread }, () => {})
            resumen()
            return
        case "next":
            state = "running"
            _request("next", { threadId: stoppedThread }, () => {})
            resumen()
            return
        case "step":
            state = "running"
            _request("stepIn", { threadId: stoppedThread }, () => {})
            resumen()
            return
        case "out":
            state = "running"
            _request("stepOut", { threadId: stoppedThread }, () => {})
            resumen()
            return
        case "pause":
            _request("pause", { threadId: stoppedThread || 1 }, () => {})
            resumen()
            return
        case "bp_add":
        case "bp_clear": {
            const f = svc._safePath(args.file)
            const l = parseInt(args.line) || 0
            if (f === "" || (action === "bp_add" && l <= 0)) {
                cb("Hace falta file (dentro de la carpeta personal) y line.")
                return
            }
            const m = Object.assign({}, breakpoints)
            if (action === "bp_add") {
                // CONDICIONAL: el adaptador solo para si la expresión es cierta
                // en ese punto. Es la diferencia entre parar mil veces en un
                // bucle y parar en la iteración que falla.
                const nueva = { file: f, line: l,
                    condition: String(args.condition || "").trim(),
                    hitCondition: String(args.hit_condition || "").trim(),
                    logMessage: String(args.log_message || "").trim() }
                m[f] = (m[f] || []).filter(x => x.line !== l).concat([nueva])
            } else {
                m[f] = (m[f] || []).filter(x => l > 0 ? x.line !== l : false)
                if (m[f].length === 0)
                    delete m[f]
            }
            breakpoints = m
            _request("setBreakpoints", {
                source: { path: f },
                breakpoints: (m[f] || []).map(bp => dbg._bpWire(bp))
            }, (body, err) => {
                if (err !== "") { cb("Error: " + err); return }
                // El adaptador dice si pudo VERIFICAR cada una: una condición
                // mal escrita o una línea sin código se ven aquí, no cuando el
                // programa no para y nadie sabe por qué.
                const ver = (body && body.breakpoints) || []
                let out = "Rupturas en " + f.split("/").pop() + ": "
                        + (dbg._fmtBps(m[f]) || "ninguna")
                const malas = ver.filter(v => v && v.verified === false)
                if (malas.length > 0)
                    out += "\nSIN VERIFICAR: " + malas.map(v =>
                        "L" + (v.line || "?") + (v.message ? " — " + v.message : ""))
                        .join("; ")
                cb(out)
            })
            return
        }
        case "stop":
            stop(() => cb("Sesión de depuración cerrada."))
            return
        }
        cb("action debe ser continue, next, step, out, pause, bp_add, bp_clear o stop.")
    }

    function stop(cb) {
        if (state === "idle") {
            cb("")
            return
        }
        _request("disconnect", { terminateDebuggee: true }, () => {})
        state = "idle"
        _flushWaiters("sesión cerrada")
        // El adaptador tiene un momento para irse por las buenas; después, tajo.
        killDelay.restart()
        cb("")
    }
    Timer {
        id: killDelay
        interval: 800
        onTriggered: proc.running = false
    }

    // ── Inspección ───────────────────────────────────────────────────────────
    function view(args, cb) {
        const what = String(args.what || "status")
        if (state === "idle") {
            cb("No hay sesión. Ábrela con debug_start.")
            return
        }
        switch (what) {
        case "status":
            cb(_sitrep())
            return
        case "stack":
            if (state !== "stopped") {
                cb("El programa no está parado (" + state + ").")
                return
            }
            _request("stackTrace", { threadId: stoppedThread, levels: 25 },
                (body, err) => {
                    if (err !== "") { cb("Error: " + err); return }
                    dbg.lastStack = (body && body.stackFrames) || []
                    let out = "Pila (" + dbg.lastStack.length + " marcos):"
                    for (let i = 0; i < dbg.lastStack.length; i++) {
                        const f = dbg.lastStack[i]
                        out += "\n#" + i + " " + f.name + "  "
                             + (f.source && f.source.path ? f.source.path : "?")
                             + ":" + f.line
                    }
                    cb(out)
                })
            return
        case "threads":
            _request("threads", {}, (body, err) => {
                if (err !== "") { cb("Error: " + err); return }
                const ts = (body && body.threads) || []
                cb("Hilos:\n" + ts.map(t => "- [" + t.id + "] " + t.name
                    + (t.id === dbg.stoppedThread ? "  ← parado" : "")).join("\n"))
            })
            return
        case "vars": {
            if (state !== "stopped") {
                cb("El programa no está parado (" + state + ").")
                return
            }
            const idx = parseInt(args.frame) || 0
            const frame = lastStack[idx]
            if (!frame) {
                cb("No existe el marco #" + idx + " (mira debug_view what=stack).")
                return
            }
            _request("scopes", { frameId: frame.id }, (body, err) => {
                if (err !== "") { cb("Error: " + err); return }
                const scopes = ((body && body.scopes) || [])
                    .filter(s => !s.expensive).slice(0, 3)
                if (scopes.length === 0) { cb("Sin ámbitos legibles."); return }
                let out = "Variables del marco #" + idx + " (" + frame.name + "):"
                let quedan = scopes.length
                for (const sc of scopes)
                    dbg._request("variables",
                        { variablesReference: sc.variablesReference },
                        (b2, e2) => {
                            out += "\n[" + sc.name + "]"
                            for (const v of ((b2 && b2.variables) || []).slice(0, 40))
                                out += "\n  " + v.name + " = "
                                     + String(v.value).slice(0, 160)
                                     + (v.type ? "   (" + v.type + ")" : "")
                            if (--quedan === 0)
                                cb(out)
                        })
            })
            return
        }
        }
        cb("what debe ser stack, vars, threads o status.")
    }

    function evaluate(args, cb) {
        const expr = String(args.expression || "").trim()
        if (expr === "") {
            cb("Falta expression.")
            return
        }
        if (state !== "stopped") {
            cb("El programa no está parado: evalúa con una ruptura puesta o tras pause.")
            return
        }
        const idx = parseInt(args.frame) || 0
        const frame = lastStack[idx]
        // context "watch" y NO "repl", y la diferencia no es cosmética.
        //
        // "repl" significa "esto lo ha tecleado alguien en la consola del
        // depurador", y gdb lo trata como tal: ejecuta COMANDOS DE GDB, no
        // expresiones. Comprobado en vivo — evaluar "x + 1" con context repl
        // devuelve «Cannot access memory at address 0x1», porque gdb entendió su
        // comando `x` de examinar memoria. Y por ese mismo camino pasarían
        // `shell`, `set` o `file`, que no son evaluar nada.
        //
        // "watch" es evaluar una expresión en un marco, que es exactamente lo
        // que promete esta herramienta. Con debugpy y lldb-dap se comporta igual
        // que antes; con gdb es la diferencia entre funcionar y no.
        _request("evaluate", {
            expression: expr, context: "watch",
            frameId: frame ? frame.id : undefined
        }, (body, err) => {
            if (err !== "") { cb("No se pudo evaluar: " + err); return }
            cb(expr + " = " + String((body && body.result) || "")
               + (body && body.type ? "   (" + body.type + ")" : ""))
        })
    }

    // El hilo muere, la sesión con él: depurar pertenece al encargo en curso.
    function resetThread() {
        if (state !== "idle")
            stop(() => {})
    }
    Component.onDestruction: if (proc.running) proc.running = false
}
