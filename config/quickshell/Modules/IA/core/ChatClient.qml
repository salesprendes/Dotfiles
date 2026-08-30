import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "../TextUtils.js" as TU
import "Payload.js" as PL

// El transporte: una vuelta al /chat/completions con streaming SSE, leída línea a
// línea con SplitParser sobre un `curl -N`.
//
// Con curl y no XMLHttpRequest porque un Process es trivial de cancelar, que es
// la mitad de un harness decente, y el SSE llega en crudo sin que nadie lo
// interprete por el camino. Aquí dentro está también la tolerancia con modelos
// locales: llamadas escritas en el texto, tool_calls sin numerar y respuestas
// vacías.
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
    // error.
    property int retries: 0
    function transient(msg) {
        return /429|rate.?limit|overloaded|unavailable|timed?.?out|502|503|500/i.test(msg)
    }

    // El contexto no cabe. Cada servidor lo dice a su manera, así que el
    // reconocimiento es amplio a propósito: el castigo por acertar de más es
    // compactar una vez sin necesidad, y el de fallar es dejar el turno muerto con
    // un error que el usuario no puede arreglar salvo borrando la conversación.
    function overflow(msg) {
        return /context[_ ]?(length|window|limit|size)|maximum context|prompt is too long|input is too long|too many tokens|token count.{0,24}exceeds|exceeds? (the )?context|exceeds the maximum number of tokens|reduce the length|request too large|n_ctx|kv cache is full/i
                   .test(msg)
    }
    // Una sola recuperación por turno: si tras compactar vuelve a desbordar, el
    // problema no era el historial y reintentar sería un bucle.
    property bool _desbordado: false
    Timer {
        id: retryTimer
        onTriggered: if (!chat.busy) chat.start()
    }

    // Parar de verdad. Matar el curl no basta: onExited seguiría su camino normal
    // —rescatar las llamadas a medias, montar sus tarjetas y encadenar la ronda
    // siguiente—, así que parar mientras el modelo escribe dejaría una tanda de
    // tarjetas recién nacidas y el turno vivo. La marca dice que lo que llegue ya
    // no vale.
    property bool aborted: false

    function stop() {
        if (!proc.running)
            return                  // nada que cortar: no se deja marca puesta
        aborted = true
        // El corte se ve al instante. Esperar a que el proceso muera para apagar
        // 'busy' no vale: matar un curl que está recibiendo un stream no es
        // inmediato, el panel seguiría diciendo "pensando" varios segundos y el
        // aviso de interrumpido llegaría tarde, que es lo que lleva a pulsar el
        // botón cinco veces.
        //
        // Así que el turno se cierra AQUÍ, con lo que hubiera escrito, y lo
        // que el proceso tarde en morir ya no lo mira nadie: su onExited ve la
        // marca y sale sin tocar el hilo.
        const dicho = TU.splitThink(chat.streamBuf).text.trim()
        chat.streamBuf = ""
        chat.reasonBuf = ""
        chat._tc = ({})
        chat.busy = false
        proc.running = false
        if (dicho !== "")
            conv.push({ role: "assistant", content: dicho, modelName: svc.model })
        conv.pushInfo(I18n.tr("Interrupted."))
        conv.save()
        svc.replied()
    }

    // El vocabulario que se le enseña a este turno. Las herramientas solo existen
    // en modo agente: en chat el modelo ni sabe que hay manos. Y las apagadas por
    // política ("off") ni se anuncian: para el modelo no existen.
    function _toolsForTurn() {
        const defs = svc.toolDefs.filter(d => {
            const n = d["function"].name
            if (svc.toolPolicy(n) === "off")
                return false
            // Sin habilidades activas, use_skill ni se anuncia; sin servidores
            // MCP, sus herramientas de recursos tampoco.
            if (n === "use_skill" && skills.activeSkills.length === 0)
                return false
            // propose_plan siempre está disponible en modo agente: quien mejor sabe
            // si una tarea merece plan es quien acaba de leer el encargo.
            if ((n === "list_mcp_resources" || n === "read_mcp_resource")
                    && (Settings.aiMcpServers || []).length === 0)
                return false
            // Sin sesión de depuración solo se anuncia la puerta de entrada; en
            // cuanto hay sesión, el turno siguiente enseña el resto.
            if (n.startsWith("debug_") && n !== "debug_start"
                    && dbg.state === "idle")
                return false
            // Habilidad en uso con allowed-tools: solo su lista, más las que nunca
            // sobran —preguntar, planificar, cambiar de habilidad— para no dejar al
            // agente sin salida.
            if (skills.activeSkillTools.length > 0
                    && skills.activeSkillTools.indexOf(n) === -1
                    && ["ask_user", "todo_write", "use_skill"].indexOf(n) === -1)
                return false
            return true
        })
            // Las herramientas MCP entran al final, filtradas igual: una política
            // "off" las borra del vocabulario como a cualquier otra.
            .concat(mcp.toolDefs.filter(d => svc.toolPolicy(d["function"].name) !== "off"))
        // Recorte por relevancia si la ventana es modesta (ver maxTools).
        return svc.selectTools(defs)
    }

    // ¿Este envío abre un encargo o continúa uno? Se mira hacia atrás desde el
    // final: si desde el último mensaje del usuario ya hay herramientas resueltas,
    // es una continuación. Lo usa el reparto de esfuerzo.
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
        // Turno nuevo, marca limpia. Sin esto, un stop pulsado cuando ya no había
        // nada corriendo dejaría la marca puesta y mataría el turno siguiente nada
        // más nacer.
        chat.aborted = false
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
                // Un modelo de solo texto no admite imágenes: mandárselas da un
                // error del servidor que el usuario no puede interpretar. Se avisa
                // al adjuntar.
                images: svc.canSeeImages ? svc.sendImages : [],
                // Algunas familias piden las imágenes antes del texto; las demás
                // las quieren detrás.
                imagesFirst: svc.profile.imagesFirst === true
            }),
            stream: true
        }
        // Temperatura: el parámetro universal del contrato, con el valor del
        // usuario (Ajustes del panel).
        req.temperature = Math.round(Settings.aiTemperature * 100) / 100
        // Lo que se sabe del modelo concreto: pensamiento, esfuerzo, muestreo
        // recomendado y tope de salida. Con uno no reconocido devuelve la misma
        // petición.
        //
        // El tipo de turno decide el esfuerzo: el primero de un encargo es donde se
        // elige el plan y merece pensar a fondo, y los que vienen detrás de un
        // resultado de herramienta son sobre todo integrar lo que ya llegó.
        svc.tuneRequest(req, chat._continuacion() ? "tools" : "turn")
        // Interruptores suaves de razonamiento que el modelo entiende dentro del
        // turno del usuario: van en el mensaje y no en la API, así que no rompen
        // nada en servidores que no los conocen. Los modelos que traen bandera
        // propia no los quieren, porque ahí solo serían ruido.
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
        // sonda, así que lo que prueba el botón "Probar" es lo que va a viajar.
        //
        // El cuerpo no viaja en el comando: se escribe en la entrada estándar en
        // cuanto el proceso arranca. Con la conversación entera en el argv, un
        // adjunto o un hilo largo pasa del tope por argumento y la petición falla
        // con E2BIG antes de salir.
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
        // Se escribe en onStarted y no justo después de running=true: hasta que el
        // proceso no existe no hay tubería a la que escribir.
        onStarted: {
            proc.write(chat._body)
            chat._body = ""
            // Cerrar la entrada es lo que hace que el shell deje de leer y lance
            // curl. Sin esto no se envía nada y no se sabría por qué.
            proc.stdinEnabled = false
        }

        stdout: SplitParser {
            onRead: (line) => {
                // Ya se paró: lo que siga llegando por la tubería mientras el
                // proceso muere no entra en el hilo. Sin esto el razonamiento
                // seguiría acumulándose con el turno ya cerrado y podría resucitar
                // llamadas que nadie aprobó.
                if (chat.aborted)
                    return
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
                        // El razonamiento llega con dos nombres según el servidor,
                        // y se aceptan ambos.
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
                                // Algunos servidores no numeran las llamadas en el
                                // stream: sin esto, dos llamadas paralelas se
                                // funden en una con los argumentos mezclados. Un id
                                // nuevo abre hueco; sin id, se sigue rellenando el
                                // último.
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
            // Interrumpido: el turno ya se cerró en stop(), así que este final
            // tardío no toca nada. Solo se tira lo que siguió llegando mientras el
            // proceso moría.
            if (chat.aborted) {
                chat.aborted = false
                chat.streamBuf = ""
                chat.reasonBuf = ""
                chat._tc = ({})
                return
            }
            const parts = TU.splitThink(chat.streamBuf)
            const think = (chat.reasonBuf + parts.think).trim()
            let text = parts.text.trim()
            // Modelo local que escribe la llamada en el texto en vez de emitirla
            // como tool_call: se rescata y se trata igual. Sin esto, el agente
            // habla de usar una herramienta y no usa ninguna.
            if (svc.agentMode && Object.keys(chat._tc).length === 0 && text !== "") {
                const found = svc.extractTextToolCalls(text)
                if (found.calls.length > 0) {
                    text = found.rest
                    for (let i = 0; i < found.calls.length; i++)
                        chat._tc[i] = { id: "", name: found.calls[i].name,
                                        args: found.calls[i].args }
                }
            }
            // En modo chat no hay herramientas, y eso tiene que ser verdad.
            // Anunciar no es lo mismo que impedir: el ejecutor actúa por nombre, así
            // que un tool_call que llegue igualmente —porque el servidor lo invente,
            // por un proxy, o porque una página inyectada convenciera al modelo de
            // escribirlo en el texto— se convertiría en tarjeta. Y una tarjeta en
            // chat es peor que en agente: el usuario no espera que
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
                chat._desbordado = false
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
            // DESBORDAMIENTO: no es un fallo transitorio y reintentar igual
            // volvería a fallar igual. Se compacta y se retoma el turno. Va
            // antes que el reintento genérico justo por eso.
            if (chat.overflow(msg) && !chat._desbordado) {
                chat._desbordado = true
                if (svc.recoverOverflow())
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
