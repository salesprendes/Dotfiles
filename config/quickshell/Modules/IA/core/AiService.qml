pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import qs.Modules.IA.agents
import qs.Modules.IA.integrations
import qs.Modules.IA.storage
import qs.Modules.IA.tools
import "../TextUtils.js" as TU
import "../tools/ToolDefs.js" as TD
import "../tools/ToolPolicy.js" as TP
import "ModelCatalog.js" as MC
import "Endpoint.js" as EP
import "ModelProfile.js" as MP
import "../tools/LocalTools.js" as LT
import "../tools/RemoteTools.js" as RT
import "../integrations/WebSearch.js" as WS
import "Payload.js" as PL

// Harness del asistente IA. La idea (tomada de la capa "aisuite" que usa
// OpenWorker) es que el panel no sepa NADA de proveedores: todos hablan el
// /chat/completions de OpenAI con streaming SSE, y aquí solo cambian URL,
// credencial y modelo.
//
// ESTE ARCHIVO ES EL ORQUESTADOR, no el sitio donde vive todo. Cada pieza del
// harness es un componente con su propio estado y sus propios procesos, y lo que
// queda aquí es lo que de verdad pertenece al centro: qué proveedor hay, cómo se
// arma una petición, el prompt de sistema, y la superficie pública que consume
// el panel. Las piezas, en orden de dependencia:
//
//   KeyStore          claves de API y contraseñas SSH (llavero del sistema)
//   ConnectionProbe   sonda de conexión y catálogo de modelos del servidor
//   McpManager        clientes MCP por stdio (JSON-RPC)
//   HookRunner        hooks del usuario, incluido el que puede vetar
//   MemoryStore       memoria del usuario e instintos del equipo
//   SkillStore        habilidades, su ranking y la carga automática
//   ConversationStore el hilo, las conversaciones y su persistencia
//   ToolRunner        aprobación y ejecución de herramientas
//   ChatClient        el transporte SSE y la tolerancia con modelos locales
//   Compactor         compactación del contexto
//   Attachments       portapapeles, captura y referencias @ruta
//   SubAgent          la delegación de solo lectura
//
// Y tres bibliotecas puras que no necesitan QML para nada: ToolPolicy.js (clase
// de riesgo y permisos), LocalTools.js / RemoteTools.js (los constructores de
// comando, que son LA jaula) y Payload.js (el historial que viaja al modelo).
Singleton {
    id: ai

    // ── Dónde vive todo lo de la IA ──────────────────────────────────────────
    // Un único sitio: el propio módulo. Las habilidades en 'skills/' y el estado
    // (historial, memoria, instintos, hooks) en 'data/', de modo que llevarse el
    // asistente a otra máquina sea copiar una carpeta. Se cuelga de
    // Quickshell.shellDir en vez de ~/.config/quickshell a pelo: así vale igual
    // si el shell se carga desde otra ruta.
    readonly property string iaDir: Quickshell.shellDir + "/Modules/IA"
    readonly property string dataDir: iaDir + "/data"
    readonly property string skillsDir: iaDir + "/skills"

    // El cerco de la carpeta de datos. Ahí dentro está la conversación entera,
    // la memoria y el registro de auditoría con los argumentos de cada llamada,
    // y nacían con 0644: legibles por cualquier cuenta de la máquina.
    //
    // Se cierra el DIRECTORIO y no solo los archivos, y es a propósito: los
    // archivos los reescribe FileView con el umask de la sesión, así que un
    // chmod sobre ellos se perdería en el siguiente guardado. Un directorio a
    // 0700 no se reescribe nunca y hace irrelevante el modo de lo que hay
    // dentro. Los archivos se aprietan igual, por si algún día se mueven.
    // Las dos cachés de ~/.cache van en el mismo viaje. No son "temporales" en
    // el sentido de inofensivas: la de deshacer guarda COPIAS ENTERAS de los
    // archivos que se editaron —con sus claves y su configuración dentro— y la
    // de búsqueda guarda qué se buscó, que dice tanto como lo que se encontró.
    // Nacían a 0755.
    Process {
        running: true
        environment: ({ QS_D: ai.dataDir,
                        QS_C: Quickshell.env("HOME") + "/.cache" })
        command: ["sh", "-c",
            'mkdir -p "$QS_D" && chmod 700 "$QS_D"; '
            + 'chmod 600 "$QS_D"/*.json "$QS_D"/*.jsonl 2>/dev/null; '
            + 'for c in quickshell-ai-undo quickshell-ai-search; do '
            + '  [ -d "$QS_C/$c" ] && chmod -R go-rwx "$QS_C/$c"; done; true']
    }

    // ── Proveedores y modelos ────────────────────────────────────────────────
    // El catálogo, la normalización de URL y el reparto de "un modelo por
    // proveedor" viven en core/Endpoint.js: son JavaScript puro, y sacarlos de
    // aquí es lo que permite probar de una en una las docenas de formas en que
    // una URL se pega mal (ver tests/t_endpoint.js). Lo que queda aquí son los
    // enlaces con los ajustes, que es lo único que de verdad es QML.
    readonly property var provider: EP.proveedorDe(Settings.aiProvider)
    // La etiqueta del servidor propio se rotula aquí, que es donde se ve I18n.
    readonly property string providerLabel:
        Settings.aiProvider === "custom" ? I18n.tr("Server") : provider.label

    readonly property var _modelos: ({
        openrouter: Settings.aiModelOpenrouter, ollama: Settings.aiModelOllama,
        custom: Settings.aiModelCustom, gemini: Settings.aiModelGemini
    })
    function modelFor(id) { return EP.modeloDe(id, ai._modelos) }
    readonly property string model: EP.modeloDe(Settings.aiProvider, _modelos)

    readonly property string apiBase:
        EP.baseDe(Settings.aiProvider, ({ ollama: Settings.aiOllamaUrl,
                                          custom: Settings.aiCustomUrl }))
    readonly property string endpoint: EP.endpointDe(apiBase)
    readonly property string modelsUrl: EP.modelosUrl(apiBase, Settings.aiProvider)

    // "ollama:qwen3" cambia proveedor Y modelo en un gesto.
    function setModel(m) {
        const r = EP.parseModelo(m, Settings.aiProvider)
        const cual = EP.ajusteDe(r.proveedor)
        if (cual === "openrouter")   Settings.aiModelOpenrouter = r.modelo
        else if (cual === "ollama")  Settings.aiModelOllama = r.modelo
        else if (cual === "custom")  Settings.aiModelCustom = r.modelo
        else                         Settings.aiModelGemini = r.modelo
        Settings.aiProvider = r.proveedor
    }

    function modelShort(id) { return MC.shortName(id) }
    function modelTag(id)   { return MC.tag(id) }
    // La variante (27b, a3b, fp8, q4_k_m…): sin ella, tres modelos distintos
    // del mismo servidor se leen iguales en la lista.
    function modelVariant(id) { return MC.variant(id) }
    // Nombre y variante juntos, que es como se nombra un modelo en voz alta.
    function modelLabel(id) {
        const v = MC.variant(id)
        return MC.shortName(id) + (v !== "" ? "  ·  " + v : "")
    }

    readonly property var modelGroups: MC.groups({
        active: Settings.aiProvider,
        model: ai.model,
        fetched: probe.fetchedModels,
        labels: { gemini: EP.PROVEEDORES.gemini.label,
                  openrouter: EP.PROVEEDORES.openrouter.label,
                  ollama: EP.PROVEEDORES.ollama.label,
                  custom: ai.providerLabel },
        modelFor: ai.modelFor
    })

    // Falta algo para poder hablar: sin URL (los de servidor propio) o sin clave
    // (los de nube). El panel lo usa para invitar a configurar en vez de dejar
    // que el envío falle con un error de red.
    readonly property var _faltan: EP.faltan(Settings.aiProvider, apiBase, apiKey)
    readonly property bool urlMissing: _faltan.url
    readonly property bool keyMissing: _faltan.clave
    readonly property bool notConfigured: _faltan.alguna

    // ── Qué modelo hay delante ───────────────────────────────────────────────
    // Lo que ese modelo concreto admite (ventana, pensamiento, muestreo,
    // imágenes). Un modelo desconocido devuelve el perfil genérico y con él
    // NADA de esto se aplica: el harness se comporta como siempre. Ver
    // ModelProfile.js.
    readonly property var profile: MP.of(model)
    readonly property string profileLabel: profile.label

    // Lo que ESTE servidor ha rechazado. Un OpenAI-compatible puede no entender
    // un campo y contestar 400; la respuesta no es dejar de mandarlo siempre
    // (el que sí lo entiende lo aprovecha) sino apagar el que molesta aquí.
    property var profileDegraded: ({})
    function profileDegrade(msg) {
        const k = MP.offenderOf(msg)
        if (k === "" || profileDegraded[k])
            return false
        const m = Object.assign({}, profileDegraded)
        m[k] = true
        profileDegraded = m
        conv.pushInfo(I18n.tr("This server does not accept %1 — turned off for this session.")
                          .arg(MP.offenderLabel(k)))
        return true
    }
    // Cambiar de modelo o de servidor estrena la hoja: lo que rechazaba uno no
    // tiene por qué rechazarlo el siguiente.
    onModelChanged: profileDegraded = ({})
    onEndpointChanged: profileDegraded = ({})

    // ── El esfuerzo de razonamiento, por tarea ───────────────────────────────
    // Un modelo con tres niveles de esfuerzo se suele dejar en el máximo "por si
    // acaso", y entonces se paga pensamiento profundo para resumir una
    // conversación. El harness sabe algo que el usuario no puede saber a mano:
    // QUÉ le está pidiendo en cada momento. Se piensa a fondo donde se toman las
    // decisiones —el turno en el que se decide el plan, la revisión de código— y
    // se va ligero donde el trabajo es mecánico: integrar el resultado de una
    // herramienta, compactar, o decidir si una llamada es peligrosa.
    readonly property string effortSetting:
        ["auto", "low", "medium", "xhigh"].indexOf(Settings.aiEffort) !== -1
            ? Settings.aiEffort : "auto"
    // 'p' permite preguntar por un perfil que no es el del agente (el supervisor
    // puede usar otro modelo). Sin él, el del agente.
    function effortFor(kind, p) {
        const perfil = p || profile
        if (!perfil.efforts || perfil.efforts.length === 0)
            return ""
        if (effortSetting !== "auto")
            return effortSetting
        switch (kind) {
        case "turn":     return agentMode ? "xhigh" : "medium"
        case "tools":    return "medium"
        case "review":   return "xhigh"
        case "subagent": return "medium"
        case "compact":  return "low"
        case "guard":    return "low"
        case "advise":   return "low"
        }
        return "medium"
    }

    // ¿Piensa en esta llamada? El ajuste del usuario manda, salvo en el modelo
    // que no admite apagarlo (y ahí ModelProfile ya lo ignora).
    readonly property bool wantThinking: Settings.aiThink !== "no_think"

    // ¿Ve imágenes? Solo se dice que NO cuando el modelo está reconocido y
    // sabemos que es de solo texto. De uno desconocido no se presume nada y se
    // mandan como siempre — quitar una capacidad por si acaso sería peor que el
    // error que evita.
    readonly property bool canSeeImages: profile.family === "" || profile.vision

    // La ÚNICA puerta por la que el perfil toca una petición. La usan el chat,
    // el subagente, la compactación y el supervisor, así que lo que se sabe del
    // modelo se aplica en los cuatro sin que ninguno tenga que acordarse.
    // La otra mitad: hay familias que no encienden el pensamiento con un campo
    // de la petición sino escribiendo en el PROMPT DE SISTEMA — una línea
    // "Reasoning strength: …" (Muse Glimmer) o un token al principio del todo
    // (Gemma 4). Por eso todo prompt de sistema del harness pasa por aquí, y
    // con un modelo desconocido sale exactamente igual que entró.
    function systemFor(text, kind, thinking, modelId) {
        const p = (modelId && modelId !== model) ? MP.of(modelId) : profile
        return MP.systemFor(text, p, ({
            thinking: thinking === undefined ? wantThinking : thinking,
            effort: effortFor(kind, p),
            degraded: profileDegraded
        }))
    }

    // 'modelId' solo hace falta cuando la petición NO va al modelo del agente
    // (el supervisor puede usar otro): aplicarle el perfil del principal sería
    // mandarle banderas de un modelo que no es.
    function tuneRequest(req, kind, thinking, modelId) {
        const p = (modelId && modelId !== model) ? MP.of(modelId) : profile
        return MP.tune(req, p, ({
            thinking: thinking === undefined ? wantThinking : thinking,
            effort: effortFor(kind, p),
            tuning: Settings.aiModelTuning !== false,
            // Reaprovechar su razonamiento tiene sentido dentro de un encargo
            // largo, no al resumir la conversación entera.
            keepThinking: Settings.aiKeepThinking !== false
                          && kind !== "compact" && kind !== "guard"
                          && kind !== "advise",
            maxOut: kind === "turn" || kind === "tools",
            degraded: profileDegraded
        }))
    }


    // ── Presupuesto de contexto ──────────────────────────────────────────────
    // Antes el recorte era de 20 000 caracteres fijos, dijera lo que dijera el
    // modelo. Con un modelo LOCAL eso es o derrochar (un Qwen de 32k aguanta el
    // triple) o desbordar (uno de 8k no llega). Ahora todo cuelga de la ventana
    // real: el usuario la declara y de ahí sale el recorte del historial, el tope
    // de cada resultado de herramienta, el del catálogo de habilidades y el
    // medidor.
    readonly property int contextTokens:
        Settings.aiContextTokens > 0 ? Settings.aiContextTokens
        // Si el modelo está reconocido, su ventana REAL manda sobre la
        // heurística: adivinar 32k para un modelo de 262k es tirar casi todo el
        // contexto que has pagado, y recortar el historial mucho antes de hacer
        // ninguna falta.
        : (profile.ctx > 0 ? profile.ctx
        : (provider.userUrl ? 32768 : 128000))    // local típico vs. nube
    // Del total, algo menos de la mitad para el historial: el resto lo comen el
    // prompt de sistema, los esquemas de herramientas y la respuesta. ~3,5
    // caracteres por token es la regla de bolsillo habitual.
    readonly property int charBudget: Math.round(contextTokens * 3.5 * 0.45)
    // Un solo resultado de herramienta no puede comerse el turno.
    readonly property int toolResultCap:
        Math.max(1500, Math.min(12000, Math.round(charBudget / 6)))

    // ── Cuántas herramientas se le enseñan de golpe ──────────────────────────
    // Casi cuarenta esquemas son mucho ruido para un modelo pequeño: le comen
    // contexto y le hacen elegir peor. Con ventana holgada se le enseñan todas;
    // con una ventana modesta, un núcleo fijo más las que vengan a cuento.
    // Recortar aquí NO quita capacidades: el ejecutor actúa por nombre, así que
    // si el modelo nombra una que no iba en la lista, funciona igual — esto es
    // una sugerencia, no un muro.
    readonly property int maxTools:
        contextTokens < 16000 ? 12 : contextTokens < 64000 ? 20 : 0    // 0 = todas
    readonly property var coreTools: ["ask_user", "todo_write", "run_command",
                                      "read_file", "write_file", "edit_file",
                                      "edit_lines", "list_dir", "grep_files"]

    // Ordena por relevancia al último mensaje y recorta, dejando siempre el
    // núcleo y lo que ya venía filtrado por modo/política.
    function selectTools(defs) {
        if (maxTools <= 0 || defs.length <= maxTools)
            return defs
        const core = defs.filter(d => coreTools.indexOf(d["function"].name) !== -1)
        const rest = defs.filter(d => coreTools.indexOf(d["function"].name) === -1)
        const texts = rest.map(d => d["function"].name + " " + (d["function"].description || ""))
        const order = TU.rankNotes(texts, lastUserText)
        const room = Math.max(0, maxTools - core.length)
        const picked = order.slice(0, room).map(i => rest[i])
        return core.concat(picked)
    }

    // ── Transporte ───────────────────────────────────────────────────────────
    // Cabecera de credencial: Bearer si hay clave (también en los servidores
    // propios con token) más la cabecera extra que pida la pasarela.
    // (Aquí vivía authArgs(), que devolvía las cabeceras como argumentos de
    // curl. Se ha ido entera: las credenciales ya no pasan por el argv en
    // ningún camino — ni en el envío, ni en la compactación, ni en el
    // subagente, ni en la sonda. Lo arma Payload.js en un fichero de
    // configuración que escribe el propio shell.)
    // Opciones de red del transporte: certificado no verificable (servidor propio
    // con TLS autofirmado). Solo donde el usuario pone la URL: nadie necesita
    // saltarse la verificación contra Google u OpenRouter.
    function netArgs() {
        return (Settings.aiInsecureTls && provider.userUrl) ? ["-k"] : []
    }

    // El argv completo de una llamada al /chat/completions. Lo comparten el
    // streaming del panel, la compactación y el subagente: antes cada uno armaba
    // su copia del mismo curl y las credenciales, los tiempos o el "-k" podían
    // divergir entre los tres caminos. 15 s para conectar (VPN, túnel, arranque
    // perezoso del modelo) y el tope total que pida cada uso.
    // Devuelve { cmd, env, body }. El cuerpo NO viaja en el comando: quien llama
    // lo escribe en la entrada estándar del proceso y la cierra. Ver el porqué
    // entero en Payload.js — resumido: el argv es de lectura pública y además
    // tiene un tope de 128 kB por argumento, así que la conversación completa
    // ahí dentro era a la vez una fuga y un fallo.
    function chatCommand(req, maxTime) {
        return PL.transport(req, {
            url: endpoint,
            maxTime: maxTime,
            stream: !!req.stream,
            bearer: apiKey,
            extraHeader: provider.userUrl ? Settings.aiCustomHeader.trim() : "",
            title: Settings.aiProvider === "openrouter",
            netFlags: netArgs()
        })
    }
    function transportError(code) { return PL.transportError(code) }

    // La sonda del catálogo, con las MISMAS credenciales y por la misma jaula:
    // el botón "Probar" tiene que probar exactamente lo que va a viajar.
    function probeCommand() {
        return PL.probeTransport({
            url: modelsUrl,
            bearer: apiKey,
            extraHeader: provider.userUrl ? Settings.aiCustomHeader.trim() : "",
            title: Settings.aiProvider === "openrouter",
            netFlags: netArgs()
        })
    }

    // ── Política de aprobación ───────────────────────────────────────────────
    // UN control en vez de cuarenta: el usuario dice hasta dónde llega el agente
    // y ToolPolicy.js reparte según la clase de riesgo de cada herramienta.
    readonly property string approvalMode: TP.mode(Settings.aiApproval)

    function riskClass(name)        { return TP.riskClass(name) }
    // El nivel numérico (0 leer … 4 crítico): lo usan la auditoría y la UI.
    function riskLevel(name)        { return TP.riskLevel(name) }
    function neverAuto(name)        { return TP.neverAuto(name) }
    function canStandingAllow(name) { return TP.canStandingAllow(name) }
    function naturalPolicy(name)    { return TP.naturalPolicy(name, approvalMode) }
    function toolPolicy(name) {
        return TP.policy(name, approvalMode, Settings.aiToolPolicies)
    }
    // Cuántas excepciones hay puestas: el panel lo enseña para que un permiso
    // olvidado no viva escondido bajo un modo que dice otra cosa.
    readonly property int toolOverrides: TP.overrideCount(Settings.aiToolPolicies)
    function setToolPolicy(name, v) {
        Settings.aiToolPolicies = TP.withOverride(Settings.aiToolPolicies, name, v,
                                                  approvalMode)
    }
    function clearToolPolicies() { Settings.aiToolPolicies = ({}) }

    // ── Herramientas: catálogo y jaula ───────────────────────────────────────
    // Las que el modelo puede PROPONER en modo agente. Ejecutar, solo tras
    // aprobación expresa — salvo las de solo lectura si el usuario aflojó la
    // correa.
    readonly property var toolDefs: TD.core().concat(sysQueryDefs).concat(sysActionDefs)
     .concat(sshQueryDefs).concat(sshActionDefs).concat(TD.dev())

    // Las nuestras MÁS las de los servidores MCP, para la lista de permisos.
    // Van aparte de `toolDefs` a propósito: esa es la que arma la petición y no
    // debe cambiar. Pero la lista de permisos sí las necesita — sin ellas no
    // había ninguna forma de decirle al harness "de este servidor me fío",
    // y como una herramienta MCP tampoco puede auto-aprobarse por su nombre
    // (ver ToolPolicy), la única salida habría sido una tarjeta por llamada
    // para siempre. Un permiso que no se puede conceder no es una defensa: es
    // una molestia que acaba en modo automático para todo.
    readonly property var policyToolDefs:
        toolDefs.concat(mcpClient ? mcpClient.toolDefs : [])

    // Dos familias con reglas distintas. Las CONSULTAS no cambian nada del
    // sistema: cuentan como lectura para la auto-aprobación y también las hereda
    // el subagente, que así sabe diagnosticar solo. Las ACCIONES (parar
    // servicios, matar procesos) siempre nacen con tarjeta.
    readonly property var sysQueryDefs: TD.sysQuery()
    readonly property var sysActionDefs: TD.sysAction()
    // Herramientas de servidores remotos. Funcionan SOLO CON LO QUE DIGA EL
    // MENSAJE: 'host' admite un destino suelto ([usuario@]host[:puerto]) o el
    // nombre de uno guardado, y user/port/password de la llamada mandan sobre lo
    // guardado. Guardar servidores es comodidad, no requisito.
    readonly property var sshQueryDefs: TD.sshQuery()
    readonly property var sshActionDefs: TD.sshAction()

    // El vocabulario de SOLO LECTURA, en un solo sitio. Leer archivos, consultar
    // el sistema y consultar servidores remotos son las tres familias que no
    // cambian nada. Se juntan aquí para que exista UNA respuesta a "¿qué puede
    // hacer algo que no toca nada?", y de ella cuelgan tanto los esquemas que ve
    // un subagente como el constructor de comandos. Antes cada uno llevaba su
    // copia y ya habían divergido.
    readonly property var _roNames: ["read_file", "read_files", "list_dir",
                                     "grep_files", "glob_files", "fetch_url"]
    readonly property var readOnlyDefs:
        TD.core().filter(d => _roNames.indexOf(d["function"].name) !== -1)
          .concat(sysQueryDefs).concat(sshQueryDefs)
          // La búsqueda estructural tampoco cambia nada: el subagente y la
          // celda de Python la heredan igual que grep.
          .concat(TD.dev().filter(d => d["function"].name === "ast_search"))

    // Lo que necesitan los constructores de comando para trabajar sin saber nada
    // del shell: la carpeta personal y el estado de los servidores guardados.
    readonly property var toolCtx: ({
        home: Quickshell.env("HOME"),
        hosts: Settings.aiSshHosts,
        pass: keys.sshPass,
        haveSshpass: keys.haveSshpass
    })

    // ── La búsqueda web ──────────────────────────────────────────────────────
    // Todo lo que WebSearch.js necesita para decidir a quién preguntar. La
    // instancia del ARGUMENTO va aparte porque manda sobre el ajuste: si el
    // usuario nombra su SearXNG en el mensaje, se usa ese y punto.
    function searchCtx(instancia) {
        return ({ instancia: String(instancia || ""),
                  url: Settings.aiSearchUrl,
                  backend: Settings.aiSearchBackend,
                  key: keys.searchKey })
    }
    // La clave del buscador se expone para que el ejecutor pueda levantar su
    // pestillo de avería en cuanto cambie: si acabas de pegar la clave, lo justo
    // es volver a intentarlo sin cambiar de conversación.
    readonly property string searchKey: keys.searchKey

    // Cómo se llama la fuente preferida, y si esa acepta clave. Lo consultan los
    // ajustes: un campo de clave rotulado "Brave Search" cuando el elegido es
    // Mojeek no confunde un poco, confunde del todo.
    readonly property string searchBackendLabel: WS.labelOf(Settings.aiSearchBackend)
    readonly property bool searchTakesKey:
        ["brave", "tavily", "exa", "kagi"].indexOf(Settings.aiSearchBackend) !== -1

    // A cuántas voces se pregunta. Con la fusión por consenso, "configurado" ya
    // no es un sí o un no: siempre hay al menos DuckDuckGo, y cada fuente que
    // añadas mejora la ordenación (lo que coincide entre varias sube).
    readonly property var searchSources: {
        // Se nombran las dependencias para que la lista se recalcule sola.
        const _ = [Settings.aiSearchBackend, keys.searchKey]
        return WS.sources(({ url: Settings.aiSearchUrl !== "" ? Settings.aiSearchUrl
                                                              : searchLocal,
                             backend: Settings.aiSearchBackend,
                             key: keys.searchKey }),
                          TU.normalizeSearchBase)
    }

    // El SearXNG de esta máquina, si lo hay. "" = ninguno. Se comprueba al
    // arrancar y cada vez que alguien abre los ajustes de búsqueda: levantar uno
    // no debería obligar a reiniciar el shell para que se entere.
    property string searchLocal: ""
    function probeSearchLocal() {
        const p = WS.localProbe()
        localProbe.command = p.cmd
        localProbe.running = true
    }
    Process {
        id: localProbe
        running: true
        command: WS.localProbe().cmd
        stdout: StdioCollector { id: localProbeOut }
        onExited: ai.searchLocal = (localProbeOut.text || "").trim()
    }

    // El trato del texto que viene de fuera, en un solo sitio: lo usan el
    // ejecutor y también los subagentes, que leen la web igual que su jefe.
    function searchFailed(salida) { return WS.failed(salida) }
    function searchFailureText(salida) { return WS.failureText(salida) }
    function stripFetchMark(salida) {
        return String(salida).replace(LT.FETCH_KO, "").trim()
    }

    // El constructor correspondiente: prueba las tres familias en orden. Devuelve
    // {cmd,env} | {error} | null (null = no es de solo lectura).
    function readOnlyCommand(tool, args) {
        return LT.sysQuery(tool, args, toolCtx)
            || RT.query(tool, args, toolCtx)
            || LT.files(tool, args, toolCtx)
    }

    // ── La puerta de los subagentes ──────────────────────────────────────────
    // Lo que un subagente puede ANUNCIAR y lo que puede EJECUTAR salen de la
    // misma concesión y de la misma lista. Que sean dos funciones y no una es
    // solo porque una devuelve esquemas y la otra comandos: si divergieran,
    // existiría una herramienta ejecutable que nadie anunció, que es
    // exactamente el agujero que esto viene a cerrar.
    readonly property var _subExtraDefs:
        TD.core().filter(d => TP.SUB_ESCRITURA.indexOf(d["function"].name) !== -1
                              || d["function"].name === "web_search")
          // El lsp de lectura: un revisor que puede saltar a la definición y
          // listar las referencias revisa de otra manera.
          .concat(TD.dev().filter(d => d["function"].name === "lsp"))

    function subagentDefs(grant) {
        return readOnlyDefs.concat(_subExtraDefs)
                 .filter(d => TP.subagentAllows(d["function"].name, grant))
    }

    // {cmd,env} | {error} | null (null = fuera de sus permisos). Dos paredes
    // distintas: se lee dentro de la RAÍZ y se escribe dentro del TALLER, que
    // nunca es la carpeta viva del usuario.
    function subagentCommand(tool, args, grant, ws) {
        if (!TP.subagentAllows(tool, grant))
            return null
        if (TP.SUB_ESCRITURA.indexOf(tool) !== -1) {
            if (!ws || ws.writeRoot === "")
                return { error: "No tienes ningún taller donde escribir." }
            const wctx = Object.assign({}, toolCtx, { root: ws.writeRoot })
            const bak = ws.undoDir + "/" + Date.now() + ".bak"
            if (tool === "edit_patch")
                return LT.hashPatch(args, wctx, bak, ws.undoDir, iaDir)
            const p = LT.safePath(args.path, wctx.home, ws.writeRoot)
            if (p === "")
                return { error: "Solo puedes escribir dentro de tu taller ("
                              + ws.writeRoot + "). Usa rutas relativas." }
            return LT.writes(tool, p, args, bak, ws.undoDir)
        }
        // La búsqueda web no la construye ninguna de las tres familias, así que
        // hasta ahora un subagente con permiso de red la tenía ANUNCIADA y le
        // rebotaba con "fuera de tus permisos" al usarla: justo la herramienta
        // por la que se delega una investigación.
        if (tool === "web_search")
            return WS.command(args.query, searchCtx(args.instance),
                              TU.normalizeSearchBase, args)
        const rctx = Object.assign({}, toolCtx, { root: ws ? ws.root : "" })
        return LT.sysQuery(tool, args, rctx)
            || RT.query(tool, args, rctx)
            || LT.files(tool, args, rctx)
    }

    // La misma resolución de rutas, para quien no construye un comando (el lsp
    // pide la ruta ya absoluta).
    function workPath(p, root) {
        return LT.safePath(p, Quickshell.env("HOME"), root)
    }
    function lspRequest(args, cb) { lspMgr.request(args, cb) }

    // Expande ~ y comprueba que la ruta quede dentro de la carpeta personal.
    function _safePath(p) { return LT.safePath(p, Quickshell.env("HOME")) }

    function redactSecrets(text) { return TU.redactSecrets(text) }

    // Los nombres que el modelo puede usar de verdad, para recordárselos cuando
    // se inventa uno.
    function knownToolNames() {
        return toolDefs.map(d => d["function"].name)
                 .concat(mcpClient.toolDefs.map(d => d["function"].name))
    }

    // Llamadas escritas EN EL TEXTO (los modelos locales lo hacen a menudo). Los
    // nombres conocidos se pasan desde aquí: así TextUtils no depende del
    // harness.
    function extractTextToolCalls(raw) {
        return TU.extractTextToolCalls(raw, knownToolNames())
    }

    // ── Prompt de sistema y personas ─────────────────────────────────────────
    readonly property var personas: ({
        normal:   "",
        concise:  " Responde en el mínimo de palabras que resuelva la duda; sin preámbulos ni cierres.",
        teacher:  " Explica como un buen profesor: paso a paso, con un ejemplo corto cuando ayude.",
        reviewer: " Actúa como revisor de código: señala problemas concretos (correctitud, seguridad, rendimiento) antes que estilo, y propone el arreglo."
    })

    // Dos modos: charlar o actuar. NO hay un tercer modo "plan" — planificar no
    // es un ajuste que el usuario tenga que elegir de antemano, sino una decisión
    // del agente al leer el encargo: si la tarea lo merece, llama a propose_plan
    // y espera el visto bueno.
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
              + "comandos, leer/listar/escribir archivos, abrir URLs, analizar "
              + "servidores por SSH, consultar el sistema, guardar notas). Para "
              + "tareas de varios pasos, enuncia un plan breve (todo_write) y ve "
              + "avanzando. Cuando necesites INFORMACIÓN de varios sitios a la "
              + "vez (leer/listar/buscar/grep), pídelo TODO en el mismo turno "
              + "con varias llamadas en paralelo, en vez de una tras otra: es "
              + "más rápido. Las que cambian algo (escribir, ejecutar) las "
              + "aprueba el usuario. Los entregables (informes, scripts) "
              + "escríbelos como archivo con write_file."
              // El ruido de la web es el que más contexto quema: una página son
              // veinte mil caracteres que se reenvían en TODAS las rondas
              // siguientes, y de los que sirven dos frases. Investigar en un
              // subagente deja ese ruido en su contexto y devuelve la conclusión.
              + " INVESTIGAR EN LA WEB: para un dato suelto, web_search y listo. "
              + "Si hace falta abrir varias páginas o comparar fuentes, delega "
              + "en un subagente con role:'research' y capabilities:['net']: lo "
              + "que ensucia el contexto son las páginas, no las respuestas. Y "
              + "si la búsqueda te dice que no hay buscador configurado, eso no "
              + "se arregla reformulando: díselo al usuario y sigue."
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
        + memoryStore.memoryBlock
        + memoryStore.instinctBlock
        + skillStore.catalogBlock
        + skillStore.activeBlock

    // Lo último que preguntó el usuario: la consulta contra la que se mide la
    // relevancia de la memoria, los instintos, las habilidades y el recorte de
    // herramientas. Se actualiza al empujar su mensaje.
    property string lastUserText: ""

    // ── Las piezas ───────────────────────────────────────────────────────────
    KeyStore { id: keys }

    ConnectionProbe { id: probe; svc: ai }

    McpManager { id: mcpClient }

    HookRunner {
        id: hookRunner
        svc: ai
        onBlocked: (gate, reason) => tools.blockTool(gate, reason)
    }

    MemoryStore { id: memoryStore; svc: ai }

    SkillStore {
        id: skillStore
        svc: ai
        // El catálogo se reescaneó porque el modelo pidió una habilidad que aún
        // no estaba: ahora sí aparece, así que se reintenta su tarjeta.
        onRescanned: (pending, want) => {
            if (pending >= 0)
                tools.approveTool(pending)
            else if (want !== "")
                conv.pushInfo(I18n.tr("Skills reloaded."))
        }
    }

    ConversationStore {
        id: conv
        svc: ai
        // El harness está en pie y con su historial: momento de session_start
        // (montar algo, precalentar, avisar) y de recolocar la habilidad que el
        // hilo restaurado traía a cuento.
        onRestored: {
            ai._restoreLastUser()
            hookRunner.fire("session_start", "", {})
        }
    }

    // Las tres piezas de desarrollo (ideas de oh-my-pi): servidores de
    // lenguaje vivos, depurador DAP y el Python persistente con loopback.
    LspManager { id: lspMgr; svc: ai; backupDir: tools.undoDir }
    DebugSession { id: dbgSess; svc: ai }
    PersistentRepl { id: replKernel; svc: ai; lsp: lspMgr }
    JobRunner { id: jobRunner; svc: ai }
    AuditLog { id: auditLog; svc: ai }

    // El segundo par de ojos. Va DESPUÉS de la auditoría porque escribe en ella,
    // y antes del ejecutor porque este le pregunta.
    AgentSupervisor { id: supervisor; svc: ai; conv: conv; audit: auditLog }

    ToolRunner {
        id: tools
        svc: ai; conv: conv; skills: skillStore
        memory: memoryStore; mcp: mcpClient; hooks: hookRunner
        lsp: lspMgr; dbg: dbgSess; repl: replKernel; jobs: jobRunner
        audit: auditLog; sup: supervisor
    }

    ChatClient {
        id: chat
        svc: ai; conv: conv; tools: tools; skills: skillStore; mcp: mcpClient
        dbg: dbgSess
    }

    Compactor { id: comp; svc: ai; conv: conv; tools: tools }

    Attachments { id: att; svc: ai }

    // ── Superficie pública ───────────────────────────────────────────────────
    // El panel habla SOLO con AiService. Los alias cuestan cero (son la misma
    // propiedad, no una copia) y permiten mover una pieza de sitio sin tocar ni
    // una línea de la interfaz.
    property alias haveKeyring: keys.haveKeyring
    // Si el llavero falló al guardar, dónde ha quedado la clave. Vacío = todo
    // bien. Lo enseña Ajustes: prometer "se guarda en el llavero" cuando no ha
    // sido así es peor que no prometer nada.
    property alias keyringWarn: keys.keyringWarn
    property alias apiKey: keys.apiKey
    property alias sshPass: keys.sshPass
    function setKey(providerId, key) { keys.setKey(providerId, key) }
    function setSshPassword(name, pw) { keys.setSshPassword(name, pw) }

    property alias connState: probe.connState
    property alias connDetail: probe.connDetail
    property alias connMs: probe.connMs
    property alias connModels: probe.connModels
    function testConnection() { probe.test() }

    property alias mcpTools: mcpClient.tools
    property alias mcpStatus: mcpClient.status

    property alias memoryList: memoryStore.notes
    property alias instinctList: memoryStore.instincts
    function removeMemory(i) { memoryStore.removeNote(i) }
    function removeInstinct(i) { memoryStore.removeInstinct(i) }
    function addInstinct(text) { return memoryStore.addInstinct(text) }

    property alias skills: skillStore.skills
    property alias autoSkill: skillStore.autoSkill
    function skillEnabled(id) { return skillStore.enabled(id) }
    function setSkillEnabled(id, on) { skillStore.setEnabled(id, on) }
    function rescanSkills() { skillStore.rescan() }

    property alias messages: conv.messages
    property alias conversations: conv.conversations
    property alias currentId: conv.currentId
    property alias convTokens: conv.convTokens
    property alias convMs: conv.convMs
    property alias contextFill: conv.contextFill
    function pushInfo(text) { conv.pushInfo(text) }

    property alias toolRounds: tools.toolRounds
    property alias maxToolRounds: tools.maxToolRounds
    // Qué tarjeta se está ejecutando ahora mismo, y desde cuándo, para que la
    // interfaz pueda decirlo. Solo corre una a la vez, así que con el índice
    // basta.
    property alias toolRunningIndex: tools.runningIndex
    property alias toolRunningSince: tools.runningSince
    // ¿Se ha dado ya por perdido el buscador en esta sesión? Los ajustes lo
    // enseñan: es la diferencia entre "no encuentro nada" y "no puedo buscar".
    property alias searchBroken: tools.searchBroken
    function approveTool(i) { tools.approveTool(i) }
    // La aprobación con un clic del usuario: se distingue de la automática para
    // que el registro de auditoría diga quién dejó pasar cada cosa.
    function approveToolByUser(i) { tools.approveToolByUser(i) }
    // Puerta de registro para lo que se ejecuta SIN tarjeta (subagentes y la
    // celda de Python por el loopback).
    function auditRecord(o) { auditLog.record(o) }

    // ── El supervisor, para la interfaz ──────────────────────────────────────
    // El veredicto de una tarjeta ({veredicto, riesgo, irreversible, ajuste,
    // fallo}) o null si aún no hay. La tarjeta ya está en pantalla mientras el
    // guardián piensa, así que esto pasa de null a objeto y la banda aparece.
    function supervisorOf(i) { return tools.supVerdict[i] || null }
    readonly property int supervisorWatching: supervisor.reviewing
    readonly property string supervisorMode: supervisor.modo
    // La observación del consejero que viaja en la siguiente petición. Vive una
    // sola vuelta: es sobre el paso que se acaba de dar.
    property string advisorNote: ""
    function dangerOf(i) {
        const m = conv.messages.get(i)
        return m ? tools.dangerOf(m.toolName, m.toolArgs) : ""
    }
    function approveToolAlways(i) { tools.approveToolAlways(i) }
    function rejectTool(i) { tools.rejectTool(i) }
    function answerQuestion(i, a) { tools.answerQuestion(i, a) }
    function approvePlan(i) { tools.approvePlan(i) }
    function rejectPlan(i, f) { tools.rejectPlan(i, f) }
    function undoEdit(i) { tools.undoEdit(i) }
    function realPathFor(i) { return tools.realPathFor(i) }

    property alias busy: chat.busy
    property alias liveText: chat.liveText
    property alias liveThink: chat.liveThink
    function isTransient(msg) { return chat.transient(msg) }
    function start() { chat.start() }
    function stop() { chat.stop() }

    property alias compacting: comp.compacting
    function compact() { comp.compact("") }
    // Podar sin resumir: recorta los resultados de herramienta que ya no hacen
    // falta literalmente y deja el hilo intacto. No cuesta una llamada. A mano
    // va sin bridas; en automático manda la caché de prefijo.
    function prune() { return comp.prune(false) }
    // Sacudir: archiva a fichero los bloques enormes de los mensajes y deja la
    // ruta en su hueco. Tampoco cuesta una llamada, y se puede recuperar.
    function shake() { return comp.shake() }
    // Traspasar: documento de continuación y conversación nueva.
    function handoff() { return comp.handoff() }

    // EL CONTEXTO DESBORDÓ. El modelo dice que no cabe lo que le mandamos.
    // Hasta ahora eso era un error rojo y se acabó el turno; ahora se compacta
    // y se REINTENTA, que es lo que separa un harness que se salva solo de uno
    // que se rinde. Es viable porque el resumen ya no manda el historial entero
    // sino una transcripción acotada: cabe justo cuando el turno no cabía.
    function recoverOverflow() {
        if (comp.compacting)
            return false
        // Compactar reescribe el historial, y eso no se hace a espaldas de
        // quien pidió llevar el contexto a mano. Con "Auto" se rescata solo;
        // con "Manual" o "Avisar" se dice qué pasó y qué tecla lo arregla, que
        // ya es infinitamente mejor que un error del proveedor que el usuario
        // no puede interpretar.
        if (Settings.aiAutoCompact !== "auto") {
            conv.pushInfo(I18n.tr("Context overflowed: the turn did not go out. Run /compact (or /prune) and send it again."))
            return false
        }
        conv.pushInfo(I18n.tr("Context overflowed — compacting and retrying."))
        return comp.compact("overflow")
    }

    // A MITAD DE TURNO. Un bucle de veinte rondas de herramienta puede llenar la
    // ventana sin que el turno haya terminado, y hasta ahora la única
    // comprobación estaba al final: se desbordaba antes de llegar a ella. El
    // coordinador de herramientas llama aquí en su frontera segura —lote
    // resuelto, nada pendiente— justo antes de devolverle la palabra al modelo.
    function maybeCompactMidTurn() {
        if (Settings.aiAutoCompact !== "auto" || comp.compacting)
            return false
        if (contextFill <= 0.85)
            return false
        return comp.compact("midturn")
    }

    // Los trabajos en segundo plano: el panel enseña cuántos corren y puede
    // cortarlos (el freno de mano del usuario, sin pasar por el modelo).
    property alias jobs: jobRunner.jobs
    readonly property var runningJobs: jobRunner.running
    function stopJob(id) { jobRunner.ctl({ action: "kill", id: id }, () => {}) }

    property alias pendingAtts: att.pendingAtts
    function removeAttachment(i) { att.removeAt(i) }
    function attachClipboard() { att.attachClipboard() }
    function attachSelection() { att.attachSelection() }
    function attachScreenshot() { att.attachScreenshot() }

    // ── Estado del turno y de la interfaz ────────────────────────────────────
    // Borrador y cola viven aquí y no en el panel, porque el panel se destruye al
    // cerrar (PanelSlot) y una captura CIERRA el panel.
    property string draft: ""
    // Cola de envío: puedes seguir escribiendo mientras responde; lo tuyo sale en
    // cuanto termina (la cola de mensajes de Claude Code).
    property var sendQueue: []
    // El plan visible del turno (herramienta todo_write, el TodoWrite de Claude
    // Code): [{content, status}]. Es efímero por diseño — pertenece a la tarea en
    // curso, no al historial.
    property var todos: []
    // Las imágenes del turno EN CURSO. Los adjuntos de texto viajan DENTRO del
    // mensaje (y quedan en el historial); las imágenes solo acompañan a este
    // turno — reenviar pantallazos viejos en cada pregunta quemaría la cuota
    // gratuita a lo tonto.
    property var sendImages: []

    signal replied()
    // El panel escucha esto para poner el texto a editar en la entrada.
    signal editRequest(string text)

    // ── Los subagentes ───────────────────────────────────────────────────────
    // VARIOS a la vez (el fan-out en paralelo de oh-my-pi): el modelo puede
    // pedir tres investigaciones en una ronda y las tres corren juntas, cada una
    // resolviendo su propia tarjeta cuando termina. Un tope evita que una ronda
    // desbocada abra veinte modelos. El panel enseña cuántos hay y qué hacen.
    property var activeSubs: []
    readonly property int maxConcurrentSubs: 4
    // Compatibilidad con el panel y con quien mire "el subagente": el primero
    // que siga vivo, o null. Así la barra existente sigue funcionando y además
    // puede contar activeSubs.length.
    readonly property var activeSub: activeSubs.length > 0 ? activeSubs[0] : null
    readonly property Component _subComp: Component { SubAgent {} }

    // La concesión que TENDRÍA un subagente con estos argumentos. La consulta el
    // ejecutor antes de arrancarlo: si incluye escritura, la tarjeta se enseña
    // sí o sí, y dice exactamente qué se está concediendo.
    function subagentGrantFor(opts) {
        const role = TP.SUB_ROLES.indexOf(String(opts.role || "")) !== -1
                     ? String(opts.role) : "research"
        const pedido = Array.isArray(opts.capabilities) ? opts.capabilities : null
        return TP.subagentGrant(role, pedido, approvalMode, Settings.aiToolPolicies)
    }
    function grantCaps(grant) { return TP.grantCaps(grant) }

    // opts = { label, role, brief, output, output_schema, capabilities,
    //          max_rounds, budget_s }. Devuelve "" si arrancó, o el motivo por
    // el que no.
    function runSubagent(task, opts, onDone) {
        if (activeSubs.length >= maxConcurrentSubs)
            return "Ya hay " + activeSubs.length + " subagentes en marcha (el "
                 + "máximo). Espera a que alguno termine."
        const role = TP.SUB_ROLES.indexOf(String(opts.role || "")) !== -1
                     ? String(opts.role) : "research"
        // El tope por defecto depende del papel. Rastrear en internet se agota
        // pronto: lo que se va a encontrar aparece en las tres primeras rondas,
        // y a partir de ahí el modelo reformula la misma consulta cada vez con
        // más contexto encima. Revisar código o diagnosticar una avería sí
        // avanza ronda a ronda, y ahí ocho siguen teniendo sentido.
        const porDefecto = role === "research" ? 5 : 8
        const mr = Math.max(1, Math.min(12,
                                        parseInt(opts.max_rounds) || porDefecto))
        // El esquema puede llegar como objeto o como texto: un modelo local
        // manda cualquiera de los dos, y rechazar el encargo por eso sería
        // absurdo.
        let esquema = opts.output_schema
        if (typeof esquema === "string")
            esquema = TU.repairJson(esquema)
        const id = "a" + Date.now().toString(36) + "-"
                 + Math.floor(Math.random() * 1679616).toString(36)
        // La raíz que pide el jefe pasa por la MISMA comprobación que cualquier
        // ruta: una carpeta de trabajo inventada no puede sacar al subagente de
        // $HOME. Si no vale, se ignora y trabaja con el alcance de siempre.
        const raiz = String(opts.workspace || "").trim() !== ""
                   ? _safePath(opts.workspace) : ""
        const s = _subComp.createObject(ai, {
            agentId: id,
            task: task,
            workspace: raiz,
            label: String(opts.label || "").slice(0, 60) || I18n.tr("Research"),
            role: role,
            brief: String(opts.brief || "").slice(0, 4000),
            expectedOutput: String(opts.output || "").slice(0, 400),
            outputSchema: esquema || null,
            grant: subagentGrantFor(opts),
            maxRounds: mr,
            budgetMs: Math.max(30, Math.min(600,
                parseInt(opts.budget_s) || 180)) * 1000
        })
        ai.activeSubs = ai.activeSubs.concat([s])
        s.finished.connect((report) => {
            ai.activeSubs = ai.activeSubs.filter(x => x !== s)
            onDone(report)
            s.destroy()
        })
        s.start()
        return ""
    }
    // Soltar los subagentes vivos sin resolver sus tarjetas. Lo usa el vigilante
    // del ejecutor cuando da por colgada la tarjeta de un subagente: si no, el
    // trabajador seguiría gastando turnos del modelo redactando un informe que
    // ya no va a leer nadie.
    function dropSubagents() { _dropSub() }
    function _dropSub() {
        const subs = activeSubs
        activeSubs = []
        for (const s of subs) {
            s.cancelSilent()
            s.destroy()
        }
    }

    // ── Operaciones de conversación ──────────────────────────────────────────
    // Todo lo que pertenece al HILO y no al historial: permisos dados de palabra,
    // la habilidad que acota el vocabulario, el plan a la vista, las rutas ya
    // resueltas. Cambiar de conversación sin soltarlo dejaría que un "siempre"
    // concedido en una charla mandara en la siguiente.
    function _resetThread() {
        stop()
        _dropSub()
        comp.cancel()
        tools.resetThread()
        skillStore.resetThread()
        // La depuración y el estado del Python pertenecen al encargo: mueren
        // con el hilo. El pool de LSP no — es por proyecto y de solo lectura.
        dbgSess.resetThread()
        replKernel.resetThread()
        jobRunner.resetThread()
        supervisor.resetThread()
        advisorNote = ""
        todos = []
        comp.warned = false
    }

    // Al entrar en una conversación (cambiar, arrancar, estrenar), la consulta de
    // relevancia vuelve a ser SU último mensaje de usuario: el orden del catálogo,
    // la memoria y el recorte de herramientas hablan del tema de este hilo, no
    // del de la conversación anterior. Y la habilidad que ese mensaje cargaría se
    // recarga: retomar un hilo de SQL a medias debe retomarlo con las
    // instrucciones de SQL puestas.
    function _restoreLastUser() {
        lastUserText = conv.lastUserText()
        if (lastUserText !== "")
            skillStore.update(lastUserText)
    }

    function newConversation() {
        _resetThread()
        conv.snapshot()
        conv.messages.clear()
        conv.currentId = String(Date.now())
        _restoreLastUser()
        conv.saveNow()
    }

    // /limpiar (el /clear de Claude Code): pizarra en blanco DE VERDAD. Nueva
    // conversación archiva la actual y abre otra al lado; esto tira el hilo en
    // curso —no queda en el historial— y con él se van el borrador, los adjuntos
    // pendientes, la cola de envío y los contadores del turno. Lo que no toca es
    // la memoria persistente: esa el usuario la guardó a propósito.
    function clearConversation() {
        _resetThread()
        sendQueue = []
        att.pendingAtts = []
        draft = ""
        chat.retries = 0
        conv.conversations = conv.conversations.filter(x => x.id !== conv.currentId)
        conv.messages.clear()
        conv.currentId = String(Date.now())
        _restoreLastUser()
        conv.recountTotals()
        conv.saveNow()
    }

    function switchTo(id) {
        if (id === conv.currentId)
            return
        const c = conv.conversations.find(x => x.id === id)
        if (!c)
            return
        _resetThread()
        conv.snapshot()
        conv.currentId = id
        conv.messages.clear()
        for (let i = 0; i < c.entries.length; i++)
            conv.append(c.entries[i])
        _restoreLastUser()
        conv.saveNow()
    }

    function deleteConversation(id) {
        conv.conversations = conv.conversations.filter(x => x.id !== id)
        // Si era la que estabas leyendo, el hilo entero se va con ella: el plan y
        // los permisos de esa charla no deben sobrevivirla.
        if (id === conv.currentId) {
            _resetThread()
            conv.messages.clear()
            conv.currentId = String(Date.now())
            _restoreLastUser()
        }
        conv.saveNow()
    }

    // Borra un mensaje suelto. Las rutas resueltas se indexan por POSICIÓN, así
    // que cualquier borrado las desplaza: se olvidan y se vuelven a resolver.
    function removeAt(index) {
        if (index >= 0 && index < conv.messages.count) {
            conv.messages.remove(index)
            tools.forgetPaths()
            conv.save()
        }
    }

    // Editar: recupera el texto de ese mensaje de usuario, lo quita junto a todo
    // lo posterior (la respuesta que provocó ya no vale) y se lo da al panel para
    // reescribirlo.
    function beginEdit(index) {
        if (busy || index < 0 || index >= conv.messages.count)
            return
        const m = conv.messages.get(index)
        if (m.role !== "user")
            return
        const text = m.content
        while (conv.messages.count > index)
            conv.messages.remove(conv.messages.count - 1)
        tools.forgetPaths()
        conv.save()
        editRequest(text)
    }

    // ↑ en la entrada vacía: editar el último mensaje propio.
    function editLast() {
        for (let i = conv.messages.count - 1; i >= 0; i--)
            if (conv.messages.get(i).role === "user") {
                beginEdit(i)
                return
            }
    }

    // ── Envío ────────────────────────────────────────────────────────────────
    function dequeue() {
        if (busy || compacting || sendQueue.length === 0)
            return
        const q = sendQueue[0]
        sendQueue = sendQueue.slice(1)
        att.pendingAtts = q.atts
        send(q.text)
    }

    function send(text) {
        // Expansión de @rutas: se lee primero y se reentra por sendExpanded con
        // el texto ya completo, para no partir el flujo de envío en dos caminos.
        if (!busy && att.expand(text))
            return
        _send(text)
    }
    // La reentrada tras expandir. El texto SIGUE conteniendo las @, así que entra
    // por aquí y no por send(): si no, se expandirían eternamente.
    function sendExpanded(text) { _send(text) }

    function _send(text) {
        let t = String(text).trim()
        if (busy || compacting) {
            // Ocupado (o compactando) no es "no": el mensaje espera su turno.
            if (t !== "" || att.pendingAtts.length > 0) {
                sendQueue = sendQueue.concat([{ text: t, atts: att.pendingAtts }])
                att.pendingAtts = []
            }
            return
        }
        tools.toolRounds = 0
        // Encargo nuevo, correa nueva: que la tanda de descargas fallidas de la
        // pregunta anterior condicionara la siguiente sería castigar al usuario
        // por un error del modelo que ya quedó atrás.
        tools.fetchSecos = 0
        // Y buscador nuevo, por el mismo motivo: la avería de la pregunta
        // anterior pudo ser una cuarentena de quince minutos, no una falta de
        // configuración. Reintentar cuesta una décima de segundo.
        tools.searchBroken = false
        chat.retries = 0
        // Y turno nuevo, derecho nuevo a una recuperación por desbordamiento:
        // que el anterior no cupiera ni siquiera compactado no significa que
        // este tampoco vaya a caber.
        chat._desbordado = false
        // Turno nuevo: el supervisor recupera su presupuesto de frenazos y
        // olvida las opiniones del anterior, y la nota del consejero caduca —
        // pertenecía al encargo que acaba de terminar.
        supervisor.resetTurn()
        ai.advisorNote = ""
        // Un modelo de solo texto con una captura adjunta: se dice ANTES de
        // mandar nada, en vez de dejar que el servidor conteste un error que no
        // explica nada.
        if (!canSeeImages && (att.pendingAtts || []).some(a => a.kind !== "text"))
            conv.pushInfo(I18n.tr("%1 only reads text: the images will not travel.")
                              .arg(profileLabel !== "" ? profileLabel : model))
        if (urlMissing) {
            conv.push({ role: "error",
                        content: I18n.tr("No server URL for %1. Add it in the panel settings.")
                            .arg(provider.label) })
            return
        }
        if (keyMissing) {
            conv.push({ role: "error",
                        content: I18n.tr("Missing API key for %1. Set it in the panel settings.")
                            .arg(provider.label) })
            return
        }
        const atts = att.pendingAtts
        let note = []
        ai.sendImages = []
        for (let i = 0; i < atts.length; i++) {
            const a = atts[i]
            note.push(a.label)
            if (a.kind === "text")
                t += "\n\n--- " + a.label + " ---\n```\n" + a.data + "\n```"
            else
                ai.sendImages.push(a.data)
        }
        if (t === "" && ai.sendImages.length === 0)
            return
        att.pendingAtts = []
        conv.push({ role: "user", content: t, attachNote: note.join(" · ") })
        lastUserText = t
        skillStore.update(t)
        hookRunner.fire("user_prompt_submit", "", { QS_HOOK_PROMPT: t.slice(0, 4000) })
        chat.start()
    }

    function retry() {
        if (!busy && !compacting)
            chat.start()
    }

    // Descarta la última respuesta y pide otra al modelo ACTUAL — también sirve
    // para comparar proveedores sobre la misma pregunta.
    function regenerate() {
        if (busy || compacting || conv.messages.count === 0)
            return
        const last = conv.messages.get(conv.messages.count - 1)
        if (last.role !== "user")
            conv.messages.remove(conv.messages.count - 1)
        tools.forgetPaths()
        conv.save()
        chat.start()
    }

    onReplied: {
        // "stop": el turno acabó. Para avisos propios (sonido, luz, registro).
        if (!busy)
            hookRunner.fire("stop", "", { QS_HOOK_TOKENS: String(convTokens) })
        // PASADA DE PODA POR TURNO. Barata, determinista y con las bridas de la
        // caché puestas: solo toca lo que sale a cuenta tocar. Es lo que evita
        // llegar al umbral en primer lugar, y por eso va antes de mirarlo.
        if (!busy && !compacting)
            comp.prune(true)
        // Contexto casi lleno: según lo elegido, avisar o compactar solo.
        if (contextFill > 0.85 && !busy && !notConfigured) {
            // "auto" = la pidió el umbral, no el usuario: si podando ya cabe,
            // el archivero no llega a llamarse.
            if (Settings.aiAutoCompact === "auto")
                comp.compact("auto")
            else if (Settings.aiAutoCompact === "warn" && !comp.warned) {
                comp.warned = true
                conv.pushInfo(I18n.tr("Context almost full — /compact will summarize it."))
            }
        }
    }

    // ── Exportar (entregable) ────────────────────────────────────────────────
    // La conversación entera como Markdown en tu carpeta personal.
    function exportMarkdown() {
        if (conv.messages.count === 0)
            return
        let md = "# " + conv.title() + "\n"
        for (let i = 0; i < conv.messages.count; i++) {
            const m = conv.messages.get(i)
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
    readonly property Process _exportProc: Process {
        id: exportProc
        onExited: (code) => {
            conv.push({ role: "info", content: code === 0
                ? I18n.tr("Conversation exported to %1").arg(ai._exportPath)
                : I18n.tr("Export failed") })
        }
    }
}
