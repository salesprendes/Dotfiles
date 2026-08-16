import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "TextUtils.js" as TU
import "Payload.js" as PL

// COMPACTAR el contexto: sustituye el historial viejo por un RESUMEN
// ESTRUCTURADO y conserva los últimos turnos literales (tarjetas de herramienta
// incluidas).
//
// Es una operación DEL HARNESS, no un mensaje del chat: viaja por su propio
// proceso, sin streaming y SIN herramientas. La versión anterior metía la
// petición de resumen por el flujo normal — en modo agente el modelo podía
// contestar al "resume esto" con una tool_call, y esa tarjeta se tomaba como
// resumen y se cargaba el historial.
Scope {
    id: comp

    property var svc
    property var conv
    property var tools

    property bool compacting: false
    // El aviso de "casi lleno" se da UNA vez por conversación.
    property bool warned: false
    // Los turnos recientes que sobreviven al resumen (ver aiCompactKeep).
    property var _keepTail: []
    property bool _retried: false

    // El resumen con las secciones que hacen falta para CONTINUAR, no para
    // recordar: es la diferencia entre un resumen y un traspaso de turno.
    readonly property string _prompt:
        "Vas a COMPACTAR esta conversación: tu respuesta sustituirá todo lo "
        + "anterior y será lo único que quede. Escribe un traspaso fiel, en "
        + "el idioma del usuario, con exactamente estas secciones:\n"
        + "**Encargo** — qué pidió el usuario y en qué estado está.\n"
        + "**Decisiones** — lo acordado y su porqué.\n"
        + "**Datos concretos** — rutas, servidores, nombres, valores e "
        + "identificadores exactos que harán falta (nunca contraseñas ni claves).\n"
        + "**Trabajo hecho** — qué comandos y herramientas se ejecutaron y "
        + "qué salió de cada uno, en una línea por acción.\n"
        + "**Pendiente** — qué falta y cuál es el siguiente paso.\n"
        + "No inventes nada y no omitas ningún dato necesario para continuar. "
        + "Solo el resumen."

    function compact() {
        if (svc.busy || compacting || svc.notConfigured || conv.messages.count < 2)
            return
        // Con una tarjeta esperando aprobación no se compacta: resolverla a mitad
        // de resumen dejaría el protocolo a medias.
        for (let i = 0; i < conv.messages.count; i++)
            if (conv.messages.get(i).role === "tool"
                    && conv.messages.get(i).toolStatus === "pending")
                return
        compacting = true
        _retried = false
        // Se aparta la cola ANTES de pedir el resumen: los últimos K turnos
        // vuelven después LITERALES, tarjetas de herramienta incluidas — el
        // resumen es para lo viejo, no para lo que aún tienes en la retina.
        _keepTail = []
        if (Settings.aiCompactKeep > 0) {
            let users = 0, cut = -1
            for (let i = conv.messages.count - 1; i >= 0; i--)
                if (conv.messages.get(i).role === "user") {
                    users++
                    if (users >= Settings.aiCompactKeep) {
                        cut = i
                        break
                    }
                }
            if (cut >= 0)
                for (let i = cut; i < conv.messages.count; i++)
                    _keepTail.push(PL.plainMsg(conv.messages.get(i)))
        }
        conv.pushInfo(I18n.tr("Compacting the context…"))
        _send()
    }

    // Cancelar: una compactación en vuelo pertenece al hilo que la pidió. Si
    // llegara después de cambiar de conversación, borraría LA NUEVA.
    function cancel() {
        if (!compacting)
            return
        proc.running = false
        compacting = false
        _keepTail = []
    }

    function _send() {
        // El historial que iba a viajar de todos modos, con el sistema sustituido
        // por la consigna de archivero y la orden al final.
        const msgs = PL.build(conv.messages, {
            charBudget: svc.charBudget,
            systemPrompt: "",
            images: []
        })
        msgs[0] = { role: "system",
                    content: svc.systemFor(
                        "Eres el archivero de una conversación entre un "
                        + "usuario y su asistente. Resumes con fidelidad.",
                        "compact") }
        msgs.push({ role: "user", content: _prompt })
        const req = { model: svc.model, messages: msgs,
                      temperature: 0.2, stream: false }
        // Resumir es trabajo mecánico: se le pide el esfuerzo mínimo. Pagar
        // pensamiento profundo por un resumen es justo el gasto que el reparto
        // por tarea existe para evitar.
        svc.tuneRequest(req, "compact")
        // El cuerpo entra por la entrada estándar: aquí va la conversación
        // ENTERA, que es justo la que no cabía en un argumento.
        const t = svc.chatCommand(req, 180)
        comp._body = t.body
        proc.command = t.cmd
        proc.environment = t.env
        proc.stdinEnabled = true
        proc.running = true
    }

    property string _body: ""

    Process {
        id: proc
        stdout: StdioCollector { id: outCol }
        stderr: StdioCollector {}
        onStarted: {
            proc.write(comp._body)
            comp._body = ""
            proc.stdinEnabled = false
        }
        onExited: (code) => {
            if (!comp.compacting)          // cancelada por /limpiar o similar
                return
            let j = null
            try { j = JSON.parse(outCol.text) } catch (e) {}
            const m = j && j.choices && j.choices[0] && j.choices[0].message
            const texto = m ? TU.splitThink(String(m.content || "")).text.trim() : ""
            if (code !== 0 || texto === "") {
                const why = (j && j.error && (j.error.message || j.error.code))
                          || (code !== 0 ? "curl " + code : I18n.tr("No response received"))
                // Un tropiezo transitorio merece UN reintento; después se desiste
                // con motivo y el historial queda como estaba.
                if (comp.svc.isTransient(String(why)) && !comp._retried) {
                    comp._retried = true
                    retry.restart()
                    return
                }
                comp.compacting = false
                comp._keepTail = []
                comp.conv.pushInfo(I18n.tr("Compaction failed: %1").arg(String(why).slice(0, 200)))
                return
            }
            comp.compacting = false
            comp.warned = false
            const cabecera = "**" + I18n.tr("Summary of the previous conversation")
                           + ":**\n\n" + texto
            // El hilo se reconstruye entero, así que las rutas resueltas —que se
            // guardan por POSICIÓN— ya no apuntan a la tarjeta que las originó:
            // se tiran antes de repoblar. Heredar un veredicto de "no escapa" de
            // otra llamada es justo lo que no puede pasar.
            comp.tools.forgetPaths()
            comp.conv.messages.clear()
            comp.conv.append({ role: "assistant", content: cabecera, modelName: comp.svc.model })
            for (let i = 0; i < comp._keepTail.length; i++)
                comp.conv.append(comp._keepTail[i])
            comp._keepTail = []
            comp.conv.push({ role: "info", content: I18n.tr("Context compacted.") })
            Qt.callLater(comp.svc.dequeue)
        }
    }
    Timer {
        id: retry
        interval: 2500
        onTriggered: if (comp.compacting) comp._send()
    }
}
