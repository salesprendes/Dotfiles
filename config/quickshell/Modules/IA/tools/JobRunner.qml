import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// TRABAJOS EN SEGUNDO PLANO: comandos que no caben en una tarjeta.
//
// `run_command` tiene un corte corto y no tiene teclado, así que un `make -j8`,
// un `npm install` o cualquier cosa que pregunte quedan fuera. Aquí un trabajo se
// lanza, sigue vivo entre turnos, y el agente lo vigila (job_view), le contesta
// (job_input) o lo mata (job_ctl).
//
// Todo pasa por bin/job-run.py, que da el mismo NDJSON con pty y sin él, así
// que aquí hay un único camino que auditar. Con pty el proceso cree que está en
// un terminal de verdad: eso es lo que hace que sudo pida la contraseña y que
// ssh acepte una huella, en vez de morir con "no tty".
Scope {
    id: runner

    property var svc

    // Los trabajos vivos y los ya terminados que aún nadie ha leído.
    property var jobs: []
    property int _nextId: 1
    readonly property int maxJobs: 6
    // Cuánta cola de salida se guarda por trabajo. Un `make` escupe megas: se
    // queda el final, que es donde está el error.
    readonly property int outputCap: 60000

    readonly property var running: jobs.filter(j => j.state === "running")

    function byId(id) {
        return jobs.find(j => String(j.jobId) === String(id)) || null
    }

    readonly property Component _jobComp: Component {
        Process {
            id: job
            property int jobId: 0
            property string label: ""
            property string cmd: ""
            property bool pty: false
            property string state: "running"   // running | done | failed | killed
            property string out: ""
            property int exitCode: -1
            property int pid: 0
            property double startedAt: 0
            property int ms: 0
            // La tarjeta que espera el primer parte (gracia inicial), si la hay.
            property var pending: null
            property var replyCb: null

            stdinEnabled: true

            // Los temporizadores son DE CADA TRABAJO, no compartidos. Con uno
            // solo, lanzar tres trabajos en la misma ronda —que es justo lo que
            // hace un modelo al que le dices "compila y mientras corre los
            // tests"— hacía que el último pisara la espera de los anteriores y
            // esos se quedaran sin contestar hasta terminar.
            readonly property Timer grace: Timer {
                onTriggered: {
                    if (!job.pending)
                        return
                    const cb = job.pending
                    job.pending = null
                    cb(runner.report(job, 3000))
                }
            }
            readonly property Timer reply: Timer {
                interval: 900
                onTriggered: {
                    const f = job.replyCb
                    job.replyCb = null
                    if (f)
                        f(runner.report(job, 2500))
                }
            }
            // Si tras la señal el proceso sigue ahí, se corta el lanzador: no se
            // deja un trabajo zombi ocupando sitio.
            readonly property Timer killer: Timer {
                interval: 1500
                onTriggered: if (job.running) job.running = false
            }

            function push(texto) {
                out = (out + texto).slice(-runner.outputCap)
            }
            function send(obj) { job.write(JSON.stringify(obj) + "\n") }

            stdout: SplitParser {
                onRead: (line) => {
                    const l = line.trim()
                    if (l === "" || l[0] !== "{")
                        return
                    let j = null
                    try { j = JSON.parse(l) } catch (e) { return }
                    if (j.t === "up") {
                        job.pid = j.pid || 0
                    } else if (j.t === "out" || j.t === "err") {
                        job.push(j.t === "err" ? j.d : j.d)
                    } else if (j.t === "exit") {
                        job.exitCode = j.code
                        job.ms = Date.now() - job.startedAt
                        if (job.state === "running")
                            job.state = (j.code === 0) ? "done" : "failed"
                        runner._settle(job)
                    }
                }
            }
            stderr: SplitParser { onRead: () => {} }
            onExited: {
                if (job.state === "running") {
                    job.state = "failed"
                    job.ms = Date.now() - job.startedAt
                    runner._settle(job)
                }
            }
        }
    }

    // start({command, pty, label, cwd, wait}, cb). Espera una GRACIA corta antes
    // de contestar: así un comando de dos segundos se comporta como el
    // run_command de siempre (respuesta con su salida) y uno largo contesta
    // "sigue corriendo, id=N" para que el agente lo vigile.
    function start(args, cb) {
        if (running.length >= maxJobs) {
            cb("Ya hay " + running.length + " trabajos en marcha (el máximo). "
               + "Cierra alguno con job_ctl action=kill.")
            return
        }
        const cmd = String(args.command || "").trim()
        if (cmd === "") {
            cb("Comando vacío.")
            return
        }
        let dir = svc.toolCtx.home
        if (String(args.cwd || "").trim() !== "") {
            dir = svc._safePath(args.cwd)
            if (dir === "") {
                cb("El directorio de trabajo debe estar dentro de la carpeta personal.")
                return
            }
        }
        const usaPty = args.pty === true
        const argv = ["python3", svc.iaDir + "/bin/job-run.py"]
            .concat(usaPty ? ["--pty"] : [])
            .concat(["--cwd", dir, "--", "sh", "-c", cmd])

        const j = _jobComp.createObject(runner, {
            jobId: _nextId++, label: String(args.label || "").slice(0, 40) || cmd.slice(0, 40),
            cmd: cmd, pty: usaPty, startedAt: Date.now(), command: argv
        })
        jobs = jobs.concat([j])
        j.running = true

        j.pending = cb
        // `|| 2` convertía un wait:0 —"lánzalo y sigue, no me esperes"— en dos
        // segundos de espera. Cero es una respuesta, no una falta de respuesta.
        const esp = parseInt(args.wait)
        j.grace.interval = Math.max(0, Math.min(30000,
            (isNaN(esp) ? 2 : esp) * 1000))
        j.grace.restart()
    }

    // Cuántos trabajos ya terminados se conservan. No es un número cosmético: cada
    // uno retiene su Process, su Timer y hasta 'outputCap' de salida capturada, así
    // que sin tope una sesión larga crece sin límite.
    //
    // Conservar algunos es deliberado, porque el modelo tiene que poder releer con
    // job_view lo que salió de un comando de hace tres turnos. Veinte cubre eso de
    // sobra y acota la memoria. Los vivos nunca se tocan.
    readonly property int finishedCap: 20

    // Suelta los terminados más antiguos que pasen del tope.
    function _pruneFinished() {
        const idos = jobs.filter(j => j.state !== "running")
        if (idos.length <= runner.finishedCap)
            return
        // 'jobs' está en orden de creación, así que los primeros son los más
        // viejos: se tiran esos y se conservan los últimos.
        const tirar = idos.slice(0, idos.length - runner.finishedCap)
        jobs = jobs.filter(j => tirar.indexOf(j) === -1)
        for (const j of tirar)
            j.destroy()
    }

    // El trabajo terminó: si alguien esperaba el primer parte, se le da ya.
    function _settle(j) {
        jobs = jobs.slice()          // el estado cambió: que la interfaz mire
        j.grace.stop()
        if (j.pending) {
            const cb = j.pending
            j.pending = null
            cb(report(j, 4000))
        }
        // Y si alguien esperaba respuesta a lo que tecleó, el fin del proceso
        // ES la respuesta.
        if (j.replyCb) {
            const f = j.replyCb
            j.replyCb = null
            j.reply.stop()
            f(report(j, 2500))
        }
        // Al final, y no antes: los parte de arriba leen 'j', así que soltarlo
        // primero dejaría un objeto destruido en medio de la respuesta.
        runner._pruneFinished()
    }

    // El parte de un trabajo
    function report(j, cola) {
        const seg = ((j.state === "running" ? Date.now() - j.startedAt : j.ms)
                     / 1000).toFixed(1)
        let out = "[trabajo " + j.jobId + "] " + j.label
                + (j.pty ? "  (pty)" : "") + "\n$ " + j.cmd + "\n"
        if (j.state === "running")
            out += "SIGUE CORRIENDO (" + seg + " s, pid " + j.pid + "). "
                 + "Míralo con job_view id=" + j.jobId
                 + ", contéstale con job_input, o córtalo con job_ctl.\n"
        else
            out += "TERMINADO: " + j.state + " (código " + j.exitCode
                 + ", " + seg + " s)\n"
        const texto = j.out
        if (texto.trim() === "")
            out += "(sin salida todavía)"
        else {
            const trozo = texto.slice(-(cola || 4000))
            out += "--- salida" + (trozo.length < texto.length ? " (cola)" : "")
                 + " ---\n" + trozo
        }
        return out
    }

    // Las operaciones
    function list() {
        if (jobs.length === 0)
            return "No hay trabajos."
        let out = "Trabajos (" + running.length + " en marcha):"
        for (const j of jobs) {
            const seg = ((j.state === "running" ? Date.now() - j.startedAt : j.ms)
                         / 1000).toFixed(1)
            out += "\n- [" + j.jobId + "] " + j.state
                 + (j.state !== "running" ? " (" + j.exitCode + ")" : "")
                 + "  " + seg + " s" + (j.pty ? "  pty" : "")
                 + "  " + j.label
        }
        return out
    }

    function view(args, cb) {
        const j = byId(args.id)
        if (!j) {
            cb("No existe el trabajo " + args.id + ". " + list())
            return
        }
        cb(report(j, Math.max(200, Math.min(20000, parseInt(args.tail) || 4000))))
    }

    // Teclear en el proceso. Va con tarjeta (clase exec) a propósito: el usuario
    // ve EXACTAMENTE qué texto se le mete al programa antes de que entre.
    function input(args, cb) {
        const j = byId(args.id)
        if (!j) { cb("No existe el trabajo " + args.id + "."); return }
        if (j.state !== "running") { cb("El trabajo " + j.jobId + " ya terminó."); return }
        const texto = String(args.text === undefined ? "" : args.text)
        if (args.eof === true) {
            j.send({ t: "eof" })
            cb("Entrada cerrada (EOF) en el trabajo " + j.jobId + ".")
            return
        }
        // Sin salto de línea explícito el programa se queda esperando: casi
        // siempre lo que se quiere es "escribe esto y pulsa Intro".
        j.send({ t: "in", d: texto + (args.newline === false ? "" : "\n") })
        // Un momento para que conteste, y se devuelve lo que haya salido.
        j.replyCb = cb
        j.reply.restart()
    }

    function ctl(args, cb) {
        const accion = String(args.action || "")
        if (accion === "clear") {
            // Limpia los terminados; los vivos no se tocan.
            const vivos = jobs.filter(j => j.state === "running")
            const idos = jobs.filter(j => j.state !== "running")
            jobs = vivos
            for (const j of idos)
                j.destroy()
            cb("Retirados " + idos.length + " trabajos terminados.")
            return
        }
        const j = byId(args.id)
        if (!j) { cb("No existe el trabajo " + args.id + ". " + list()); return }
        switch (accion) {
        case "signal":
        case "kill": {
            const sig = accion === "kill" ? "KILL"
                : (["INT", "TERM", "HUP", "QUIT", "KILL"]
                   .indexOf(String(args.signal || "")) !== -1 ? args.signal : "TERM")
            if (j.state !== "running") { cb("El trabajo " + j.jobId + " ya terminó."); return }
            j.state = "killed"
            // La duración se cierra AQUÍ: el aviso de salida puede tardar (o no
            // llegar si hay que cortar el lanzador), y un trabajo de diez
            // minutos no puede figurar como "0,0 s" en la lista.
            j.ms = Date.now() - j.startedAt
            j.send({ t: "sig", s: sig })
            j.killer.restart()
            cb("Señal " + sig + " enviada al trabajo " + j.jobId + " (y a su grupo).")
            return
        }
        }
        cb("action debe ser kill, signal o clear.")
    }

    // Los trabajos pertenecen al ENCARGO: cambiar de conversación o limpiarla se
    // los lleva. Dejar un `make` corriendo sin nadie que pueda pararlo sería
    // peor que perderlo.
    function resetThread() {
        const todos = jobs
        jobs = []
        for (const j of todos) {
            if (j.state === "running")
                j.send({ t: "sig", s: "TERM" })
            j.running = false
            j.destroy()
        }
    }
    Component.onDestruction: resetThread()
}
