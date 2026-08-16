import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "../TextUtils.js" as TU

// REGISTRO DE AUDITORÍA: qué ejecutó el agente, cuándo, por qué se le dejó y
// quién lo pidió.
//
// Con un harness que alcanza shell, archivos, git, MCP, LSP, depurador, Python,
// trabajos y red, la pregunta "¿qué ha hecho esto en mi equipo?" tiene que
// tener UNA respuesta, y no puede ser el historial de la conversación (que se
// compacta, se borra y se puede limpiar). Va a un JSONL aparte, en la misma
// carpeta de estado, y sobrevive a /limpiar y a cambiar de conversación.
//
// Se registra TODO lo que llega a ejecutarse, venga de donde venga: la tarjeta
// del agente principal, un subagente autónomo, la celda de Python por el
// loopback, o un veto de un hook. Lo que NO se registra: el contenido de los
// resultados (solo su tamaño) — el registro dice qué se hizo, no vuelve a
// guardar lo que se leyó.
//
// Los argumentos van truncados y pasados por el mismo tapado de secretos que el
// resto: un registro de seguridad que filtre contraseñas sería el colmo.
Scope {
    id: audit

    property var svc

    // Un apunte por línea. Se acumulan y se vuelcan en lote: escribir en el
    // camino caliente de cada herramienta sería E/S por gusto.
    property var _cola: []
    property bool _volcando: false

    readonly property string path: svc ? svc.dataDir + "/ai-audit.jsonl" : ""

    // origen: card | subagent | cell | hook | supervisor
    // decision: auto | user | always | rejected | blocked | denied
    //           ok | dudo | bloqueo | consejo   (los del supervisor)
    function record(o) {
        if (!svc || Settings.aiAudit === false)
            return
        const apunte = {
            ts: new Date().toISOString(),
            conv: svc.currentId,
            src: String(o.src || "card"),
            tool: String(o.tool || ""),
            risk: TU.dangerScan ? svc.riskClass(String(o.tool || "")) : "",
            lvl: svc.riskLevel(String(o.tool || "")),
            dec: String(o.decision || ""),
            args: svc.redactSecrets(String(o.args || "")).slice(0, 600),
            model: svc.model
        }
        if (o.danger)
            apunte.danger = String(o.danger)
        if (o.bytes !== undefined)
            apunte.bytes = o.bytes
        if (o.why)
            apunte.why = String(o.why).slice(0, 300)
        _cola = _cola.concat([JSON.stringify(apunte)])
        flushTimer.restart()
    }

    Timer {
        id: flushTimer
        interval: 1200
        onTriggered: audit.flush()
    }

    function flush() {
        if (_volcando || _cola.length === 0 || !svc)
            return
        _volcando = true
        const lote = _cola.join("\n") + "\n"
        _cola = []
        // Append por shell: FileView reescribe el archivo entero y un registro
        // que se reescribe no es un registro. La rotación va aquí mismo, que es
        // donde se sabe si el archivo creció (1 MB ≈ varios miles de apuntes).
        proc.environment = ({ QS_P: audit.path, QS_L: lote })
        proc.command = ["sh", "-c",
            // umask 077 ANTES de crear nada: aquí dentro va el nombre de cada
            // herramienta con sus argumentos, y en los argumentos va lo que el
            // usuario haya escrito. Nacía con 0644, o sea legible por cualquier
            // cuenta de la máquina. Y el chmod al final arregla también los
            // archivos que ya existían de antes.
            'umask 077; mkdir -p "$(dirname -- "$QS_P")"; '
            + 'printf %s "$QS_L" >> "$QS_P"; '
            + 'chmod 600 -- "$QS_P" 2>/dev/null; '
            + 'if [ "$(wc -c < "$QS_P")" -gt 1048576 ]; then '
            + 'mv -f -- "$QS_P" "$QS_P.1"; chmod 600 -- "$QS_P.1" 2>/dev/null; fi']
        proc.running = true
    }

    Process {
        id: proc
        onExited: {
            audit._volcando = false
            if (audit._cola.length > 0)
                flushTimer.restart()
        }
    }

    // Lo pendiente no se pierde al recargar el shell ni al cerrar.
    Component.onDestruction: if (_cola.length > 0) flush()
}
