import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "LocalTools.js" as LT

// Hooks del usuario (idea de OpenHarness): comandos propios que el harness
// dispara en momentos concretos del ciclo de vida. Es la puerta de extensión que
// faltaba — el usuario puede auditar, registrar o VETAR lo que haga el agente
// sin tocar ni una línea de este código.
//
// Se declaran en Modules/IA/data/ai-hooks.json:
//   { "hooks": [
//       { "event": "pre_tool_use", "matcher": "run_command|ssh_exec",
//         "command": "~/bin/vetar.sh", "priority": 10 },
//       { "event": "stop", "command": "notify-send 'listo'" } ] }
//
// El único que puede BLOQUEAR es pre_tool_use: si su comando termina con código
// distinto de 0, la llamada se rechaza y su salida se le devuelve al modelo como
// motivo. Los demás son avisos (no frenan nada).
// El contexto viaja por ENTORNO (QS_HOOK_*), nunca en argv.
Scope {
    id: runner

    property var svc

    readonly property var events: ["session_start", "user_prompt_submit",
                                   "pre_tool_use", "post_tool_use", "stop"]
    property var hooks: []              // [{event, matcher, command, priority}]

    // Un veto. Lleva la 'puerta' que le pasó quien pidió el permiso (la tarjeta
    // que esperaba) para que el harness sepa a qué llamada corresponde: así los
    // hooks no necesitan saber nada del modelo de mensajes.
    signal blocked(int gate, string reason)

    // Los hooks se leen de su archivo y se recargan solos al editarlo.
    FileView {
        path: runner.svc ? runner.svc.dataDir + "/ai-hooks.json" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let list = []
            try {
                const j = JSON.parse(text())
                list = (j.hooks || []).filter(h => h && h.event && h.command
                            && runner.events.indexOf(h.event) !== -1)
            } catch (e) {
                runner.svc.pushInfo(I18n.tr("ai-hooks.json is not valid JSON — hooks disabled."))
            }
            runner.hooks = list
        }
        onLoadFailed: runner.hooks = []  // sin archivo, sin hooks: es lo normal
    }

    // Los que aplican a un evento (y a una herramienta, si llevan matcher), por
    // prioridad descendente.
    function hooksFor(event, toolName) {
        return (hooks || []).filter(h => {
            if (h.event !== event)
                return false
            const m = String(h.matcher || "").trim()
            if (m === "" || m === "*")
                return true
            try { return new RegExp("^(" + m + ")$").test(String(toolName || "")) }
            catch (e) { return m === toolName }
        }).sort((a, b) => (b.priority || 0) - (a.priority || 0))
    }

    // Los hooks de AVISO (todos menos pre_tool_use) se lanzan sueltos: no
    // devuelven nada ni frenan nada, así que no comparten la cola — si la
    // compartieran, un aviso en marcha pisaría al que sí puede vetar.
    function fire(event, toolName, payload) {
        const list = hooksFor(event, toolName)
        for (let i = 0; i < list.length; i++)
            Quickshell.execDetached({
                command: ["sh", "-c", String(list[i].command)],
                environment: Object.assign({ QS_HOOK_EVENT: event }, payload || ({}))
            })
    }

    // ── El bloqueante ────────────────────────────────────────────────────────
    // Corre EN SERIE por prioridad y espera veredicto, así el que veta lo hace
    // antes de que el siguiente diga nada.
    property var _queue: []
    property string _event: ""
    property var _payload: ({})
    property int _gate: -1              // la tarjeta que espera el veredicto
    property var _done: null            // qué hacer si ninguno veta
    // Quince segundos. Un hook decide si algo puede pasar; si necesita más que
    // eso, no es un hook, es un trabajo. Se corta CERRADO a propósito: un hook
    // que existe para vetar y se cuelga no puede acabar dejando pasar la acción.
    readonly property int plazoHook: 15

    function run(event, toolName, payload, gate, onDone) {
        const list = hooksFor(event, toolName)
        if (list.length === 0) {
            if (onDone) onDone()
            return
        }
        _event = event
        _queue = list
        _done = onDone || null
        _payload = payload || ({})
        _gate = gate === undefined ? -1 : gate
        _next()
    }

    function _next() {
        if (_queue.length === 0) {
            const done = _done
            _done = null
            _gate = -1
            if (done) done()
            return
        }
        const h = _queue[0]
        _queue = _queue.slice(1)
        // Con plazo y con tope de salida, igual que las herramientas. Un hook es
        // un comando del usuario, y un comando del usuario se cuelga: el
        // bloqueante corre EN SERIE y con una tarjeta esperando su veredicto, así
        // que uno que no vuelve deja el turno congelado para siempre y sin decir
        // por qué. Y su salida la recogía un StdioCollector sin límite, que es la
        // misma bomba de memoria que ya se tapó en el ejecutor.
        proc.command = LT.acotado(runner.plazoHook, ["sh", "-c", String(h.command)])
        proc.environment = Object.assign({ QS_HOOK_EVENT: runner._event },
                                         runner._payload)
        proc.running = true
    }

    Process {
        id: proc
        stdout: StdioCollector { id: outCol }
        stderr: StdioCollector { id: errCol }
        onExited: (code) => {
            // Solo pre_tool_use puede vetar; los demás son avisos.
            if (code !== 0 && runner._event === "pre_tool_use"
                    && runner._gate >= 0) {
                let why = (outCol.text || "").trim() || (errCol.text || "").trim()
                // Un hook cortado por el plazo veta, pero se dice como lo que
                // es: "no contestó en 15 s" es un hook que arreglar, y "salió
                // con 3" es una decisión suya. Confundirlos deja al usuario
                // buscando una regla que no existe.
                if (code === 124 || code === 137)
                    why = I18n.tr("a hook did not answer within %1 s")
                              .arg(runner.plazoHook)
                if (why === "")
                    why = I18n.tr("blocked by a hook (exit %1)").arg(code)
                const gate = runner._gate
                runner._queue = []
                runner._done = null
                runner._gate = -1
                runner.blocked(gate, why)
                return
            }
            runner._next()
        }
    }
}
