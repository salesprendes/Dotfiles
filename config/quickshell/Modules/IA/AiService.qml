pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "TextUtils.js" as TU
import "ToolDefs.js" as TD

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

    // ── Dónde vive todo lo de la IA ──────────────────────────────────────────
    // Un único sitio: el propio módulo. Las habilidades en 'skills/' y el
    // estado (historial, memoria, instintos, hooks) en 'data/', de modo que
    // llevarse el asistente a otra máquina sea copiar una carpeta. Se cuelga
    // de Quickshell.shellDir en vez de ~/.config/quickshell a pelo: así vale
    // igual si el shell se carga desde otra ruta.
    readonly property string iaDir: Quickshell.shellDir + "/Modules/IA"
    readonly property string dataDir: iaDir + "/data"

    // ── Proveedores y modelos ────────────────────────────────────────────────
    // 'base' es la raíz /v1 del contrato OpenAI: de ahí salen SIEMPRE las dos
    // direcciones que usa el harness (/chat/completions para hablar y /models
    // para descubrir el catálogo). Los dos proveedores con URL de usuario la
    // dejan vacía y la calculan en 'apiBase'.
    readonly property var providers: ({
        gemini: {
            label: "Gemini",
            base: "https://generativelanguage.googleapis.com/v1beta/openai",
            needsKey: true,
            userUrl: false
        },
        openrouter: {
            label: "OpenRouter",
            base: "https://openrouter.ai/api/v1",
            needsKey: true,
            userUrl: false
        },
        ollama: {
            label: "Ollama",
            base: "",           // la URL base la pone el usuario (aiOllamaUrl)
            needsKey: false,
            userUrl: true
        },
        // Cualquier servidor OpenAI-compatible, REMOTO o local: vLLM, TGI,
        // LiteLLM, LM Studio publicado, un Ollama tras un proxy inverso…
        // URL base /v1 configurable y clave OPCIONAL (needsKey false: sin
        // clave no se bloquea el envío; si la pones, viaja como Bearer).
        custom: {
            label: I18n.tr("Server"),
            base: "",
            needsKey: false,
            userUrl: true
        }
    })

    readonly property var provider: providers[Settings.aiProvider] || providers.gemini
    readonly property string model:
        Settings.aiProvider === "openrouter" ? Settings.aiModelOpenrouter
        : Settings.aiProvider === "ollama"   ? Settings.aiModelOllama
        : Settings.aiProvider === "custom"   ? Settings.aiModelCustom
                                             : Settings.aiModelGemini

    // Normaliza lo que escriba el usuario hasta una raíz /v1 utilizable. Es
    // deliberadamente indulgente porque una URL remota se copia y se pega mal:
    // sobran barras, falta el esquema, se pega el endpoint completo… Todo eso
    // acaba en la misma base. Sin esquema se asume https, salvo que apunte a
    // una IP o a localhost (ahí lo normal es http).
    // Lógica en TextUtils.js (pura); aquí solo el puente para no tocar llamadas.
    function normalizeBase(u) { return TU.normalizeBase(u) }
    function normalizeSearchBase(u) { return TU.normalizeSearchBase(u) }

    // Raíz /v1 efectiva del proveedor activo ("" si aún falta la URL).
    readonly property string apiBase:
        provider.userUrl
            ? normalizeBase(Settings.aiProvider === "ollama"
                            ? Settings.aiOllamaUrl : Settings.aiCustomUrl)
            : provider.base
    readonly property string endpoint:
        apiBase === "" ? "" : apiBase + "/chat/completions"
    // Catálogo del servidor. Ollama publica el suyo fuera de /v1 (/api/tags);
    // el resto, en el /models del contrato OpenAI.
    readonly property string modelsUrl:
        apiBase === "" ? ""
        : Settings.aiProvider === "ollama"
            ? apiBase.replace(/\/v1$/, "") + "/api/tags"
            : apiBase + "/models"

    // ── Presupuesto de contexto ──────────────────────────────────────────────
    // Antes el recorte era de 20 000 caracteres fijos, dijera lo que dijera el
    // modelo. Con un modelo LOCAL eso es o derrochar (un Qwen de 32k aguanta
    // el triple) o desbordar (uno de 8k no llega). Ahora todo cuelga de la
    // ventana real: el usuario la declara y de ahí sale el recorte del
    // historial, el tope de cada resultado de herramienta y el medidor.
    readonly property int contextTokens:
        Settings.aiContextTokens > 0 ? Settings.aiContextTokens
        : (provider.userUrl ? 32768 : 128000)     // local típico vs. nube
    // Del total, algo menos de la mitad para el historial: el resto lo comen
    // el prompt de sistema, los esquemas de herramientas y la respuesta.
    // ~3,5 caracteres por token es la regla de bolsillo habitual.
    readonly property int charBudget: Math.round(contextTokens * 3.5 * 0.45)
    // Un solo resultado de herramienta no puede comerse el turno.
    readonly property int toolResultCap:
        Math.max(1500, Math.min(12000, Math.round(charBudget / 6)))

    // ── Cuántas herramientas se le enseñan de golpe ──────────────────────────
    // Casi cuarenta esquemas son mucho ruido para un modelo pequeño: le comen
    // contexto y le hacen elegir peor. Con ventana holgada se le enseñan
    // todas; con una ventana modesta, un núcleo fijo más las que vengan a
    // cuento. Recortar aquí NO quita capacidades: approveTool ejecuta por
    // nombre, así que si el modelo nombra una que no iba en la lista, funciona
    // igual — esto es una sugerencia, no un muro.
    readonly property int maxTools:
        contextTokens < 16000 ? 12 : contextTokens < 64000 ? 20 : 0    // 0 = todas
    readonly property var coreTools: ["ask_user", "todo_write", "run_command",
                                      "read_file", "write_file", "edit_file",
                                      "edit_lines", "list_dir", "grep_files"]

    // Ordena por relevancia al último mensaje y recorta, dejando siempre el
    // núcleo y lo que ya venía filtrado por modo/política.
    function _selectTools(defs) {
        if (maxTools <= 0 || defs.length <= maxTools)
            return defs
        const core = defs.filter(d => coreTools.indexOf(d["function"].name) !== -1)
        const rest = defs.filter(d => coreTools.indexOf(d["function"].name) === -1)
        const texts = rest.map(d => d["function"].name + " " + (d["function"].description || ""))
        const order = _rankNotes(texts, _lastUserText)
        const room = Math.max(0, maxTools - core.length)
        const picked = order.slice(0, room).map(i => rest[i])
        return core.concat(picked)
    }

    // Falta algo para poder hablar: sin URL (los de servidor propio) o sin
    // clave (los de nube). El panel lo usa para invitar a configurar en vez de
    // dejar que el envío falle con un error de red.
    readonly property bool urlMissing: provider.userUrl && apiBase === ""
    readonly property bool notConfigured: urlMissing || keyMissing

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

    // Catálogo por proveedor descubierto EN EL SERVIDOR (ver testConnection):
    // mapa id → [modelos]. Con un servidor remoto no hay forma de adivinar qué
    // sirve, así que el propio servidor lo dice; mientras no conteste, se usa
    // la lista de reserva de abajo. El elegido actual siempre entra en la
    // lista aunque sea un id escrito a mano.
    property var fetchedModels: ({})
    readonly property var modelOptions: {
        let base = fetchedModels[Settings.aiProvider] || []
        if (base.length === 0) {
            if (Settings.aiProvider === "openrouter")
                base = ["qwen/qwen3-30b-a3b:free", "qwen/qwen3-14b:free",
                        "deepseek/deepseek-chat-v3-0324:free",
                        "meta-llama/llama-3.3-70b-instruct:free"]
            else if (Settings.aiProvider === "gemini")
                base = ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5-pro",
                        "gemini-2.0-flash"]
        }
        const out = base.slice()
        if (ai.model !== "" && out.indexOf(ai.model) === -1)
            out.unshift(ai.model)
        const opts = out.map(m => ({ text: m, value: m }))
        // Servidor recién configurado y todavía sin modelo: el desplegable
        // debe decirlo. Sin esta entrada, al no encontrar el valor vigente
        // pintaría la primera opción de la lista y parecería que hay elegido
        // un modelo que no está en uso.
        if (ai.model === "")
            opts.unshift({ text: I18n.tr("Choose a model"), value: "" })
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

    // ── Cuánta correa lleva el agente ────────────────────────────────────────
    // UN control en vez de cuarenta. La aprobación sale de la CLASE DE RIESGO
    // (ver riskClass): el usuario dice hasta dónde llega el agente y el harness
    // reparte. Poner una fila por herramienta era pedirle al usuario que
    // repitiera cuarenta veces la misma decisión — y quien no la toma se queda
    // con un agente que pregunta por leer un archivo.
    readonly property var approvalModes: ["careful", "normal", "auto"]
    readonly property string approvalMode:
        approvalModes.indexOf(Settings.aiApproval) !== -1 ? Settings.aiApproval
                                                          : "normal"
    // Lo que el modo concede a cada clase de riesgo. Lo que no aparece,
    // pregunta.
    function _modeGrants(risk) {
        if (approvalMode === "auto")
            return risk !== "ask"            // preguntar nunca se auto-responde
        if (approvalMode === "normal")
            return risk === "read"
        return false                          // careful: hasta leer se pregunta
    }

    // Herramientas de contabilidad del propio harness: no tocan el equipo, y
    // pedir permiso para ellas convertiría cada turno en un formulario. Leer
    // una habilidad que el usuario instaló es leer el manual, no actuar.
    readonly property var _bookkeeping: ["use_skill", "todo_write",
                                         "notify_user", "learn"]

    // ── Cómo se enseña un modelo ─────────────────────────────────────────────
    // Un id de modelo es una ruta con proveedor, familia y etiquetas
    // ("qwen/qwen3-30b-a3b:free"). En un botón de cabecera lo que importa es el
    // NOMBRE; el resto sale como insignia aparte o no sale.
    function modelShort(id) {
        let s = String(id || "")
        const slash = s.lastIndexOf("/")
        if (slash >= 0) s = s.slice(slash + 1)
        const colon = s.indexOf(":")
        if (colon > 0) s = s.slice(0, colon)
        return s
    }
    // La etiqueta de la derecha: gratis, local o nada.
    function modelTag(id) {
        const s = String(id || "")
        if (s.indexOf(":free") !== -1) return "free"
        return ""
    }

    // Catálogo agrupado por proveedor para el selector: el del proveedor
    // activo, entero; de los demás, el modelo que tengan elegido — cambiar de
    // cerebro (o de nube a local) sin pasar por la configuración.
    readonly property var modelGroups: {
        const ids = ["gemini", "openrouter", "ollama", "custom"]
        const out = []
        for (let i = 0; i < ids.length; i++) {
            const id = ids[i]
            const activo = id === Settings.aiProvider
            const suyo = id === "openrouter" ? Settings.aiModelOpenrouter
                       : id === "ollama" ? Settings.aiModelOllama
                       : id === "custom" ? Settings.aiModelCustom
                       : Settings.aiModelGemini
            let lista = activo ? modelOptions.map(o => o.value).filter(v => v !== "")
                               : (suyo !== "" ? [suyo] : [])
            // Los "proveedor:modelo" de la cola de modelOptions ya salen en su
            // propio grupo: aquí sobran.
            lista = lista.filter(v => v.indexOf(":") === -1
                                   || !providers[v.slice(0, v.indexOf(":"))])
            if (lista.length === 0)
                continue
            out.push({ provider: id, label: providers[id].label,
                       active: activo, models: lista })
        }
        return out
    }

    // Política efectiva de una herramienta: la excepción del usuario manda; si
    // no hay, decide el modo sobre su clase de riesgo.
    function toolPolicy(name) {
        const over = (Settings.aiToolPolicies || {})[name]
        if (over === "ask" || over === "auto" || over === "off")
            return over
        if (_bookkeeping.indexOf(name) !== -1)
            return "auto"
        return _modeGrants(riskClass(name)) ? "auto" : "ask"
    }

    // Cuántas excepciones hay puestas: el panel lo enseña para que un permiso
    // olvidado no viva escondido bajo un modo que dice otra cosa.
    readonly property int toolOverrides: {
        const p = Settings.aiToolPolicies || {}
        let n = 0
        for (const k in p)
            if (p[k] === "ask" || p[k] === "auto" || p[k] === "off")
                n++
        return n
    }
    function setToolPolicy(name, v) {
        const p = Object.assign({}, Settings.aiToolPolicies)
        // El modo ya dice lo que hace falta: una excepción que COINCIDE con él
        // no se guarda, se borra. Así el contador dice la verdad y volver al
        // valor de siempre limpia de verdad en vez de dejar rastro.
        const natural = _bookkeeping.indexOf(name) !== -1 ? "auto"
                      : (_modeGrants(riskClass(name)) ? "auto" : "ask")
        if (v === natural)
            delete p[name]
        else
            p[name] = v
        Settings.aiToolPolicies = p
    }
    function clearToolPolicies() { Settings.aiToolPolicies = ({}) }

    // ── Riesgo de cada herramienta (idea de OpenWorker) ──────────────────────
    // La clase de riesgo INTRÍNSECA gobierna la aprobación, en vez de listas
    // sueltas repartidas. Cuatro clases, de menor a mayor:
    //   read      no cambia nada — la tarjeta puede saltarse
    //   external  efecto FUERA del equipo pero sin destruir (abrir URL, buscar,
    //             delegar, herramientas MCP): aprobable "para siempre" en la
    //             conversación
    //   write     modifica archivos (locales o remotos): SIEMPRE pregunta
    //   exec      ejecuta comandos / actúa sobre servicios: SIEMPRE pregunta
    // La regla de OpenWorker que adopto: una aprobación permanente solo se
    // ofrece para read/external — "el shell pregunta para siempre".
    readonly property var _riskWrite: ["write_file", "edit_file", "edit_lines",
                                       "remember", "sftp_get", "sftp_put"]
    readonly property var _riskExec: ["run_command", "ssh_exec", "service_ctl",
                                      "kill_process"]
    readonly property var _riskExternal: ["open_url", "fetch_url", "web_search",
                                          "subagent"]
    function riskClass(name) {
        // Preguntar no es un efecto: es una pausa. Clase propia para que la
        // tarjeta se pinte como pregunta y nunca se auto-apruebe ni se
        // permita "siempre" (un permiso permanente sobre preguntar sería
        // responder solo).
        if (name === "ask_user") return "ask"
        if (name === "propose_plan") return "plan"
        if (name.startsWith("mcp__")) return "external"
        if (_riskExec.indexOf(name) !== -1) return "exec"
        if (_riskWrite.indexOf(name) !== -1) return "write"
        if (_riskExternal.indexOf(name) !== -1) return "external"
        return "read"
    }
    // ¿Se puede ofrecer "permitir siempre en esta conversación"? Solo si no
    // destruye ni ejecuta: leer y los externos benignos.
    function canStandingAllow(name) {
        const r = riskClass(name)
        return r === "read" || r === "external"
    }

    // La respuesta del usuario a un ask_user: vuelve al modelo como resultado
    // de la herramienta y la conversación sigue sola.
    function answerQuestion(index, answer) {
        const m = messages.get(index)
        if (!m || m.role !== "tool" || m.toolStatus !== "pending"
                || m.toolName !== "ask_user")
            return
        const a = String(answer).trim()
        if (a === "")
            return
        _resolveTool(index, a)
    }

    // Metacaracteres que convierten UN comando permitido en varios (cadenas,
    // tuberías, redirecciones, sustitución). La guardia de OpenWorker: aunque
    // el usuario ponga run_command/ssh_exec en "auto", un comando con estos
    // vuelve a pedir aprobación — "allow git status" no debe colar
    // "git status; rm -rf ~".
    function _hasShellOps(cmd) { return TU.hasShellOps(cmd) }

    // Permisos permanentes de ESTA conversación (el "session allowlist" de
    // OpenWorker): el usuario pulsa "Siempre" en una tarjeta y esa herramienta
    // deja de preguntar hasta que cambie de conversación. Efímero por diseño.
    property var sessionAllow: ({})
    function allowForSession(name) {
        const m = Object.assign({}, sessionAllow)
        m[name] = true
        sessionAllow = m
    }

    // Política de UNA LLAMADA concreta: la del nombre, salvo en las consultas
    // remotas, donde también cuentan los argumentos. Leer un servidor que el
    // usuario ya guardó es rutina; asomarse por primera vez a una máquina que
    // acaba de nombrar en el mensaje merece que se vea la tarjeta.
    function callPolicy(name, argsJson) {
        // Preguntar y proponer plan SIEMPRE esperan al usuario: son la pausa,
        // no una acción que se pueda automatizar.
        if (name === "ask_user" || name === "propose_plan")
            return "ask"
        // Permiso permanente de la conversación (solo para lo aprobable así).
        if (sessionAllow[name] && canStandingAllow(name))
            return "auto"

        const p = toolPolicy(name)
        const a = repairJson(argsJson) || ({})

        // Guardia de shell: un comando "auto" que encadena/redirige vuelve a
        // preguntar. Se aplica a lo que ejecuta comandos.
        if (p === "auto" && (name === "run_command" || name === "ssh_exec")
                && _hasShellOps(a.command))
            return "ask"

        // Consulta a un servidor: aunque esté permitida (por política o por la
        // auto-lectura), asomarse por primera vez a una máquina que acaba de
        // salir del mensaje se enseña; a una ya guardada, no.
        if (sshQueryDefs.some(d => d["function"].name === name) && p === "auto") {
            const h = _sshHost(a.host, a)
            return (h && h.saved) ? "auto" : "ask"
        }
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

    // ── Conexión: sonda y catálogo ───────────────────────────────────────────
    // Una sola llamada resuelve las dos preguntas que importan con un servidor
    // REMOTO: ¿contesta y me acepta la credencial?, ¿qué modelos sirve? Es un
    // GET al catálogo del proveedor midiendo código HTTP y latencia. Antes los
    // modelos de Ollama salían de `ollama list` (solo servía para el Ollama de
    // esta máquina); ahora se piden por HTTP, así que un Ollama remoto se
    // descubre igual que uno local.
    property string connState: "idle"    // idle | probing | ok | fail
    property string connDetail: ""       // qué pasó, en una línea
    property int    connMs: 0            // latencia del ida y vuelta
    property int    connModels: 0        // modelos que publica el servidor
    property real   _probeT0: 0

    function testConnection() {
        if (probeProc.running || ai.modelsUrl === "")
            return
        ai.connState = "probing"
        ai.connDetail = ""
        ai._probeT0 = Date.now()
        probeProc.forProvider = Settings.aiProvider
        probeProc.command = ["curl", "-sS", "--max-time", "15",
                             "-w", "\n__QS %{http_code}", ai.modelsUrl]
            .concat(ai._authArgs()).concat(ai._netArgs())
        probeProc.running = true
    }

    // Cabecera de credencial: Bearer si hay clave (también en los servidores
    // propios con token) más la cabecera extra que pida la pasarela.
    function _authArgs() {
        let a = []
        if (ai.apiKey !== "")
            a = a.concat(["-H", "Authorization: Bearer " + ai.apiKey])
        const extra = Settings.aiCustomHeader.trim()
        if (extra !== "" && provider.userUrl)
            a = a.concat(["-H", extra])
        if (Settings.aiProvider === "openrouter")
            a = a.concat(["-H", "X-Title: Quickshell"])
        return a
    }
    // Opciones de red del transporte: certificado no verificable (servidor
    // propio con TLS autofirmado). Solo donde el usuario pone la URL: nadie
    // necesita saltarse la verificación contra Google u OpenRouter.
    function _netArgs() {
        return (Settings.aiInsecureTls && provider.userUrl) ? ["-k"] : []
    }

    Process {
        id: probeProc
        property string forProvider: ""
        stdout: StdioCollector { id: probeOut }
        onExited: (code) => {
            ai.connMs = Date.now() - ai._probeT0
            const raw = (probeOut.text || "")
            const cut = raw.lastIndexOf("__QS ")
            const status = cut >= 0 ? parseInt(raw.slice(cut + 5).trim()) || 0 : 0
            const body = cut >= 0 ? raw.slice(0, cut) : raw

            if (code !== 0) {
                ai.connState = "fail"
                ai.connDetail = code === 6 ? I18n.tr("Host not found")
                              : code === 7 ? I18n.tr("Server unreachable")
                              : code === 28 ? I18n.tr("Timed out")
                              : code === 60 ? I18n.tr("TLS certificate not trusted")
                              : I18n.tr("Connection failed (curl exit %1)").arg(code)
                return
            }
            if (status >= 400) {
                ai.connState = "fail"
                ai.connDetail = (status === 401 || status === 403)
                    ? I18n.tr("Rejected credentials (HTTP %1)").arg(status)
                    : status === 404
                    ? I18n.tr("No catalog at %1 (HTTP 404)").arg(ai.modelsUrl)
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

            // Contesta 200 pero sin catálogo: casi siempre es la URL de un
            // panel web, no la raíz /v1 de la API. Decirlo así ahorra el
            // "no funciona" sin pista.
            if (names.length === 0) {
                ai.connState = "fail"
                ai.connDetail = I18n.tr("Answered, but published no models — is that the /v1 base?")
                return
            }
            // OpenRouter publica cientos: el desplegable se queda con los
            // gratuitos (más el que ya usas, que lo añade modelOptions).
            if (probeProc.forProvider === "openrouter")
                names = names.filter(n => n.endsWith(":free"))
            names.sort()
            const map = Object.assign({}, ai.fetchedModels)
            map[probeProc.forProvider] = names
            ai.fetchedModels = map
            ai.connModels = names.length
            ai.connState = "ok"
            ai.connDetail = ""
            // Servidor nuevo sin modelo elegido: se adopta el primero que
            // publique, para no obligar a copiar un id a mano.
            if (ai.model === "" && names.length > 0)
                ai.setModel(names[0])
        }
    }

    // Sonda automática con freno: cambiar de proveedor, pegar una URL o
    // teclear la clave dispara UNA comprobación cuando la mano se para.
    readonly property string _connKey: Settings.aiProvider + "|" + modelsUrl + "|"
                                       + apiKey + "|" + Settings.aiCustomHeader
                                       + "|" + Settings.aiInsecureTls
    on_ConnKeyChanged: {
        ai.connState = "idle"
        ai.connDetail = ""
        if (ai.modelsUrl !== "" && !ai.keyMissing)
            probeDebounce.restart()
    }
    Timer {
        id: probeDebounce
        interval: 1200
        onTriggered: ai.testConnection()
    }
    Component.onCompleted: if (modelsUrl !== "" && !keyMissing) probeDebounce.restart()

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
    // Llenado aproximado del contexto que viaja al modelo (0..1), medido
    // contra charBudget — que sale de la ventana real del modelo.
    property real contextFill: 0

    function _recountTotals() {
        let tok = 0, ms = 0, chars = 0
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i)
            tok += m.tokens
            ms += m.ms
            if (m.role === "user" || m.role === "assistant")
                chars += m.content.length
            // Las herramientas también viajan al modelo (argumentos y
            // resultado): en modo agente son LA mayor parte del contexto, y
            // un medidor que las ignore dice "medio vacío" con la ventana
            // desbordando. Debe medir lo mismo que _payloadMessages manda.
            else if (m.role === "tool" && m.toolStatus !== "pending")
                chars += m.toolArgs.length + m.toolResult.length
        }
        convTokens = tok
        convMs = ms
        contextFill = Math.min(1, chars / charBudget)
    }

    // Cola de envío: puedes seguir escribiendo mientras responde; lo tuyo
    // sale en cuanto termina (la cola de mensajes de Claude Code).
    property var sendQueue: []
    function _dequeue() {
        if (busy || compacting || sendQueue.length === 0)
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

    // El plan visible del turno (herramienta todo_write, el TodoWrite de
    // Claude Code): [{content, status}]. Es efímero por diseño — pertenece a
    // la tarea en curso, no al historial.
    property var todos: []

    // El subagente en marcha (uno cada vez, como el Task de Claude Code en
    // su forma bloqueante): el panel enseña su etiqueta, sus rondas y un
    // botón de cancelar. null cuando no hay ninguno.
    property var activeSub: null
    readonly property Component _subComp: Component { SubAgent {} }

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
    // El JsonAdapter propaga sus escrituras con un tick de retraso: leer
    // mem.notes justo después de asignarlo devuelve el valor ANTERIOR. Con las
    // llamadas en paralelo, dos operaciones de memoria del mismo lote se
    // pisarían (la segunda copiaría el array viejo). Por eso la fuente de
    // verdad en memoria es _notesLocal en cuanto se escribe una vez; el
    // adaptador queda como persistencia.
    property var _notesLocal: null
    readonly property var memoryList: _notesLocal !== null ? _notesLocal : (mem.notes || [])
    function _setNotes(arr) {
        _notesLocal = arr
        mem.notes = arr
    }
    function removeMemory(i) {
        const n = memoryList.slice()
        n.splice(i, 1)
        _setNotes(n)
    }

    // ── Instintos (idea de ECC) ──────────────────────────────────────────────
    // Lecciones OPERATIVAS que el agente aprende trabajando en ESTE equipo:
    // "aquí systemctl pide contraseña", "el servidor web1 escucha en el 2222",
    // "grep sobre este archivo necesita -a". Van aparte de la memoria porque
    // son otra cosa: la memoria guarda hechos del usuario, el instinto guarda
    // cómo trabajar aquí. Cada uno lleva una CONFIANZA que sube cuando el
    // agente vuelve a toparse con lo mismo, y de ahí sale el orden con el que
    // entran al prompt: lo que se ha confirmado varias veces pesa más.
    property var _instLocal: null
    readonly property var instinctList: _instLocal !== null ? _instLocal : (inst.items || [])
    function _setInstincts(arr) {
        _instLocal = arr
        inst.items = arr
    }
    function removeInstinct(i) {
        const n = instinctList.slice()
        n.splice(i, 1)
        _setInstincts(n)
    }
    // Guardar una lección. Si ya existe una igual, no se duplica: sube su
    // confianza — que es justo la señal de que la lección es de verdad.
    function addInstinct(text) {
        const t = String(text || "").trim().slice(0, 300)
        if (t === "")
            return "Lección vacía."
        const list = instinctList.slice()
        const low = t.toLowerCase()
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].text).toLowerCase() === low) {
                list[i] = { text: list[i].text,
                            confidence: Math.min(9, (list[i].confidence || 1) + 1) }
                _setInstincts(list)
                return "Ya lo sabía; ahora con más confianza (" + list[i].confidence + ")."
            }
        }
        list.push({ text: t, confidence: 1 })
        _setInstincts(list.slice(-40))     // tope: lo viejo cede sitio
        return "Aprendido."
    }

    readonly property string _instinctBlock: {
        const all = instinctList
        if (all.length === 0)
            return ""
        // Primero por confianza; a igualdad, por relevancia a lo que se acaba
        // de preguntar (el mismo criterio que la memoria).
        const texts = all.map(x => String(x.text))
        const byRel = TU.rankNotes(texts, _lastUserText)
        const order = byRel.slice().sort((a, b) =>
            ((all[b].confidence || 1) - (all[a].confidence || 1))
            || (byRel.indexOf(a) - byRel.indexOf(b)))
        let block = "\nLo que has aprendido trabajando en este equipo (entre "
                  + "paréntesis, cuántas veces se ha confirmado). Tenlo en "
                  + "cuenta antes de repetir un error ya conocido:"
        let chars = 0
        for (let k = 0; k < order.length; k++) {
            const it = all[order[k]]
            chars += String(it.text).length
            if (chars > 1200)
                break
            block += "\n- " + it.text + " (" + (it.confidence || 1) + ")"
        }
        return block
    }
    readonly property string _memoryBlock: {
        const n = memoryList
        if (n.length === 0)
            return ""
        // Cada nota va con su [#id] (idea de OpenWorker): así el modelo puede
        // CORREGIR o RETIRAR una que ya no vale, en vez de apilar el dato
        // nuevo al lado del rancio y contradecirse más tarde.
        let block = "\nMemoria del usuario (notas que él aprobó guardar). Si "
                  + "alguna queda desfasada, corrígela con memory_update o "
                  + "retírala con memory_forget usando su número, en vez de "
                  + "guardar una nota nueva que la contradiga:"
        // Orden por RELEVANCIA a lo último que preguntó el usuario (idea de
        // OpenHarness): con el presupuesto lleno, lo que entra es lo que viene
        // a cuento, no lo que se guardó primero. Los ids [#n] siguen siendo
        // los de la lista real, para que corregir siga apuntando bien.
        const order = _rankNotes(n, _lastUserText)
        let chars = 0
        for (let k = 0; k < order.length; k++) {
            const i = order[k]
            chars += n[i].length
            if (chars > 2000)
                break
            block += "\n- [#" + (i + 1) + "] " + n[i]
        }
        return block
    }

    // Lo último que preguntó el usuario: la consulta contra la que se mide la
    // relevancia. Se actualiza al empujar su mensaje.
    property string _lastUserText: ""

    // Devuelve los ÍNDICES de las notas ordenados por relevancia. Puntúa por
    // palabras compartidas con la consulta (ignorando las muy cortas, que son
    // artículos y preposiciones); a igualdad, respeta el orden original —
    // sin consulta, el orden es el de siempre.
    function _rankNotes(notes, query) { return TU.rankNotes(notes, query) }

    // ── Hooks del usuario (idea de OpenHarness) ──────────────────────────────
    // Comandos propios que el harness dispara en momentos concretos del ciclo
    // de vida. Es la puerta de extensión que faltaba: el usuario puede
    // auditar, registrar o VETAR lo que haga el agente sin tocar este código.
    //
    // Se declaran en Modules/IA/data/ai-hooks.json:
    //   { "hooks": [
    //       { "event": "pre_tool_use", "matcher": "run_command|ssh_exec",
    //         "command": "~/bin/vetar.sh", "priority": 10 },
    //       { "event": "stop", "command": "notify-send 'listo'" } ] }
    //
    // El único que puede BLOQUEAR es pre_tool_use: si su comando termina con
    // código distinto de 0, la llamada se rechaza y su salida se le devuelve
    // al modelo como motivo. Los demás son avisos (no frenan nada).
    // El contexto viaja por ENTORNO (QS_HOOK_*), nunca en argv.
    readonly property var hookEvents: ["session_start", "user_prompt_submit",
                                       "pre_tool_use", "post_tool_use", "stop"]
    property var hooks: []              // [{event, matcher, command, priority}]

    // Los hooks se leen de su archivo y se recargan solos al editarlo.
    readonly property FileView _hooksFile: FileView {
        path: ai.dataDir + "/ai-hooks.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let list = []
            try {
                const j = JSON.parse(text())
                list = (j.hooks || []).filter(h => h && h.event && h.command
                            && ai.hookEvents.indexOf(h.event) !== -1)
            } catch (e) {
                ai.pushInfo(I18n.tr("ai-hooks.json is not valid JSON — hooks disabled."))
            }
            ai.hooks = list
        }
        onLoadFailed: ai.hooks = []     // sin archivo, sin hooks: es lo normal
    }

    // Cola de ejecución: los hooks de un evento corren EN SERIE por prioridad,
    // así el que veta lo hace antes de que el siguiente diga nada.
    property var _hookQueue: []
    property string _hookEvent: ""
    property int _hookGateIndex: -1     // tarjeta que espera el veredicto
    property var _hookDone: null        // qué hacer si ninguno veta

    // Los hooks de AVISO (todos menos pre_tool_use) se lanzan sueltos: no
    // devuelven nada ni frenan nada, así que no comparten la cola — si la
    // compartieran, un aviso en marcha pisaría al que sí puede vetar.
    function _fireHooks(event, toolName, payload) {
        const list = _hooksFor(event, toolName)
        for (let i = 0; i < list.length; i++)
            Quickshell.execDetached({
                command: ["sh", "-c", String(list[i].command)],
                environment: Object.assign({ QS_HOOK_EVENT: event }, payload || ({}))
            })
    }

    // El bloqueante: corre en serie y espera veredicto.
    function _runHooks(event, toolName, payload, onDone) {
        const list = _hooksFor(event, toolName)
        if (list.length === 0) {
            if (onDone) onDone()
            return
        }
        _hookEvent = event
        _hookQueue = list
        _hookDone = onDone || null
        _hookPayload = payload || ({})
        _nextHook()
    }
    property var _hookPayload: ({})
    property int _hookPassed: -1        // tarjeta cuyos hooks ya dieron paso

    function _nextHook() {
        if (_hookQueue.length === 0) {
            const done = _hookDone
            _hookDone = null
            _hookGateIndex = -1
            if (done) done()
            return
        }
        const h = _hookQueue[0]
        _hookQueue = _hookQueue.slice(1)
        hookProc.command = ["sh", "-c", String(h.command)]
        hookProc.environment = Object.assign({
            QS_HOOK_EVENT: ai._hookEvent
        }, ai._hookPayload)
        hookProc.running = true
    }

    readonly property Process _hookProc: Process {
        id: hookProc
        stdout: StdioCollector { id: hookOut }
        stderr: StdioCollector { id: hookErr }
        onExited: (code) => {
            // Solo pre_tool_use puede vetar; los demás son avisos.
            if (code !== 0 && ai._hookEvent === "pre_tool_use"
                    && ai._hookGateIndex >= 0) {
                let why = (hookOut.text || "").trim() || (hookErr.text || "").trim()
                if (why === "")
                    why = I18n.tr("blocked by a hook (exit %1)").arg(code)
                const idx = ai._hookGateIndex
                ai._hookQueue = []
                ai._hookDone = null
                ai._hookGateIndex = -1
                ai._blockTool(idx, why)
                return
            }
            ai._nextHook()
        }
    }

    // Una llamada vetada por un hook: se marca rechazada y el motivo vuelve al
    // modelo, que así puede corregir en vez de reintentar a ciegas.
    function _blockTool(index, reason) {
        const m = messages.get(index)
        if (!m || m.toolStatus !== "pending")
            return
        messages.setProperty(index, "toolStatus", "rejected")
        messages.setProperty(index, "toolResult",
            I18n.tr("Blocked by a hook: ") + String(reason).slice(0, 2000))
        _saveHistory()
        _advanceTools()
    }

    function _hooksFor(event, toolName) {
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

    // ── Habilidades (skills) ─────────────────────────────────────────────────
    // Carpetas sueltas en Modules/IA/skills/<nombre>/SKILL.md, con el
    // mismo formato que las de Claude Code: frontmatter YAML (name/description)
    // y el cuerpo en Markdown. Se cargan con REVELACIÓN PROGRESIVA — al prompt
    // de sistema va el catálogo (nombre y descripción, ordenado por lo que
    // venga a cuento) y el texto entero solo cuando hace falta. Así se pueden
    // tener veinte habilidades sin gastar contexto en las diecinueve que hoy
    // no pintan nada. Quién decide que "hace falta": el modelo con use_skill,
    // y también el propio harness (ver autoSkill) — que no todos los modelos
    // se acuerdan de pedir lo que necesitan.
    readonly property string skillsDir: iaDir + "/skills"
    property var skills: []            // [{id, name, description}]

    // Habilitadas: el mapa de Ajustes manda, y lo que no esté en el mapa cuenta
    // como habilitada (instalar una carpeta ya es decir que la quieres).
    function skillEnabled(id) {
        const m = Settings.aiSkills || ({})
        return m[id] !== false
    }
    function setSkillEnabled(id, on) {
        const m = Object.assign({}, Settings.aiSkills)
        m[id] = on
        Settings.aiSkills = m
    }
    readonly property var activeSkills: skills.filter(s => skillEnabled(s.id))

    function rescanSkills() {
        if (!skillScan.running)
            skillScan.running = true
    }

    Process {
        id: skillScan
        running: true
        // Una sola pasada: por cada SKILL.md, un separador con su id y el
        // archivo ENTERO (tope de 24 kB). Antes solo se leía el frontmatter y
        // el cuerpo se iba a buscar con otro proceso al invocarla; teniéndolo
        // ya en memoria, invocar una habilidad es instantáneo y —lo que
        // importa— el harness puede decidir él mismo cargarla.
        command: ["sh", "-c",
            'for f in "$QS_DIR"/*/SKILL.md; do [ -f "$f" ] || continue; '
            + 'd=$(dirname -- "$f"); printf "===QS-SKILL===%s\\n" "$(basename -- "$d")"; '
            + 'head -c 24000 -- "$f"; printf "\\n"; done']
        environment: ({ QS_DIR: ai.skillsDir })
        stdout: StdioCollector { id: skillOut }
        onExited: {
            const parts = (skillOut.text || "").split("===QS-SKILL===")
            const found = []
            for (let i = 1; i < parts.length; i++) {
                const nl = parts[i].indexOf("\n")
                if (nl < 0)
                    continue
                const id = parts[i].slice(0, nl).trim()
                const head = parts[i].slice(nl + 1)     // el archivo entero
                // Frontmatter: el bloque entre las dos primeras líneas "---".
                let name = id, desc = "", allowed = []
                const fm = head.match(/^---\s*\n([\s\S]*?)\n---/)
                if (fm) {
                    // allowed-tools: la habilidad puede declarar a QUÉ
                    // herramientas se limita mientras esté en uso (formato de
                    // Anthropic/OpenWorker). Admite lista en línea
                    // ("a, b, c") y lista YAML de guiones.
                    const at = fm[1].match(/^allowed[-_]tools:\s*(.*)$/m)
                    if (at) {
                        const inline = at[1].trim().replace(/^\[|\]$/g, "")
                        if (inline !== "")
                            allowed = inline.split(",").map(x => x.trim().replace(/^["']|["']$/g, ""))
                                            .filter(x => x !== "")
                        else {
                            const rest = fm[1].slice(fm[1].indexOf(at[0]) + at[0].length)
                            const items = rest.match(/^\s*-\s*(.+)$/gm) || []
                            allowed = items.map(l => l.replace(/^\s*-\s*/, "").trim()
                                                      .replace(/^["']|["']$/g, ""))
                        }
                    }
                    const n = fm[1].match(/^name:\s*(.+)$/m)
                    const d = fm[1].match(/^description:\s*(.+)$/m)
                    if (n) name = n[1].trim().replace(/^["']|["']$/g, "")
                    if (d) desc = d[1].trim().replace(/^["']|["']$/g, "")
                }
                // 'text' es lo que devuelve use_skill (el archivo tal cual) y
                // 'body' lo que se inyecta al cargarla sola: sin el
                // frontmatter, que en el prompt no aporta nada.
                found.push({ id: id, name: name, description: desc,
                             allowedTools: allowed,
                             text: head.trim(),
                             body: (fm ? head.slice(fm[0].length) : head).trim() })
            }
            ai.skills = found
            // Reescaneo por fallo (regla de OpenWorker): si el modelo pidió una
            // habilidad que aún no estaba y por eso se reescaneó, se reintenta
            // la lectura ahora que sí aparece.
            if (ai._skillRetry !== "") {
                const want = ai._skillRetry
                ai._skillRetry = ""
                const idx = ai._skillPending
                ai._skillPending = -1
                if (idx >= 0)
                    ai.approveTool(idx)
                else if (want !== "")
                    ai.pushInfo(I18n.tr("Skills reloaded."))
            }
        }
    }
    // Estado del reintento tras reescanear (habilidad creada tras arrancar).
    property string _skillRetry: ""
    property int _skillPending: -1
    // Vocabulario acotado por la habilidad en uso (allowed-tools). Vacío = sin
    // límite. Se olvida al cambiar de conversación.
    property var activeSkillTools: []

    // ── Qué habilidad hace falta AHORA ───────────────────────────────────────
    // La revelación progresiva de Claude Code confía en que el modelo, viendo
    // la lista, se acuerde de pedir la que toca. Un modelo grande lo hace; uno
    // local pequeño, la mitad de las veces no — y entonces la habilidad no
    // existe en la práctica. Así que aquí el harness también mira: puntúa las
    // habilidades contra lo que acaba de pedir el usuario y, si una encaja
    // claramente, le CARGA sus instrucciones sin esperar a que las pida.
    // Sigue pudiendo pedir cualquier otra con use_skill.
    readonly property var _rankedSkills:
        agentMode ? TU.rankSkills(activeSkills, _lastUserText) : []

    // Cuándo se considera que encaja "claramente": que se nombre su tema
    // (una palabra propia de su nombre vale 3) o que coincidan tres términos
    // de su descripción. Y además tiene que DESPEGARSE de la segunda: ante una
    // duda entre dos, no se carga ninguna y decide el modelo con el catálogo
    // delante. Cargar la equivocada cuesta más que no cargar ninguna.
    readonly property int autoSkillFloor: 2
    readonly property int autoSkillMargin: 2
    readonly property var autoSkill: {
        const r = _rankedSkills
        if (r.length === 0 || r[0].score < autoSkillFloor)
            return null
        if (r.length > 1 && r[0].score - r[1].score < autoSkillMargin)
            return null
        return r[0].skill
    }

    // Presupuesto del catálogo, como todo lo demás: proporcional a la ventana
    // del modelo. Con ventana holgada caben las descripciones enteras de
    // muchas habilidades; con una modesta, entran las que vienen a cuento y el
    // resto se anuncian solo por su nombre — que para pedirlas basta.
    readonly property int skillsBudget:
        Math.max(1000, Math.min(8000, Math.round(charBudget * 0.12)))

    readonly property string _skillsBlock: {
        const r = _rankedSkills
        if (r.length === 0)
            return ""
        let block = "\nHabilidades disponibles (instrucciones que el usuario ha "
                  + "instalado). Si la tarea encaja con una, LEE sus instrucciones "
                  + "con la herramienta use_skill ANTES de trabajar, y síguelas:"
        // Por orden de encaje y con la descripción COMPLETA: es lo que decide
        // si se usa o no, y recortarla a mitad de frase se comía justo la
        // parte que dice cuándo viene a cuento.
        let chars = 0
        const resto = []
        for (let i = 0; i < r.length; i++) {
            const s = r[i].skill
            // La que ya va cargada entera no se anuncia otra vez.
            if (autoSkill && s.id === autoSkill.id)
                continue
            const line = "\n- " + s.name + ": " + s.description
            if (chars + line.length > skillsBudget && chars > 0) {
                resto.push(s.name)
                continue
            }
            chars += line.length
            block += line
        }
        if (resto.length > 0)
            block += "\nInstaladas también, por si vienen al caso (pídelas por "
                   + "su nombre con use_skill): " + resto.join(", ") + "."
        return block
    }

    // Las instrucciones de la habilidad que el harness ha decidido cargar.
    readonly property string _autoSkillBlock: {
        const s = autoSkill
        if (!s)
            return ""
        const cap = Math.max(2000, Math.min(12000, Math.round(charBudget * 0.3)))
        return "\n\nINSTRUCCIONES DE LA HABILIDAD «" + s.name + "», cargadas "
             + "porque encajan con lo que te acaban de pedir. Síguelas; no "
             + "hace falta que la pidas con use_skill.\n"
             + s.body.slice(0, cap)
    }

    // Dos modos: charlar o actuar. NO hay un tercer modo "plan" — planificar
    // no es un ajuste que el usuario tenga que elegir de antemano, sino una
    // decisión del agente al leer el encargo: si la tarea lo merece, llama a
    // propose_plan y espera el visto bueno (ver el prompt de agente).
    readonly property bool agentMode: Settings.aiMode === "agent"

    // Aprobar el plan que el agente propuso: luz verde y a ejecutarlo.
    function approvePlan(index) {
        const m = messages.get(index)
        if (!m || m.toolName !== "propose_plan" || m.toolStatus !== "pending")
            return
        _resolveTool(index, "El usuario APROBÓ el plan. Ejecútalo paso a paso, "
            + "verificando como dijiste; anótalo con todo_write para que se "
            + "vea el avance.")
    }
    function rejectPlan(index, feedback) {
        const m = messages.get(index)
        if (!m || m.toolName !== "propose_plan" || m.toolStatus !== "pending")
            return
        const f = String(feedback || "").trim()
        _resolveTool(index, "El usuario NO aprobó el plan"
            + (f !== "" ? ". Dice: " + f : "")
            + ". Revísalo y vuelve a proponerlo; no ejecutes nada aún.")
    }

    readonly property string systemPrompt:
        "Eres un asistente integrado en el escritorio Linux del usuario "
        + "(Arch + Hyprland + Quickshell). Fecha actual: "
        + new Date().toLocaleDateString(Qt.locale(), "yyyy-MM-dd") + ". "
        + "Idioma de la interfaz: " + Settings.language + " (responde en el "
        + "idioma del usuario). Usa Markdown; código en bloques ```. No "
        + "inventes: si no sabes algo, dilo."
        + (agentMode
            ? " Estás en modo AGENTE: dispones de herramientas (ejecutar "
              + "comandos, leer/listar/escribir archivos, abrir URLs, analizar "
              + "servidores por SSH, consultar el sistema, guardar notas). Para "
              + "tareas de varios pasos, enuncia un plan breve (todo_write) y ve "
              + "avanzando. Cuando necesites INFORMACIÓN de varios sitios a la "
              + "vez (leer/listar/buscar/grep), pídelo TODO en el mismo turno "
              + "con varias llamadas en paralelo, en vez de una tras otra: es "
              + "más rápido. Las que cambian algo (escribir, ejecutar) las "
              + "aprueba el usuario. Los entregables (informes, scripts) "
              + "escríbelos como archivo con write_file."
              + " ANTES de tocar nada, decide TÚ si la tarea merece un plan: "
              + "si lleva tres pasos o más, o si algo es irreversible (borrar, "
              + "sobrescribir, reiniciar servicios, cambiar un servidor), "
              + "explora lo justo y llama a propose_plan; mientras el usuario "
              + "no lo apruebe no ejecutes nada. Para lo pequeño o reversible "
              + "no lo uses: hazlo y ya."
            : " Estás en modo CHAT, sin herramientas: solo conversación.")
        + (personas[Settings.aiPersona] || "")
        + (Settings.aiCustomPrompt.trim() !== ""
            ? "\nInstrucciones del usuario: " + Settings.aiCustomPrompt.trim() : "")
        + _memoryBlock
        + _instinctBlock
        + _skillsBlock
        + _autoSkillBlock

    // Las herramientas que el modelo puede PROPONER en modo agente. Ejecutar,
    // solo tras aprobación expresa (ver approveTool) — salvo las de solo
    // lectura si el usuario activó la auto-aprobación.
    readonly property var toolDefs: TD.core().concat(sysQueryDefs).concat(sysActionDefs)
     .concat(sshQueryDefs).concat(sshActionDefs)

    // ── Herramientas de administración de sistemas ───────────────────────────
    // Dos familias con reglas distintas. Las CONSULTAS no cambian nada del
    // sistema (systemctl status, journalctl, ss, df, pacman -Q…): cuentan como
    // lectura para la auto-aprobación y también las hereda el subagente, que
    // así sabe diagnosticar solo. Las ACCIONES (parar servicios, matar
    // procesos) siempre nacen con tarjeta. Todo argumento del modelo viaja por
    // entorno — nada se interpola en la línea de comandos.
    readonly property var sysQueryDefs: TD.sysQuery()
    // Herramientas de servidores remotos. Funcionan SOLO CON LO QUE DIGA EL
    // MENSAJE: 'host' admite un destino suelto ([usuario@]host[:puerto]) o el
    // nombre de uno guardado, y user/port/password de la llamada mandan sobre
    // lo guardado. Guardar servidores es comodidad, no requisito.
    readonly property var sshQueryDefs: TD.sshQuery()
    readonly property var sshActionDefs: TD.sshAction()

    readonly property var sysActionDefs: TD.sysAction()

    // ── El vocabulario de SOLO LECTURA, en un solo sitio ─────────────────────
    // Leer archivos, consultar el sistema y consultar servidores remotos son
    // las tres familias que no cambian nada. Se juntan aquí para que exista UNA
    // respuesta a "¿qué puede hacer algo que no toca nada?", y de ella cuelgan
    // tanto los esquemas que ve un subagente como el constructor de comandos.
    // Antes cada uno llevaba su copia y ya habían divergido: el subagente
    // anunciaba un read_file sin offset/limit que el harness sí sabía hacer.
    readonly property var _roNames: ["read_file", "read_files", "list_dir",
                                     "grep_files", "glob_files", "fetch_url"]
    readonly property var readOnlyDefs:
        TD.core().filter(d => _roNames.indexOf(d["function"].name) !== -1)
          .concat(sysQueryDefs).concat(sshQueryDefs)

    // El constructor correspondiente: prueba las tres familias en orden.
    // Devuelve {cmd,env} | {error} | null (null = no es de solo lectura).
    function readOnlyCommand(tool, args) {
        return sysQueryCommand(tool, args)
            || sshQueryCommand(tool, args)
            || roCommand(tool, args)
    }

    // Construye el comando de una CONSULTA de sistema. Lo comparten la tarjeta
    // del agente principal y el subagente: una sola jaula que mantener.
    function sysQueryCommand(tool, args) {
        switch (tool) {
        case "system_status":
            return { cmd: ["sh", "-c",
                'echo "== uptime"; uptime; '
                + 'echo "== memoria"; free -h; '
                + 'echo "== discos"; df -h -x tmpfs -x devtmpfs -x efivarfs; '
                + 'echo "== unidades fallidas"; systemctl --failed --no-legend --no-pager | head -n 10; '
                + 'systemctl --user --failed --no-legend --no-pager | head -n 5; '
                + 'echo "== temperatura"; sensors 2>/dev/null | grep -E "°C" | head -n 8'],
                env: {} }
        case "journal_query": {
            const lines = Math.min(Math.max(parseInt(args.lines) || 60, 1), 200)
            let script = 'journalctl --no-pager -o short-iso -n ' + lines
            const env = {}
            if (String(args.unit || "").trim() !== "") {
                script += ' -u "$QS_UNIT"'
                env.QS_UNIT = String(args.unit).trim()
            }
            const prios = ["emerg", "alert", "crit", "err", "warning", "notice", "info", "debug"]
            if (prios.indexOf(String(args.priority || "")) !== -1)
                script += ' -p ' + args.priority
            if (String(args.since || "").trim() !== "") {
                script += ' --since "$QS_SINCE"'
                env.QS_SINCE = String(args.since).trim()
            }
            if (String(args.grep || "").trim() !== "") {
                script += ' -g "$QS_GREP"'
                env.QS_GREP = String(args.grep).trim()
            }
            return { cmd: ["sh", "-c", script + ' | tail -c 16000'], env: env }
        }
        case "service_query": {
            const scope = args.user === true ? " --user" : ""
            const list = String(args.list || "")
            if (list === "failed")
                return { cmd: ["sh", "-c", 'systemctl' + scope + ' --failed --no-pager --no-legend'], env: {} }
            if (list === "timers")
                return { cmd: ["sh", "-c", 'systemctl' + scope + ' list-timers --no-pager | head -n 25'], env: {} }
            if (list === "running")
                return { cmd: ["sh", "-c", 'systemctl' + scope + ' list-units --type=service --state=running --no-pager --no-legend | head -n 40'], env: {} }
            const unit = String(args.name || "").trim()
            if (unit === "")
                return { error: "Falta la unidad o un listado (failed/timers/running)." }
            return { cmd: ["sh", "-c", 'systemctl' + scope + ' status --no-pager -l -n 15 -- "$QS_UNIT" | head -c 8000; exit 0'],
                     env: { QS_UNIT: unit } }
        }
        case "process_query": {
            const f = String(args.filter || "").trim()
            if (f !== "")
                return { cmd: ["sh", "-c", 'pgrep -af -- "$QS_F" | head -n 30'], env: { QS_F: f } }
            const key = args.sort === "mem" ? "-%mem" : "-%cpu"
            return { cmd: ["sh", "-c",
                'ps axo pid,user,%cpu,%mem,etime,comm --sort=' + key + ' | head -n 16'], env: {} }
        }
        case "network_query": {
            switch (String(args.kind || "")) {
            case "interfaces": return { cmd: ["sh", "-c", 'ip -br addr'], env: {} }
            case "routes":     return { cmd: ["sh", "-c", 'ip route; echo; ip -6 route | head -n 10'], env: {} }
            case "ports":      return { cmd: ["sh", "-c", 'ss -tulpn 2>/dev/null | head -n 40'], env: {} }
            case "ping": {
                const h = String(args.host || "").trim()
                if (h === "") return { error: "Falta el host." }
                return { cmd: ["sh", "-c", 'ping -c 3 -W 2 -- "$QS_H" 2>&1 | tail -n 5'], env: { QS_H: h } }
            }
            }
            return { error: "kind debe ser interfaces, routes, ports o ping." }
        }
        case "disk_query": {
            let p = String(args.path || "").trim()
            if (p === "")
                return { cmd: ["sh", "-c", 'df -h -x tmpfs -x devtmpfs -x efivarfs'], env: {} }
            // df/du no expanden la tilde: se hace aquí (sin clamp — un admin
            // también mira /var; la consulta sigue siendo solo lectura).
            const home = Quickshell.env("HOME")
            if (p === "~") p = home
            else if (p.startsWith("~/")) p = home + p.slice(1)
            return { cmd: ["sh", "-c",
                'df -h -- "$QS_P" 2>/dev/null; echo; du -xh -d1 -- "$QS_P" 2>/dev/null | sort -rh | head -n 15'],
                env: { QS_P: p } }
        }
        case "package_query": {
            const n = String(args.name || "").trim()
            const env = { QS_N: n }
            switch (String(args.op || "")) {
            case "info":
                if (n === "") return { error: "Falta el nombre." }
                return { cmd: ["sh", "-c", 'pacman -Qi -- "$QS_N" 2>/dev/null || pacman -Si -- "$QS_N" 2>/dev/null || echo "No existe."'], env: env }
            case "search":
                if (n === "") return { error: "Falta el término." }
                return { cmd: ["sh", "-c", 'pacman -Ss -- "$QS_N" | head -n 30'], env: env }
            case "updates":
                return { cmd: ["sh", "-c", 'checkupdates 2>/dev/null || pacman -Qu 2>/dev/null || echo "Al día (o sin caché de sincronización)."'], env: {} }
            case "orphans":
                return { cmd: ["sh", "-c", 'pacman -Qtdq 2>/dev/null || echo "Sin huérfanos."'], env: {} }
            case "owns":
                if (n === "") return { error: "Falta la ruta." }
                return { cmd: ["sh", "-c", 'pacman -Qo -- "$QS_N" 2>&1'], env: env }
            }
            return { error: "op debe ser info, search, updates, orphans u owns." }
        }
        }
        return null
    }

    // Hash corto de una línea, definido UNA vez y compartido por quien numera
    // (read_file) y quien verifica (edit_lines): si divergieran, el ancla
    // nunca casaría. Es un FNV-1a de 16 bits en base36 — no busca resistencia
    // criptográfica, solo detectar que la línea ya no es la que el modelo vio.
    // Se ignoran los espacios del final, que cambian sin querer decir nada.
    readonly property string _pyHash:
        'def h(s):\n'
        + '    v=2166136261\n'
        + '    for c in s.rstrip().encode("utf-8",errors="replace"):\n'
        + '        v=((v^c)*16777619)&0xFFFFFFFF\n'
        + '    v&=0xFFFF\n'
        + '    d="0123456789abcdefghijklmnopqrstuvwxyz"; o=""\n'
        + '    for _ in range(3):\n'
        + '        o=d[v%36]+o; v//=36\n'
        + '    return o\n'

    // Constructor de las herramientas de SOLO LECTURA locales (leer, listar,
    // grep, glob, descargar). Vive UNA vez y lo comparten el agente principal
    // y el subagente: la misma jaula ($HOME clampado, todo por entorno) que
    // auditar en un solo sitio. Devuelve {cmd,env} | {error} | null.
    function roCommand(tool, args) {
        switch (tool) {
        case "read_file": {
            const p = _safePath(args.path)
            if (p === "") return { error: "Ruta fuera de la carpeta personal." }
            const off = Math.max(1, parseInt(args.offset) || 1)
            const lim = Math.max(1, Math.min(2000, parseInt(args.limit) || 400))
            // Lectura por TRAMOS de líneas: antes solo llegaban los primeros
            // 16 kB, lo que en un archivo grande es inútil. Y en modo
            // 'numbered', cada línea sale como N#hash|contenido para que
            // edit_lines pueda comprobar después que nada se movió.
            return { cmd: ["python3", "-c", _pyHash
                + 'import os,sys\n'
                + 'p=os.environ["QS_P"]; off=int(os.environ["QS_OFF"]); lim=int(os.environ["QS_LIM"])\n'
                + 'num=os.environ["QS_NUM"]=="1"\n'
                + 'try: lines=open(p,encoding="utf-8",errors="replace").read().split("\\n")\n'
                + 'except OSError as e: print("No se pudo leer:",e); raise SystemExit\n'
                + 'total=len(lines); sel=lines[off-1:off-1+lim]\n'
                + 'out=[]\n'
                + 'for i,l in enumerate(sel):\n'
                + '    n=off+i\n'
                + '    out.append(f"{n}#{h(l)}|{l}" if num else l)\n'
                + 'body="\\n".join(out)[:16000]\n'
                + 'print(body)\n'
                + 'end=off-1+len(sel)\n'
                + 'if end<total: print(f"\\n[…{total-end} lineas mas; sigue con offset={end+1}]")\n'],
                env: { QS_P: p, QS_OFF: String(off), QS_LIM: String(lim),
                       QS_NUM: args.numbered ? "1" : "0" } }
        }
        case "read_files": {
            const lista = Array.isArray(args.paths) ? args.paths.slice(0, 8) : []
            if (lista.length === 0)
                return { error: "Falta la lista 'paths' (hasta 8 rutas)." }
            // Cada ruta se resuelve y se acota en python: aquí realpath ya
            // sigue los enlaces, así que un symlink que escapa de $HOME se
            // rechaza directamente (más estricto que el aviso del caso de un
            // solo archivo, y suficiente para una lectura en lote).
            return { cmd: ["python3", "-c",
                'import os\n'
                + 'home=os.path.realpath(os.path.expanduser("~"))\n'
                + 'out=[]\n'
                + 'for p in os.environ["QS_LIST"].split("\\n"):\n'
                + '    p=p.strip()\n'
                + '    if not p: continue\n'
                + '    ap=os.path.realpath(os.path.abspath(os.path.expanduser(p)))\n'
                + '    cab="\\n--- %s ---\\n" % p\n'
                + '    if ap!=home and not ap.startswith(home+os.sep):\n'
                + '        out.append(cab+"[fuera de la carpeta personal]"); continue\n'
                + '    try: s=open(ap,encoding="utf-8",errors="replace").read(8000)\n'
                + '    except OSError as e: out.append(cab+"[no se pudo leer: %s]"%e); continue\n'
                + '    out.append(cab+s)\n'
                + 'print("".join(out)[:24000])\n'],
                env: { QS_LIST: lista.map(String).join("\n") } }
        }
        case "list_dir": {
            const p = _safePath(args.path)
            if (p === "") return { error: "Ruta fuera de la carpeta personal." }
            return { cmd: ["sh", "-c", 'ls -lah -- "$QS_P" | head -n 80'], env: { QS_P: p } }
        }
        case "grep_files": {
            const p = _safePath(args.path)
            if (p === "") return { error: "Ruta fuera de la carpeta personal." }
            return { cmd: ["sh", "-c",
                'timeout 15 grep -rnIi --exclude-dir=.git -e "$QS_PAT" -- "$QS_P" | head -c 16000'],
                env: { QS_PAT: String(args.pattern || ""), QS_P: p } }
        }
        case "glob_files": {
            const p = _safePath(args.path)
            if (p === "") return { error: "Ruta fuera de la carpeta personal." }
            return { cmd: ["sh", "-c",
                'find "$QS_P" -iname "$QS_PAT" -not -path "*/.git/*" 2>/dev/null | head -n 100'],
                env: { QS_PAT: String(args.pattern || "*"), QS_P: p } }
        }
        case "fetch_url": {
            const url = String(args.url || "").trim()
            if (!/^https?:\/\//i.test(url)) return { error: "Solo URLs http(s)." }
            return { cmd: ["sh", "-c",
                'curl -sSL --max-time 20 --max-filesize 2000000 -- "$QS_U" | '
                // errors=replace: una web en Latin-1 (las viejas en español)
                // no debe tirar la herramienta entera por un byte — los que no
                // sean UTF-8 salen como "�" y el resto del texto se conserva.
                + 'python3 -c "import sys,re,html; sys.stdin.reconfigure(errors=\'replace\'); t=sys.stdin.read(); '
                + "t=re.sub(r'(?is)<(script|style)[^>]*>.*?</\\\\1>',' ',t); "
                + "t=re.sub(r'(?s)<[^>]+>',' ',t); t=html.unescape(t); "
                + "t=re.sub(r'[ \\\\t]+',' ',t); t=re.sub(r'\\\\n\\\\s*\\\\n+','\\\\n\\\\n',t); "
                + 'print(t.strip()[:20000])"'], env: { QS_U: url } }
        }
        }
        return null
    }

    // ── Servidores remotos: SSH / SFTP / Plesk / cPanel ──────────────────────
    // La misma división que en local: CONSULTAS curadas (el harness construye
    // el comando, el modelo solo elige host y unos filtros → auto-aprobables y
    // heredadas por el subagente) y ACCIONES crudas (ejecutar por SSH, subir/
    // bajar archivos, tocar el panel de hosting → siempre con tarjeta).
    //
    // Transporte: ssh/scp con clave (agente) o, si el host tiene contraseña,
    // sshpass tomándola por ENTORNO (SSHPASS) — jamás en argv, que se ve en
    // `ps`. Cualquier dato del modelo que entre en un comando REMOTO viaja en
    // base64 y se descodifica en el otro extremo (`printf %s B64 | base64 -d`):
    // el base64 no lleva comillas ni metacaracteres, así que no hay forma de
    // que un nombre de dominio "creativo" se convierta en otra orden.

    // Resolución del destino. La idea es que el harness FUNCIONE SOLO: si el
    // usuario dice "entra en root@1.2.3.4 con la contraseña X y mírame los
    // logs", eso basta — no hay que registrar nada antes. Los servidores
    // guardados existen como comodidad (escribir "web1" en vez de repetir
    // credenciales), no como requisito.
    //
    // 'host' admite las dos formas: el nombre de uno guardado, o un destino
    // suelto tipo [usuario@]host[:puerto]. Los parámetros user/port/password
    // de la llamada siempre mandan sobre lo guardado.
    function _sshHost(spec, args) {
        const raw = String(spec || "").trim()
        if (raw === "")
            return null
        const saved = (Settings.aiSshHosts || []).find(h => h.name === raw)
        let host = saved
            ? { name: saved.name, host: saved.host, user: saved.user,
                port: saved.port, saved: true }
            : null
        if (!host) {
            // Destino suelto del mensaje: [usuario@]host[:puerto]
            let rest = raw, user = "root", port = 22
            const at = rest.indexOf("@")
            if (at > 0) { user = rest.slice(0, at); rest = rest.slice(at + 1) }
            const colon = rest.lastIndexOf(":")
            if (colon > 0 && /^\d+$/.test(rest.slice(colon + 1))) {
                port = parseInt(rest.slice(colon + 1))
                rest = rest.slice(0, colon)
            }
            if (rest === "")
                return null
            host = { name: raw, host: rest, user: user, port: port, saved: false }
        }
        // Lo que venga en la llamada pisa: el mensaje es la última palabra.
        const a = args || ({})
        if (String(a.user || "").trim() !== "") host.user = String(a.user).trim()
        if (parseInt(a.port) > 0) host.port = parseInt(a.port)
        return host
    }
    // Contraseñas en memoria de sesión (cargadas del llavero al arrancar, o
    // escritas en Ajustes). El argumento 'password' de una llamada las pisa
    // para el caso "te la escribo en el mensaje".
    property var sshPass: ({})
    // ¿Está sshpass? Sin él, el login por contraseña no es posible y conviene
    // decirlo claro en vez de dejar que el Process falle con "command not found".
    property bool haveSshpass: false
    readonly property Process _sshpassCheck: Process {
        running: true
        command: ["sh", "-c", "command -v sshpass"]
        onExited: (code) => ai.haveSshpass = (code === 0)
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
    readonly property Instantiator _sshPassLoad: Instantiator {
        model: Settings.aiSshHosts
        delegate: Process {
            readonly property string hn: (modelData && modelData.name) || ""
            running: ai.haveKeyring && hn !== ""
            command: ["secret-tool", "lookup", "service", "quickshell-ai-ssh", "host", hn]
            stdout: StdioCollector { id: spOut }
            onExited: {
                const k = (spOut.text || "").trim()
                if (k !== "") {
                    const m = Object.assign({}, ai.sshPass)
                    m[hn] = k
                    ai.sshPass = m
                }
            }
        }
    }

    // Prefijo argv del transporte + entorno, según haya contraseña o no.
    function _sshArgv(bin, host, portFlag, explicitPw) {
        const pw = String(explicitPw || "").trim() !== ""
            ? String(explicitPw).trim() : (sshPass[host.name] || "")
        // Marca de contraseña-sin-sshpass: quien llama lo detecta y avisa.
        if (pw !== "" && !haveSshpass)
            return { argv: [], env: {}, needsSshpass: true }
        const port = String(host.port || 22)
        const opts = ["-o", "StrictHostKeyChecking=accept-new",
                      "-o", "ConnectTimeout=12", "-o", "ServerAliveInterval=5",
                      "-o", "NumberOfPasswordPrompts=1", portFlag, port]
        const dest = (host.user || "root") + "@" + host.host
        if (pw !== "")
            return { argv: ["sshpass", "-e", bin].concat(opts).concat([dest]),
                     env: { SSHPASS: pw } }
        // Sin contraseña: clave/agente, y BatchMode para que no se cuelgue
        // pidiéndola por un terminal que no existe.
        return { argv: [bin].concat(opts).concat(["-o", "BatchMode=yes", dest]),
                 env: {} }
    }
    // Destino + transporte de una llamada remota, con los dos fallos que
    // siempre hay que contar antes de intentar nada: no sé a qué máquina, o
    // hay contraseña y no está sshpass. Los tres sitios que abren una conexión
    // repetían estas mismas comprobaciones y sus mismos mensajes.
    // Devuelve {host, t} o {error}.
    function _sshFor(args, bin, portFlag) {
        const host = _sshHost(args.host, args)
        if (!host)
            return { error: "Falta el servidor. Dime el destino (por ejemplo "
                + "root@1.2.3.4) o el nombre de uno guardado." }
        const t = _sshArgv(bin, host, portFlag, args.password)
        if (t.needsSshpass)
            return { error: "Falta 'sshpass' para entrar con contraseña. "
                + "Instálalo (pacman -S sshpass) o usa una clave SSH." }
        return { host: host, t: t }
    }

    // Un dato del modelo, listo para viajar dentro de un comando remoto.
    // TU.b64utf8, no Qt.btoa: btoa trabaja en Latin-1 y cualquier tilde
    // ("sesión", un dominio con ñ) llegaba al servidor como byte inválido.
    function _rarg(v) {
        return '"$(printf %s ' + TU.b64utf8(String(v)) + ' | base64 -d)"'
    }

    // CONSULTAS remotas (solo lectura). Comparten builder con el subagente.
    function sshQueryCommand(tool, args) {
        const isRemote = ["server_status", "server_logs", "sftp_ls", "hosting_query"]
        if (isRemote.indexOf(tool) === -1)
            return null
        const conn = _sshFor(args, "ssh", "-p")
        if (conn.error !== undefined)
            return conn
        const host = conn.host, t = conn.t
        let remote = ""
        switch (tool) {
        case "server_status":
            remote = 'echo "== uptime"; uptime; echo "== memoria"; free -h; '
                   + 'echo "== discos"; df -h -x tmpfs -x devtmpfs 2>/dev/null; '
                   + 'echo "== fallidas"; systemctl --failed --no-legend --no-pager 2>/dev/null | head -n 10; '
                   + 'echo "== top"; ps axo pid,%cpu,%mem,comm --sort=-%cpu | head -n 8'
            break
        case "server_logs": {
            const lines = Math.min(Math.max(parseInt(args.lines) || 60, 1), 300)
            const path = String(args.path || "").trim()
            if (path !== "") {
                // Un archivo de log concreto (nginx, apache, plesk…).
                remote = 'tail -n ' + lines + ' -- ' + _rarg(path)
                if (String(args.grep || "").trim() !== "")
                    remote += ' | grep -iF -- ' + _rarg(args.grep)
            } else {
                remote = 'journalctl --no-pager -o short-iso -n ' + lines
                if (String(args.unit || "").trim() !== "")
                    remote += ' -u ' + _rarg(args.unit)
                const prios = ["emerg","alert","crit","err","warning","notice","info","debug"]
                if (prios.indexOf(String(args.priority || "")) !== -1)
                    remote += ' -p ' + args.priority
                if (String(args.since || "").trim() !== "")
                    remote += ' --since ' + _rarg(args.since)
                if (String(args.grep || "").trim() !== "")
                    remote += ' -g ' + _rarg(args.grep)
            }
            remote += ' 2>&1 | tail -c 16000'
            break
        }
        case "sftp_ls": {
            const path = String(args.path || ".").trim() || "."
            remote = 'ls -lah -- ' + _rarg(path) + ' 2>&1 | head -n 100'
            break
        }
        case "hosting_query":
            return _hostingRead(host, t, args)
        }
        return { cmd: t.argv.concat([remote]), env: t.env }
    }

    // Lecturas de Plesk / cPanel: cada 'op' es un comando FIJO del panel; lo
    // único variable (un dominio, una cuenta) entra en base64.
    function _hostingRead(host, t, args) {
        const panel = String(args.panel || "")
        const op = String(args.op || "")
        const name = String(args.name || "").trim()
        let remote = ""
        if (panel === "plesk") {
            switch (op) {
            case "version": remote = 'plesk version'; break
            case "domains": remote = 'plesk bin domain --list'; break
            case "subscriptions": remote = 'plesk bin subscription --list'; break
            case "databases": remote = 'plesk bin database --list'; break
            case "domain_info":
                if (name === "") return { error: "Falta el dominio." }
                remote = 'plesk bin domain --info ' + _rarg(name); break
            default: return { error: "op de Plesk no válida (version, domains, subscriptions, databases, domain_info)." }
            }
        } else if (panel === "cpanel") {
            switch (op) {
            case "version": remote = 'whmapi1 version'; break
            case "accounts": remote = 'whmapi1 listaccts'; break
            case "account_info":
                if (name === "") return { error: "Falta la cuenta." }
                remote = 'whmapi1 accountsummary user=' + _rarg(name); break
            case "domains": remote = 'whmapi1 get_domain_info'; break
            case "disk": remote = 'whmapi1 getdiskusage'; break
            default: return { error: "op de cPanel no válida (version, accounts, account_info, domains, disk)." }
            }
        } else {
            return { error: "panel debe ser 'plesk' o 'cpanel'." }
        }
        // Panel bajo sudo si el usuario no es root (habitual con Plesk/WHM).
        const wrapped = (host.user && host.user !== "root")
            ? 'sudo -n sh -c ' + _rarg(remote) : remote
        return { cmd: t.argv.concat([wrapped + ' 2>&1 | tail -c 16000']), env: t.env }
    }

    // ── Cliente MCP (Model Context Protocol, transporte stdio) ───────────────
    // Cada servidor de Settings.aiMcpServers es un proceso hijo que habla
    // JSON-RPC línea a línea: initialize → notifications/initialized →
    // tools/list, y sus herramientas se anuncian al modelo con el prefijo
    // mcp__<servidor>__<tool> (el mismo esquema de nombres de Claude Code).
    // Ejecutar una pasa por la MISMA tarjeta de aprobación que el resto.
    property var mcpTools: []          // [{server, name, description, schema}]
    property var mcpStatus: ({})       // servidor → starting|ok|error(<msg>)
    property var _mcpProcs: ({})       // servidor → Process vivo (registro)

    function _mcpSetStatus(name, st) {
        const m = Object.assign({}, mcpStatus)
        m[name] = st
        mcpStatus = m
    }
    function _mcpSetTools(name, tools) {
        // Reemplaza las de ese servidor, conserva las del resto.
        mcpTools = mcpTools.filter(t => t.server !== name).concat(tools)
    }
    // Quitar un servidor de la lista debe retirar sus herramientas AHORA: el
    // Instantiator destruye el proceso y su onExited puede no llegar a correr.
    readonly property Connections _mcpPrune: Connections {
        target: Settings
        function onAiMcpServersChanged() {
            const names = (Settings.aiMcpServers || []).map(s => s.name)
            ai.mcpTools = ai.mcpTools.filter(t => names.indexOf(t.server) !== -1)
        }
    }
    // Las herramientas MCP en formato OpenAI, listas para req.tools.
    readonly property var mcpToolDefs: mcpTools.map(t => ({
        type: "function", "function": {
            name: "mcp__" + t.server + "__" + t.name,
            description: "[" + t.server + "] " + t.description,
            parameters: t.schema
        } }))

    Instantiator {
        model: Settings.aiMcpServers
        delegate: Process {
            id: mcp
            // modelData llega como propiedad de contexto del Instantiator.
            readonly property var srv: modelData
            readonly property string srvName: (srv && srv.name) || "mcp"
            property int nextId: 1
            property var pending: ({})     // id → callback(result, error)

            running: true
            command: ["sh", "-c", (srv && srv.command) || "false"]
            stdinEnabled: true

            function rpc(method, params, cb) {
                const id = nextId++
                if (cb) pending[id] = cb
                mcp.write(JSON.stringify({ jsonrpc: "2.0", id: id,
                                           method: method, params: params }) + "\n")
            }
            function notify(method, params) {
                mcp.write(JSON.stringify({ jsonrpc: "2.0",
                                           method: method, params: params }) + "\n")
            }

            onStarted: {
                ai._mcpProcs[srvName] = mcp
                ai._mcpSetStatus(srvName, "starting")
                rpc("initialize", {
                    protocolVersion: "2024-11-05",
                    capabilities: {},
                    clientInfo: { name: "quickshell-ia", version: "1.0" }
                }, () => {
                    notify("notifications/initialized", {})
                    rpc("tools/list", {}, (res) => {
                        const list = (res && res.tools) || []
                        ai._mcpSetTools(mcp.srvName, list.map(t => ({
                            server: mcp.srvName,
                            name: t.name,
                            description: String(t.description || "").slice(0, 250),
                            schema: t.inputSchema || { type: "object", properties: {} }
                        })))
                        ai._mcpSetStatus(mcp.srvName, "ok")
                    })
                })
            }

            stdout: SplitParser {
                onRead: (line) => {
                    const l = line.trim()
                    if (l === "" || l[0] !== "{")
                        return
                    try {
                        const j = JSON.parse(l)
                        if (j.id !== undefined && mcp.pending[j.id]) {
                            const cb = mcp.pending[j.id]
                            delete mcp.pending[j.id]
                            cb(j.result, j.error)
                        }
                    } catch (e) { /* línea no-JSON del servidor: se ignora */ }
                }
            }
            stderr: SplitParser { onRead: () => {} }

            onExited: (code) => {
                delete ai._mcpProcs[srvName]
                ai._mcpSetTools(srvName, [])
                ai._mcpSetStatus(srvName, "error: terminó con " + code)
            }
        }
    }

    // Una llamada JSON-RPC a un servidor MCP que acaba resolviendo la tarjeta.
    // Las tres cosas que se le piden (ejecutar, listar recursos, leer uno) solo
    // se diferencian en cómo se lee la respuesta: eso es 'render'. Lo demás
    // —servidor caído, error del protocolo— se contesta igual siempre.
    function _mcpRpc(index, server, method, params, render) {
        const proc = ai._mcpProcs[server]
        if (!proc || !proc.running) {
            _resolveTool(index, "El servidor MCP '" + server + "' no está conectado.")
            return
        }
        proc.rpc(method, params, (res, err) => {
            if (err) {
                ai._resolveTool(index, "Error MCP: " + (err.message || JSON.stringify(err)))
                return
            }
            ai._resolveTool(index, render(res || ({})))
        })
    }

    // Los bloques de texto de una respuesta MCP, aplanados.
    function _mcpText(list) {
        let out = ""
        const l = list || []
        for (let i = 0; i < l.length; i++)
            if (l[i].text !== undefined)
                out += l[i].text + "\n"
        return out
    }

    // Llama a una herramienta MCP y resuelve la tarjeta con su resultado.
    function _mcpCall(index, server, tool, args) {
        _mcpRpc(index, server, "tools/call", { name: tool, arguments: args },
            (res) => {
                const out = ai._mcpText((res.content || [])
                                .filter(c => c.type === "text"))
                return ((res.isError ? "[error de la herramienta] " : "") + out)
                       .trim() || "(sin contenido)"
            })
    }

    // ── Deshacer una edición ─────────────────────────────────────────────────
    // Dónde viven las copias de seguridad de las ediciones.
    readonly property string _undoDir:
        Quickshell.env("HOME") + "/.cache/quickshell-ai-undo"

    // Deshacer una edición: devuelve el archivo a como estaba justo antes.
    function undoEdit(index) {
        const m = messages.get(index)
        if (!m || String(m.undoPath || "") === "")
            return
        let target = ""
        const a = repairJson(m.toolArgs) || ({})
        target = _safePath(a.path)
        if (target === "")
            return
        undoProc.command = ["sh", "-c",
            'if [ -f "$QS_BAK" ]; then cp -a -- "$QS_BAK" "$QS_P" && echo restaurado; '
            + 'else rm -f -- "$QS_P" && echo borrado; fi']
        undoProc.environment = ({ QS_BAK: String(m.undoPath), QS_P: target })
        undoProc.running = true
        _undoTarget = target
    }
    property string _undoTarget: ""
    readonly property Process _undoProc: Process {
        id: undoProc
        stdout: StdioCollector { id: undoOut }
        onExited: (code) => {
            ai.pushInfo(code === 0
                ? ((undoOut.text || "").trim() === "borrado"
                    ? I18n.tr("Undone: %1 removed (it didn't exist before).").arg(ai._undoTarget)
                    : I18n.tr("Undone: %1 back as it was.").arg(ai._undoTarget))
                : I18n.tr("Could not undo %1").arg(ai._undoTarget))
        }
    }

    // ── Tolerancia con modelos LOCALES ───────────────────────────────────────
    // Un Qwen o un Muse sobre Ollama/llama.cpp no se comporta como un modelo de
    // nube: a veces no emite tool_calls nativos y escribe la llamada en el
    // texto, y muy a menudo manda argumentos que NO son JSON válido. Un harness
    // que exige perfección se rompe con ellos varias veces por conversación.
    // Lo de aquí abajo absorbe lo que se puede absorber sin adivinar.

    // Detección de bucles (idea de gemini-cli): el atasco más típico de un
    // modelo pequeño es repetir LA MISMA llamada una y otra vez porque no le
    // gusta el resultado. El tope de pasos lo cortaría ocho turnos después,
    // habiendo gastado contexto y tiempo; esto lo corta al tercer intento
    // idéntico y se lo dice, que así cambia de táctica o pregunta.
    // Idénticas = mismo nombre Y mismos argumentos.
    // Solo cuenta DENTRO del encargo en curso (desde el último mensaje del
    // usuario): repetir una consulta legítima tres veces a lo largo del día
    // no es un bucle, es usar el asistente. El bucle es repetirse sin que
    // nadie haya pedido nada nuevo.
    readonly property int loopThreshold: 3
    function _loopCount(name, argsJson) {
        const sig = String(name) + " " + String(argsJson || "")
        let start = 0
        for (let i = messages.count - 1; i >= 0; i--)
            if (messages.get(i).role === "user") {
                start = i
                break
            }
        let n = 0
        for (let i = start; i < messages.count; i++) {
            const m = messages.get(i)
            if (m.role === "tool" && m.toolStatus !== "pending"
                    && (String(m.toolName) + " " + String(m.toolArgs)) === sig)
                n++
        }
        return n
    }

    // Repara los defectos típicos de un JSON generado por un modelo pequeño:
    // vallas de Markdown, comas colgantes, comillas simples, literales de
    // Python. Si aun así no parsea, devuelve null (nunca inventa argumentos).
    function repairJson(raw) { return TU.repairJson(raw) }

    // Llamadas escritas EN EL TEXTO. Cada familia de modelos abiertos tiene su
    // propia manía, y un servidor que no traduce a la API de OpenAI las deja
    // pasar tal cual. Se reconocen las cuatro formas habituales:
    //   <tool_call>{…}</tool_call>          Qwen, Hermes
    //   <|python_tag|>{…}  /  functools[…]  Llama 3.x y familia (Muse)
    //   <function=nombre>{…}</function>     variante de Llama
    //   [TOOL_CALLS] [ … ]                  Mistral / Mixtral
    // Y como última red, un objeto JSON suelto {"name":…, "arguments":…} —
    // ese solo cuenta si el nombre EXISTE en el catálogo, para no confundir a
    // un modelo que simplemente está enseñando JSON en su respuesta.
    // Devuelve {calls:[{name,args}], rest:"texto sin las llamadas"}.
    function extractTextToolCalls(raw) {
        // Los nombres conocidos (para la última red) se pasan desde aquí: así
        // TextUtils no depende del harness.
        const known = ai.toolDefs.map(d => d["function"].name)
                        .concat(ai.mcpToolDefs.map(d => d["function"].name))
        return TU.extractTextToolCalls(raw, known)
    }

    // Separa el razonamiento <think>…</think> (Qwen y compañía) del texto.
    function splitThink(raw) { return TU.splitThink(raw) }

    // ── Operaciones de conversación ──────────────────────────────────────────
    // Tira el subagente en marcha sin resolver su tarjeta: el hilo que la
    // contenía deja de existir.
    function _dropSub() {
        if (activeSub) {
            activeSub.cancelSilent()
            activeSub.destroy()
            activeSub = null
        }
    }

    function stop() {
        if (streamProc.running)
            streamProc.running = false
    }

    // Todo lo que pertenece al HILO y no al historial: permisos dados de
    // palabra, la habilidad que acota el vocabulario, el plan a la vista, las
    // rutas ya resueltas. Cambiar de conversación sin soltarlo dejaría que un
    // "siempre" concedido en una charla mandara en la siguiente.
    function _resetThread() {
        stop()
        _dropSub()
        // Una compactación en vuelo pertenece al hilo que muere: si llegara
        // después de cambiar de conversación, borraría LA NUEVA.
        if (compacting) {
            compactProc.running = false
            compacting = false
            _keepTail = []
        }
        sessionAllow = ({})
        activeSkillTools = []
        pathReal = ({})
        todos = []
        _compactWarned = false
    }

    function newConversation() {
        _resetThread()
        _snapshotCurrent()
        messages.clear()
        currentId = String(Date.now())
        _saveHistoryNow()
    }

    // /limpiar (el /clear de Claude Code): pizarra en blanco DE VERDAD. Nueva
    // conversación archiva la actual y abre otra al lado; esto tira el hilo en
    // curso —no queda en el historial— y con él se van el borrador, los
    // adjuntos pendientes, la cola de envío y los contadores del turno. Lo que
    // no toca es la memoria persistente: esa el usuario la guardó a propósito.
    function clearConversation() {
        _resetThread()
        // Y además lo que aún no había salido: cola, borrador y contadores.
        sendQueue = []
        pendingAtts = []
        draft = ""
        toolRounds = 0
        _retries = 0
        compacting = false
        _keepTail = []
        conversations = conversations.filter(x => x.id !== currentId)
        messages.clear()
        currentId = String(Date.now())
        _recountTotals()
        _saveHistoryNow()
    }

    function switchTo(id) {
        if (id === currentId)
            return
        const c = conversations.find(x => x.id === id)
        if (!c)
            return
        _resetThread()
        _snapshotCurrent()
        currentId = id
        messages.clear()
        for (let i = 0; i < c.entries.length; i++)
            _append(c.entries[i])
        _saveHistoryNow()
    }

    function deleteConversation(id) {
        conversations = conversations.filter(x => x.id !== id)
        // Si era la que estabas leyendo, el hilo entero se va con ella: el
        // plan y los permisos de esa charla no deben sobrevivirla.
        if (id === currentId) {
            _resetThread()
            messages.clear()
            currentId = String(Date.now())
        }
        _saveHistoryNow()
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

    // ── Referencias @ruta en el mensaje (idea de gemini-cli) ─────────────────
    // "arregla @~/.config/quickshell/Bar/Bar.qml" adjunta el archivo sin tener
    // que pedirle al agente que lo lea: un paso menos, y el contenido llega ya
    // en el primer turno. Se resuelven antes de enviar; lo que no exista o se
    // salga de la carpeta personal se deja tal cual, como texto.
    function _atRefs(t) { return TU.atRefs(t) }
    property var _atPending: null       // {text, atts} esperando la expansión
    readonly property Process _atProc: Process {
        id: atProc
        stdout: StdioCollector { id: atOut }
        onExited: {
            const p = ai._atPending
            ai._atPending = null
            if (!p)
                return
            const extra = (atOut.text || "")
            // Si no se pudo leer nada, se manda el mensaje tal cual: una @ que
            // no era una ruta es simplemente texto.
            ai.pendingAtts = p.atts
            // El texto expandido SIGUE conteniendo las @: sin esta marca,
            // send() volvería a expandirlas eternamente.
            ai._atSkip = true
            ai.send(p.text + extra)
        }
    }
    property bool _atSkip: false

    function send(text) {
        // Expansión de @rutas: se lee primero y se reentra con el texto ya
        // completo, para no partir el flujo de envío en dos caminos.
        if (_atSkip) {
            _atSkip = false              // este ya viene expandido
        } else if (_atPending === null && !busy) {
            const refs = _atRefs(text)
            if (refs.length > 0) {
                _atPending = { text: String(text), atts: pendingAtts }
                // Las rutas viajan por ENTORNO (una por línea) y el bucle las
                // lee de ahí: nada se interpola en la línea de comandos, así
                // un nombre de archivo raro no puede convertirse en otra orden.
                // La tilde la expande el propio harness, no el shell.
                const home = Quickshell.env("HOME")
                const abs = refs.map(r => r === "~" ? home
                                        : r.startsWith("~/") ? home + r.slice(1) : r)
                atProc.command = ["sh", "-c",
                    'printf %s "$QS_REFS" | while IFS= read -r p; do '
                    + '[ -f "$p" ] || continue; '
                    + 'printf "\\n\\n--- %s ---\\n" "$p"; head -c 20000 -- "$p"; done']
                atProc.environment = ({ QS_REFS: abs.join("\n") + "\n" })
                atProc.running = true
                return
            }
        }

        let t = String(text).trim()
        if (busy || compacting) {
            // Ocupado (o compactando) no es "no": el mensaje espera su turno.
            if (t !== "" || pendingAtts.length > 0) {
                sendQueue = sendQueue.concat([{ text: t, atts: pendingAtts }])
                pendingAtts = []
            }
            return
        }
        toolRounds = 0
        _retries = 0
        if (urlMissing) {
            _push({ role: "error",
                    content: I18n.tr("No server URL for %1. Add it in the panel settings.")
                        .arg(provider.label) })
            return
        }
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
        _lastUserText = t
        _fireHooks("user_prompt_submit", "", { QS_HOOK_PROMPT: t.slice(0, 4000) })
        _start()
    }

    function retry() {
        if (!busy && !compacting)
            _start()
    }

    // Descarta la última respuesta y pide otra al modelo ACTUAL — también
    // sirve para comparar proveedores sobre la misma pregunta.
    function regenerate() {
        if (busy || compacting || messages.count === 0)
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

    // "Aprobar siempre" (esta conversación): recuerda la herramienta y aprueba
    // esta llamada. Solo tiene sentido para lo que se puede permitir en firme.
    function approveToolAlways(index) {
        const m = messages.get(index)
        if (!m || m.role !== "tool")
            return
        if (canStandingAllow(m.toolName))
            allowForSession(m.toolName)
        approveTool(index)
    }

    function approveTool(index) {
        const m = messages.get(index)
        if (!m || m.role !== "tool" || m.toolStatus !== "pending" || busy
                || compacting)
            return
        ai._toolIndex = index
        // Argumentos tolerantes: un modelo local manda JSON roto a menudo. Si
        // ni con reparación sale, se le dice al modelo qué esperaba en vez de
        // ejecutar con argumentos vacíos (que sería peor que fallar).
        const parsed = repairJson(m.toolArgs)
        if (parsed === null) {
            _resolveTool(index, "No entendí los argumentos: no son JSON válido. "
                + "Vuelve a llamar a " + m.toolName + " con un objeto JSON correcto.")
            return
        }
        const args = parsed

        // ask_user y propose_plan no se "aprueban": esperan al usuario. Su
        // tarjeta se pinta distinta (pregunta con opciones / plan con "Empezar")
        // y se resuelven por answerQuestion o approvePlan.
        if (m.toolName === "ask_user" || m.toolName === "propose_plan")
            return

        // Hooks pre_tool_use: la última palabra del usuario antes de que algo
        // corra. Se ejecutan UNA vez por llamada; si uno veta, la tarjeta se
        // rechaza con su motivo y el modelo se entera.
        if (_hookPassed !== index && _hooksFor("pre_tool_use", m.toolName).length > 0) {
            _hookGateIndex = index
            _runHooks("pre_tool_use", m.toolName,
                      { QS_HOOK_TOOL: m.toolName, QS_HOOK_ARGS: String(m.toolArgs || ""),
                        QS_HOOK_RISK: riskClass(m.toolName) },
                      () => { ai._hookPassed = index; ai.approveTool(index) })
            return
        }
        _hookPassed = -1

        // Herramienta de un servidor MCP: el nombre viaja con el esquema
        // mcp__<servidor>__<tool> de Claude Code. Se enruta a su proceso.
        if (m.toolName.startsWith("mcp__")) {
            const parts = m.toolName.split("__")
            if (parts.length < 3) { _resolveTool(index, "Nombre MCP inválido."); return }
            _mcpCall(index, parts[1], parts.slice(2).join("__"), args)
            return
        }

        // Todo lo que no cambia nada (leer archivos, consultar el sistema,
        // consultar un servidor) lo construye el mismo sitio que sirve al
        // subagente: una sola jaula que auditar.
        const built = readOnlyCommand(m.toolName, args)
        if (built !== null) {
            if (built.error !== undefined) { _resolveTool(index, built.error); return }
            _exec(built.cmd, built.env)
            return
        }

        switch (m.toolName) {
        case "ssh_exec": {
            const cmd = String(args.command || "").trim()
            if (cmd === "") { _resolveTool(index, "Comando vacío."); return }
            const c = _sshFor(args, "ssh", "-p")
            if (c.error !== undefined) { _resolveTool(index, c.error); return }
            // El comando remoto viaja como UN argumento a ssh; el shell remoto
            // lo ejecuta tal cual. Es crudo a propósito (por eso lleva tarjeta).
            _exec(c.t.argv.concat(["--", cmd + " 2>&1 | tail -c 16000"]), c.t.env)
            return
        }
        // Subir y bajar son el mismo scp con el origen y el destino cambiados
        // de sitio: se resuelven juntos para que no puedan divergir.
        case "sftp_get":
        case "sftp_put": {
            const down = m.toolName === "sftp_get"
            const local = _safePath(args.local_path)
            if (local === "") {
                _resolveTool(index, (down ? "El destino" : "El origen")
                    + " local debe estar dentro de tu carpeta personal.")
                return
            }
            const rp = String(args.remote_path || "").trim()
            if (rp === "") { _resolveTool(index, "Falta la ruta remota."); return }
            const c = _sshFor(args, "scp", "-P")
            if (c.error !== undefined) { _resolveTool(index, c.error); return }
            // scp recibe las rutas como ARGUMENTOS (no dentro de un shell), así
            // que un nombre raro no puede convertirse en otra orden. El último
            // elemento del argv es el user@host; el resto son las opciones.
            const dest = c.t.argv[c.t.argv.length - 1]
            const base = c.t.argv.slice(0, c.t.argv.length - 1)
            _exec(base.concat(down ? [dest + ":" + rp, local]
                                   : [local, dest + ":" + rp]), c.t.env)
            return
        }
        case "service_ctl": {
            const actions = ["start", "stop", "restart", "reload", "enable", "disable"]
            const action = String(args.action || "")
            const unit = String(args.unit || "").trim()
            if (actions.indexOf(action) === -1) { _resolveTool(index, "Acción inválida."); return }
            if (unit === "" || unit[0] === "-") { _resolveTool(index, "Unidad inválida."); return }
            // Sin sh: systemctl recibe la unidad como argumento literal. Las
            // de sistema pasarán por polkit (el agente propio del shell).
            _exec(args.user === true
                    ? ["systemctl", "--user", action, "--", unit]
                    : ["systemctl", action, "--", unit], ({}))
            return
        }
        case "kill_process": {
            const pid = parseInt(args.pid)
            if (!isFinite(pid) || pid <= 1) { _resolveTool(index, "PID inválido."); return }
            const sigs = ["TERM", "KILL", "HUP", "INT"]
            const sig = sigs.indexOf(String(args.signal || "")) !== -1 ? args.signal : "TERM"
            _exec(["sh", "-c",
                'ps -p "$QS_PID" -o comm= 2>/dev/null; kill -s ' + sig + ' -- "$QS_PID" && echo "Señal ' + sig + ' enviada." || echo "No se pudo (PID inexistente o de otro usuario)."'],
                ({ QS_PID: String(pid) }))
            return
        }
        case "todo_write": {
            // El plan visible (el TodoWrite de Claude Code): sustituye la
            // lista entera; el panel la pinta encima de la entrada.
            const list = Array.isArray(args.todos) ? args.todos : []
            ai.todos = list.slice(0, 20).map(t => ({
                content: String(t.content || "").slice(0, 200),
                status: ["pending", "in_progress", "completed"]
                            .indexOf(t.status) >= 0 ? t.status : "pending"
            }))
            const done = ai.todos.filter(t => t.status === "completed").length
            _resolveTool(index, "Plan actualizado: " + done + "/" + ai.todos.length
                                + " pasos completados.")
            return
        }
        case "web_search": {
            const q = String(args.query || "").trim()
            if (q === "") { _resolveTool(index, "Consulta vacía."); return }
            // Contra un SearXNG del usuario (ajuste aiSearchUrl), por su API
            // JSON. Se probó scrapear DuckDuckGo y Bing: el primero bloquea
            // ("anomaly") y el segundo sirve resultados-señuelo a los bots —
            // un buscador que miente es peor que ninguno.
            // De más específico a más general: lo que diga el mensaje, luego
            // el ajuste si lo hay, y si no una instancia pública. La
            // herramienta funciona SIEMPRE; configurarla solo cambia adónde va.
            const base = normalizeSearchBase(args.instance)
                      || normalizeSearchBase(Settings.aiSearchUrl)
                      || "https://searx.be"
            _exec(["sh", "-c",
                'curl -sSL --max-time 15 "$QS_B/search?format=json&q=$(python3 -c \'import urllib.parse,os; print(urllib.parse.quote(os.environ[\"QS_Q\"]))\')" | '
                + 'python3 -c \''
                + 'import sys,json\n'
                + 'try: d=json.load(sys.stdin)\n'
                + 'except Exception: print("El buscador no devolvio JSON (activa format=json en tu SearXNG)."); raise SystemExit\n'
                + 'rs=d.get("results",[])[:8]\n'
                + 'if not rs: print("(sin resultados)")\n'
                + 'for r in rs:\n'
                + '    print("- "+r.get("title","")+"\\n  "+r.get("url","")+"\\n  "+(r.get("content") or "")[:200])\n\''],
                ({ QS_Q: q, QS_B: base }))
            return
        }
        case "notify_user": {
            const title = String(args.title || "").slice(0, 120)
            if (title === "") { _resolveTool(index, "Título vacío."); return }
            Quickshell.execDetached(["notify-send", "-a", "Asistente IA",
                                     title, String(args.body || "").slice(0, 400)])
            _resolveTool(index, "Notificación mostrada.")
            return
        }
        case "subagent": {
            if (ai.activeSub) { _resolveTool(index, "Ya hay un subagente en marcha."); return }
            const task = String(args.task || "").trim()
            if (task === "") { _resolveTool(index, "Encargo vacío."); return }
            const s = ai._subComp.createObject(ai, {
                task: task,
                label: String(args.label || "").slice(0, 60) || I18n.tr("Research")
            })
            ai.activeSub = s
            s.finished.connect((report) => {
                ai.activeSub = null
                ai._resolveTool(index, report)
                s.destroy()
            })
            s.start()
            return
        }
        case "list_mcp_resources":
            _mcpRpc(index, String(args.server || "").trim(), "resources/list", {},
                (res) => {
                    const rs = res.resources || []
                    return rs.length === 0 ? "(sin recursos)"
                        : rs.map(r => "- " + (r.name || "") + "  " + r.uri
                              + (r.description
                                 ? "\n  " + String(r.description).slice(0, 150) : ""))
                            .join("\n")
                })
            return
        case "read_mcp_resource":
            _mcpRpc(index, String(args.server || "").trim(), "resources/read",
                { uri: String(args.uri || "") },
                (res) => ai._mcpText(res.contents).trim() || "(recurso sin texto)")
            return
        case "edit_lines": {
            const p = _safePath(args.path)
            if (p === "") { _resolveTool(index, "Ruta fuera de la carpeta personal."); return }
            const st = parseInt(args.start), en = parseInt(args.end)
            if (!(st >= 1) || !(en >= st)) { _resolveTool(index, "Rango inválido: start debe ser ≥1 y end ≥ start."); return }
            // Edición por rango con ANCLA: si el hash de los extremos ya no
            // coincide, el archivo cambió desde que el modelo lo leyó y la
            // edición se niega. Es lo que evita el destrozo clásico de editar
            // por número de línea sobre un archivo que se movió.
            const bakL = _backupFor(index, p)
            _exec(["python3", "-c", _pyHash
                + 'import os,sys,shutil\n'
                + 'p=os.environ["QS_P"]; st=int(os.environ["QS_ST"]); en=int(os.environ["QS_EN"])\n'
                + 'sh_=os.environ["QS_SH"]; eh=os.environ["QS_EH"]; new=os.environ["QS_TXT"]\n'
                + 'try: lines=open(p,encoding="utf-8",errors="replace").read().split("\\n")\n'
                + 'except OSError as e: print("No se pudo leer:",e); raise SystemExit\n'
                + 'if en>len(lines): print(f"El archivo tiene {len(lines)} lineas; pediste hasta {en}."); raise SystemExit\n'
                + 'if sh_ and h(lines[st-1])!=sh_:\n'
                + '    print(f"La linea {st} ya no es la que viste (hash {h(lines[st-1])}, esperabas {sh_}). Vuelve a leer el archivo."); raise SystemExit\n'
                + 'if eh and h(lines[en-1])!=eh:\n'
                + '    print(f"La linea {en} ya no es la que viste (hash {h(lines[en-1])}, esperabas {eh}). Vuelve a leer el archivo."); raise SystemExit\n'
                + 'os.makedirs(os.environ["QS_BD"],exist_ok=True); shutil.copy2(p,os.environ["QS_BAK"])\n'
                + 'rep=new.split("\\n") if new!="" else []\n'
                + 'out=lines[:st-1]+rep+lines[en:]\n'
                + 'open(p,"w",encoding="utf-8").write("\\n".join(out))\n'
                + 'print(f"Editado {p}: lineas {st}-{en} ({en-st+1}) sustituidas por {len(rep)}.")\n'],
                ({ QS_P: p, QS_ST: String(st), QS_EN: String(en),
                   QS_SH: String(args.start_hash || ""),
                   QS_EH: String(args.end_hash || ""),
                   QS_TXT: String(args.text || ""),
                   QS_BAK: bakL, QS_BD: _undoDir }))
            return
        }
        case "edit_file": {
            const p = _safePath(args.path)
            if (p === "") { _resolveTool(index, "Ruta fuera de la carpeta personal."); return }
            // Sustitución exacta con la regla de unicidad del FileEditTool:
            // 0 apariciones = error, 2+ = error (pide más contexto), 1 = edita.
            // Todo por entorno y en python3, que no re-interpreta nada.
            const bakE = _backupFor(index, p)
            _exec(["python3", "-c",
                'import os,sys,shutil\n'
                + 'p=os.environ["QS_P"]; old=os.environ["QS_OLD"]; new=os.environ["QS_NEW"]\n'
                + 'try: s=open(p,encoding="utf-8",errors="replace").read()\n'
                + 'except OSError as e: print("No se pudo leer:",e); sys.exit(0)\n'
                + 'n=s.count(old)\n'
                + 'if n==0: print("old_string no aparece en el archivo."); sys.exit(0)\n'
                + 'if n>1: print("old_string aparece",n,"veces; amplia el contexto para que sea unico."); sys.exit(0)\n'
                + 'os.makedirs(os.environ["QS_BD"],exist_ok=True); shutil.copy2(p,os.environ["QS_BAK"])\n'
                + 'open(p,"w",encoding="utf-8").write(s.replace(old,new,1))\n'
                + 'print("Editado:",p)'],
                ({ QS_P: p,
                   QS_OLD: String(args.old_string || ""),
                   QS_NEW: String(args.new_string || ""),
                   QS_BAK: bakE, QS_BD: _undoDir }))
            return
        }
        case "open_url": {
            const url = args.url || ""
            if (url !== "")
                Quickshell.execDetached(["xdg-open", url])
            _resolveTool(index, url !== "" ? "URL abierta en el navegador."
                                           : "URL inválida.")
            return
        }
        case "write_file": {
            const p = _safePath(args.path)
            if (p === "") { _resolveTool(index, "Ruta fuera de la carpeta personal."); return }
            // El contenido viaja por entorno (nunca argv) y se escribe con
            // printf; la carpeta destino se crea si falta.
            // Copia de seguridad antes de sobrescribir: es lo que permite
            // Deshacer. Si el archivo no existía, no hay nada que copiar (y
            // deshacer significará borrarlo).
            const bak = _backupFor(index, p)
            _exec(["sh", "-c",
                'mkdir -p "$QS_BD" "$(dirname -- "$QS_P")"; '
                + '[ -f "$QS_P" ] && cp -a -- "$QS_P" "$QS_BAK"; '
                + 'printf %s "$QS_C" > "$QS_P" && echo "Escrito: $QS_P ($(wc -c < "$QS_P") bytes)"'],
                ({ QS_P: p, QS_C: args.content || "",
                   QS_BAK: bak, QS_BD: _undoDir }))
            return
        }
        case "use_skill": {
            // La ruta se construye a partir del id de la carpeta encontrada al
            // escanear, nunca de lo que diga el modelo: pida lo que pida, solo
            // puede acabar leyendo un SKILL.md de la carpeta de habilidades.
            const want = String(args.name || "").trim().toLowerCase()
            const s = ai.activeSkills.find(x => x.id.toLowerCase() === want
                                             || x.name.toLowerCase() === want)
            if (!s) {
                // Puede que la habilidad se instalara DESPUÉS de arrancar el
                // shell: se reescanea la carpeta y se reintenta una vez, en
                // vez de contestar 404 sobre un catálogo viejo.
                if (ai._skillRetry === "" && !skillScan.running) {
                    ai._skillRetry = want
                    ai._skillPending = index
                    ai.rescanSkills()
                    return
                }
                _resolveTool(index, "No hay ninguna habilidad activa con ese nombre. Disponibles: "
                    + ai.activeSkills.map(x => x.name).join(", "))
                return
            }
            // La habilidad puede acotar su propio vocabulario mientras esté en
            // uso (allowed-tools del frontmatter): un manual de lectura no
            // debería poder pedir un rm.
            ai.activeSkillTools = (s.allowedTools && s.allowedTools.length > 0)
                ? s.allowedTools.slice() : []
            // El texto ya está en memoria desde el escaneo: no hace falta ir
            // al disco otra vez.
            _resolveTool(index, s.text)
            return
        }
        case "memory_update": {
            const n = memoryList.slice()
            const i = parseInt(args.id) - 1
            if (!(i >= 0 && i < n.length)) { _resolveTool(index, "No existe la nota [#" + args.id + "]."); return }
            const txt = String(args.note || "").trim().slice(0, 400)
            if (txt === "") { _resolveTool(index, "Nota vacía."); return }
            const before = n[i]
            n[i] = txt
            _setNotes(n)
            _resolveTool(index, "Nota [#" + (i + 1) + "] corregida.\nAntes: " + before + "\nAhora: " + txt)
            return
        }
        case "memory_forget": {
            const n = memoryList.slice()
            const i = parseInt(args.id) - 1
            if (!(i >= 0 && i < n.length)) { _resolveTool(index, "No existe la nota [#" + args.id + "]."); return }
            const gone = n[i]
            n.splice(i, 1)
            _setNotes(n)
            _resolveTool(index, "Nota retirada: " + gone)
            return
        }
        case "learn": {
            _resolveTool(index, addInstinct(args.lesson))
            return
        }
        case "remember": {
            const note = String(args.note || "").trim().slice(0, 400)
            if (note === "") { _resolveTool(index, "Nota vacía."); return }
            _setNotes(memoryList.concat([note]))
            _resolveTool(index, "Nota guardada en memoria.")
            return
        }
        case "run_command": {
            // Acotado a 20 s; stdout y stderr vuelven al modelo.
            const cmd = args.command || ""
            if (cmd === "") { _resolveTool(index, "Comando vacío."); return }
            _exec(["timeout", "20", "sh", "-c", cmd], ({}))
            return
        }
        default: {
            // Nombre que no existe. Antes caía aquí run_command, así que un
            // modelo que alucinaba un nombre con un argumento 'command' podía
            // acabar ejecutando un comando bajo otra etiqueta. Ahora se
            // rechaza y se le recuerda el vocabulario: los modelos locales se
            // inventan nombres a menudo y así corrigen en el siguiente turno.
            const known = ai.toolDefs.map(d => d["function"].name)
                            .concat(ai.mcpToolDefs.map(d => d["function"].name))
            _resolveTool(index, "No existe la herramienta '" + m.toolName
                + "'. Las disponibles son: " + known.join(", "))
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

    // ── Guardarraíl de privacidad ────────────────────────────────────────────
    // Lo que una herramienta lee acaba EN EL CONTEXTO, y de ahí viaja al
    // modelo (y a su servidor, si no es local). Antes de entrar se tapan los
    // secretos de forma inequívoca: claves privadas, Bearer, y asignaciones de
    // password/token/api_key. Solo formas de ALTA confianza — enmascarar de
    // más rompería trabajos legítimos —, y el hueco se marca a la vista para
    // que se sepa que hay algo tapado en vez de creer que no había nada.
    readonly property var _secretRules: [
        // Bloques PEM enteros (clave privada SSH/TLS).
        { re: /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g,
          to: "[clave privada oculta]" },
        // Cabeceras de autorización.
        { re: /(authorization\s*:\s*bearer\s+)[A-Za-z0-9._~+/=-]{12,}/gi,
          to: "$1[oculto]" },
        // clave = valor en configuraciones y .env
        { re: /((?:password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|private[_-]?key)\s*[:=]\s*["']?)([^\s"'\n]{6,})/gi,
          to: "$1[oculto]" }
    ]
    function redactSecrets(text) {
        let s = String(text || "")
        for (let i = 0; i < _secretRules.length; i++)
            s = s.replace(_secretRules[i].re, _secretRules[i].to)
        return s
    }

    function _resolveTool(index, result) {
        messages.setProperty(index, "toolStatus", "done")
        messages.setProperty(index, "toolResult",
                            redactSecrets(String(result)).slice(0, toolResultCap))
        _saveHistory()
        // Aviso de "esto ya corrió": para registrar, medir o encadenar.
        const done = messages.get(index)
        if (done)
            _fireHooks("post_tool_use", done.toolName,
                       { QS_HOOK_TOOL: String(done.toolName || ""),
                         QS_HOOK_ARGS: String(done.toolArgs || ""),
                         QS_HOOK_RESULT: String(result).slice(0, 4000) })
        _advanceTools()   // ¿otra herramienta del lote?; si no, sigue el modelo
    }

    // ── Rutas reales: los enlaces simbólicos, a la vista ─────────────────────
    // El cerco a $HOME no puede parar a un agente decidido (con run_command se
    // sale por la puerta grande); sirve contra ACCIDENTES. Por eso un enlace
    // que apunta fuera no se prohíbe —perderías rutas legítimas como
    // ~/datos → /mnt/almacen— sino que se DESTAPA: se resuelve el destino
    // real y, si sale de tu carpeta, esa llamada nunca se auto-aprueba y la
    // tarjeta enseña adónde va de verdad. Escape visible en vez de prohibido.
    property var pathReal: ({})        // índice de mensaje → {real, escapes}

    function realPathFor(index) {
        const r = pathReal[index]
        return (r && r.escapes) ? r.real : ""
    }

    // El argumento que es una ruta LOCAL, según la herramienta.
    function _pathArgOf(toolName, args) {
        switch (toolName) {
        case "read_file": case "list_dir": case "write_file": case "edit_file":
        case "grep_files": case "glob_files":
            return String(args.path || "")
        case "sftp_get": case "sftp_put":
            return String(args.local_path || "")
        }
        return ""
    }

    property int _resolveIndex: -1
    function _resolvePath(index, p) {
        const abs = _safePath(p)
        if (abs === "") {                  // ya fuera del cerco: no hay nada que mirar
            const m = Object.assign({}, pathReal)
            m[index] = { real: "", escapes: false }
            pathReal = m
            _advanceTools()
            return
        }
        _resolveIndex = index
        // readlink -f canoniza siguiendo los enlaces; si el archivo aún no
        // existe (write_file), resuelve igual la cadena de carpetas.
        realProc.command = ["sh", "-c", 'readlink -f -- "$QS_P" 2>/dev/null || printf %s "$QS_P"']
        realProc.environment = ({ QS_P: abs })
        realProc.running = true
    }
    readonly property Process _realProc: Process {
        id: realProc
        stdout: StdioCollector { id: realOut }
        onExited: {
            const home = Quickshell.env("HOME")
            const real = (realOut.text || "").trim()
            const escapes = real !== "" && !real.startsWith(home + "/") && real !== home
            const m = Object.assign({}, ai.pathReal)
            m[ai._resolveIndex] = { real: real, escapes: escapes }
            ai.pathReal = m
            ai._resolveIndex = -1
            ai._advanceTools()
        }
    }

    // El coordinador de un turno con VARIAS herramientas (el modelo puede
    // pedir varias lecturas de golpe). Tras resolver una: si queda alguna
    // pendiente, la auto-aprobable se ejecuta y la manual espera al usuario;
    // solo cuando NO queda ninguna pendiente se devuelve todo al modelo con
    // una única continuación. Así N llamadas paralelas no disparan N _start.
    function _advanceTools() {
        if (busy || compacting)
            return
        if (_resolveIndex >= 0)        // resolviendo una ruta: se espera
            return
        // Un plan esperando visto bueno PARA todo lo demás, aunque el modelo
        // lo haya pedido junto a otras herramientas: proponer y ejecutar a la
        // vez sería proponer de boquilla.
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i)
            if (m.role === "tool" && m.toolStatus === "pending"
                    && m.toolName === "propose_plan")
                return
        }
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i)
            if (m.role === "tool" && m.toolStatus === "pending") {
                // Si la llamada lleva una ruta local, primero se averigua
                // adónde apunta DE VERDAD (puede ser un enlace). Se hace una
                // sola vez por tarjeta, y al volver se re-entra aquí.
                const args = repairJson(m.toolArgs) || ({})
                const p = _pathArgOf(m.toolName, args)
                if (p !== "" && pathReal[i] === undefined) {
                    _resolvePath(i, p)
                    return
                }
                // Hay pendientes: si esta es auto (y no se pasó el tope de
                // pasos), se ejecuta sola; si es manual, se espera aquí.
                // Una ruta que se va fuera de $HOME por un enlace NUNCA va
                // sola, por muy "auto" que esté la herramienta: eso lo miras.
                const escapes = pathReal[i] && pathReal[i].escapes
                if (toolRounds <= maxToolRounds && !escapes
                        && callPolicy(m.toolName, m.toolArgs) === "auto")
                    approveTool(i)
                return
            }
        }
        // Nada pendiente: el lote está completo, se continúa la conversación.
        _start()
    }

    // Lanzar la herramienta aprobada. Un solo Process para todas (solo corre
    // una cada vez, por diseño), así que arrancarlo era el mismo trío de
    // líneas repetido veinte veces; aquí se dice una.
    function _exec(cmd, env) {
        toolProc.command = cmd
        toolProc.environment = env || ({})
        toolProc.running = true
    }

    // Dónde va la copia de seguridad de esta edición, anotada en la tarjeta:
    // es lo que hace posible Deshacer. Las tres herramientas que escriben
    // llevaban la misma línea de armar la ruta.
    function _backupFor(index, path) {
        const bak = _undoDir + "/" + Date.now() + "-" + path.split("/").pop()
        messages.setProperty(index, "undoPath", bak)
        return bak
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
    // Recorte por DETRÁS (16 mensajes o el presupuesto de caracteres, lo que
    // llegue antes) y reconstrucción del protocolo de herramientas: cada
    // tarjeta resuelta se traduce al par
    // assistant(tool_calls) + tool(result) que exige el contrato OpenAI.
    function _payloadMessages() {
        const out = []
        let chars = 0
        let i = messages.count - 1
        while (i >= 0 && out.length < 16) {
            const m = messages.get(i)
            if (m.role === "tool") {
                // Un LOTE de tarjetas contiguas (el modelo pidió varias de
                // golpe) debe viajar como UN solo mensaje assistant con
                // tool_calls:[N] seguido de N resultados — es lo que exige el
                // contrato. Antes cada tarjeta iba como su propio assistant
                // de una sola llamada: los servidores tolerantes lo tragaban,
                // pero es inválido y a un modelo local lo despista.
                const batch = []
                let tag = null
                while (i >= 0) {
                    const t = messages.get(i)
                    if (t.role !== "tool")
                        break
                    // Dos RONDAS seguidas sin texto entre medias también son
                    // tarjetas contiguas: la marca de lote las separa (los
                    // resultados de la primera informaron a la segunda, y ese
                    // orden debe conservarse). Historiales viejos sin marca
                    // se agrupan por contigüidad, como antes.
                    const tb = String(t.toolBatch || "")
                    if (tag !== null && tb !== tag)
                        break
                    tag = tb
                    if (t.toolStatus !== "pending")
                        batch.unshift({ id: t.toolId, name: t.toolName,
                                        args: t.toolArgs, result: t.toolResult,
                                        content: t.content })
                    i--
                }
                if (batch.length === 0)
                    continue
                const calls = []
                let said = ""
                for (let k = 0; k < batch.length; k++) {
                    calls.push({ id: batch[k].id, type: "function",
                                 "function": { name: batch[k].name,
                                               arguments: batch[k].args } })
                    if (batch[k].content !== "")
                        said = batch[k].content
                    // Lo que pesa en agente son las herramientas: sus
                    // argumentos y resultados cuentan contra el presupuesto
                    // igual que la prosa, o el recorte se queda corto.
                    chars += batch[k].args.length + batch[k].result.length
                }
                for (let k = batch.length - 1; k >= 0; k--)
                    out.unshift({ role: "tool", tool_call_id: batch[k].id,
                                  content: batch[k].result })
                out.unshift({ role: "assistant", content: said,
                              tool_calls: calls })
                if (chars > charBudget && out.length > 0)
                    break
                continue
            }
            if (m.role !== "user" && m.role !== "assistant") {
                i--
                continue
            }
            chars += m.content.length
            if (chars > charBudget && out.length > 0)
                break
            out.unshift({ role: m.role, content: m.content })
            i--
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
    property int _tcCur: 0              // último hueco (servidores sin index)

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
        ai._tcCur = 0
        ai._t0 = Date.now()
        const req = {
            model: ai.model,
            messages: ai._payloadMessages(),
            stream: true
        }
        // Temperatura: el parámetro universal del contrato, con el valor del
        // usuario (Ajustes del panel).
        req.temperature = Math.round(Settings.aiTemperature * 100) / 100
        // Interruptor de razonamiento de Qwen3: "/think" y "/no_think" son
        // interruptores SUAVES que el modelo entiende dentro del turno del
        // usuario — van en el mensaje, no en la API, así que no rompen nada
        // en servidores que no los conocen. Con un Qwen local, apagar el
        // pensamiento es la mayor mejora de latencia que existe.
        if (Settings.aiThink !== "auto")
            for (let i = req.messages.length - 1; i >= 0; i--)
                if (req.messages[i].role === "user"
                        && typeof req.messages[i].content === "string") {
                    req.messages[i] = { role: "user",
                        content: req.messages[i].content + " /" + Settings.aiThink }
                    break
                }
        // Las herramientas solo existen en modo agente: en chat el modelo ni
        // sabe que hay manos (los modos plan/build de opencode, en pequeño).
        // Y las apagadas por política ("off") ni se anuncian: para el modelo
        // no existen (las listas de denegación de aisuite).
        if (ai.agentMode) {
            const defs = ai.toolDefs.filter(d => {
                const n = d["function"].name
                if (ai.toolPolicy(n) === "off")
                    return false
                // Sin habilidades activas, use_skill ni se anuncia; sin
                // servidores MCP, sus herramientas de recursos tampoco.
                if (n === "use_skill" && ai.activeSkills.length === 0)
                    return false
                // propose_plan siempre está disponible en modo agente: quien
                // mejor sabe si una tarea merece plan es quien acaba de leer
                // el encargo, no el usuario antes de escribirlo.
                if ((n === "list_mcp_resources" || n === "read_mcp_resource")
                        && (Settings.aiMcpServers || []).length === 0)
                    return false
                // Habilidad en uso con allowed-tools: solo su lista, más las
                // que nunca sobran (preguntar, planificar, cambiar de
                // habilidad) para no dejar al agente sin salida.
                if (ai.activeSkillTools.length > 0
                        && ai.activeSkillTools.indexOf(n) === -1
                        && ["ask_user", "todo_write", "use_skill"].indexOf(n) === -1)
                    return false
                return true
            })
                // Las herramientas MCP entran al final, filtradas igual: una
                // política "off" sobre mcp__servidor__tool la borra del
                // vocabulario del modelo como cualquier otra.
                .concat(ai.mcpToolDefs.filter(d =>
                    ai.toolPolicy(d["function"].name) !== "off"))
            // Recorte por relevancia si la ventana es modesta (ver maxTools).
            const sent = ai._selectTools(defs)
            if (sent.length > 0)
                req.tools = sent
        }
        if (Settings.aiProvider !== "gemini")
            req.stream_options = { include_usage: true }
        // Un servidor remoto puede tardar en aceptar la conexión (VPN, túnel,
        // arranque perezoso del modelo): 15 s para conectar, 300 para el
        // stream entero. Credenciales y opciones de red salen de las mismas
        // funciones que usa la sonda, así que lo que prueba el botón "Probar"
        // es exactamente lo que va a viajar.
        let cmd = ["curl", "-sS", "-N", "--no-buffer",
                   "--connect-timeout", "15", "--max-time", "300",
                   "-X", "POST", ai.endpoint,
                   "-H", "Content-Type: application/json"]
        cmd = cmd.concat(ai._authArgs()).concat(ai._netArgs())
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
                        // El razonamiento llega con dos nombres según el
                        // servidor: reasoning_content (Qwen/DashScope/vLLM)
                        // o reasoning (OpenRouter). Se aceptan ambos.
                        const razon = d.reasoning_content || d.reasoning
                        if (razon)
                            ai.reasonBuf += razon
                        if (d.content)
                            ai.streamBuf += d.content
                        // Propuestas de herramienta: llegan troceadas
                        // (nombre en un delta, argumentos gota a gota).
                        if (d.tool_calls)
                            for (let k = 0; k < d.tool_calls.length; k++) {
                                const tc = d.tool_calls[k]
                                // Algunos servidores de Qwen no numeran las
                                // llamadas en el stream (falta 'index'). Sin
                                // esto, dos llamadas paralelas se fundían en
                                // una sola con los argumentos mezclados: un
                                // id NUEVO abre hueco nuevo; sin id, se sigue
                                // rellenando el último.
                                let idx = tc.index
                                if (idx === undefined || idx === null) {
                                    if (tc.id && ai._tc[ai._tcCur]
                                            && ai._tc[ai._tcCur].id !== tc.id)
                                        ai._tcCur++
                                    idx = ai._tcCur
                                } else {
                                    ai._tcCur = idx
                                }
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
            let text = parts.text.trim()
            // Modelo local que escribe la llamada en el texto en vez de
            // emitirla como tool_call: se rescata y se trata igual. Sin esto,
            // con Qwen sobre un servidor que no traduce, el agente "habla" de
            // usar una herramienta y no usa ninguna.
            if (Object.keys(ai._tc).length === 0 && text !== "") {
                const found = ai.extractTextToolCalls(text)
                if (found.calls.length > 0) {
                    text = found.rest
                    for (let i = 0; i < found.calls.length; i++)
                        ai._tc[i] = { id: "", name: found.calls[i].name,
                                      args: found.calls[i].args }
                }
            }
            const tcKeys = Object.keys(ai._tc)

            if (tcKeys.length > 0) {
                // El modelo propone una o VARIAS herramientas → una tarjeta
                // por cada una. Los modelos buenos piden varias lecturas de
                // golpe; antes se perdían todas menos la primera. El texto y
                // el razonamiento acompañan solo a la primera tarjeta.
                // ¿Se ha atascado repitiendo la misma llamada? Se corta aquí.
                let looped = ""
                for (let i = 0; i < tcKeys.length; i++) {
                    const tc = ai._tc[tcKeys[i]]
                    if (tc.name && ai._loopCount(tc.name, tc.args) >= ai.loopThreshold)
                        looped = tc.name
                }
                if (looped !== "") {
                    ai.streamBuf = ""
                    ai.reasonBuf = ""
                    ai.pushInfo(I18n.tr("Stopped: it repeated the same %1 call over and over.")
                                    .arg(looped))
                    ai.replied()
                    return
                }
                // Todas las tarjetas de esta ronda comparten marca de lote:
                // es lo que luego permite reconstruir el protocolo (un
                // assistant con N tool_calls por ronda, no por tarjeta).
                const rondaId = "b" + Date.now()
                for (let i = 0; i < tcKeys.length; i++) {
                    const tc = ai._tc[tcKeys[i]]
                    if (!tc.name)     // fragmento sin nombre: no es una llamada
                        continue
                    ai._push({ role: "tool", content: i === 0 ? text : "",
                               toolName: tc.name, toolArgs: tc.args,
                               toolId: tc.id !== "" ? tc.id : ("call_" + Date.now() + "_" + i),
                               toolStatus: "pending", toolBatch: rondaId,
                               modelName: ai.model, reasoning: i === 0 ? think : "" })
                }
                ai.streamBuf = ""
                ai.reasonBuf = ""
                ai.toolRounds++
                if (ai.toolRounds === ai.maxToolRounds + 1)
                    ai.pushInfo(I18n.tr("Step limit reached — approvals are manual again."))
                // El coordinador ejecuta las auto en serie y deja las manuales
                // esperando; devuelve al modelo cuando el lote esté resuelto.
                ai._advanceTools()
                ai.replied()
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
            // Una respuesta VACÍA con conexión limpia cuenta como transitoria:
            // los Qwen locales la sueltan de vez en cuando y a la siguiente va
            // (la regla de reintento de qwen-code).
            const vacia = code === 0 && ai._errBuf.trim() === ""
            if ((ai._transient(msg) || vacia) && ai._retries < 2) {
                ai._retries++
                ai.pushInfo(I18n.tr("Temporary error — retrying (%1/2)…").arg(ai._retries))
                retryTimer.interval = ai._retries * 2500
                retryTimer.restart()
                return
            }
            ai._push({ role: "error", content: msg })
            Qt.callLater(ai._dequeue)
        }
    }

    // ── Compactar contexto ───────────────────────────────────────────────────
    // Sustituye el historial viejo por un RESUMEN ESTRUCTURADO y conserva los
    // últimos turnos literales (tarjetas de herramienta incluidas). Es una
    // operación DEL HARNESS, no un mensaje del chat: viaja por su propio
    // proceso, sin streaming y SIN herramientas. La versión anterior metía la
    // petición de resumen por el flujo normal — en modo agente el modelo
    // podía contestar al "resume esto" con una tool_call, y esa tarjeta se
    // tomaba como resumen y se cargaba el historial.
    property bool compacting: false
    // El aviso de "casi lleno" se da UNA vez por conversación.
    property bool _compactWarned: false
    // Los turnos recientes que sobreviven al resumen (ver aiCompactKeep).
    property var _keepTail: []
    property bool _compactRetried: false

    // El resumen con las secciones que hacen falta para CONTINUAR, no para
    // recordar: es la diferencia entre un resumen y un traspaso de turno.
    readonly property string _compactPrompt:
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
        if (busy || compacting || notConfigured || messages.count < 2)
            return
        // Con una tarjeta esperando aprobación no se compacta: resolverla a
        // mitad de resumen dejaría el protocolo a medias.
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).role === "tool"
                    && messages.get(i).toolStatus === "pending")
                return
        compacting = true
        _compactRetried = false
        // Se aparta la cola ANTES de pedir el resumen: los últimos K turnos
        // vuelven después LITERALES, tarjetas de herramienta incluidas — el
        // resumen es para lo viejo, no para lo que aún tienes en la retina.
        _keepTail = []
        if (Settings.aiCompactKeep > 0) {
            let users = 0, cut = -1
            for (let i = messages.count - 1; i >= 0; i--)
                if (messages.get(i).role === "user") {
                    users++
                    if (users >= Settings.aiCompactKeep) {
                        cut = i
                        break
                    }
                }
            if (cut >= 0)
                for (let i = cut; i < messages.count; i++) {
                    const m = messages.get(i)
                    _keepTail.push({ role: m.role, content: m.content,
                        reasoning: m.reasoning, modelName: m.modelName,
                        ms: m.ms, tokens: m.tokens, ts: m.ts,
                        toolName: m.toolName, toolArgs: m.toolArgs,
                        toolId: m.toolId, toolResult: m.toolResult,
                        toolStatus: m.toolStatus, toolBatch: m.toolBatch,
                        attachNote: m.attachNote, undoPath: m.undoPath })
                }
        }
        pushInfo(I18n.tr("Compacting the context…"))
        _compactSend()
    }

    function _compactSend() {
        // El historial que iba a viajar de todos modos, con el sistema
        // sustituido por la consigna de archivero y la orden al final.
        const msgs = _payloadMessages()
        msgs[0] = { role: "system",
                    content: "Eres el archivero de una conversación entre un "
                        + "usuario y su asistente. Resumes con fidelidad." }
        msgs.push({ role: "user", content: _compactPrompt })
        const req = { model: model, messages: msgs,
                      temperature: 0.2, stream: false }
        let cmd = ["curl", "-sS", "--connect-timeout", "15", "--max-time", "180",
                   "-X", "POST", endpoint, "-H", "Content-Type: application/json"]
        cmd = cmd.concat(_authArgs()).concat(_netArgs())
        cmd = cmd.concat(["-d", JSON.stringify(req)])
        compactProc.command = cmd
        compactProc.running = true
    }

    readonly property Process _compactProc: Process {
        id: compactProc
        stdout: StdioCollector { id: compactOut }
        stderr: StdioCollector {}
        onExited: (code) => {
            if (!ai.compacting)          // cancelada por /limpiar o similar
                return
            let j = null
            try { j = JSON.parse(compactOut.text) } catch (e) {}
            const m = j && j.choices && j.choices[0] && j.choices[0].message
            const texto = m ? ai.splitThink(String(m.content || "")).text.trim() : ""
            if (code !== 0 || texto === "") {
                const why = (j && j.error && (j.error.message || j.error.code))
                          || (code !== 0 ? "curl " + code : I18n.tr("No response received"))
                // Un tropiezo transitorio merece UN reintento; después se
                // desiste con motivo y el historial queda como estaba.
                if (ai._transient(String(why)) && !ai._compactRetried) {
                    ai._compactRetried = true
                    compactRetry.restart()
                    return
                }
                ai.compacting = false
                ai._keepTail = []
                ai.pushInfo(I18n.tr("Compaction failed: %1").arg(String(why).slice(0, 200)))
                return
            }
            ai.compacting = false
            ai._compactWarned = false
            const cabecera = "**" + I18n.tr("Summary of the previous conversation")
                           + ":**\n\n" + texto
            ai.messages.clear()
            ai._append({ role: "assistant", content: cabecera, modelName: ai.model })
            for (let i = 0; i < ai._keepTail.length; i++)
                ai._append(ai._keepTail[i])
            ai._keepTail = []
            ai._push({ role: "info", content: I18n.tr("Context compacted.") })
            Qt.callLater(ai._dequeue)
        }
    }
    Timer {
        id: compactRetry
        interval: 2500
        onTriggered: if (ai.compacting) ai._compactSend()
    }

    onReplied: {
        // "stop": el turno acabó. Para avisos propios (sonido, luz, registro).
        if (!busy)
            _fireHooks("stop", "", { QS_HOOK_TOKENS: String(convTokens) })
        // Contexto casi lleno: según lo elegido, avisar o compactar solo.
        if (contextFill > 0.85 && !busy && !notConfigured) {
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
    // Todo en data/ai-history.json, dentro del módulo y, como settings.json,
    // fuera de git.
    function _append(m) {
        messages.append({
            role: m.role || "user", content: m.content || "",
            reasoning: m.reasoning || "", modelName: m.modelName || "",
            ms: m.ms || 0, tokens: m.tokens || 0,
            toolName: m.toolName || "", toolArgs: m.toolArgs || "",
            toolId: m.toolId || "", toolResult: m.toolResult || "",
            toolStatus: m.toolStatus || "", attachNote: m.attachNote || "",
            ts: m.ts || "",
            // Copia de seguridad del archivo ANTES de una edición: es lo que
            // permite el botón Deshacer. Un ListModel congela sus roles con la
            // primera fila, así que va aquí como todos los demás.
            undoPath: m.undoPath || "",
            // Marca del lote: qué tarjetas nacieron en la misma ronda del
            // modelo (reconstrucción fiel del protocolo en _payloadMessages).
            toolBatch: m.toolBatch || ""
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
                           ts: m.ts, undoPath: m.undoPath,
                           toolBatch: m.toolBatch })
        }
        const rest = conversations.filter(c => c.id !== currentId)
        // Una conversación vacía no merece hueco en la lista.
        if (entries.length > 0)
            rest.unshift({ id: currentId, title: _title(),
                           updated: Date.now(), entries: entries })
        conversations = rest
    }

    // Guardado del historial con FRENO. Antes cada mensaje reescribía todo el
    // JSON a disco (snapshot de N mensajes + serialización + escritura); en un
    // hilo largo y con streaming eso es mucha E/S en el camino caliente. Ahora
    // el recuento para el medidor es inmediato (barato, y la UI lo necesita en
    // vivo), pero el volcado a disco se agrupa: varias mutaciones seguidas se
    // funden en una sola escritura. Las transiciones que no admiten pérdida
    // (cambiar de conversación, cerrar) fuerzan un flush con _saveHistoryNow.
    function _saveHistory() {
        _recountTotals()
        saveTimer.restart()
    }
    function _saveHistoryNow() {
        saveTimer.stop()
        _snapshotCurrent()
        hist.convs = conversations
        hist.current = currentId
        _recountTotals()
    }
    Timer {
        id: saveTimer
        interval: 500
        onTriggered: ai._saveHistoryNow()
    }
    // El shell se recarga con cada cambio de un .qml: si pillaba al freno de
    // guardado a medio contar, los últimos mensajes se esfumaban con la
    // recarga. Al morir, lo pendiente se vuelca.
    Component.onDestruction: if (saveTimer.running) _saveHistoryNow()

    // La carpeta de estado se crea al arrancar: en una instalación recién
    // clonada 'data/' no existe (solo lleva .gitkeep) y FileView no crea el
    // directorio padre al escribir, así que sin esto el primer guardado
    // fallaría en silencio.
    Process {
        running: true
        command: ["mkdir", "-p", ai.dataDir]
    }

    FileView {
        id: histFile
        path: ai.dataDir + "/ai-history.json"
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
            // El harness está en pie y con su historial: momento de
            // session_start (montar algo, precalentar, avisar).
            ai._fireHooks("session_start", "", {})
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
        path: ai.dataDir + "/ai-memory.json"
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: mem
            property var notes: []
        }
    }

    // Los INSTINTOS, en el suyo. Van aparte de la memoria a propósito: son
    // cosas distintas y mezclarlas ensucia las dos.
    FileView {
        path: ai.dataDir + "/ai-instincts.json"
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: inst
            property var items: []      // [{text, confidence}]
        }
    }






















}
