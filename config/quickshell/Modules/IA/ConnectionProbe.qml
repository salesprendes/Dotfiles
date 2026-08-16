import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// La SONDA de conexión y el catálogo de modelos del servidor.
//
// Una sola llamada resuelve las dos preguntas que importan con un servidor
// REMOTO: ¿contesta y me acepta la credencial?, ¿qué modelos sirve? Es un GET
// al catálogo del proveedor midiendo código HTTP y latencia. Antes los modelos
// de Ollama salían de `ollama list` (solo servía para el Ollama de esta
// máquina); ahora se piden por HTTP, así que un Ollama remoto se descubre igual
// que uno local.
Scope {
    id: probe

    // El harness. De él salen la URL del catálogo, las credenciales y las
    // opciones de red: lo que prueba el botón "Probar" es EXACTAMENTE lo que va
    // a viajar después en una conversación.
    property var svc

    property string connState: "idle"    // idle | probing | ok | fail
    property string connDetail: ""       // qué pasó, en una línea
    property int    connMs: 0            // latencia del ida y vuelta
    property int    connModels: 0        // modelos que publica el servidor
    property real   _t0: 0

    // Catálogo por proveedor descubierto EN EL SERVIDOR: mapa id → [modelos].
    // Con un servidor remoto no hay forma de adivinar qué sirve, así que el
    // propio servidor lo dice.
    property var fetchedModels: ({})

    function test() {
        if (proc.running || svc.modelsUrl === "")
            return
        probe.connState = "probing"
        probe.connDetail = ""
        probe._t0 = Date.now()
        proc.forProvider = Settings.aiProvider
        // La clave sale del argv también aquí: es pequeña y la petición no lleva
        // cuerpo, pero /proc/<pid>/cmdline lo lee cualquiera igual.
        const t = svc.probeCommand()
        proc.command = t.cmd
        proc.environment = t.env
        proc.running = true
    }

    Process {
        id: proc
        property string forProvider: ""
        stdout: StdioCollector { id: out }
        onExited: (code) => {
            probe.connMs = Date.now() - probe._t0
            const raw = (out.text || "")
            const cut = raw.lastIndexOf("__QS ")
            const status = cut >= 0 ? parseInt(raw.slice(cut + 5).trim()) || 0 : 0
            const body = cut >= 0 ? raw.slice(0, cut) : raw

            if (code !== 0) {
                probe.connState = "fail"
                probe.connDetail = code === 6 ? I18n.tr("Host not found")
                              : code === 7 ? I18n.tr("Server unreachable")
                              : code === 28 ? I18n.tr("Timed out")
                              : code === 60 ? I18n.tr("TLS certificate not trusted")
                              : I18n.tr("Connection failed (curl exit %1)").arg(code)
                return
            }
            if (status >= 400) {
                probe.connState = "fail"
                probe.connDetail = (status === 401 || status === 403)
                    ? I18n.tr("Rejected credentials (HTTP %1)").arg(status)
                    : status === 404
                    ? I18n.tr("No catalog at %1 (HTTP 404)").arg(probe.svc.modelsUrl)
                    : I18n.tr("Server error (HTTP %1)").arg(status)
                return
            }

            // El catálogo llega en dos formatos: {data:[{id}]} del contrato
            // OpenAI y {models:[{name}]} de Ollama.
            let names = []
            try {
                const j = JSON.parse(body)
                if (Array.isArray(j.data))
                    names = j.data.map(m => String(m.id || m.name || "")).filter(s => s !== "")
                else if (Array.isArray(j.models))
                    names = j.models.map(m => String(m.name || m.model || "")).filter(s => s !== "")
            } catch (e) {}

            // Contesta 200 pero sin catálogo: casi siempre es la URL de un panel
            // web, no la raíz /v1 de la API. Decirlo así ahorra el "no funciona"
            // sin pista.
            if (names.length === 0) {
                probe.connState = "fail"
                probe.connDetail = I18n.tr("Answered, but published no models — is that the /v1 base?")
                return
            }
            // OpenRouter publica cientos: el desplegable se queda con los
            // gratuitos (más el que ya usas, que lo añade el catálogo agrupado).
            if (proc.forProvider === "openrouter")
                names = names.filter(n => n.endsWith(":free"))
            names.sort()
            const map = Object.assign({}, probe.fetchedModels)
            map[proc.forProvider] = names
            probe.fetchedModels = map
            probe.connModels = names.length
            probe.connState = "ok"
            probe.connDetail = ""
            // Servidor nuevo sin modelo elegido: se adopta el primero que
            // publique, para no obligar a copiar un id a mano.
            if (probe.svc.model === "" && names.length > 0)
                probe.svc.setModel(names[0])
        }
    }

    // Sonda automática con freno: cambiar de proveedor, pegar una URL o teclear
    // la clave dispara UNA comprobación cuando la mano se para.
    readonly property string _key:
        Settings.aiProvider + "|" + (svc ? svc.modelsUrl : "") + "|"
        + (svc ? svc.apiKey : "") + "|" + Settings.aiCustomHeader
        + "|" + Settings.aiInsecureTls
    on_KeyChanged: {
        probe.connState = "idle"
        probe.connDetail = ""
        if (svc && svc.modelsUrl !== "" && !svc.keyMissing)
            debounce.restart()
    }
    Timer {
        id: debounce
        interval: 1200
        onTriggered: probe.test()
    }
    Component.onCompleted:
        if (svc && svc.modelsUrl !== "" && !svc.keyMissing)
            debounce.restart()
}
