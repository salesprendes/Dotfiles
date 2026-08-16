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

    // ── El pestillo de la búsqueda web ───────────────────────────────────────
    // Cuando no hay NINGÚN buscador que funcione, el fallo no es de la consulta:
    // es de configuración, y va a fallar igual las diez veces siguientes. Sin
    // este pestillo el modelo lo descubría una vez por llamada —reformulando y
    // razonando entre medias, que es lo caro— hasta agotar las rondas del turno.
    // Con él, la primera avería se explica entera y las siguientes se contestan
    // en el acto y sin red.
    //
    // Es de SESIÓN, no de encargo: si el buscador está caído, sigue caído en el
    // mensaje siguiente. Se levanta solo cuando el usuario cambia algo que puede
    // arreglarlo, que es la única novedad que justifica volver a probar.
    property bool searchBroken: false
    property int _searchIndex: -1
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
        // Un aviso del propio harness (no se pudo descargar, la página no tenía
        // texto) tampoco se enmarca: sería decirle al modelo que lo ha escrito
        // un desconocido.
        if (externo && String(result).indexOf(LT.FETCH_KO) !== -1) {
            result = String(result).replace(LT.FETCH_KO, "").trim()
            externo = false
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
        if (!svc.busy)
            svc.start()      // que el modelo reaccione al rechazo
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
                label: args.label, role: args.role, brief: args.brief,
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
            const bE = LT.writes("edit_file", p, args, backupFor(index, p), undoDir)
            exec(bE.cmd, bE.env)
            return
        }
        case "open_url": {
            const url = args.url || ""
            if (url !== "")
                Quickshell.execDetached(["xdg-open", url])
            resolveTool(index, url !== "" ? "URL abierta en el navegador."
                                          : "URL inválida.")
            return
        }
        case "write_file": {
            const p = svc._safePath(args.path)
            if (p === "") { resolveTool(index, "Ruta fuera de la carpeta personal."); return }
            const bW = LT.writes("write_file", p, args, backupFor(index, p), undoDir)
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
    function exec(cmd, env) {
        proc.command = cmd
        proc.environment = env || ({})
        proc.running = true
    }

    Process {
        id: proc
        stdout: StdioCollector { id: outCol }
        stderr: StdioCollector { id: errCol }
        onExited: (code) => {
            let out = (outCol.text || "")
            if ((errCol.text || "").trim() !== "")
                out += (out !== "" ? "\n" : "") + "[stderr] " + errCol.text
            if (out.trim() === "")
                out = "(sin salida; código " + code + ")"
            runner.resolveTool(runner._toolIndex, out)
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
        undoProc.command = ["sh", "-c",
            'if [ -f "$QS_BAK" ]; then cp -a -- "$QS_BAK" "$QS_P" && echo restaurado; '
            + 'else rm -f -- "$QS_P" && echo borrado; fi']
        undoProc.environment = ({ QS_BAK: String(m.undoPath), QS_P: target })
        undoProc.running = true
        _undoTarget = target
    }
    Process {
        id: undoProc
        stdout: StdioCollector { id: undoOut }
        onExited: (code) => {
            conv.pushInfo(code === 0
                ? ((undoOut.text || "").trim() === "borrado"
                    ? I18n.tr("Undone: %1 removed (it didn't exist before).").arg(runner._undoTarget)
                    : I18n.tr("Undone: %1 back as it was.").arg(runner._undoTarget))
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
