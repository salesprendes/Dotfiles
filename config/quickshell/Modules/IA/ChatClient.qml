import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "TextUtils.js" as TU
import "Payload.js" as PL

// EL TRANSPORTE: una vuelta al /chat/completions con streaming SSE, leída línea
// a línea con SplitParser sobre un `curl -N`.
//
// Por qué curl y no XMLHttpRequest: un Process es trivial de cancelar (SIGTERM),
// que es la mitad de un harness decente, y el SSE llega en crudo sin que nadie
// lo interprete por el camino. Aquí dentro está también toda la tolerancia con
// modelos LOCALES — llamadas escritas en el texto, tool_calls sin numerar,
// respuestas vacías — que es lo que separa "funciona con GPT" de "funciona con
// el Qwen que tienes en casa".
Scope {
    id: chat

    property var svc
    property var conv
    property var tools
    property var skills
    property var mcp
    property var dbg

    property bool busy: false
    property string streamBuf: ""
    property string reasonBuf: ""

    readonly property var _liveSplit: TU.splitThink(streamBuf)
    readonly property string liveText: _liveSplit.text
    readonly property string liveThink: (reasonBuf + _liveSplit.think).trim()

    property string _errBuf: ""
    property double _t0: 0
    property int _usageTokens: 0
    property var _tc: ({})              // tool calls en streaming, por índice
    property int _tcCur: 0              // último hueco (servidores sin index)

    // Reintento con espera ante errores TRANSITORIOS (429 de cuota, 5xx,
    // timeouts): dos intentos con pausa creciente antes de rendirse y enseñar el
    // error. Lo de siempre en los clientes de aider/OpenAI.
    property int retries: 0
    function transient(msg) {
        return /429|rate.?limit|overloaded|unavailable|timed?.?out|502|503|500/i.test(msg)
    }
    Timer {
        id: retryTimer
        onTriggered: if (!chat.busy) chat.start()
    }

    function stop() {
        if (proc.running)
            proc.running = false
    }

    // El vocabulario que se le enseña a ESTE turno. Las herramientas solo existen
    // en modo agente: en chat el modelo ni sabe que hay manos (los modos
    // plan/build de opencode, en pequeño). Y las apagadas por política ("off") ni
    // se anuncian: para el modelo no existen (las listas de denegación de
    // aisuite).
    function _toolsForTurn() {
        const defs = svc.toolDefs.filter(d => {
            const n = d["function"].name
            if (svc.toolPolicy(n) === "off")
                return false
            // Sin habilidades activas, use_skill ni se anuncia; sin servidores
            // MCP, sus herramientas de recursos tampoco.
            if (n === "use_skill" && skills.activeSkills.length === 0)
                return false
            // propose_plan siempre está disponible en modo agente: quien mejor
            // sabe si una tarea merece plan es quien acaba de leer el encargo, no
            // el usuario antes de escribirlo.
            if ((n === "list_mcp_resources" || n === "read_mcp_resource")
                    && (Settings.aiMcpServers || []).length === 0)
                return false
            // Sin sesión de depuración, controlarla o mirarla no significa
            // nada: solo se anuncia la puerta de entrada (debug_start). En
            // cuanto hay sesión, el turno siguiente ya enseña el resto.
            if (n.startsWith("debug_") && n !== "debug_start"
                    && dbg.state === "idle")
                return false
            // Habilidad en uso con allowed-tools: solo su lista, más las que
            // nunca sobran (preguntar, planificar, cambiar de habilidad) para no
            // dejar al agente sin salida.
            if (skills.activeSkillTools.length > 0
                    && skills.activeSkillTools.indexOf(n) === -1
                    && ["ask_user", "todo_write", "use_skill"].indexOf(n) === -1)
                return false
            return true
        })
            // Las herramientas MCP entran al final, filtradas igual: una política
            // "off" sobre mcp__servidor__tool la borra del vocabulario del modelo
            // como cualquier otra.
            .concat(mcp.toolDefs.filter(d => svc.toolPolicy(d["function"].name) !== "off"))
        // Recorte por relevancia si la ventana es modesta (ver maxTools).
        return svc.selectTools(defs)
    }

    // ¿Este envío ABRE un encargo o CONTINÚA uno? Se mira hacia atrás desde el
    // final: si desde el último mensaje del usuario ya hay herramientas
    // resueltas, esto es una continuación. Lo usa el reparto de esfuerzo.
    function _continuacion() {
        for (let i = conv.messages.count - 1; i >= 0; i--) {
            const m = conv.messages.get(i)
            if (m.role === "user")
                return false
            if (m.role === "tool" && m.toolStatus !== "pending")
                return true
        }
        return false
    }

    function start() {
        chat.streamBuf = ""
        chat.reasonBuf = ""
        chat._errBuf = ""
        chat._usageTokens = 0
        chat._tc = ({})
        chat._tcCur = 0
        chat._t0 = Date.now()
        const req = {
            model: svc.model,
            messages: PL.build(conv.messages, {
                charBudget: svc.charBudget,
                systemPrompt: svc.systemFor(svc.systemPrompt,
                                  chat._continuacion() ? "tools" : "turn"),
                advisorNote: svc.advisorNote,
                // Su propio razonamiento de vuelta, solo si el modelo sabe
                // aprovecharlo y el servidor no lo ha rechazado.
                keepReasoning: svc.profile.preserveThinking
                               && Settings.aiKeepThinking !== false
                               && !svc.profileDegraded.reasoning,
                // Un modelo de solo texto no admite imágenes: mandárselas es un
                // error del servidor y un "algo falló" que el usuario no puede
                // interpretar. Se avisa al adjuntar (ver AiService.canSeeImages).
                images: svc.canSeeImages ? svc.sendImages : [],
                // Gemma 4 pide las imágenes ANTES del texto; los demás las
                // quieren detrás, que es como estaban.
                imagesFirst: svc.profile.imagesFirst === true
            }),
            stream: true
        }
        // Temperatura: el parámetro universal del contrato, con el valor del
        // usuario (Ajustes del panel).
        req.temperature = Math.round(Settings.aiTemperature * 100) / 100
        // Lo que sabemos del modelo concreto: pensamiento, esfuerzo, muestreo
        // recomendado y tope de salida. Con un modelo no reconocido esta línea
        // no hace nada — devuelve la misma petición.
        //
        // El TIPO de turno decide el esfuerzo: el primero de un encargo es
        // donde se elige el plan y merece pensar a fondo; los que vienen detrás
        // de un resultado de herramienta son sobre todo integrar lo que ya
        // llegó, y ahí pensar a fondo es pagar de más en cada ronda.
        svc.tuneRequest(req, chat._continuacion() ? "tools" : "turn")
        // Interruptor de razonamiento de Qwen3: "/think" y "/no_think" son
        // interruptores SUAVES que el modelo entiende dentro del turno del
        // usuario — van en el mensaje, no en la API, así que no rompen nada en
        // servidores que no los conocen. Con un Qwen local, apagar el pensamiento
        // es la mayor mejora de latencia que existe. Los modelos que traen
        // bandera propia (Qwen 3.8) no los quieren: ahí solo serían ruido dentro
        // del mensaje del usuario.
        if (Settings.aiThink !== "auto" && svc.profile.softSwitch)
            for (let i = req.messages.length - 1; i >= 0; i--)
                if (req.messages[i].role === "user"
                        && typeof req.messages[i].content === "string") {
                    req.messages[i] = { role: "user",
                        content: req.messages[i].content + " /" + Settings.aiThink }
                    break
                }
        if (svc.agentMode) {
            const sent = _toolsForTurn()
            if (sent.length > 0)
                req.tools = sent
        }
        if (Settings.aiProvider !== "gemini")
            req.stream_options = { include_usage: true }
        // Credenciales y opciones de red salen de las mismas funciones que usa la
        // sonda, así que lo que prueba el botón "Probar" es exactamente lo que va
        // a viajar. 300 s para el stream entero.
        // El cuerpo ya no viaja en el comando: se escribe en la entrada estándar
        // en cuanto el proceso arranca (ver onStarted). Con la conversación
        // entera en el argv, un adjunto de captura o un hilo largo pasaba de los
        // 128 kB por argumento y la petición fallaba con E2BIG antes de salir.
        const t = svc.chatCommand(req, 300)
        chat._body = t.body
        proc.command = t.cmd
        proc.environment = t.env
        proc.stdinEnabled = true
        chat.busy = true
        proc.running = true
    }

    // El cuerpo en vuelo, esperando a que el proceso esté vivo para escribirlo.
    property string _body: ""

    Process {
        id: proc
        // Se escribe en onStarted y no justo después de running=true: hasta que
        // el proceso no existe no hay tubería a la que escribir.
        onStarted: {
            proc.write(chat._body)
            chat._body = ""
            // Cerrar la entrada es lo que hace que el shell deje de leer y
            // lance curl. Sin esto no se envía nada y no se sabría por qué.
            proc.stdinEnabled = false
        }

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
                            chat._errBuf += (j.error.message || JSON.stringify(j.error))
                            return
                        }
                        if (j.usage && j.usage.completion_tokens)
                            chat._usageTokens = j.usage.completion_tokens
                        const d = j.choices && j.choices[0] && j.choices[0].delta
                        if (!d)
                            return
                        // El razonamiento llega con dos nombres según el servidor:
                        // reasoning_content (Qwen/DashScope/vLLM) o reasoning
                        // (OpenRouter). Se aceptan ambos.
                        const razon = d.reasoning_content || d.reasoning
                        if (razon)
                            chat.reasonBuf += razon
                        if (d.content)
                            chat.streamBuf += d.content
                        // Propuestas de herramienta: llegan troceadas (nombre en
                        // un delta, argumentos gota a gota).
                        if (d.tool_calls)
                            for (let k = 0; k < d.tool_calls.length; k++) {
                                const tc = d.tool_calls[k]
                                // Algunos servidores de Qwen no numeran las
                                // llamadas en el stream (falta 'index'). Sin
                                // esto, dos llamadas paralelas se fundían en una
                                // sola con los argumentos mezclados: un id NUEVO
                                // abre hueco nuevo; sin id, se sigue rellenando
                                // el último.
                                let idx = tc.index
                                if (idx === undefined || idx === null) {
                                    if (tc.id && chat._tc[chat._tcCur]
                                            && chat._tc[chat._tcCur].id !== tc.id)
                                        chat._tcCur++
                                    idx = chat._tcCur
                                } else {
                                    chat._tcCur = idx
                                }
                                if (!chat._tc[idx])
                                    chat._tc[idx] = { id: "", name: "", args: "" }
                                if (tc.id) chat._tc[idx].id = tc.id
                                if (tc["function"]) {
                                    if (tc["function"].name)
                                        chat._tc[idx].name = tc["function"].name
                                    if (tc["function"].arguments)
                                        chat._tc[idx].args += tc["function"].arguments
                                }
                            }
                    } catch (e) { /* fragmento no-JSON: se ignora */ }
                } else {
                    chat._errBuf += l
                }
            }
        }
        stderr: SplitParser {
            onRead: (line) => { if (line.trim() !== "") chat._errBuf += line + " " }
        }

        onExited: (code) => {
            chat.busy = false
            const parts = TU.splitThink(chat.streamBuf)
            const think = (chat.reasonBuf + parts.think).trim()
            let text = parts.text.trim()
            // Modelo local que escribe la llamada en el texto en vez de emitirla
            // como tool_call: se rescata y se trata igual. Sin esto, con Qwen
            // sobre un servidor que no traduce, el agente "habla" de usar una
            // herramienta y no usa ninguna.
            if (svc.agentMode && Object.keys(chat._tc).length === 0 && text !== "") {
                const found = svc.extractTextToolCalls(text)
                if (found.calls.length > 0) {
                    text = found.rest
                    for (let i = 0; i < found.calls.length; i++)
                        chat._tc[i] = { id: "", name: found.calls[i].name,
                                        args: found.calls[i].args }
                }
            }
            // EN MODO CHAT NO HAY HERRAMIENTAS, Y ESO TIENE QUE SER VERDAD.
            // Chat no las anuncia (ver arriba, `if (svc.agentMode)` al armar la
            // petición), pero anunciar no es lo mismo que impedir: el ejecutor
            // actúa por NOMBRE, así que un tool_call que llegue igualmente
            // —porque el servidor lo inventa, porque hay un proxy por medio, o
            // porque una página inyectada convenció al modelo de escribirlo en
            // el texto— se convertía en tarjeta como cualquier otra. Y una
            // tarjeta en Chat es peor que en agente: el usuario NO espera que
            // ahí pueda ejecutarse nada, así que la aprobaría con menos cuidado.
            //
            // Se descarta en silencio para el modelo pero se dice en el hilo: si
            // no se contase, el modelo parecería no haber contestado.
            if (!svc.agentMode && Object.keys(chat._tc).length > 0) {
                chat._tc = ({})
                conv.pushInfo(I18n.tr("In Chat mode no tools are run. Switch to "
                                      + "Agent if you want it to act."))
            }
            const tcKeys = Object.keys(chat._tc)

            if (tcKeys.length > 0) {
                // El modelo propone una o VARIAS herramientas → una tarjeta por
                // cada una. Los modelos buenos piden varias lecturas de golpe;
                // antes se perdían todas menos la primera. El texto y el
                // razonamiento acompañan solo a la primera tarjeta.
                // ¿Se ha atascado repitiendo la misma llamada? Se corta aquí.
                let looped = ""
                for (let i = 0; i < tcKeys.length; i++) {
                    const tc = chat._tc[tcKeys[i]]
                    if (tc.name && chat.tools.loopCount(tc.name, tc.args) >= chat.tools.loopThreshold)
                        looped = tc.name
                }
                if (looped !== "") {
                    chat.streamBuf = ""
                    chat.reasonBuf = ""
                    conv.pushInfo(I18n.tr("Stopped: it repeated the same %1 call over and over.")
                                      .arg(looped))
                    svc.replied()
                    return
                }
                // Todas las tarjetas de esta ronda comparten marca de lote: es lo
                // que luego permite reconstruir el protocolo (un assistant con N
                // tool_calls por ronda, no por tarjeta).
                const rondaId = "b" + Date.now()
                for (let i = 0; i < tcKeys.length; i++) {
                    const tc = chat._tc[tcKeys[i]]
                    if (!tc.name)     // fragmento sin nombre: no es una llamada
                        continue
                    conv.push({ role: "tool", content: i === 0 ? text : "",
                                toolName: tc.name, toolArgs: tc.args,
                                toolId: tc.id !== "" ? tc.id : ("call_" + Date.now() + "_" + i),
                                toolStatus: "pending", toolBatch: rondaId,
                                modelName: svc.model, reasoning: i === 0 ? think : "" })
                }
                chat.streamBuf = ""
                chat.reasonBuf = ""
                chat.tools.toolRounds++
                if (chat.tools.toolRounds === chat.tools.maxToolRounds + 1)
                    conv.pushInfo(I18n.tr("Step limit reached — approvals are manual again."))
                // El coordinador ejecuta las auto en serie y deja las manuales
                // esperando; devuelve al modelo cuando el lote esté resuelto.
                chat.tools.advance()
                svc.replied()
                return
            }

            if (text !== "" || think !== "") {
                chat.retries = 0
                conv.push({ role: "assistant",
                            content: text !== "" ? text : think,
                            reasoning: text !== "" ? think : "",
                            modelName: svc.model,
                            ms: Date.now() - chat._t0, tokens: chat._usageTokens })
                chat.streamBuf = ""
                chat.reasonBuf = ""
                svc.replied()
                Qt.callLater(svc.dequeue)
                return
            }

            let msg = chat._errBuf.trim()
            try {
                let j = JSON.parse(msg)
                if (Array.isArray(j))    // Gemini envuelve el error en un array
                    j = j[0] || {}
                msg = (j.error && (j.error.message || j.error.code)) || msg
            } catch (e) {}
            if (msg === "")
                msg = code === 0 ? I18n.tr("No response received")
                                 : I18n.tr("Connection failed (curl exit %1)").arg(code)
            // Transitorio y con intentos en la recámara: se reintenta solo, con
            // espera creciente, sin molestar con una tarjeta de error. Una
            // respuesta VACÍA con conexión limpia cuenta como transitoria: los
            // Qwen locales la sueltan de vez en cuando y a la siguiente va (la
            // regla de reintento de qwen-code).
            // El servidor ha rechazado algo que le mandábamos por el perfil
            // del modelo: se apaga ESO —no todo— y se reintenta enseguida. No
            // cuenta como reintento transitorio, porque no es un fallo de red
            // sino una incompatibilidad que acabamos de aprender de este
            // servidor concreto.
            if (svc.profileDegrade(msg)) {
                retryTimer.interval = 200
                retryTimer.restart()
                return
            }
            const vacia = code === 0 && chat._errBuf.trim() === ""
            if ((chat.transient(msg) || vacia) && chat.retries < 2) {
                chat.retries++
                conv.pushInfo(I18n.tr("Temporary error — retrying (%1/2)…").arg(chat.retries))
                retryTimer.interval = chat.retries * 2500
                retryTimer.restart()
                return
            }
            conv.push({ role: "error", content: msg })
            Qt.callLater(svc.dequeue)
        }
    }
}
