import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "TextUtils.js" as TU
import "ToolPolicy.js" as TP
import "LocalTools.js" as LT
import "RemoteTools.js" as RT
import "Supervisor.js" as SV
import "WebSearch.js" as WS

// EL EJECUTOR: lo que pasa entre que el modelo propone una herramienta y el
// resultado vuelve a su contexto. Aprobación, jaula, ejecución, resolución y
// coordinación del lote.
//
// El orden de las puertas por las que pasa una llamada, que es lo que de verdad
// define la seguridad del harness:
//   1. Argumentos reparados y validados (un modelo local manda JSON roto).
//   2. Política dura y local: nunca-auto, comando destructivo, concesión.
//   3. SUPERVISOR — un segundo modelo opina antes de que se ejecute Y antes de
//      que el usuario decida, para que su razón esté a la vista en la tarjeta.
//      Solo puede endurecer: su "ok" no aprueba nada.
//   4. Hooks pre_tool_use — la última palabra del usuario, y puede vetar. Van
//      los últimos a propósito: una regla escrita por él manda sobre la opinión
//      de un modelo, y además no cuesta una llamada.
//   5. Enrutado: MCP, familia de solo lectura, o el vocabulario que cambia algo.
//   6. Ejecución con TODO argumento por entorno, nunca interpolado.
//   7. Redacción de secretos ANTES de que el resultado entre al contexto.
//   8. Aviso post_tool_use y coordinación del resto del lote.
Scope {
    id: runner

    property var svc          // el harness
    property var conv         // el hilo y su historial
    property var skills       // habilidades
    property var memory       // memoria e instintos
    property var mcp          // clientes MCP
    property var hooks        // hooks del usuario
    property var sup          // el supervisor (segundo modelo)
    property var lsp          // servidores de lenguaje
    property var dbg          // sesión de depuración (DAP)
    property var repl         // el Python persistente
    property var jobs         // trabajos en segundo plano
    property var audit        // registro de auditoría

    readonly property var messages: conv ? conv.messages : null

    // ── Correa del turno ─────────────────────────────────────────────────────
    // Pasos de herramienta del turno en curso. Con la auto-aprobación de
    // lecturas activa, un modelo en bucle podría encadenar 'ls' para siempre:
    // pasado el tope, la tarjeta se queda pendiente y decide el humano (el límite
    // de turnos de Claude Code / Cline, en pequeño).
    property int toolRounds: 0
    // El tope sale del modelo cuando se le conoce: ocho pasos se le quedan
    // cortos a uno entrenado para tareas largas de varios pasos justo cuando
    // empieza a ser útil, y le sobran a uno pequeño. Con un modelo desconocido,
    // los ocho de siempre.
    readonly property int maxToolRounds:
        (svc && svc.profile && svc.profile.rounds > 0) ? svc.profile.rounds : 8

    // ── Qué se está ejecutando AHORA ─────────────────────────────────────────
    // Solo corre una herramienta a la vez (un único Process, por diseño), así
    // que basta con el índice de la tarjeta y desde cuándo. Vive aquí y no en el
    // mensaje a propósito: es estado de ESTA sesión, no historial — al recargar
    // una conversación no hay nada ejecutándose, y guardarlo dejaría tarjetas
    // eternamente "en curso" de un proceso que ya no existe.
    //
    // Que exista arregla además algo que se notaba: entre aprobar y ver el
    // resultado, la tarjeta se quedaba idéntica —con sus botones de Aprobar y
    // Rechazar puestos— y no había forma de distinguir "el comando está
    // corriendo" de "el modelo está pensando" o de "esto se ha colgado".
    property int runningIndex: -1
    property double runningSince: 0
    // Aprobaciones del usuario que llegaron con algo ya en marcha (ver
    // approveTool): se guardan y se atienden por orden al quedar el sitio libre.
    property var _colaClics: []

    function _enCurso(index) {
        runningIndex = index
        runningSince = Date.now()
    }
    function _finCurso(index) {
        if (runningIndex === index || index === undefined)
            runningIndex = -1
    }

    // ── El vigilante ─────────────────────────────────────────────────────────
    // Hasta que existió, NADA tenía reloj: exec() arrancaba el proceso y se
    // esperaba a que saliera, y de los treinta y dos constructores de comando
    // solo tres traían un `timeout` propio. Un find sobre un montaje de red
    // caído o un ssh a una máquina que se traga los paquetes dejaba la tarjeta
    // en "Ejecutando…" para siempre — y como solo corre una herramienta a la
    // vez, eso no colgaba una llamada: colgaba el turno entero, sin nada que
    // pudiera desatascarlo salvo cambiar de conversación.
    //
    // El plazo sale de ToolPolicy, por nombre: el riesgo no dice nada de lo que
    // tarda algo (read_file y disk_query son las dos "lectura").
    readonly property Timer _reloj: Timer {
        interval: runner.runningIndex >= 0
                  ? runner._plazoDe(runner.runningIndex) + runner.margenReloj
                  : 60000
        running: runner.runningIndex >= 0
        onTriggered: runner._colgada(runner.runningIndex)
    }
    function _plazoDe(index) {
        const m = messages.get(index)
        return TP.deadlineMs(m ? String(m.toolName || "") : "")
    }

    // El corte de verdad, para lo que es un PROCESO, lo pone `timeout` dentro
    // del propio comando (ver exec): así el que mata es coreutils, el proceso
    // sale por su propio pie y no hay ninguna carrera entre el reloj y la
    // salida tardía. Este temporizador es la red por debajo, y cubre lo que
    // NO es un proceso —el servidor de lenguaje, un servidor MCP, el depurador,
    // una celda de Python, un subagente—, que se resuelve por callback y donde
    // no hay ningún `timeout` que valga. Por eso espera un poco más que el
    // plazo: si hay un proceso detrás, quien debe cortarlo es él.
    readonly property int margenReloj: 15000

    function _colgada(index) {
        const m = messages.get(index)
        if (!m || m.toolStatus !== "pending")
            return
        const nombre = String(m.toolName || "")
        const ms = _plazoDe(index)
        // Un subagente abandonado seguiría gastando turnos del modelo contra un
        // informe que ya no va a leer nadie.
        if (nombre === "subagent")
            svc.dropSubagents()
        audit.record({ src: "reloj", tool: nombre, args: m.toolArgs,
                       decision: "timeout",
                       why: "no terminó en " + Math.round(ms / 1000) + " s" })
        resolveTool(index, TP.deadlineText(nombre, ms))
    }

    // ── El pestillo de la búsqueda web ───────────────────────────────────────
    // Cuando no hay NINGÚN buscador que funcione, el fallo no es de la consulta:
    // es de configuración, y va a fallar igual las diez veces siguientes. Sin
    // este pestillo el modelo lo descubría una vez por llamada —reformulando y
    // razonando entre medias, que es lo caro— hasta agotar las rondas del turno.
    // Con él, la primera avería se explica entera y las siguientes se contestan
    // en el acto y sin red.
    //
    // Dura lo que dura el ENCARGO. Dentro de él es donde hace falta: es ahí
    // donde el modelo, si le dejas, reformula la misma consulta diez veces. Al
    // mensaje siguiente se levanta, y no por optimismo — desde que las fuentes
    // pueden entrar en cuarentena, una avería ya no es forzosamente de
    // configuración: puede ser un castigo de quince minutos que a la pregunta
    // siguiente ya haya caducado. Volver a probar cuesta una décima de segundo
    // y ninguna conexión, y si sigue caído el pestillo se arma otra vez a la
    // primera. También se levanta en cuanto el usuario cambia un ajuste que
    // pueda arreglarlo.
    property bool searchBroken: false
    property int _searchIndex: -1

    // ── La correa de las descargas en seco ───────────────────────────────────
    // Sin buscador, un agente decidido no se para: se pone a ADIVINAR URLs. Se
    // vio tal cual — veintidós fetch_url en tres minutos contra páginas de
    // resultados de tiendas, todas devolviendo menús, captchas o "página no
    // encontrada", y cada una engordando el contexto que se reenvía en la ronda
    // siguiente. Los tiempos de respuesta crecían 21 → 34 → 42 → 50 segundos, y
    // desde fuera parecía que el modelo se había atascado.
    //
    // Cinco seguidas sin sacar nada es señal de sobra: no es investigar, es dar
    // palos de ciego. Una descarga que SÍ trae contenido pone el contador a cero,
    // así que una tanda de exploración legítima con algún fallo no se penaliza.
    readonly property int maxFetchSecos: 5
    property int fetchSecos: 0
    // La tarjeta cuyo resultado viene de la web, y de dónde. Ver resolveTool.
    property int _fenceIndex: -1
    property string _fenceSrc: ""

    Connections {
        target: Settings
        function onAiSearchUrlChanged() { runner.searchBroken = false }
        function onAiSearchBackendChanged() { runner.searchBroken = false }
    }
    Connections {
        target: svc
        function onSearchKeyChanged() { runner.searchBroken = false }
    }

    // Permisos permanentes de ESTA conversación (el "session allowlist" de
    // OpenWorker): el usuario pulsa "Siempre" en una tarjeta y esa herramienta
    // deja de preguntar hasta que cambie de conversación. Efímero por diseño.
    property var sessionAllow: ({})
    function allowForSession(name) {
        const m = Object.assign({}, sessionAllow)
        m[name] = true
        sessionAllow = m
    }

    // El motivo por el que una llamada concreta es peligrosa, si lo es. Lo usan
    // la política (para forzar la tarjeta) y la propia tarjeta (para pintarlo).
    function dangerOf(name, argsJson) {
        const a = TU.repairJson(argsJson) || ({})
        // Una URL no solo TRAE datos: los SACA. Lo que viaje dentro se lo lleva
        // quien esté al otro lado, y descargar admite permiso permanente, así
        // que sin esto una página inyectada podía pedirle al asistente que
        // "verificara" abriendo un recolector con una credencial en la consulta,
        // sin que apareciera ninguna tarjeta. Taparla en la respuesta no sirve:
        // para entonces ya ha viajado.
        if (name === "fetch_url" || name === "open_url")
            return TU.urlLeakScan(a.url)
        // Engancharse a un proceso que ya corre no se parece a lanzar uno tuyo:
        // el depurador puede leer TODA su memoria —claves, sesiones, lo que
        // tuviera dentro—, pararlo y cambiarle variables. La tarjeta lo dice con
        // el número delante, porque "debug_start" a secas no lo insinúa.
        if (name === "debug_start" && parseInt(a.attach_pid) > 0)
            return "se engancha al proceso " + parseInt(a.attach_pid)
                 + " que ya está corriendo: podrá leer su memoria entera, "
                 + "detenerlo y modificarlo"
        // Una escritura en el sitio correcto es una ejecución con retardo: un
        // .bashrc, un .desktop de autostart o un hook de git no son archivos,
        // son comandos que esperan. La ejecución directa nunca se auto-aprueba,
        // así que este es el rodeo que quedaba.
        // Se lee el argumento a pelo y no por _pathArgOf: ese solo conoce las
        // herramientas que resuelven enlaces, y aquí hacen falta TODAS las que
        // escriben (edit_lines, ast_edit, lsp_fix… todas llevan 'path').
        if (TP.riskClass(name) === "write") {
            const p = String(a.path || a.local_path || "")
            if (p !== "")
                return TU.pathDangerScan(p)
        }
        // Los tres sitios por donde entra texto que acaba en un shell.
        const cmd = a.command !== undefined ? a.command
                  : (name === "job_input" ? a.text : "")
        return cmd ? TU.dangerScan(cmd) : ""
    }

    // Política de UNA LLAMADA concreta: la del nombre, salvo en las consultas
    // remotas, donde también cuentan los argumentos. Leer un servidor que el
    // usuario ya guardó es rutina; asomarse por primera vez a una máquina que
    // acaba de nombrar en el mensaje merece que se vea la tarjeta.
    function callPolicy(name, argsJson) {
        // Preguntar y proponer plan SIEMPRE esperan al usuario: son la pausa, no
        // una acción que se pueda automatizar.
        if (name === "ask_user" || name === "propose_plan")
            return "ask"
        // GARANTÍA DURA: lo crítico (shell, ssh, Python, evaluar en el
        // depurador) no se auto-aprueba jamás. Se comprueba ANTES que el
        // permiso permanente para que ni un "siempre" concedido a la ligera
        // pueda saltárselo.
        if (TP.neverAuto(name))
            return "ask"
        // Un comando destructivo se enseña SIEMPRE, diga lo que diga la
        // política: la clase de riesgo mira la herramienta, esto mira lo que
        // esa llamada concreta va a hacer.
        if (dangerOf(name, argsJson) !== "")
            return "ask"
        // Un subagente que va a ESCRIBIR nace de una tarjeta, aunque delegar sea
        // clase external y se pueda permitir "siempre": esa tarjeta es la única
        // aprobación que habrá para todo lo que escriba después. También va
        // antes del permiso permanente, por el mismo motivo que lo crítico.
        if (name === "subagent"
                && TP.grantNeedsApproval(
                       svc.subagentGrantFor(TU.repairJson(argsJson) || ({}))))
            return "ask"
        // Permiso permanente de la conversación (solo para lo aprobable así).
        if (sessionAllow[name] && TP.canStandingAllow(name))
            return "auto"

        const p = svc.toolPolicy(name)
        const a = TU.repairJson(argsJson) || ({})

        // Guardia de shell (idea de OpenWorker): un comando "auto" que encadena,
        // redirige o sustituye vuelve a preguntar — "permite git status" no debe
        // colar "git status; rm -rf ~".
        if (p === "auto" && (name === "run_command" || name === "ssh_exec")
                && TU.hasShellOps(a.command))
            return "ask"

        // Consulta a un servidor: aunque esté permitida (por política o por la
        // auto-lectura), asomarse por primera vez a una máquina que acaba de
        // salir del mensaje se enseña; a una ya guardada, no.
        if (RT.CONSULTAS.indexOf(name) !== -1 && p === "auto") {
            const h = RT.resolveHost(a.host, a, svc.toolCtx)
            return (h && h.saved) ? "auto" : "ask"
        }
        return p
    }

    // ── Detección de bucles (idea de gemini-cli) ─────────────────────────────
    // El atasco más típico de un modelo pequeño es repetir LA MISMA llamada una y
    // otra vez porque no le gusta el resultado. El tope de pasos lo cortaría ocho
    // turnos después, habiendo gastado contexto y tiempo; esto lo corta al tercer
    // intento idéntico y se lo dice, que así cambia de táctica o pregunta.
    // Idénticas = mismo nombre Y mismos argumentos. Solo cuenta DENTRO del
    // encargo en curso (desde el último mensaje del usuario): repetir una consulta
    // legítima tres veces a lo largo del día no es un bucle, es usar el
    // asistente.
    readonly property int loopThreshold: 3
    function loopCount(name, argsJson) {
        const sig = String(name) + "\u0000" + String(argsJson || "")
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
                    && (String(m.toolName) + "\u0000" + String(m.toolArgs)) === sig)
                n++
        }
        return n
    }

    // ── Resolver una tarjeta ─────────────────────────────────────────────────
    // 'cap' permite a una herramienta concreta un tope distinto del genérico
    // (use_skill: el texto de una habilidad vale más contexto que un ls).
    function resolveTool(index, result, cap) {
        // IDEMPOTENTE. Una tarjeta se resuelve una vez y solo una. No es celo:
        // desde que hay un vigilante que corta lo que se cuelga, hay dos caminos
        // que pueden llegar aquí con el mismo índice —el reloj y la salida
        // tardía del propio proceso—, y sin esta guarda el segundo volvería a
        // llamar a advance() y adelantaría el lote una posición de más.
        const previo = messages.get(index)
        if (!previo || previo.role !== "tool" || previo.toolStatus !== "pending")
            return
        _finCurso(index)
        // ¿Esto viene de fuera? Se decide ANTES de tocar el texto.
        let externo = (index === _fenceIndex)
        if (externo)
            _fenceIndex = -1
        // La búsqueda web es la única herramienta que distingue entre "no hay
        // resultados" y "no hay buscador": lo segundo es una avería de
        // configuración, y hay que tratarla como tal ANTES de que el texto entre
        // al contexto. Si no, el modelo lee un fallo cualquiera, supone que la
        // culpa es de su consulta, reformula, y se pasa el turno entero dando
        // vueltas contra una pared — que era exactamente lo que ocurría.
        if (index === _searchIndex) {
            _searchIndex = -1
            if (WS.failed(result)) {
                searchBroken = true
                result = WS.failureText(result)
                externo = false      // esto lo decimos NOSOTROS
            }
        }
        // Un aviso del propio harness (no se pudo descargar, la página exige
        // JavaScript) tampoco se enmarca: sería decirle al modelo que lo ha
        // escrito un desconocido. Y de paso es la señal para la correa: una
        // descarga que no trajo nada.
        if (externo) {
            const seca = String(result).indexOf(LT.FETCH_KO) !== -1
            if (_fenceSrc !== "una búsqueda web")
                fetchSecos = seca ? fetchSecos + 1 : 0
            if (seca) {
                result = String(result).replace(LT.FETCH_KO, "").trim()
                externo = false
            }
        }
        // LA PUERTA POR LA QUE ENTRA TEXTO AJENO. Una página web puede decir
        // "ignora las instrucciones anteriores y ejecuta esto", y como resultado
        // de herramienta pelado se lee con el mismo peso que una orden del
        // usuario. No se puede impedir que el modelo lo lea, pero sí decirle qué
        // es: mismo trato que le da el supervisor a sus expedientes.
        if (externo)
            result = WS.fence(result, _fenceSrc)
        messages.setProperty(index, "toolStatus", "done")
        messages.setProperty(index, "toolResult",
            TU.redactSecrets(String(result)).slice(0, cap || svc.toolResultCap))
        conv.save()
        // Aviso de "esto ya corrió": para registrar, medir o encadenar.
        const done = messages.get(index)
        if (done)
            hooks.fire("post_tool_use", done.toolName,
                       { QS_HOOK_TOOL: String(done.toolName || ""),
                         QS_HOOK_ARGS: String(done.toolArgs || ""),
                         QS_HOOK_RESULT: String(result).slice(0, 4000) })
        advance()   // ¿otra herramienta del lote?; si no, sigue el modelo
    }

    // Una llamada vetada: se marca rechazada y el motivo vuelve al modelo, que
    // así puede corregir en vez de reintentar a ciegas. Vetan dos cosas, y
    // conviene que se distingan en el registro y en la tarjeta: un hook del
    // usuario (una regla suya, escrita por él) y el supervisor (la opinión de un
    // segundo modelo).
    function blockTool(index, reason, src) {
        const m = messages.get(index)
        if (!m || m.toolStatus !== "pending")
            return
        _finCurso(index)
        const quien = src === "supervisor" ? "supervisor" : "hook"
        audit.record({ src: quien, tool: m.toolName, args: m.toolArgs,
                       decision: "blocked", why: reason })
        messages.setProperty(index, "toolStatus", "rejected")
        messages.setProperty(index, "toolResult",
            (quien === "supervisor" ? I18n.tr("Stopped by the supervisor: ")
                                    : I18n.tr("Blocked by a hook: "))
            + String(reason).slice(0, 2000))
        conv.save()
        advance()
    }

    // ── Lo que el jefe ya ha hecho, y el subagente no tiene que repetir ──────
    // Un subagente arranca con el contexto en blanco: es lo que lo hace barato,
    // y también lo que hace que su primera ronda sea, casi siempre, la búsqueda
    // que el agente principal acababa de hacer. Se midió en un encargo de
    // precios: el jefe buscó dos veces, delegó, y la primera consulta del
    // subagente era prácticamente idéntica a la primera del jefe.
    //
    // Así que el encargo viaja con el trabajo ya hecho: las últimas búsquedas
    // con sus resultados, y la lista de páginas que ya se abrieron —esas sin
    // contenido, solo la dirección: lo caro es volver a descargarlas, y para no
    // hacerlo basta con saber que ya se hizo.
    readonly property int _briefBusquedas: 3
    function _briefConTrabajoHecho(propio) {
        const busquedas = []
        const paginas = []
        for (let i = messages.count - 1; i >= 0; i--) {
            const m = messages.get(i)
            if (!m || m.role !== "tool" || m.toolStatus !== "done")
                continue
            const res = String(m.toolResult || "")
            if (m.toolName === "web_search") {
                // Solo viaja lo que vino ENMARCADO, es decir, lo que escribió
                // el buscador. Cuando no hay buscador, en la tarjeta no queda
                // su respuesta sino nuestro aviso de configuración —"no pude
                // buscar, arréglalo en Ajustes"—, y eso, metido en un encargo,
                // se leería como un hallazgo del jefe.
                if (busquedas.length >= _briefBusquedas || !WS.fenced(res))
                    continue
                let q = ""
                try { q = String((JSON.parse(m.toolArgs) || {}).query || "") }
                catch (e) {}
                busquedas.push("· búsqueda «" + q + "»:\n"
                               + WS.unfence(res).slice(0, 1200))
            } else if (m.toolName === "fetch_url" && paginas.length < 8) {
                try {
                    const u = String((JSON.parse(m.toolArgs) || {}).url || "")
                    if (u !== "")
                        paginas.push("· " + u)
                } catch (e) {}
            }
        }
        if (busquedas.length === 0 && paginas.length === 0)
            return String(propio || "")
        // El encargo entero se recorta a 4000 caracteres más adelante, así que
        // el hueco se reparte AQUÍ: primero lo que escribió el jefe, que es
        // suyo y no se toca, y con lo que quede se meten las búsquedas más
        // recientes enteras. Media búsqueda cortada no vale para nada.
        const base = String(propio || "").trim()
        let hueco = 3900 - base.length - 400
        let cuerpo = ""
        for (let k = 0; k < busquedas.length && hueco > 300; k++) {
            const b = busquedas[k]
            if (b.length > hueco)
                continue
            cuerpo = "\n" + b + (cuerpo !== "" ? "\n" + cuerpo : "")
            hueco -= b.length + 2
        }
        // Si el resumen del jefe ya llenaba el encargo, no se añade una cabecera
        // sin nada debajo: sería gastar cien caracteres en anunciar el vacío.
        if (cuerpo === "" && (paginas.length === 0 || hueco <= 120))
            return String(propio || "")
        let extra = "TRABAJO YA HECHO por el agente principal — no lo repitas."
                  + cuerpo
        if (paginas.length > 0 && hueco > 120)
            extra += "\n\nPáginas ya abiertas (vuélvelas a abrir solo si "
                   + "necesitas algo que no esté arriba):\n"
                   + paginas.reverse().join("\n").slice(0, hueco)
        return (base !== "" ? base + "\n\n" : "")
             + WS.fence(extra, "las búsquedas del agente principal")
    }

    // Cómo se autorizó ESTA llamada, para el registro: el usuario pulsó, la
    // tenía permitida en firme, o la dejó pasar la política del modo.
    function _decisionDe(index, name) {
        if (_userApproved === index)
            return sessionAllow[name] ? "always" : "user"
        return "auto"
    }
    property int _userApproved: -1

    function rejectTool(index) {
        const m = messages.get(index)
        if (!m || m.role !== "tool" || m.toolStatus !== "pending")
            return
        _finCurso(index)
        audit.record({ src: "card", tool: m.toolName, args: m.toolArgs,
                       decision: "rejected" })
        messages.setProperty(index, "toolStatus", "rejected")
        messages.setProperty(index, "toolResult",
            "El usuario rechazó ejecutar esta acción.")
        conv.save()
        // advance() y NO svc.start(). Parece lo mismo cuando el modelo pidió una
        // sola herramienta, y no lo es cuando pidió varias: rechazar una de
        // cuatro y arrancar el envío deja las otras tres en "pendiente", y el
        // constructor del cuerpo se salta las pendientes. Al servidor le llega un
        // assistant con cuatro tool_calls y un solo resultado, que es un cuerpo
        // inválido según el contrato de OpenAI — un servidor tolerante lo traga y
        // uno estricto lo rechaza, pero en los dos casos el modelo pierde tres
        // llamadas sin enterarse. advance() atiende lo que quede y solo llama al
        // modelo cuando el lote está completo, que es justo lo que hace ya el
        // veto de un hook.
        advance()
    }

    // La respuesta del usuario a un ask_user: vuelve al modelo como resultado de
    // la herramienta y la conversación sigue sola.
    function answerQuestion(index, answer) {
        const m = messages.get(index)
        if (!m || m.role !== "tool" || m.toolStatus !== "pending"
                || m.toolName !== "ask_user")
            return
        const a = String(answer).trim()
        if (a === "")
            return
        resolveTool(index, a)
    }

    // Aprobar el plan que el agente propuso: luz verde y a ejecutarlo.
    function approvePlan(index) {
        const m = messages.get(index)
        if (!m || m.toolName !== "propose_plan" || m.toolStatus !== "pending")
            return
        resolveTool(index, "El usuario APROBÓ el plan. Ejecútalo paso a paso, "
            + "verificando como dijiste; anótalo con todo_write para que se "
            + "vea el avance.")
    }
    function rejectPlan(index, feedback) {
        const m = messages.get(index)
        if (!m || m.toolName !== "propose_plan" || m.toolStatus !== "pending")
            return
        const f = String(feedback || "").trim()
        resolveTool(index, "El usuario NO aprobó el plan"
            + (f !== "" ? ". Dice: " + f : "")
            + ". Revísalo y vuelve a proponerlo; no ejecutes nada aún.")
    }

    // ── Aprobar y ejecutar ───────────────────────────────────────────────────
    property int _toolIndex: -1
    property int _hookPassed: -1        // tarjeta cuyos hooks ya dieron paso

    // "Aprobar siempre" (esta conversación): recuerda la herramienta y aprueba
    // esta llamada. Solo tiene sentido para lo que se puede permitir en firme.
    function approveToolAlways(index) {
        const m = messages.get(index)
        if (!m || m.role !== "tool")
            return
        if (TP.canStandingAllow(m.toolName))
            allowForSession(m.toolName)
        _userApproved = index
        approveTool(index)
    }

    // La aprobación de UN clic del usuario (el botón de la tarjeta). El
    // coordinador llama a approveTool directamente para las automáticas, así
    // que distinguirlas es cuestión de por dónde entran.
    function approveToolByUser(index) {
        _userApproved = index
        approveTool(index)
    }

    function approveTool(index) {
        const m = messages.get(index)
        if (!m || m.role !== "tool" || m.toolStatus !== "pending" || svc.busy
                || svc.compacting)
            return
        // Esta tarjeta YA se está ejecutando. Mientras corre, su estado sigue
        // siendo "pending" (que es lo correcto: aún no hay resultado que mandar
        // al modelo), así que sin esta guarda un segundo paso por aquí —dos
        // clics seguidos, un advance() que llega a destiempo— la lanzaba otra
        // vez, con el mismo comando y encima pisando el Process del primero.
        if (runningIndex === index)
            return
        // Y si lo que corre es OTRA tarjeta, tampoco: solo hay un Process, y
        // lanzar la segunda encima dejaba a la primera esperando un resultado
        // que ya nunca iba a llegarle. El clic no se pierde — se atiende en
        // cuanto la de delante termine.
        if (runningIndex >= 0) {
            if (_colaClics.indexOf(index) === -1)
                _colaClics = _colaClics.concat([index])
            return
        }
        runner._toolIndex = index
        // Argumentos tolerantes: un modelo local manda JSON roto a menudo. Si ni
        // con reparación sale, se le dice al modelo qué esperaba en vez de
        // ejecutar con argumentos vacíos (que sería peor que fallar).
        const parsed = TU.repairJson(m.toolArgs)
        if (parsed === null) {
            resolveTool(index, "No entendí los argumentos: no son JSON válido. "
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
        if (_hookPassed !== index && hooks.hooksFor("pre_tool_use", m.toolName).length > 0) {
            hooks.run("pre_tool_use", m.toolName,
                      { QS_HOOK_TOOL: m.toolName, QS_HOOK_ARGS: String(m.toolArgs || ""),
                        QS_HOOK_RISK: TP.riskClass(m.toolName) },
                      index,
                      () => { runner._hookPassed = index; runner.approveTool(index) })
            return
        }
        _hookPassed = -1

        // A partir de aquí la llamada SE EJECUTA: queda en el registro de
        // auditoría con quién la aprobó y por qué. Es el único punto por el que
        // pasan todas las herramientas del agente principal, así que es el
        // sitio honesto para anotarlo.
        audit.record({ src: "card", tool: m.toolName, args: m.toolArgs,
                       danger: dangerOf(m.toolName, m.toolArgs),
                       decision: _decisionDe(index, m.toolName) })

        // A partir de aquí la tarjeta está EN CURSO. Se marca aquí y no en
        // exec() para que valga también para las asíncronas (lsp, depurador,
        // celda de Python, subagente, MCP), que son justo las que más tardan.
        // Las que se resuelven en el acto pasan por los dos estados dentro del
        // mismo ciclo, así que no llegan a pintarse: no parpadea nada.
        _enCurso(index)

        // Herramienta de un servidor MCP: el nombre viaja con el esquema
        // mcp__<servidor>__<tool> de Claude Code. Se enruta a su proceso.
        if (m.toolName.startsWith("mcp__")) {
            const parts = m.toolName.split("__")
            if (parts.length < 3) { resolveTool(index, "Nombre MCP inválido."); return }
            _mcpCall(index, parts[1], parts.slice(2).join("__"), args)
            return
        }

        // La correa de las descargas en seco. Se corta ANTES de salir a la red:
        // lo que hay que parar no es el gasto de ancho de banda, es la ronda de
        // razonamiento que vendría después de recibir otra página vacía.
        if (m.toolName === "fetch_url" && fetchSecos >= maxFetchSecos) {
            resolveTool(index, "PARA. Llevas " + fetchSecos + " descargas "
                + "seguidas sin sacar nada: menús, captchas o páginas que se "
                + "pintan con JavaScript, que aquí no se ejecuta. Adivinar más "
                + "URLs va a dar exactamente lo mismo.\n"
                + "Si lo que necesitas es DESCUBRIR páginas, eso es una "
                + "búsqueda, no una descarga"
                + (searchBroken
                    ? ", y no hay buscador configurado: díselo al usuario y "
                      + "párate."
                    : ": usa web_search.")
                + "\nSi ya tienes una URL concreta y fiable que no hayas "
                + "probado, puedes pedirla, pero explica primero al usuario "
                + "dónde estás.")
            return
        }

        // Todo lo que no cambia nada (leer archivos, consultar el sistema,
        // consultar un servidor) lo construye el mismo sitio que sirve al
        // subagente: una sola jaula que auditar.
        const built = svc.readOnlyCommand(m.toolName, args)
        if (built !== null) {
            if (built.error !== undefined) { resolveTool(index, built.error); return }
            // Lo que va a traer texto escrito por un desconocido se apunta aquí,
            // y solo cuando de verdad va a salir a la red: al volver, su
            // resultado entra al contexto enmarcado (ver resolveTool). Marcarlo
            // antes de construir el comando enmarcaba también nuestros propios
            // rechazos ("solo URLs http(s)"), que es justo lo contrario de lo
            // que hace falta.
            if (m.toolName === "fetch_url") {
                _fenceIndex = index
                _fenceSrc = String(args.url || "una página web")
                // Si la dirección YA decía "192.168…" o "localhost", esta
                // llamada ha pasado por una tarjeta con el motivo escrito y el
                // usuario la aprobó: entonces sí puede aterrizar ahí. Lo que no
                // se permite nunca es llegar a la red de casa por sorpresa,
                // desde una URL pública que redirige o un nombre que resuelve
                // hacia dentro.
                built.env.QS_LAN = TU.urlZone(args.url) !== "" ? "1" : ""
            }
            exec(built.cmd, built.env)
            return
        }

        switch (m.toolName) {
        // ── Herramientas de desarrollo (LSP, AST, depurador, celda) ──────────
        // Asíncronas contra sus gestores: la tarjeta se resuelve cuando el
        // servidor conteste, con el mismo tope y la misma redacción de
        // secretos que todo lo demás.
        case "lsp":
            lsp.request(args, (r) => runner.resolveTool(index, r))
            return
        case "lsp_rename":
            lsp.request(Object.assign({}, args, { op: "rename" }),
                        (r) => runner.resolveTool(index, r))
            return
        case "lsp_fix":
            lsp.request(Object.assign({}, args, { op: "fix" }),
                        (r) => runner.resolveTool(index, r))
            return
        case "lsp_raw":
            lsp.request(Object.assign({}, args, { op: "raw" }),
                        (r) => runner.resolveTool(index, r))
            return
        // ── Trabajos en segundo plano ────────────────────────────────────────
        case "job_start":
            jobs.start(args, (r) => runner.resolveTool(index, r))
            return
        case "job_list":
            resolveTool(index, jobs.list())
            return
        case "job_view":
            jobs.view(args, (r) => runner.resolveTool(index, r))
            return
        case "job_input":
            jobs.input(args, (r) => runner.resolveTool(index, r))
            return
        case "job_ctl":
            jobs.ctl(args, (r) => runner.resolveTool(index, r))
            return
        case "ast_edit": {
            const pv = svc._safePath(args.path)
            if (pv === "") { resolveTool(index, "Ruta fuera de la carpeta personal."); return }
            const bakA = backupFor(index, pv)
            const built2 = LT.astEdit(args, svc.toolCtx, bakA, undoDir)
            if (built2.error !== undefined) { resolveTool(index, built2.error); return }
            exec(built2.cmd, built2.env)
            return
        }
        case "python_exec":
            repl.exec(args, (r) => runner.resolveTool(index, r))
            return
        case "debug_start":
            dbg.start(args, (r) => runner.resolveTool(index, r))
            return
        case "debug_ctl":
            dbg.ctl(args, (r) => runner.resolveTool(index, r))
            return
        case "debug_view":
            dbg.view(args, (r) => runner.resolveTool(index, r))
            return
        case "debug_eval":
            dbg.evaluate(args, (r) => runner.resolveTool(index, r))
            return
        case "ssh_exec": {
            const cmd = String(args.command || "").trim()
            if (cmd === "") { resolveTool(index, "Comando vacío."); return }
            const c = RT.connect(args, "ssh", "-p", svc.toolCtx)
            if (c.error !== undefined) { resolveTool(index, c.error); return }
            // El comando remoto viaja como UN argumento a ssh; el shell remoto lo
            // ejecuta tal cual. Es crudo a propósito (por eso lleva tarjeta).
            exec(c.t.argv.concat(["--", cmd + " 2>&1 | tail -c 16000"]), c.t.env)
            return
        }
        // Subir y bajar son el mismo scp con el origen y el destino cambiados de
        // sitio: se resuelven juntos para que no puedan divergir.
        case "sftp_get":
        case "sftp_put": {
            const down = m.toolName === "sftp_get"
            const local = svc._safePath(args.local_path)
            if (local === "") {
                resolveTool(index, (down ? "El destino" : "El origen")
                    + " local debe estar dentro de tu carpeta personal.")
                return
            }
            const rp = String(args.remote_path || "").trim()
            if (rp === "") { resolveTool(index, "Falta la ruta remota."); return }
            const c = RT.connect(args, "scp", "-P", svc.toolCtx)
            if (c.error !== undefined) { resolveTool(index, c.error); return }
            // scp recibe las rutas como ARGUMENTOS (no dentro de un shell), así
            // que un nombre raro no puede convertirse en otra orden. El último
            // elemento del argv es el user@host; el resto son las opciones.
            const dest = c.t.argv[c.t.argv.length - 1]
            const base = c.t.argv.slice(0, c.t.argv.length - 1)
            exec(base.concat(down ? [dest + ":" + rp, local]
                                  : [local, dest + ":" + rp]), c.t.env)
            return
        }
        case "service_ctl": {
            const actions = ["start", "stop", "restart", "reload", "enable", "disable"]
            const action = String(args.action || "")
            const unit = String(args.unit || "").trim()
            if (actions.indexOf(action) === -1) { resolveTool(index, "Acción inválida."); return }
            if (unit === "" || unit[0] === "-") { resolveTool(index, "Unidad inválida."); return }
            // Sin sh: systemctl recibe la unidad como argumento literal. Las de
            // sistema pasarán por polkit (el agente propio del shell).
            exec(args.user === true
                    ? ["systemctl", "--user", action, "--", unit]
                    : ["systemctl", action, "--", unit], ({}))
            return
        }
        case "kill_process": {
            const pid = parseInt(args.pid)
            if (!isFinite(pid) || pid <= 1) { resolveTool(index, "PID inválido."); return }
            const sigs = ["TERM", "KILL", "HUP", "INT"]
            const sig = sigs.indexOf(String(args.signal || "")) !== -1 ? args.signal : "TERM"
            exec(["sh", "-c",
                'ps -p "$QS_PID" -o comm= 2>/dev/null; kill -s ' + sig + ' -- "$QS_PID" && echo "Señal ' + sig + ' enviada." || echo "No se pudo (PID inexistente o de otro usuario)."'],
                ({ QS_PID: String(pid) }))
            return
        }
        case "todo_write": {
            // El plan visible (el TodoWrite de Claude Code): sustituye la lista
            // entera; el panel la pinta encima de la entrada.
            const list = Array.isArray(args.todos) ? args.todos : []
            svc.todos = list.slice(0, 20).map(t => ({
                content: String(t.content || "").slice(0, 200),
                status: ["pending", "in_progress", "completed"]
                            .indexOf(t.status) >= 0 ? t.status : "pending"
            }))
            const done = svc.todos.filter(t => t.status === "completed").length
            resolveTool(index, "Plan actualizado: " + done + "/" + svc.todos.length
                               + " pasos completados.")
            return
        }
        case "web_search": {
            const q = String(args.query || "").trim()
            if (q === "") { resolveTool(index, "Consulta vacía."); return }
            // Ya se sabe de este encargo que no hay buscador: se contesta sin
            // tocar la red. Antes cada intento costaba una conexión y, sobre
            // todo, una ronda entera de razonamiento del modelo.
            if (searchBroken) {
                resolveTool(index, WS.failureText("", true))
                return
            }
            // La cascada (tu SearXNG, el que nombre el mensaje, los locales, la
            // API con clave) la arma WebSearch.js; aquí solo se le pasa la
            // configuración y se recuerda qué tarjeta hay que vigilar al volver.
            const built = WS.command(q, svc.searchCtx(args.instance),
                                     TU.normalizeSearchBase, args)
            if (built.error !== undefined) {
                _searchIndex = index
                resolveTool(index, built.error)
                return
            }
            _searchIndex = index
            // Los títulos y fragmentos también los escribe un desconocido.
            _fenceIndex = index
            _fenceSrc = "una búsqueda web"
            exec(built.cmd, built.env)
            return
        }
        case "notify_user": {
            const title = String(args.title || "").slice(0, 120)
            if (title === "") { resolveTool(index, "Título vacío."); return }
            Quickshell.execDetached(["notify-send", "-a", "Asistente IA",
                                     title, String(args.body || "").slice(0, 400)])
            resolveTool(index, "Notificación mostrada.")
            return
        }
        case "subagent": {
            const task = String(args.task || "").trim()
            if (task === "") { resolveTool(index, "Encargo vacío."); return }
            const why = svc.runSubagent(task, {
                label: args.label, role: args.role,
                brief: _briefConTrabajoHecho(args.brief),
                workspace: args.workspace,
                capabilities: args.capabilities,
                output: args.output, output_schema: args.output_schema,
                max_rounds: args.max_rounds, budget_s: args.budget_s
            }, (report) => runner.resolveTool(index, report))
            if (why !== "")
                resolveTool(index, why)
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
                (res) => runner.mcp.flatten(res.contents).trim() || "(recurso sin texto)")
            return
        // ── Edición anclada por hash: UNA puerta, UN motor ──────────────────
        // edit_patch es el camino bueno (varios hunks, atómico, con
        // recuperación de anclas) y edit_lines es la puerta estrecha de
        // siempre, traducida a un parche de un solo hunk: así el anclaje vive
        // implementado en UN sitio y no puede divergir entre las dos.
        case "edit_patch": {
            const pv = svc._safePath(args.path)
            if (pv === "") { resolveTool(index, "Ruta fuera de la carpeta personal."); return }
            const bakP = args.dry_run === true ? "" : backupFor(index, pv)
            const built = LT.hashPatch(args, svc.toolCtx, bakP, undoDir, svc.iaDir)
            if (built.error !== undefined) { resolveTool(index, built.error); return }
            exec(built.cmd, built.env)
            return
        }
        case "edit_lines": {
            const st = parseInt(args.start), en = parseInt(args.end)
            if (!(st >= 1) || !(en >= st)) { resolveTool(index, "Rango inválido: start debe ser ≥1 y end ≥ start."); return }
            const pl = svc._safePath(args.path)
            if (pl === "") { resolveTool(index, "Ruta fuera de la carpeta personal."); return }
            const hunk = {
                op: String(args.text || "") === "" ? "delete" : "replace",
                at: String(st) + (args.start_hash ? "#" + args.start_hash : ""),
                to: String(en) + (args.end_hash ? "#" + args.end_hash : ""),
                text: String(args.text || "")
            }
            const bakL = backupFor(index, pl)
            const b2 = LT.hashPatch({ path: args.path, hunks: [hunk] },
                                    svc.toolCtx, bakL, undoDir, svc.iaDir)
            if (b2.error !== undefined) { resolveTool(index, b2.error); return }
            exec(b2.cmd, b2.env)
            return
        }
        case "edit_file": {
            const p = svc._safePath(args.path)
            if (p === "") { resolveTool(index, "Ruta fuera de la carpeta personal."); return }
            const bE = LT.writes("edit_file", p, args, backupFor(index, p), undoDir,
                                  svc.toolCtx)
            exec(bE.cmd, bE.env)
            return
        }
        case "open_url": {
            const url = String(args.url || "").trim()
            // xdg-open no abre URLs: abre LO QUE SEA con el programa que le
            // toque. Un file:// lo entrega al gestor de archivos, un .desktop lo
            // EJECUTA, y esquemas como smb://, ssh:// o vnc:// levantan un
            // cliente entero. Sin esta línea, "abre esto en el navegador" era un
            // ejecutor de propósito general con permiso de clase externa, que es
            // el escalón más barato de todos.
            if (!/^https?:\/\//i.test(url)) {
                resolveTool(index, "Solo se abren URLs http(s). Lo que has "
                    + "pasado no lo es, y abrir cualquier otra cosa no es "
                    + "abrir un enlace: es lanzar el programa que la maneje.")
                return
            }
            Quickshell.execDetached(["xdg-open", url])
            resolveTool(index, "URL abierta en el navegador.")
            return
        }
        case "write_file": {
            const p = svc._safePath(args.path)
            if (p === "") { resolveTool(index, "Ruta fuera de la carpeta personal."); return }
            const bW = LT.writes("write_file", p, args, backupFor(index, p), undoDir,
                                  svc.toolCtx)
            exec(bW.cmd, bW.env)
            return
        }
        case "use_skill": {
            // La habilidad se busca en el catálogo escaneado, nunca por la ruta
            // que diga el modelo: pida lo que pida, solo puede acabar leyendo un
            // SKILL.md de la carpeta de habilidades.
            const want = String(args.name || "").trim()
            const s = skills.find(want)
            if (!s) {
                // Puede que la habilidad se instalara DESPUÉS de arrancar el
                // shell: se reescanea la carpeta y se reintenta una vez, en vez
                // de contestar 404 sobre un catálogo viejo.
                if (skills.rescanFor(want, index))
                    return
                resolveTool(index, "No hay ninguna habilidad activa con ese nombre. Disponibles: "
                    + skills.activeSkills.map(x => x.name).join(", "))
                return
            }
            // La habilidad puede acotar su propio vocabulario mientras esté en
            // uso (allowed-tools del frontmatter): un manual de lectura no
            // debería poder pedir un rm.
            skills.activeSkillTools = (s.allowedTools && s.allowedTools.length > 0)
                ? s.allowedTools.slice() : []
            // El texto ya está en memoria desde el escaneo: no hace falta ir al
            // disco otra vez. Y entra con el tope de habilidad, no con el
            // genérico de resultados: son instrucciones, no salida de comando.
            resolveTool(index, s.text, Math.max(svc.toolResultCap, skills.textCap))
            return
        }
        case "memory_update": {
            const n = memory.notes.slice()
            const i = parseInt(args.id) - 1
            if (!(i >= 0 && i < n.length)) { resolveTool(index, "No existe la nota [#" + args.id + "]."); return }
            const txt = String(args.note || "").trim().slice(0, 400)
            if (txt === "") { resolveTool(index, "Nota vacía."); return }
            const before = n[i]
            n[i] = txt
            memory.setNotes(n)
            resolveTool(index, "Nota [#" + (i + 1) + "] corregida.\nAntes: " + before + "\nAhora: " + txt)
            return
        }
        case "memory_forget": {
            const n = memory.notes.slice()
            const i = parseInt(args.id) - 1
            if (!(i >= 0 && i < n.length)) { resolveTool(index, "No existe la nota [#" + args.id + "]."); return }
            const gone = n[i]
            n.splice(i, 1)
            memory.setNotes(n)
            resolveTool(index, "Nota retirada: " + gone)
            return
        }
        case "learn":
            resolveTool(index, memory.addInstinct(args.lesson))
            return
        case "remember": {
            const note = String(args.note || "").trim().slice(0, 400)
            if (note === "") { resolveTool(index, "Nota vacía."); return }
            memory.setNotes(memory.notes.concat([note]))
            resolveTool(index, "Nota guardada en memoria.")
            return
        }
        case "run_command": {
            // Acotado a 20 s; stdout y stderr vuelven al modelo.
            const cmd = args.command || ""
            if (cmd === "") { resolveTool(index, "Comando vacío."); return }
            exec(["timeout", "20", "sh", "-c", cmd], ({}))
            return
        }
        default: {
            // Nombre que no existe. Antes caía aquí run_command, así que un
            // modelo que alucinaba un nombre con un argumento 'command' podía
            // acabar ejecutando un comando bajo otra etiqueta. Ahora se rechaza y
            // se le recuerda el vocabulario: los modelos locales se inventan
            // nombres a menudo y así corrigen en el siguiente turno.
            resolveTool(index, "No existe la herramienta '" + m.toolName
                + "'. Las disponibles son: " + svc.knownToolNames().join(", "))
        }
        }
    }

    // Una llamada MCP que acaba resolviendo la tarjeta: el error se contesta
    // igual siempre y 'render' pone cómo se lee el resultado bueno.
    function _mcpRpc(index, server, method, params, render) {
        mcp.rpc(server, method, params, (res, err) => {
            runner.resolveTool(index, err !== "" ? err : render(res))
        })
    }
    function _mcpCall(index, server, tool, args) {
        _mcpRpc(index, server, "tools/call", { name: tool, arguments: args },
            (res) => {
                const out = runner.mcp.flatten((res.content || [])
                                .filter(c => c.type === "text"))
                return ((res.isError ? "[error de la herramienta] " : "") + out)
                       .trim() || "(sin contenido)"
            })
    }

    // Lanzar la herramienta aprobada. Un solo Process para todas (solo corre una
    // cada vez, por diseño), así que arrancarlo era el mismo trío de líneas
    // repetido veinte veces; aquí se dice una.
    // De QUIÉN es el proceso que corre ahora mismo. Se apunta al lanzarlo y NO
    // se lee `_toolIndex` al volver: si una salida llega tarde —porque la
    // tarjeta ya se dio por colgada y el lote siguió—, `_toolIndex` ya apunta a
    // otra tarjeta, y resolverla con esta salida sería ponerle a una llamada el
    // resultado de otra. Con el índice capturado, lo peor que puede pasar es
    // que la resolución no haga nada, que es justo lo que debe pasar.
    property int _procIndex: -1

    function exec(cmd, env) {
        const m = messages.get(_toolIndex)
        const seg = Math.round(TP.deadlineMs(m ? String(m.toolName || "") : "") / 1000)
        _procIndex = _toolIndex
        proc.command = LT.acotado(seg, cmd)
        proc.environment = env || ({})
        proc.running = true
    }

    Process {
        id: proc
        stdout: StdioCollector { id: outCol }
        stderr: StdioCollector { id: errCol }
        onExited: (code, estado) => {
            const idx = runner._procIndex
            const m = messages.get(idx)
            const nombre = m ? String(m.toolName || "") : ""
            const plazo = TP.deadlineMs(nombre)
            // Un comando cortado suele traer salida A MEDIAS, y esa media salida
            // es peor que nada: el modelo la leería como el resultado completo.
            // Así que aquí se descarta y se dice lo que pasó de verdad.
            //
            // Tres formas de volver de un corte, y hay que reconocer las tres:
            //   124  `timeout` cortó y salió por su cuenta.
            //   137  cortó, hubo que rematar con KILL, y él sobrevivió.
            //   muerte por señal — el caso normal en realidad: `timeout` mata al
            //     GRUPO de procesos (que es lo que queremos, para que no queden
            //     hijos sueltos), y en ese grupo está él mismo. Comprobado: sale
            //     con exitStatus de caída y sin código.
            // El último es ambiguo —un programa que revienta llega igual—, así
            // que se desempata con el reloj: si murió al cumplirse el plazo, fue
            // el plazo; si murió antes, reventó, y eso se dice como lo que es.
            const señal = estado !== 0
            const tarde = (Date.now() - runner.runningSince) >= plazo - 500
            if (code === 124 || code === 137 || (señal && tarde)) {
                audit.record({ src: "reloj", tool: nombre,
                    args: m ? m.toolArgs : "", decision: "timeout",
                    why: "cortado al cumplirse el plazo de "
                         + Math.round(plazo / 1000) + " s" })
                runner.resolveTool(idx, TP.deadlineText(nombre, plazo))
                return
            }
            if (señal) {
                runner.resolveTool(idx, "La herramienta " + nombre + " murió por "
                    + "una señal antes de terminar (no fue el plazo: llevaba "
                    + Math.round((Date.now() - runner.runningSince) / 1000)
                    + " s). Lo que hubiera escrito hasta ahí está a medias y no "
                    + "se usa.")
                return
            }
            // Se pasó del tope de salida y `head` le cerró la tubería. Decirlo
            // con nombre y no como "murió por señal": es un fallo con arreglo
            // —acotar, filtrar, redirigir a un archivo— y el modelo puede tomar
            // esa decisión si se le cuenta lo que pasó.
            // Los dos códigos se comprueban con la salida delante: 141 y 97 los
            // puede devolver también la propia herramienta, y confundir un
            // `exit 97` suyo con un fallo nuestro sería mentirle al modelo.
            if (code === 141 && ((outCol.text || "").length >= 2097152
                                 || (errCol.text || "").length >= 131072)) {
                runner.resolveTool(idx, "La herramienta " + nombre + " escribió "
                    + "más salida de la que cabe (2 MB por la salida normal, "
                    + "128 kB por la de errores) y se cortó para no agotar la "
                    + "memoria. Lo que llegó está a medias y no se usa. Repite "
                    + "acotando la salida (un filtro, menos alcance, o "
                    + "redirigiendo a un archivo y leyendo un trozo).")
                return
            }
            // El cerco de rutas del envoltorio: la ruta resolvía fuera de la
            // pared siguiendo un enlace simbólico. El motivo ya viene escrito
            // por el shell, con la ruta real dentro, que es el dato que importa.
            if (code === 96 && (errCol.text || "").indexOf("enlace") !== -1) {
                runner.resolveTool(idx, (errCol.text || "").trim())
                return
            }
            if (code === 97 && (outCol.text || "") === ""
                    && (errCol.text || "") === "") {
                runner.resolveTool(idx, "No se pudo preparar la ejecución de "
                    + nombre + ": falló el archivo temporal (¿disco lleno?).")
                return
            }
            let out = (outCol.text || "")
            if ((errCol.text || "").trim() !== "")
                out += (out !== "" ? "\n" : "") + "[stderr] " + errCol.text
            if (out.trim() === "")
                out = "(sin salida; código " + code + ")"
            runner.resolveTool(idx, out)
        }
    }

    // ── Deshacer una edición ─────────────────────────────────────────────────
    readonly property string undoDir:
        Quickshell.env("HOME") + "/.cache/quickshell-ai-undo"

    // Dónde va la copia de seguridad de esta edición, anotada en la tarjeta: es
    // lo que hace posible Deshacer. Las tres herramientas que escriben llevaban
    // la misma línea de armar la ruta.
    function backupFor(index, path) {
        const bak = undoDir + "/" + Date.now() + "-" + path.split("/").pop()
        messages.setProperty(index, "undoPath", bak)
        return bak
    }

    // Devuelve el archivo a como estaba justo antes de la edición.
    property string _undoTarget: ""
    function undoEdit(index) {
        const m = messages.get(index)
        if (!m || String(m.undoPath || "") === "")
            return
        const a = TU.repairJson(m.toolArgs) || ({})
        const target = svc._safePath(a.path)
        if (target === "")
            return
        // Tres desenlaces, no dos. Antes eran dos —"hay copia, restauro" y "no
        // hay copia, borro"— y el segundo daba por hecho que la falta de copia
        // significaba que el archivo era nuevo. También significa que la copia
        // FALLÓ (disco lleno, permisos, la carpeta de copias limpiada), y ahí
        // borrar es destruir el archivo que se venía a salvar. Ahora quien
        // escribe deja una señal explícita cuando el archivo no existía, y sin
        // copia y sin señal esto NO toca nada.
        undoProc.command = ["sh", "-c",
            'if [ -f "$QS_BAK" ]; then cp -a -- "$QS_BAK" "$QS_P" && echo restaurado; '
            + 'elif [ -f "$QS_BAK.nuevo" ]; then rm -f -- "$QS_P" && echo borrado; '
            + 'else echo sincopia; exit 1; fi']
        undoProc.environment = ({ QS_BAK: String(m.undoPath), QS_P: target })
        undoProc.running = true
        _undoTarget = target
    }
    Process {
        id: undoProc
        stdout: StdioCollector { id: undoOut }
        onExited: (code) => {
            const salida = (undoOut.text || "").trim()
            conv.pushInfo(code === 0
                ? (salida === "borrado"
                    ? I18n.tr("Undone: %1 removed (it didn't exist before).").arg(runner._undoTarget)
                    : I18n.tr("Undone: %1 back as it was.").arg(runner._undoTarget))
                : salida === "sincopia"
                    ? I18n.tr("Did NOT undo %1: there is no backup copy, so it cannot be told apart from a file that never existed. Nothing was touched.").arg(runner._undoTarget)
                    : I18n.tr("Could not undo %1").arg(runner._undoTarget))
        }
    }

    // ── Rutas reales: los enlaces simbólicos, a la vista ─────────────────────
    // El cerco a $HOME no puede parar a un agente decidido (con run_command se
    // sale por la puerta grande); sirve contra ACCIDENTES. Por eso un enlace que
    // apunta fuera no se prohíbe —perderías rutas legítimas como ~/datos →
    // /mnt/almacen— sino que se DESTAPA: se resuelve el destino real y, si sale
    // de tu carpeta, esa llamada nunca se auto-aprueba y la tarjeta enseña adónde
    // va de verdad. Escape visible en vez de prohibido.
    property var pathReal: ({})        // índice de mensaje → {real, escapes}

    // ── Veredictos del supervisor ────────────────────────────────────────────
    // Índice de mensaje → {veredicto, riesgo, irreversible, ajuste, fallo}. Se
    // indexa por POSICIÓN, igual que pathReal, así que caduca exactamente igual
    // (ver forgetPaths): heredar el "ok" de otra tarjeta sería justo el fallo
    // que este componente viene a evitar.
    property var supVerdict: ({})

    function _supDone(index, v) {
        const m = Object.assign({}, supVerdict)
        m[index] = v
        supVerdict = m
        // Frenazo: se trata igual que el veto de un hook —tarjeta rechazada y el
        // motivo de vuelta al modelo—, con la diferencia de que se le invita a
        // rebatir. Un bloqueo sin réplica convierte al agente en alguien que
        // reintenta a ciegas.
        if (v && v.veredicto === "bloqueo") {
            blockTool(index, SV.motivoBloqueo(v), "supervisor")
            return
        }
        advance()
    }

    function realPathFor(index) {
        const r = pathReal[index]
        return (r && r.escapes) ? r.real : ""
    }

    // El argumento que es una ruta LOCAL, según la herramienta.
    function _pathArgOf(toolName, args) {
        switch (toolName) {
        case "read_file": case "list_dir": case "write_file": case "edit_file":
        case "grep_files": case "glob_files": case "edit_patch":
            return String(args.path || "")
        case "sftp_get": case "sftp_put":
            return String(args.local_path || "")
        }
        return ""
    }

    property int _resolveIndex: -1
    function _resolvePath(index, p) {
        const abs = svc._safePath(p)
        if (abs === "") {                  // ya fuera del cerco: no hay nada que mirar
            const m = Object.assign({}, pathReal)
            m[index] = { real: "", escapes: false }
            pathReal = m
            advance()
            return
        }
        _resolveIndex = index
        // readlink -f canoniza siguiendo los enlaces; si el archivo aún no existe
        // (write_file), resuelve igual la cadena de carpetas.
        realProc.command = ["sh", "-c", 'readlink -f -- "$QS_P" 2>/dev/null || printf %s "$QS_P"']
        realProc.environment = ({ QS_P: abs })
        realProc.running = true
    }
    Process {
        id: realProc
        stdout: StdioCollector { id: realOut }
        onExited: {
            const home = Quickshell.env("HOME")
            const real = (realOut.text || "").trim()
            const escapes = real !== "" && !real.startsWith(home + "/") && real !== home
            const m = Object.assign({}, runner.pathReal)
            m[runner._resolveIndex] = { real: real, escapes: escapes }
            runner.pathReal = m
            runner._resolveIndex = -1
            runner.advance()
        }
    }

    // ── El coordinador del lote ──────────────────────────────────────────────
    // El modelo puede pedir varias herramientas de golpe. Tras resolver una: si
    // queda alguna pendiente, la auto-aprobable se ejecuta y la manual espera al
    // usuario; solo cuando NO queda ninguna pendiente se devuelve todo al modelo
    // con una única continuación. Así N llamadas paralelas no disparan N envíos.
    function advance() {
        if (svc.busy || svc.compacting)
            return
        if (_resolveIndex >= 0)        // resolviendo una ruta: se espera
            return
        // Un plan esperando visto bueno PARA todo lo demás, aunque el modelo lo
        // haya pedido junto a otras herramientas: proponer y ejecutar a la vez
        // sería proponer de boquilla.
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i)
            if (m.role === "tool" && m.toolStatus === "pending"
                    && m.toolName === "propose_plan")
                return
        }
        // Un clic del usuario que llegó tarde (había otra herramienta corriendo)
        // se atiende ANTES que la ronda automática: lo pidió él.
        while (_colaClics.length > 0) {
            const k = _colaClics[0]
            _colaClics = _colaClics.slice(1)
            const mk = messages.get(k)
            if (mk && mk.role === "tool" && mk.toolStatus === "pending") {
                approveTool(k)
                return
            }
        }
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i)
            if (m.role === "tool" && m.toolStatus === "pending") {
                // Si la llamada lleva una ruta local, primero se averigua adónde
                // apunta DE VERDAD (puede ser un enlace). Se hace una sola vez por
                // tarjeta, y al volver se re-entra aquí.
                const args = TU.repairJson(m.toolArgs) || ({})
                const p = _pathArgOf(m.toolName, args)
                if (p !== "" && pathReal[i] === undefined) {
                    _resolvePath(i, p)
                    return
                }
                const escapes = pathReal[i] && pathReal[i].escapes
                const pol = callPolicy(m.toolName, m.toolArgs)
                // Solo se calcula si hay quien lo mire: es un JSON.parse más
                // en un camino por el que se pasa muchas veces.
                const peligro = sup ? dangerOf(m.toolName, m.toolArgs) : ""
                // SUPERVISOR: el segundo modelo opina ANTES de que esto corra y
                // antes de que el usuario decida. Igual que el enlace simbólico:
                // se pregunta una sola vez por tarjeta, se guarda el veredicto y
                // al volver se re-entra aquí.
                if (sup && supVerdict[i] === undefined
                        && sup.wants(m.toolName, m.toolArgs, peligro, escapes)) {
                    sup.review(i, m,
                        ({ politica: pol, danger: peligro,
                           escapa: escapes ? pathReal[i].real : "" }),
                        (v) => runner._supDone(i, v))
                    return
                }
                // Hay pendientes: si esta es auto (y no se pasó el tope de pasos),
                // se ejecuta sola; si es manual, se espera aquí. Una ruta que se
                // va fuera de $HOME por un enlace NUNCA va sola, por muy "auto"
                // que esté la herramienta: eso lo miras. Y una llamada sobre la
                // que el supervisor tiene dudas tampoco: su "ok" no aprueba
                // nada, pero su duda sí frena la aprobación automática.
                const duda = supVerdict[i] && supVerdict[i].veredicto !== "ok"
                if (toolRounds <= maxToolRounds && !escapes && !duda
                        && pol === "auto")
                    approveTool(i)
                return
            }
        }
        // Nada pendiente: el lote está completo, se continúa la conversación.
        // Antes de seguir se le da un toque al CONSEJERO — no se le espera (no
        // frena nada y su observación viaja en la petición siguiente), y solo
        // opina en turnos que ya se han hecho largos, que es donde un agente se
        // pone a dar vueltas.
        if (sup)
            sup.observe()
        svc.start()
    }

    // Todo lo que pertenece al HILO y no al historial: permisos dados de palabra,
    // el plan a la vista, las rutas ya resueltas.
    function resetThread() {
        sessionAllow = ({})
        pathReal = ({})
        supVerdict = ({})
        toolRounds = 0
        _hookPassed = -1
        _userApproved = -1
        _toolIndex = -1
        _resolveIndex = -1
        _searchIndex = -1
        _fenceIndex = -1
        runningIndex = -1
        _colaClics = []
        fetchSecos = 0
        // El pestillo del buscador NO se levanta al cambiar de conversación: la
        // avería es de la máquina, no del hilo. Se levanta al tocar los ajustes.
    }

    // Las rutas resueltas se indexan por POSICIÓN en el hilo, así que cualquier
    // reordenación (compactar, borrar un mensaje, editar) las invalida: dejarlas
    // haría que la tarjeta N heredara el veredicto de otra distinta — y un
    // "no escapa" heredado por error sí abre la puerta a una auto-aprobación que
    // no tocaba. Se tiran, que volver a resolverlas cuesta un readlink.
    function forgetPaths() {
        pathReal = ({})
        supVerdict = ({})
    }
}
