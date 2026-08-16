import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// El LLAVERO del asistente: todo lo que es secreto, en un solo sitio. Claves de
// API de los proveedores y contraseñas de los servidores SSH.
//
// Con secret-tool disponible viven en el llavero del sistema (Secret Service),
// las de API bajo service=quickshell-ai y las de SSH bajo
// service=quickshell-ai-ssh; settings.json se queda sin ellas (las que hubiera
// se MIGRAN al primer arranque). Sin llavero, todo funciona como antes contra
// Settings.
//
// El secreto viaja SIEMPRE por entorno y stdin, jamás en argv — que es visible
// en `ps` para cualquier proceso del equipo. Esa es la razón de que aquí no
// haya ni un solo `secret-tool store <clave>`.
Scope {
    id: keys

    // ── Claves de API ────────────────────────────────────────────────────────
    property bool haveKeyring: false
    property string keyGemini: ""
    property string keyOpenrouter: ""
    property string keyCustom: ""
    // La del BUSCADOR (Brave o Tavily). No es la de un proveedor de modelos,
    // pero es un secreto que viaja a un servidor ajeno: mismo llavero, mismas
    // reglas — nunca en argv, nunca en el chat.
    property string keySearch: ""

    // La del proveedor activo: la del llavero si la hay, y si no la de Settings
    // (instalaciones sin llavero, o antes de que termine la migración).
    readonly property string apiKey:
        Settings.aiProvider === "openrouter"
            ? (keyOpenrouter !== "" ? keyOpenrouter : Settings.aiKeyOpenrouter)
        : Settings.aiProvider === "gemini"
            ? (keyGemini !== "" ? keyGemini : Settings.aiKeyGemini)
        : Settings.aiProvider === "custom"
            ? (keyCustom !== "" ? keyCustom : Settings.aiKeyCustom)
            : ""

    function setKey(providerId, key) {
        const k = String(key).trim()
        if (providerId === "gemini") keys.keyGemini = k
        else if (providerId === "custom") keys.keyCustom = k
        else if (providerId === "search") keys.keySearch = k
        else keys.keyOpenrouter = k
        if (keys.haveKeyring) {
            // Vacío = borrar la entrada.
            if (k === "")
                Quickshell.execDetached(["secret-tool", "clear",
                                         "service", "quickshell-ai", "provider", providerId])
            else
                Quickshell.execDetached({
                    command: ["sh", "-c",
                        'printf %s "$QS_AI_KEY" | secret-tool store --label "Quickshell IA ' + providerId
                        + '" service quickshell-ai provider ' + providerId],
                    environment: { QS_AI_KEY: k }
                })
            // El fallback en claro se limpia: la fuente de verdad es el llavero.
            if (providerId === "gemini") Settings.aiKeyGemini = ""
            else if (providerId === "custom") Settings.aiKeyCustom = ""
            else if (providerId === "search") Settings.aiKeySearch = ""
            else Settings.aiKeyOpenrouter = ""
        } else {
            if (providerId === "gemini") Settings.aiKeyGemini = k
            else if (providerId === "custom") Settings.aiKeyCustom = k
            else if (providerId === "search") Settings.aiKeySearch = k
            else Settings.aiKeyOpenrouter = k
        }
    }

    // La del buscador, con el mismo respaldo que las demás: el llavero manda, y
    // si no hay llavero se usa la de Settings.
    readonly property string searchKey:
        keySearch !== "" ? keySearch : Settings.aiKeySearch

    Process {
        running: true
        command: ["sh", "-c", "command -v secret-tool"]
        onExited: (code) => {
            keys.haveKeyring = (code === 0)
            if (keys.haveKeyring) {
                keyLookup.stage = "gemini"
                keyLookup.running = true
            }
        }
    }
    // Las cuatro claves se leen EN CADENA (cada una arranca la siguiente al
    // terminar) en vez de con cuatro procesos a la vez: son consultas al
    // mismo demonio y encadenarlas evita despertarlo por triplicado en el
    // arranque, que es justo el momento en que el escritorio tiene prisa.
    Process {
        id: keyLookup
        property string stage: "gemini"
        command: ["secret-tool", "lookup", "service", "quickshell-ai", "provider", stage]
        stdout: StdioCollector { id: keyOut }
        onExited: {
            const k = (keyOut.text || "").trim()
            if (keyLookup.stage === "gemini") {
                if (k !== "") keys.keyGemini = k
                else if (Settings.aiKeyGemini !== "")
                    keys.setKey("gemini", Settings.aiKeyGemini)   // migración
                keyLookup.stage = "openrouter"
                keyLookup.running = true
            } else if (keyLookup.stage === "openrouter") {
                if (k !== "") keys.keyOpenrouter = k
                else if (Settings.aiKeyOpenrouter !== "")
                    keys.setKey("openrouter", Settings.aiKeyOpenrouter)
                keyLookup.stage = "custom"
                keyLookup.running = true
            } else if (keyLookup.stage === "custom") {
                if (k !== "") keys.keyCustom = k
                else if (Settings.aiKeyCustom !== "")
                    keys.setKey("custom", Settings.aiKeyCustom)
                keyLookup.stage = "search"
                keyLookup.running = true
            } else {
                if (k !== "") keys.keySearch = k
                else if (Settings.aiKeySearch !== "")
                    keys.setKey("search", Settings.aiKeySearch)
            }
        }
    }

    // ── Contraseñas de servidores ────────────────────────────────────────────
    // En memoria de sesión (cargadas del llavero al arrancar, o escritas en
    // Ajustes). El argumento 'password' de una llamada las pisa para el caso
    // "te la escribo en el mensaje".
    property var sshPass: ({})

    // ¿Está sshpass? Sin él, el login por contraseña no es posible y conviene
    // decirlo claro en vez de dejar que el Process falle con "command not
    // found".
    property bool haveSshpass: false

    Process {
        running: true
        command: ["sh", "-c", "command -v sshpass"]
        onExited: (code) => keys.haveSshpass = (code === 0)
    }

    function setSshPassword(name, pw) {
        const m = Object.assign({}, sshPass)
        if (pw === "") delete m[name]; else m[name] = pw
        sshPass = m
        if (haveKeyring) {
            if (pw === "")
                Quickshell.execDetached(["secret-tool", "clear",
                    "service", "quickshell-ai-ssh", "host", name])
            else
                Quickshell.execDetached({ command: ["sh", "-c",
                    'printf %s "$QS_PW" | secret-tool store --label "Quickshell SSH ' + name
                    + '" service quickshell-ai-ssh host ' + name],
                    environment: { QS_PW: pw } })
        }
    }

    // Carga de contraseñas del llavero, una por host registrado.
    Instantiator {
        model: Settings.aiSshHosts
        delegate: Process {
            readonly property string hn: (modelData && modelData.name) || ""
            running: keys.haveKeyring && hn !== ""
            command: ["secret-tool", "lookup", "service", "quickshell-ai-ssh", "host", hn]
            stdout: StdioCollector { id: spOut }
            onExited: {
                const k = (spOut.text || "").trim()
                if (k !== "") {
                    const m = Object.assign({}, keys.sshPass)
                    m[hn] = k
                    keys.sshPass = m
                }
            }
        }
    }
}
