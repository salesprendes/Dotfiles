pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Harness del asistente IA. La idea (tomada de la capa "aisuite" que usa
// OpenWorker) es que el panel no sepa NADA de proveedores: todos hablan el
// /chat/completions de OpenAI con streaming SSE, y aquí solo cambian URL,
// credencial y modelo. Transporte por curl -N leído con SplitParser; un
// Process es además trivial de cancelar (SIGTERM), que es la mitad de un
// harness decente.
//
// Qué añade esta versión sobre el chat básico:
//   · CONVERSACIONES: varias, con título, persistidas en ai-history.json.
//   · ADJUNTOS del escritorio: portapapeles y selección (texto), captura de
//     pantalla (visión, si el modelo la tiene).
//   · HERRAMIENTAS con aprobación (estilo OpenWorker): el modelo puede
//     proponer run_command / open_url; NADA corre sin que el usuario apruebe
//     la tarjeta. El resultado vuelve al modelo y la conversación sigue.
//   · CLAVES EN EL LLAVERO del sistema (secret-tool) en vez de settings.json;
//     si no hay llavero, cae al comportamiento anterior.
//   · PERSONAS: el estilo de respuesta es un ajuste, no un prompt a mano.
Singleton {
    id: ai

    // ── Proveedores y modelos ────────────────────────────────────────────────
    readonly property var providers: ({
        gemini: {
            label: "Gemini",
            url: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            needsKey: true
        },
        openrouter: {
            label: "OpenRouter",
            url: "https://openrouter.ai/api/v1/chat/completions",
            needsKey: true
        },
        ollama: {
            label: "Ollama",
            url: "",            // la URL base la pone el usuario (aiOllamaUrl)
            needsKey: false
        },
        // Cualquier servidor OpenAI-compatible (llama.cpp, LM Studio, vLLM…):
        // URL base /v1 configurable y clave OPCIONAL (needsKey false: sin
        // clave no se bloquea el envío; si la pones, viaja como Bearer).
        custom: {
            label: "LLM",
            url: "",
            needsKey: false
        }
    })

    readonly property var provider: providers[Settings.aiProvider] || providers.gemini
    readonly property string model:
        Settings.aiProvider === "openrouter" ? Settings.aiModelOpenrouter
        : Settings.aiProvider === "ollama"   ? Settings.aiModelOllama
        : Settings.aiProvider === "custom"   ? Settings.aiModelCustom
                                             : Settings.aiModelGemini
    readonly property string endpoint: {
        if (Settings.aiProvider === "ollama")
            return Settings.aiOllamaUrl.replace(/\/+$/, "") + "/v1/chat/completions"
        if (Settings.aiProvider === "custom") {
            // La base puede venir con o sin /v1: se normaliza, no se exige.
            let base = Settings.aiCustomUrl.replace(/\/+$/, "")
            if (!base.endsWith("/v1"))
                base += "/v1"
            return base + "/chat/completions"
        }
        return provider.url
    }

    // Acepta la sintaxis "proveedor:modelo" de aisuite: "ollama:qwen3" cambia
    // proveedor Y modelo en un gesto. Sin prefijo conocido, es solo el modelo
    // del proveedor actual (los ":free" de OpenRouter no chocan: el prefijo
    // se compara contra el catálogo de proveedores).
    function setModel(m) {
        let target = Settings.aiProvider
        let name = String(m).trim()
        const colon = name.indexOf(":")
        if (colon > 0) {
            const prefix = name.slice(0, colon)
            if (providers[prefix]) {
                target = prefix
                name = name.slice(colon + 1)
            }
        }
        if (target === "openrouter")
            Settings.aiModelOpenrouter = name
        else if (target === "ollama")
            Settings.aiModelOllama = name
        else if (target === "custom")
            Settings.aiModelCustom = name
        else
            Settings.aiModelGemini = name
        Settings.aiProvider = target
    }

    // Modelos instalados en Ollama (detectados con `ollama list`; vacío si no
    // está instalado) y catálogo razonable para los de nube. El elegido
    // actual siempre entra en la lista aunque sea un id escrito a mano.
    property var ollamaModels: []
    readonly property var modelOptions: {
        let base
        if (Settings.aiProvider === "ollama")
            base = ollamaModels
        else if (Settings.aiProvider === "openrouter")
            base = ["qwen/qwen3-30b-a3b:free", "qwen/qwen3-14b:free",
                    "deepseek/deepseek-chat-v3-0324:free",
                    "meta-llama/llama-3.3-70b-instruct:free"]
        else
            base = ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5-pro",
                    "gemini-2.0-flash"]
        const out = base.slice()
        if (ai.model !== "" && out.indexOf(ai.model) === -1)
            out.unshift(ai.model)
        const opts = out.map(m => ({ text: m, value: m }))
        // Cola del desplegable: el modelo vigente de los OTROS proveedores,
        // en sintaxis proveedor:modelo — cambiar de cerebro entre nubes (o a
        // local) sin pasar por la config.
        const ids = ["gemini", "openrouter", "ollama", "custom"]
        for (let i = 0; i < ids.length; i++) {
            if (ids[i] === Settings.aiProvider)
                continue
            const other = ids[i] === "openrouter" ? Settings.aiModelOpenrouter
                        : ids[i] === "ollama" ? Settings.aiModelOllama
                        : ids[i] === "custom" ? Settings.aiModelCustom
                        : Settings.aiModelGemini
            if (other !== "")
                opts.push({ text: ids[i] + ":" + other, value: ids[i] + ":" + other })
        }
        return opts
    }

    // Política efectiva de una herramienta (estilo aisuite): el mapa de
    // Ajustes manda; el interruptor antiguo de auto-lectura sigue contando
    // como "auto" para leer/listar (nada se rompe hacia atrás).
    function toolPolicy(name) {
        const p = (Settings.aiToolPolicies || {})[name] || "ask"
        if (p === "ask" && Settings.aiAutoRead
                && (name === "read_file" || name === "list_dir"))
            return "auto"
        return p
    }

    // ── Claves: llavero del sistema ──────────────────────────────────────────
    // Con secret-tool disponible, las claves viven en el llavero (Secret
    // Service) bajo service=quickshell-ai; settings.json se queda sin ellas
    // (las que hubiera se MIGRAN al primer arranque). Sin llavero, todo
    // funciona como antes contra Settings.
    property bool haveKeyring: false
    property string keyGemini: ""
    property string keyOpenrouter: ""
    property string keyCustom: ""

    readonly property string apiKey:
        Settings.aiProvider === "openrouter"
            ? (keyOpenrouter !== "" ? keyOpenrouter : Settings.aiKeyOpenrouter)
        : Settings.aiProvider === "gemini"
            ? (keyGemini !== "" ? keyGemini : Settings.aiKeyGemini)
        : Settings.aiProvider === "custom"
            ? (keyCustom !== "" ? keyCustom : Settings.aiKeyCustom)
            : ""
    readonly property bool keyMissing: provider.needsKey && apiKey === ""

    function setKey(providerId, key) {
        const k = String(key).trim()
        if (providerId === "gemini") ai.keyGemini = k
        else if (providerId === "custom") ai.keyCustom = k
        else ai.keyOpenrouter = k
        if (ai.haveKeyring) {
            // El secreto viaja por entorno y stdin, nunca en argv (visible
            // en `ps`). Vacío = borrar la entrada.
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
            else Settings.aiKeyOpenrouter = ""
        } else {
            if (providerId === "gemini") Settings.aiKeyGemini = k
            else if (providerId === "custom") Settings.aiKeyCustom = k
            else Settings.aiKeyOpenrouter = k
        }
    }

    Process {
        id: keyringCheck
        running: true
        command: ["sh", "-c", "command -v secret-tool"]
        onExited: (code) => {
            ai.haveKeyring = (code === 0)
            if (ai.haveKeyring) {
                keyLookup.stage = "gemini"
                keyLookup.running = true
            }
        }
    }
    Process {
        id: keyLookup
        property string stage: "gemini"
        command: ["secret-tool", "lookup", "service", "quickshell-ai", "provider", stage]
        stdout: StdioCollector { id: keyOut }
        onExited: {
            const k = (keyOut.text || "").trim()
            if (keyLookup.stage === "gemini") {
                if (k !== "") ai.keyGemini = k
                else if (Settings.aiKeyGemini !== "")
                    ai.setKey("gemini", Settings.aiKeyGemini)   // migración
                keyLookup.stage = "openrouter"
                keyLookup.running = true
            } else if (keyLookup.stage === "openrouter") {
                if (k !== "") ai.keyOpenrouter = k
                else if (Settings.aiKeyOpenrouter !== "")
                    ai.setKey("openrouter", Settings.aiKeyOpenrouter)
                keyLookup.stage = "custom"
                keyLookup.running = true
            } else {
                if (k !== "") ai.keyCustom = k
                else if (Settings.aiKeyCustom !== "")
                    ai.setKey("custom", Settings.aiKeyCustom)
            }
        }
    }

    // Detección de modelos locales.
    Process {
        id: ollamaList
        running: true
        command: ["sh", "-c", "command -v ollama >/dev/null && ollama list || true"]
        stdout: StdioCollector { id: ollamaOut }
        onExited: {
            const lines = (ollamaOut.text || "").split("\n")
            const names = []
            for (let i = 1; i < lines.length; i++) {     // salta la cabecera
                const n = lines[i].trim().split(/\s+/)[0]
                if (n) names.push(n)
            }
            ai.ollamaModels = names
        }
    }

    // ── Conversaciones ───────────────────────────────────────────────────────
    // La activa vive en 'messages' (ListModel: append añade UNA burbuja en
    // vez de reconstruirlas todas). El resto, serializadas en 'conversations'
    // y persistidas en disco. Roles de cada fila — siempre todos, que un
    // ListModel fija los roles con la primera fila:
    //   role: user | assistant | error | tool
    //   content, reasoning, modelName, ms, tokens
    //   toolName, toolArgs, toolId, toolResult, toolStatus (pending|done|rejected)
    //   attachNote: etiqueta de adjuntos ("captura", …) para pintarla en la burbuja
    property ListModel messages: ListModel {}
    property var conversations: []      // [{id, title, updated, entries:[…]}]
    property string currentId: ""
    property bool busy: false
    property string streamBuf: ""
    property string reasonBuf: ""

    // ── Contadores del harness ───────────────────────────────────────────────
    // Pasos de herramienta del turno en curso. Con la auto-aprobación de
    // lecturas activa, un modelo en bucle podría encadenar 'ls' para siempre:
    // pasado el tope, la tarjeta se queda pendiente y decide el humano (el
    // límite de turnos de Claude Code / Cline, en pequeño).
    property int toolRounds: 0
    readonly property int maxToolRounds: 8

    // Totales de la conversación (los muestra el cajón, estilo aider).
    property int convTokens: 0
    property real convMs: 0
    // Llenado aproximado del contexto que viaja al modelo (0..1), contra el
    // presupuesto de ~20k caracteres del recorte.
    property real contextFill: 0

    function _recountTotals() {
        let tok = 0, ms = 0, chars = 0
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i)
            tok += m.tokens
            ms += m.ms
            if (m.role === "user" || m.role === "assistant")
                chars += m.content.length
        }
        convTokens = tok
        convMs = ms
        contextFill = Math.min(1, chars / 20000)
    }

    // Cola de envío: puedes seguir escribiendo mientras responde; lo tuyo
    // sale en cuanto termina (la cola de mensajes de Claude Code).
    property var sendQueue: []
    function _dequeue() {
        if (busy || sendQueue.length === 0)
            return
        const q = sendQueue[0]
        sendQueue = sendQueue.slice(1)
        pendingAtts = q.atts
        send(q.text)
    }

    // Borrador y adjuntos pendientes: viven aquí y no en el panel, porque el
    // panel se destruye al cerrar (PanelSlot) y una captura CIERRA el panel.
    property string draft: ""
    property var pendingAtts: []        // [{kind: text|image, label, data}]

    readonly property var _liveSplit: splitThink(streamBuf)
    readonly property string liveText: _liveSplit.text
    readonly property string liveThink: (reasonBuf + _liveSplit.think).trim()

    signal replied()
    // El panel escucha esto para poner el texto a editar en la entrada.
    signal editRequest(string text)

    // ── Prompt de sistema y personas ─────────────────────────────────────────
    readonly property var personas: ({
        normal:   "",
        concise:  " Responde en el mínimo de palabras que resuelva la duda; sin preámbulos ni cierres.",
        teacher:  " Explica como un buen profesor: paso a paso, con un ejemplo corto cuando ayude.",
        reviewer: " Actúa como revisor de código: señala problemas concretos (correctitud, seguridad, rendimiento) antes que estilo, y propone el arreglo."
    })
    // Memoria persistente entre conversaciones (estilo OpenWorker): notas que
    // el modelo guarda con la herramienta 'remember' (aprobada por el usuario)
    // y que se inyectan en el prompt de sistema. Editable desde la config.
    readonly property var memoryList: mem.notes || []
    function removeMemory(i) {
        const n = (mem.notes || []).slice()
        n.splice(i, 1)
        mem.notes = n
    }
    readonly property string _memoryBlock: {
        const n = mem.notes || []
        if (n.length === 0)
            return ""
        let block = "\nMemoria del usuario (notas que él aprobó guardar):"
        let chars = 0
        for (let i = 0; i < n.length; i++) {
            chars += n[i].length
            if (chars > 2000)
                break
            block += "\n- " + n[i]
        }
        return block
    }

    readonly property bool agentMode: Settings.aiMode === "agent"

    readonly property string systemPrompt:
        "Eres un asistente integrado en el escritorio Linux del usuario "
        + "(Arch + Hyprland + Quickshell). Fecha actual: "
        + new Date().toLocaleDateString(Qt.locale(), "yyyy-MM-dd") + ". "
        + "Idioma de la interfaz: " + Settings.language + " (responde en el "
        + "idioma del usuario). Usa Markdown; código en bloques ```. No "
        + "inventes: si no sabes algo, dilo."
        + (agentMode
            ? " Estás en modo AGENTE: dispones de herramientas (ejecutar "
              + "comandos, leer/listar/escribir archivos, abrir URLs, guardar "
              + "notas en memoria). Para tareas de varios pasos, enuncia un "
              + "plan breve y ve herramienta a herramienta; cada llamada la "
              + "aprueba el usuario a mano. Los entregables (informes, "
              + "scripts) escríbelos como archivo con write_file."
            : " Estás en modo CHAT, sin herramientas: solo conversación.")
        + (personas[Settings.aiPersona] || "")
        + (Settings.aiCustomPrompt.trim() !== ""
            ? "\nInstrucciones del usuario: " + Settings.aiCustomPrompt.trim() : "")
        + _memoryBlock

    // Las herramientas que el modelo puede PROPONER en modo agente. Ejecutar,
    // solo tras aprobación expresa (ver approveTool) — salvo las de solo
    // lectura si el usuario activó la auto-aprobación.
    readonly property var toolDefs: [
        { type: "function", "function": {
            name: "run_command",
            description: "Ejecuta un comando de shell (sh) en el equipo del usuario y devuelve su salida.",
            parameters: { type: "object",
                properties: { command: { type: "string", description: "Comando sh a ejecutar" } },
                required: ["command"] } } },
        { type: "function", "function": {
            name: "open_url",
            description: "Abre una URL en el navegador del usuario.",
            parameters: { type: "object",
                properties: { url: { type: "string" } },
                required: ["url"] } } },
        { type: "function", "function": {
            name: "read_file",
            description: "Lee un archivo de texto de la carpeta personal del usuario (máx. 16 kB).",
            parameters: { type: "object",
                properties: { path: { type: "string", description: "Ruta, admite ~" } },
                required: ["path"] } } },
        { type: "function", "function": {
            name: "list_dir",
            description: "Lista el contenido de una carpeta de la carpeta personal del usuario.",
            parameters: { type: "object",
                properties: { path: { type: "string" } },
                required: ["path"] } } },
        { type: "function", "function": {
            name: "write_file",
            description: "Escribe un archivo de texto dentro de la carpeta personal del usuario (entregables: informes, scripts, notas). Sobrescribe si existe.",
            parameters: { type: "object",
                properties: { path: { type: "string" },
                              content: { type: "string" } },
                required: ["path", "content"] } } },
        { type: "function", "function": {
            name: "remember",
            description: "Guarda una nota corta en la memoria persistente del asistente (preferencias del usuario, datos útiles entre conversaciones).",
            parameters: { type: "object",
                properties: { note: { type: "string" } },
                required: ["note"] } } }
    ]

    // Separa el razonamiento <think>…</think> (Qwen y compañía) del texto.
    function splitThink(raw) {
        const open = raw.indexOf("<think>")
        if (open === -1)
            return { think: "", text: raw }
        const close = raw.indexOf("</think>", open)
        if (close === -1)
            return { think: raw.slice(open + 7), text: raw.slice(0, open) }
        return { think: raw.slice(open + 7, close),
                 text: raw.slice(0, open) + raw.slice(close + 8) }
    }

    // ── Operaciones de conversación ──────────────────────────────────────────
    function stop() {
        if (streamProc.running)
            streamProc.running = false
    }

    function newConversation() {
        stop()
        _snapshotCurrent()
        messages.clear()
        currentId = String(Date.now())
        _compactWarned = false
        _saveHistory()
    }

    function switchTo(id) {
        if (id === currentId)
            return
        stop()
        _snapshotCurrent()
        const c = conversations.find(x => x.id === id)
        if (!c)
            return
        currentId = id
        messages.clear()
        for (let i = 0; i < c.entries.length; i++)
            _append(c.entries[i])
        _compactWarned = false
        _saveHistory()
    }

    function deleteConversation(id) {
        conversations = conversations.filter(x => x.id !== id)
        if (id === currentId) {
            stop()
            messages.clear()
            currentId = String(Date.now())
        }
        _saveHistory()
    }

    // Borra un mensaje suelto.
    function removeAt(index) {
        if (index >= 0 && index < messages.count) {
            messages.remove(index)
            _saveHistory()
        }
    }

    // Editar: recupera el texto de ese mensaje de usuario, lo quita junto a
    // todo lo posterior (la respuesta que provocó ya no vale) y se lo da al
    // panel para reescribirlo.
    function beginEdit(index) {
        if (busy || index < 0 || index >= messages.count)
            return
        const m = messages.get(index)
        if (m.role !== "user")
            return
        const text = m.content
        while (messages.count > index)
            messages.remove(messages.count - 1)
        _saveHistory()
        editRequest(text)
    }

    // ↑ en la entrada vacía: editar el último mensaje propio.
    function editLast() {
        for (let i = messages.count - 1; i >= 0; i--)
            if (messages.get(i).role === "user") {
                beginEdit(i)
                return
            }
    }

    // ── Adjuntos ─────────────────────────────────────────────────────────────
    function addTextAttachment(label, text) {
        const t = String(text).trim().slice(0, 8000)
        if (t === "")
            return
        ai.pendingAtts = ai.pendingAtts.concat([{ kind: "text", label: label, data: t }])
    }
    function removeAttachment(i) {
        const a = ai.pendingAtts.slice()
        a.splice(i, 1)
        ai.pendingAtts = a
    }

    function attachClipboard() { clipProc.primary = false; clipProc.running = true }
    function attachSelection() { clipProc.primary = true; clipProc.running = true }
    Process {
        id: clipProc
        property bool primary: false
        command: primary ? ["wl-paste", "-p", "-n"] : ["wl-paste", "-n"]
        stdout: StdioCollector { id: clipOut }
        onExited: (code) => {
            if (code === 0)
                ai.addTextAttachment(clipProc.primary ? I18n.tr("Selection")
                                                      : I18n.tr("Clipboard"),
                                     clipOut.text)
        }
    }

    // Captura: cierra el panel (saldría en la foto), espera a que se
    // desvanezca, captura el monitor donde vivía y reabre con la imagen ya
    // adjunta. El borrador sobrevive porque vive aquí.
    property string _shotMonitor: ""
    function attachScreenshot() {
        const scr = Globals.focusedScreen()
        ai._shotMonitor = scr ? scr.name : ""
        Globals.closeAll()
        shotDelay.restart()
    }
    Timer {
        id: shotDelay
        interval: 400
        onTriggered: shotProc.running = true
    }
    Process {
        id: shotProc
        command: ["sh", "-c", ai._shotMonitor !== ""
            ? 'grim -o "$QS_MON" - | base64 -w0'
            : "grim - | base64 -w0"]
        environment: ({ QS_MON: ai._shotMonitor })
        stdout: StdioCollector { id: shotOut }
        onExited: (code) => {
            const b64 = (shotOut.text || "").trim()
            if (code === 0 && b64 !== "")
                ai.pendingAtts = ai.pendingAtts.concat([{
                    kind: "image", label: I18n.tr("Screenshot"), data: b64 }])
            Globals.open("ai")
        }
    }

    // ── Envío ────────────────────────────────────────────────────────────────
    property var _sendImages: []        // imágenes del turno EN CURSO

    function send(text) {
        let t = String(text).trim()
        if (busy) {
            // Ocupado no es "no": el mensaje espera su turno.
            if (t !== "" || pendingAtts.length > 0) {
                sendQueue = sendQueue.concat([{ text: t, atts: pendingAtts }])
                pendingAtts = []
            }
            return
        }
        toolRounds = 0
        _retries = 0
        if (keyMissing) {
            _push({ role: "error",
                    content: I18n.tr("Missing API key for %1. Set it in the panel settings.")
                        .arg(provider.label) })
            return
        }
        // Los adjuntos de texto viajan DENTRO del mensaje (así quedan en el
        // historial y el modelo los ve en turnos futuros); las imágenes solo
        // acompañan a este turno — reenviar pantallazos viejos en cada
        // pregunta quemaría la cuota gratuita a lo tonto.
        const atts = ai.pendingAtts
        let note = []
        ai._sendImages = []
        for (let i = 0; i < atts.length; i++) {
            const a = atts[i]
            note.push(a.label)
            if (a.kind === "text")
                t += "\n\n--- " + a.label + " ---\n```\n" + a.data + "\n```"
            else
                ai._sendImages.push(a.data)
        }
        if (t === "" && ai._sendImages.length === 0)
            return
        ai.pendingAtts = []
        _push({ role: "user", content: t, attachNote: note.join(" · ") })
        _start()
    }

    function retry() {
        if (!busy)
            _start()
    }

    // Descarta la última respuesta y pide otra al modelo ACTUAL — también
    // sirve para comparar proveedores sobre la misma pregunta.
    function regenerate() {
        if (busy || messages.count === 0)
            return
        const last = messages.get(messages.count - 1)
        if (last.role !== "user")
            messages.remove(messages.count - 1)
        _saveHistory()
        _start()
    }

    // ── Aprobación de herramientas ───────────────────────────────────────────
    property int _toolIndex: -1

    // Expande ~ y comprueba que la ruta quede dentro de la carpeta personal:
    // las herramientas de archivos NO salen de $HOME, y los ".." no cuelan.
    function _safePath(p) {
        const home = Quickshell.env("HOME")
        let path = String(p).trim()
        if (path === "~") path = home
        else if (path.startsWith("~/")) path = home + path.slice(1)
        if (!path.startsWith(home + "/") && path !== home)
            return ""
        if (path.indexOf("..") !== -1)
            return ""
        return path
    }

    function approveTool(index) {
        const m = messages.get(index)
        if (!m || m.role !== "tool" || m.toolStatus !== "pending" || busy)
            return
        ai._toolIndex = index
        let args = ({})
        try { args = JSON.parse(m.toolArgs) } catch (e) {}

        switch (m.toolName) {
        case "open_url": {
            const url = args.url || ""
            if (url !== "")
                Quickshell.execDetached(["xdg-open", url])
            _resolveTool(index, url !== "" ? "URL abierta en el navegador."
                                           : "URL inválida.")
            return
        }
        case "read_file": {
            const p = _safePath(args.path)
            if (p === "") { _resolveTool(index, "Ruta fuera de la carpeta personal."); return }
            toolProc.command = ["sh", "-c", 'head -c 16000 -- "$QS_P"']
            toolProc.environment = ({ QS_P: p })
            toolProc.running = true
            return
        }
        case "list_dir": {
            const p = _safePath(args.path)
            if (p === "") { _resolveTool(index, "Ruta fuera de la carpeta personal."); return }
            toolProc.command = ["sh", "-c", 'ls -lah -- "$QS_P" | head -n 80']
            toolProc.environment = ({ QS_P: p })
            toolProc.running = true
            return
        }
        case "write_file": {
            const p = _safePath(args.path)
            if (p === "") { _resolveTool(index, "Ruta fuera de la carpeta personal."); return }
            // El contenido viaja por entorno (nunca argv) y se escribe con
            // printf; la carpeta destino se crea si falta.
            toolProc.command = ["sh", "-c",
                'mkdir -p "$(dirname -- "$QS_P")" && printf %s "$QS_C" > "$QS_P" && echo "Escrito: $QS_P ($(wc -c < "$QS_P") bytes)"']
            toolProc.environment = ({ QS_P: p, QS_C: args.content || "" })
            toolProc.running = true
            return
        }
        case "remember": {
            const note = String(args.note || "").trim().slice(0, 400)
            if (note === "") { _resolveTool(index, "Nota vacía."); return }
            mem.notes = (mem.notes || []).concat([note])
            _resolveTool(index, "Nota guardada en memoria.")
            return
        }
        default: {
            // run_command: acotado a 20 s; stdout y stderr vuelven al modelo.
            const cmd = args.command || ""
            if (cmd === "") { _resolveTool(index, "Comando vacío."); return }
            toolProc.command = ["timeout", "20", "sh", "-c", cmd]
            toolProc.environment = ({})
            toolProc.running = true
        }
        }
    }

    function rejectTool(index) {
        const m = messages.get(index)
        if (!m || m.role !== "tool" || m.toolStatus !== "pending")
            return
        messages.setProperty(index, "toolStatus", "rejected")
        messages.setProperty(index, "toolResult",
            "El usuario rechazó ejecutar esta acción.")
        _saveHistory()
        if (!busy)
            _start()      // que el modelo reaccione al rechazo
    }

    function _resolveTool(index, result) {
        messages.setProperty(index, "toolStatus", "done")
        messages.setProperty(index, "toolResult", String(result).slice(0, 4000))
        _saveHistory()
        if (!busy)
            _start()      // devuelve el resultado al modelo y sigue
    }

    Process {
        id: toolProc
        stdout: StdioCollector { id: toolOut }
        stderr: StdioCollector { id: toolErr }
        onExited: (code) => {
            let out = (toolOut.text || "")
            if ((toolErr.text || "").trim() !== "")
                out += (out !== "" ? "\n" : "") + "[stderr] " + toolErr.text
            if (out.trim() === "")
                out = "(sin salida; código " + code + ")"
            ai._resolveTool(ai._toolIndex, out)
        }
    }

    // ── Historial que viaja al modelo ────────────────────────────────────────
    // Recorte por DETRÁS (16 turnos / ~20k caracteres) y reconstrucción del
    // protocolo de herramientas: cada tarjeta resuelta se traduce al par
    // assistant(tool_calls) + tool(result) que exige el contrato OpenAI.
    function _payloadMessages() {
        const out = []
        let chars = 0
        for (let i = messages.count - 1; i >= 0 && out.length < 16; i--) {
            const m = messages.get(i)
            if (m.role === "tool") {
                if (m.toolStatus === "pending")
                    continue
                out.unshift({ role: "tool", tool_call_id: m.toolId,
                              content: m.toolResult })
                out.unshift({ role: "assistant", content: m.content,
                              tool_calls: [{ id: m.toolId, type: "function",
                                  "function": { name: m.toolName,
                                                arguments: m.toolArgs } }] })
                continue
            }
            if (m.role !== "user" && m.role !== "assistant")
                continue
            chars += m.content.length
            if (chars > 20000 && out.length > 0)
                break
            out.unshift({ role: m.role, content: m.content })
        }
        // Las imágenes del turno en curso se cuelgan del último mensaje de
        // usuario, en el formato multimodal del contrato.
        if (ai._sendImages.length > 0)
            for (let i = out.length - 1; i >= 0; i--)
                if (out[i].role === "user") {
                    const parts = [{ type: "text", text: out[i].content }]
                    for (let k = 0; k < ai._sendImages.length; k++)
                        parts.push({ type: "image_url", image_url: {
                            url: "data:image/png;base64," + ai._sendImages[k] } })
                    out[i] = { role: "user", content: parts }
                    break
                }
        out.unshift({ role: "system", content: ai.systemPrompt })
        return out
    }

    property string _errBuf: ""
    property double _t0: 0
    property int _usageTokens: 0
    property var _tc: ({})              // tool calls en streaming, por índice

    // Reintento con espera ante errores TRANSITORIOS (429 de cuota, 5xx,
    // timeouts): dos intentos con pausa creciente antes de rendirse y enseñar
    // el error. Lo de siempre en los clientes de aider/OpenAI.
    property int _retries: 0
    function _transient(msg) {
        return /429|rate.?limit|overloaded|unavailable|timed?.?out|502|503|500/i.test(msg)
    }
    Timer {
        id: retryTimer
        onTriggered: if (!ai.busy) ai._start()
    }

    function _start() {
        ai.streamBuf = ""
        ai.reasonBuf = ""
        ai._errBuf = ""
        ai._usageTokens = 0
        ai._tc = ({})
        ai._t0 = Date.now()
        const req = {
            model: ai.model,
            messages: ai._payloadMessages(),
            stream: true
        }
        // Temperatura: el parámetro universal del contrato, con el valor del
        // usuario (Ajustes del panel).
        req.temperature = Math.round(Settings.aiTemperature * 100) / 100
        // Las herramientas solo existen en modo agente: en chat el modelo ni
        // sabe que hay manos (los modos plan/build de opencode, en pequeño).
        // Y las apagadas por política ("off") ni se anuncian: para el modelo
        // no existen (las listas de denegación de aisuite).
        if (ai.agentMode) {
            const defs = ai.toolDefs.filter(d => ai.toolPolicy(d["function"].name) !== "off")
            if (defs.length > 0)
                req.tools = defs
        }
        if (Settings.aiProvider !== "gemini")
            req.stream_options = { include_usage: true }
        let cmd = ["curl", "-sS", "-N", "--no-buffer",
                   "--connect-timeout", "8", "--max-time", "180",
                   "-X", "POST", ai.endpoint,
                   "-H", "Content-Type: application/json"]
        if (ai.apiKey !== "")
            cmd = cmd.concat(["-H", "Authorization: Bearer " + ai.apiKey])
        if (Settings.aiProvider === "openrouter")
            cmd = cmd.concat(["-H", "X-Title: Quickshell"])
        cmd = cmd.concat(["-d", JSON.stringify(req)])
        streamProc.command = cmd
        ai.busy = true
        streamProc.running = true
    }

    Process {
        id: streamProc

        stdout: SplitParser {
            onRead: (line) => {
                const l = line.trim()
                if (l === "" || l.startsWith(":"))     // keep-alive de SSE
                    return
                if (l.startsWith("data:")) {
                    const payload = l.slice(5).trim()
                    if (payload === "[DONE]")
                        return
                    try {
                        const j = JSON.parse(payload)
                        if (j.error) {
                            ai._errBuf += (j.error.message || JSON.stringify(j.error))
                            return
                        }
                        if (j.usage && j.usage.completion_tokens)
                            ai._usageTokens = j.usage.completion_tokens
                        const d = j.choices && j.choices[0] && j.choices[0].delta
                        if (!d)
                            return
                        if (d.reasoning)
                            ai.reasonBuf += d.reasoning
                        if (d.content)
                            ai.streamBuf += d.content
                        // Propuestas de herramienta: llegan troceadas
                        // (nombre en un delta, argumentos gota a gota).
                        if (d.tool_calls)
                            for (let k = 0; k < d.tool_calls.length; k++) {
                                const tc = d.tool_calls[k]
                                const idx = tc.index || 0
                                if (!ai._tc[idx])
                                    ai._tc[idx] = { id: "", name: "", args: "" }
                                if (tc.id) ai._tc[idx].id = tc.id
                                if (tc["function"]) {
                                    if (tc["function"].name)
                                        ai._tc[idx].name = tc["function"].name
                                    if (tc["function"].arguments)
                                        ai._tc[idx].args += tc["function"].arguments
                                }
                            }
                    } catch (e) { /* fragmento no-JSON: se ignora */ }
                } else {
                    ai._errBuf += l
                }
            }
        }
        stderr: SplitParser {
            onRead: (line) => { if (line.trim() !== "") ai._errBuf += line + " " }
        }

        onExited: (code) => {
            ai.busy = false
            const parts = ai.splitThink(ai.streamBuf)
            const think = (ai.reasonBuf + parts.think).trim()
            const text = parts.text.trim()
            const tcKeys = Object.keys(ai._tc)

            if (tcKeys.length > 0) {
                // El modelo propone una herramienta → tarjeta pendiente de
                // aprobación. Solo la primera: más de una por turno es
                // rarísimo en estos modelos y complica la aprobación.
                const tc = ai._tc[tcKeys[0]]
                ai._push({ role: "tool", content: text,
                           toolName: tc.name, toolArgs: tc.args,
                           toolId: tc.id !== "" ? tc.id : ("call_" + Date.now()),
                           toolStatus: "pending",
                           modelName: ai.model, reasoning: think })
                ai.streamBuf = ""
                ai.reasonBuf = ""
                ai.toolRounds++
                // La política decide (estilo aisuite): "auto" ejecuta sin
                // preguntar — pasado el tope de pasos, también las "auto"
                // vuelven a pedir permiso: un agente en bucle no se
                // auto-alimenta.
                if (ai.toolPolicy(tc.name) === "auto"
                        && ai.toolRounds <= ai.maxToolRounds)
                    ai.approveTool(ai.messages.count - 1)
                else {
                    if (ai.toolRounds === ai.maxToolRounds + 1)
                        ai.pushInfo(I18n.tr("Step limit reached — approvals are manual again."))
                    ai.replied()
                }
                return
            }

            if (text !== "" || think !== "") {
                ai._retries = 0
                ai._push({ role: "assistant",
                           content: text !== "" ? text : think,
                           reasoning: text !== "" ? think : "",
                           modelName: ai.model,
                           ms: Date.now() - ai._t0, tokens: ai._usageTokens })
                ai.streamBuf = ""
                ai.reasonBuf = ""
                ai.replied()
                Qt.callLater(ai._dequeue)
                return
            }

            let msg = ai._errBuf.trim()
            try {
                let j = JSON.parse(msg)
                if (Array.isArray(j))    // Gemini envuelve el error en un array
                    j = j[0] || {}
                msg = (j.error && (j.error.message || j.error.code)) || msg
            } catch (e) {}
            if (msg === "")
                msg = code === 0 ? I18n.tr("No response received")
                                 : I18n.tr("Connection failed (curl exit %1)").arg(code)
            // Transitorio y con intentos en la recámara: se reintenta solo,
            // con espera creciente, sin molestar con una tarjeta de error.
            if (ai._transient(msg) && ai._retries < 2 && !ai.compacting) {
                ai._retries++
                ai.pushInfo(I18n.tr("Temporary error — retrying (%1/2)…").arg(ai._retries))
                retryTimer.interval = ai._retries * 2500
                retryTimer.restart()
                return
            }
            // Si lo que falló era la petición del RESUMEN, la compactación se
            // cancela limpiamente: sin esto, 'compacting' quedaba atascado y
            // bloqueaba cualquier compactación futura.
            if (ai.compacting) {
                ai.compacting = false
                ai._keepTail = []
            }
            ai._push({ role: "error", content: msg })
            Qt.callLater(ai._dequeue)
        }
    }

    // ── Compactar contexto ───────────────────────────────────────────────────
    // El /compact de opencode, en pequeño: pide al modelo un resumen de la
    // conversación y SUSTITUYE el historial por él. La siguiente pregunta
    // paga un puñado de viñetas, no toda la sesión.
    property bool compacting: false
    // El aviso de "casi lleno" se da UNA vez por conversación.
    property bool _compactWarned: false
    // Los turnos recientes que sobreviven al resumen (ver aiCompactKeep).
    property var _keepTail: []

    function compact() {
        if (busy || compacting || keyMissing || messages.count < 2)
            return
        compacting = true
        // Se aparta la cola ANTES de pedir el resumen: los últimos K turnos
        // (pregunta+respuesta) vuelven después literales — el resumen es para
        // lo viejo, no para lo que aún tienes en la retina.
        _keepTail = []
        let users = 0
        for (let i = messages.count - 1; i >= 0 && users < Settings.aiCompactKeep; i--) {
            const m = messages.get(i)
            if (m.role !== "user" && m.role !== "assistant")
                continue
            _keepTail.unshift({ role: m.role, content: m.content,
                                reasoning: m.reasoning, modelName: m.modelName,
                                ms: m.ms, tokens: m.tokens, ts: m.ts })
            if (m.role === "user")
                users++
        }
        _push({ role: "user", content:
            "Resume esta conversación en viñetas breves con TODOS los datos "
            + "útiles para seguir trabajando (decisiones, rutas, valores). "
            + "Solo el resumen." })
        _start()
    }

    onReplied: {
        if (compacting) {
            compacting = false
            _compactWarned = false
            // La última entrada es el resumen: sustituye al historial viejo,
            // y detrás vuelven los turnos conservados.
            const last = messages.get(messages.count - 1)
            const summary = "**" + I18n.tr("Summary of the previous conversation")
                + ":**\n\n" + last.content
            messages.clear()
            _append({ role: "assistant", content: summary, modelName: last.modelName })
            for (let i = 0; i < _keepTail.length; i++)
                _append(_keepTail[i])
            _keepTail = []
            _push({ role: "info", content: I18n.tr("Context compacted.") })
            Qt.callLater(_dequeue)
            return
        }
        // Contexto casi lleno: según lo elegido, avisar o compactar solo.
        if (contextFill > 0.85 && !busy && !keyMissing) {
            if (Settings.aiAutoCompact === "auto")
                compact()
            else if (Settings.aiAutoCompact === "warn" && !_compactWarned) {
                _compactWarned = true
                pushInfo(I18n.tr("Context almost full — /compact will summarize it."))
            }
        }
    }

    // ── Exportar (entregable) ────────────────────────────────────────────────
    // La conversación entera como Markdown en tu carpeta personal.
    function exportMarkdown() {
        if (messages.count === 0)
            return
        let md = "# " + _title() + "\n"
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i)
            if (m.role === "user")
                md += "\n## Usuario\n\n" + m.content + "\n"
            else if (m.role === "assistant")
                md += "\n## Asistente (" + m.modelName + ")\n\n" + m.content + "\n"
            else if (m.role === "tool")
                md += "\n> herramienta " + m.toolName + " (" + m.toolStatus + "): `"
                    + m.toolArgs.replace(/`/g, "'") + "`\n"
        }
        const stamp = new Date().toISOString().slice(0, 16).replace(/[T:]/g, "-")
        const path = Quickshell.env("HOME") + "/ia-" + stamp + ".md"
        exportProc.environment = ({ QS_P: path, QS_C: md })
        exportProc.command = ["sh", "-c", 'printf %s "$QS_C" > "$QS_P"']
        exportProc.running = true
        _exportPath = path
    }
    property string _exportPath: ""
    Process {
        id: exportProc
        onExited: (code) => {
            ai._push({ role: "info", content: code === 0
                ? I18n.tr("Conversation exported to %1").arg(ai._exportPath)
                : I18n.tr("Export failed") })
        }
    }

    // ── Persistencia (multi-conversación) ────────────────────────────────────
    // Todo en ai-history.json, junto a settings.json y como él fuera de git.
    function _append(m) {
        messages.append({
            role: m.role || "user", content: m.content || "",
            reasoning: m.reasoning || "", modelName: m.modelName || "",
            ms: m.ms || 0, tokens: m.tokens || 0,
            toolName: m.toolName || "", toolArgs: m.toolArgs || "",
            toolId: m.toolId || "", toolResult: m.toolResult || "",
            toolStatus: m.toolStatus || "", attachNote: m.attachNote || "",
            ts: m.ts || ""
        })
    }
    function _push(m) {
        // Hora del mensaje: se estampa al nacer, no se deriva luego.
        if (!m.ts)
            m.ts = new Date().toLocaleTimeString(Qt.locale(), "HH:mm")
        _append(m)
        _saveHistory()
        // Con el panel cerrado, la llegada se avisa por el sistema de
        // notificaciones (el del propio shell): pediste algo, te fuiste, y
        // el resultado te encuentra.
        if (!Globals.aiOpen
                && (m.role === "assistant" || m.role === "error"
                    || (m.role === "tool" && m.toolStatus === "pending"))) {
            const title = m.role === "error" ? I18n.tr("Assistant error")
                        : m.role === "tool" ? I18n.tr("Approval needed")
                        : I18n.tr("Reply ready")
            Quickshell.execDetached({
                command: ["sh", "-c",
                    'command -v notify-send >/dev/null && notify-send -a "IA" "$QS_T" "$QS_B" || true'],
                environment: { QS_T: title, QS_B: String(m.content).slice(0, 140) }
            })
        }
    }

    // Nota informativa en el hilo (la usan los comandos slash y el panel).
    function pushInfo(text) {
        _push({ role: "info", content: text })
    }

    readonly property string _newTitle: I18n.tr("New conversation")
    function _title() {
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).role === "user") {
                const t = messages.get(i).content.split("\n")[0]
                return t.length > 42 ? t.slice(0, 42) + "…" : t
            }
        return _newTitle
    }

    function _snapshotCurrent() {
        if (currentId === "")
            currentId = String(Date.now())
        const entries = []
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i)
            entries.push({ role: m.role, content: m.content, reasoning: m.reasoning,
                           modelName: m.modelName, ms: m.ms, tokens: m.tokens,
                           toolName: m.toolName, toolArgs: m.toolArgs,
                           toolId: m.toolId, toolResult: m.toolResult,
                           toolStatus: m.toolStatus, attachNote: m.attachNote,
                           ts: m.ts })
        }
        const rest = conversations.filter(c => c.id !== currentId)
        // Una conversación vacía no merece hueco en la lista.
        if (entries.length > 0)
            rest.unshift({ id: currentId, title: _title(),
                           updated: Date.now(), entries: entries })
        conversations = rest
    }

    function _saveHistory() {
        _snapshotCurrent()
        hist.convs = conversations
        hist.current = currentId
        _recountTotals()
    }

    FileView {
        id: histFile
        path: Quickshell.env("HOME") + "/.config/quickshell/ai-history.json"
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            if (ai.messages.count > 0)
                return
            // Formato viejo (una sola conversación plana): se migra.
            if ((!hist.convs || hist.convs.length === 0) && hist.entries
                    && hist.entries.length > 0)
                hist.convs = [{ id: String(Date.now()),
                                title: ai._newTitle,
                                updated: Date.now(), entries: hist.entries }]
            ai.conversations = hist.convs || []
            const target = ai.conversations.find(c => c.id === hist.current)
                        || ai.conversations[0]
            if (target) {
                ai.currentId = target.id
                for (let i = 0; i < target.entries.length; i++)
                    ai._append(target.entries[i])
            } else {
                ai.currentId = String(Date.now())
            }
            ai._recountTotals()
        }

        JsonAdapter {
            id: hist
            property var convs: []
            property string current: ""
            property var entries: []    // solo para leer el formato viejo
        }
    }

    // La memoria persistente, en su propio archivo (también fuera de git).
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/ai-memory.json"
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: mem
            property var notes: []
        }
    }
}
