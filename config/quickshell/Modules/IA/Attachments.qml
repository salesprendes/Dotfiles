import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "TextUtils.js" as TU

// Lo que el usuario ADJUNTA desde el escritorio antes de enviar: portapapeles,
// selección, captura de pantalla y las referencias @ruta del mensaje.
//
// Vive aquí y no en el panel porque el panel se destruye al cerrar (PanelSlot) y
// una captura CIERRA el panel: si el borrador y los adjuntos colgaran de la
// interfaz, hacer una captura los perdería justo al hacerla.
Scope {
    id: att

    property var svc

    property var pendingAtts: []        // [{kind: text|image, label, data}]

    function addText(label, text) {
        const t = String(text).trim().slice(0, 8000)
        if (t === "")
            return
        att.pendingAtts = att.pendingAtts.concat([{ kind: "text", label: label, data: t }])
    }
    function removeAt(i) {
        const a = att.pendingAtts.slice()
        a.splice(i, 1)
        att.pendingAtts = a
    }

    function attachClipboard() { clip.primary = false; clip.running = true }
    function attachSelection() { clip.primary = true; clip.running = true }
    Process {
        id: clip
        property bool primary: false
        command: primary ? ["wl-paste", "-p", "-n"] : ["wl-paste", "-n"]
        stdout: StdioCollector { id: clipOut }
        onExited: (code) => {
            if (code === 0)
                att.addText(clip.primary ? I18n.tr("Selection") : I18n.tr("Clipboard"),
                            clipOut.text)
        }
    }

    // Captura: cierra el panel (saldría en la foto), espera a que se desvanezca,
    // captura el monitor donde vivía y reabre con la imagen ya adjunta. El
    // borrador sobrevive porque vive fuera del panel.
    property string _monitor: ""
    function attachScreenshot() {
        const scr = Globals.focusedScreen()
        att._monitor = scr ? scr.name : ""
        Globals.closeAll()
        delay.restart()
    }
    Timer {
        id: delay
        interval: 400
        onTriggered: shot.running = true
    }
    Process {
        id: shot
        command: ["sh", "-c", att._monitor !== ""
            ? 'grim -o "$QS_MON" - | base64 -w0'
            : "grim - | base64 -w0"]
        environment: ({ QS_MON: att._monitor })
        stdout: StdioCollector { id: shotOut }
        onExited: (code) => {
            const b64 = (shotOut.text || "").trim()
            if (code === 0 && b64 !== "")
                att.pendingAtts = att.pendingAtts.concat([{
                    kind: "image", label: I18n.tr("Screenshot"), data: b64 }])
            Globals.open("ai")
        }
    }

    // ── Referencias @ruta en el mensaje (idea de gemini-cli) ─────────────────
    // "arregla @~/.config/quickshell/Bar/Bar.qml" adjunta el archivo sin tener
    // que pedirle al agente que lo lea: un paso menos, y el contenido llega ya en
    // el primer turno. Lo que no exista o se salga de la carpeta personal se deja
    // tal cual, como texto — una @ que no era una ruta es simplemente texto.
    property var _pending: null         // {text, atts} esperando la expansión

    // Devuelve true si hay expansión en marcha (el envío se reanuda solo al
    // terminar, con el texto ya completo).
    function expand(text) {
        if (_pending !== null)
            return false
        const refs = TU.atRefs(text)
        if (refs.length === 0)
            return false
        _pending = { text: String(text), atts: pendingAtts }
        // Las rutas viajan por ENTORNO (una por línea) y el bucle las lee de ahí:
        // nada se interpola en la línea de comandos, así un nombre de archivo raro
        // no puede convertirse en otra orden. La tilde la expande el propio
        // harness, no el shell.
        const home = Quickshell.env("HOME")
        const abs = refs.map(r => r === "~" ? home
                                : r.startsWith("~/") ? home + r.slice(1) : r)
        refProc.command = ["sh", "-c",
            'printf %s "$QS_REFS" | while IFS= read -r p; do '
            + '[ -f "$p" ] || continue; '
            + 'printf "\\n\\n--- %s ---\\n" "$p"; head -c 20000 -- "$p"; done']
        refProc.environment = ({ QS_REFS: abs.join("\n") + "\n" })
        refProc.running = true
        return true
    }

    Process {
        id: refProc
        stdout: StdioCollector { id: refOut }
        onExited: {
            const p = att._pending
            att._pending = null
            if (!p)
                return
            att.pendingAtts = p.atts
            att.svc.sendExpanded(p.text + (refOut.text || ""))
        }
    }
}
