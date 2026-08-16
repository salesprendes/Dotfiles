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
        const enClaro = (v) => {
            if (providerId === "gemini") Settings.aiKeyGemini = v
            else if (providerId === "custom") Settings.aiKeyCustom = v
            else if (providerId === "search") Settings.aiKeySearch = v
            else Settings.aiKeyOpenrouter = v
        }
        if (!keys.haveKeyring) {
            enClaro(k)
            return
        }
        keys._guardar({
            servicio: "quickshell-ai", campo: "provider", valor: providerId,
            secreto: k, etiqueta: "Quickshell IA " + providerId,
            hecho: (bien) => {
                if (bien) {
                    // Ahora SÍ: guardado y comprobado, la copia en claro sobra.
                    enClaro("")
                    keys.keyringWarn = ""
                } else {
                    // El llavero ha fallado. La clave se queda donde el usuario
                    // pueda seguir usándola, y se dice por qué.
                    enClaro(k)
                    keys.keyringWarn = I18n.tr("The system keyring did not accept the key, so it stays in the settings file. Check that a keyring daemon is running.")
                }
            }
        })
    }

    // La del buscador, con el mismo respaldo que las demás: el llavero manda, y
    // si no hay llavero se usa la de Settings.
    readonly property string searchKey:
        keySearch !== "" ? keySearch : Settings.aiKeySearch

    // ¿Hay llavero? Y ojo con la pregunta: NO es "¿está instalado secret-tool?".
    // Esta máquina tiene el binario y NO tiene servicio detrás —el bus contesta
    // "The name is not activatable"—, así que la versión anterior daba llavero
    // por bueno, guardaba en el vacío y, acto seguido, borraba la copia en claro
    // de Settings porque "la fuente de verdad es el llavero". La clave
    // desaparecía. No es un riesgo teórico: se reprodujo aquí.
    //
    // Se pregunta por el SERVICIO, con un ping de D-Bus: sin escribir nada, sin
    // desbloquear nada, sin prompt, y sin leer prosa traducida — solo un código
    // de salida.
    Process {
        running: true
        command: ["sh", "-c",
            'command -v secret-tool >/dev/null 2>&1 || exit 1\n'
            + 'busctl --user call org.freedesktop.secrets /org/freedesktop/secrets '
            + 'org.freedesktop.DBus.Peer Ping >/dev/null 2>&1']
        onExited: (code) => {
            keys.haveKeyring = (code === 0)
            if (keys.haveKeyring) {
                keyLookup.stage = "gemini"
                keyLookup.running = true
            }
        }
    }

    // ── El escribano del llavero ─────────────────────────────────────────────
    // Una cola de UN proceso, con el secreto por la entrada estándar (que es
    // como `secret-tool store` lo espera) y sin ningún `sh -c`: así el nombre
    // del proveedor y —sobre todo— el del servidor SSH viajan como argumentos
    // sueltos y no como texto que un shell va a interpretar. Un host llamado
    // `x"; rm -rf ~; #` era ejecutable antes de esto.
    //
    // Y se ESPERA el resultado. Lo de antes era execDetached: se lanzaba y se
    // daba por hecho. Ahora la copia en claro solo se borra si el guardado ha
    // salido bien, y si ha salido mal se conserva — perder la clave del usuario
    // por un llavero caído es el peor de los desenlaces.
    property var _cola: []
    property var _tarea: null
    property string keyringWarn: ""

    function _guardar(t) {
        keys._cola = keys._cola.concat([t])
        keys._siguiente()
    }
    function _siguiente() {
        if (keys._tarea !== null || keys._cola.length === 0)
            return
        const t = keys._cola[0]
        keys._cola = keys._cola.slice(1)
        keys._tarea = t
        guarda.command = t.secreto === ""
            ? ["secret-tool", "clear", "service", t.servicio, t.campo, t.valor]
            : ["secret-tool", "store", "--label", t.etiqueta,
               "service", t.servicio, t.campo, t.valor]
        guarda.stdinEnabled = t.secreto !== ""
        guarda.running = true
    }
    readonly property Process _guarda: Process {
        id: guarda
        onStarted: {
            if (keys._tarea && keys._tarea.secreto !== "") {
                guarda.write(keys._tarea.secreto)
                guarda.stdinEnabled = false
            }
        }
        onExited: (code) => {
            const t = keys._tarea
            keys._tarea = null
            if (t && t.hecho)
                t.hecho(code === 0)
            keys._siguiente()
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
        // Aquí el nombre lo escribe el usuario y antes se interpolaba dentro de
        // un `sh -c`: un host llamado `x"; rm -rf ~; #` era un comando. Ahora va
        // como argumento suelto y no hay shell que interpretar.
        if (haveKeyring)
            keys._guardar({ servicio: "quickshell-ai-ssh", campo: "host",
                            valor: name, secreto: pw,
                            etiqueta: "Quickshell SSH " + name })
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
