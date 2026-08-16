import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "TextUtils.js" as TU
import "ToolPolicy.js" as TP
import "Schema.js" as SC

// UN SUBAGENTE. No es "otro chat": es un trabajador con encargo, paredes,
// presupuesto y un contrato de entrega.
//
//   encargo  →  concesión (ToolPolicy)  →  taller (AgentWorkspace)
//            →  contexto propio  →  resultado tipado (Schema)  →  jefe
//
// Lo que hace que esto no sea una conversación anidada:
//
//   · CONCESIÓN. Sus herramientas no son "las de solo lectura" por costumbre,
//     sino las que le concede TP.subagentGrant — que nunca alcanza lo crítico
//     ni lo de ejecución, nunca es más de lo que tiene el usuario, y solo llega
//     a escribir si alguien lo aprobó a mano.
//   · TALLER. Si escribe, escribe en una copia (worktree de git) o en una
//     carpeta suya. Jamás encima de los archivos vivos.
//   · CONTEXTO PROPIO. Se compacta solo: los resultados viejos se recortan para
//     que la ronda ocho siga cabiendo. Y no hereda el hilo del jefe — solo el
//     resumen que este le entrega.
//   · PRESUPUESTO. Rondas Y reloj. Al agotarse cualquiera de los dos se le
//     retira el vocabulario y no le queda más que redactar.
//   · ENTREGA. Si el encargo trae esquema, el informe se comprueba y, si no
//     cumple, se le devuelve el fallo para que lo arregle (hasta dos veces).
//   · TRAZA. Todo lo que hizo queda en un jsonl dentro de su taller: un
//     subagente corre SIN tarjetas, así que lo mínimo es poder mirar después.
//
// Habla el mismo /chat/completions que el harness pero SIN streaming: aquí
// nadie mira la pantalla, y un JSON entero es más simple que un SSE.
QtObject {
    id: sub

    // ── El encargo ───────────────────────────────────────────────────────────
    property string agentId: ""
    property string label: ""
    property string task: ""
    // Lo que el jefe YA sabe y no hace falta redescubrir. Un subagente que
    // empieza de cero repite el trabajo que motivó delegarlo.
    property string brief: ""
    // La raíz a la que se acota (vacía = toda la carpeta personal). Estrechar
    // el foco no es solo seguridad: un subagente al que se le dice "esto es tu
    // proyecto" deja de traer resultados de otros veinte.
    property string workspace: ""
    property string role: "research"     // research | review | debug | build
    property string expectedOutput: ""   // la forma del informe, en prosa
    property var outputSchema: null      // …o comprobable, que es mejor
    property var grant: null             // lo que se le concede
    property int maxRounds: 8
    property int budgetMs: 180000        // el otro presupuesto: el reloj

    // ── Estado ───────────────────────────────────────────────────────────────
    property int rounds: 0
    property string state: "running"     // running | done | error
    property var msgs: []
    property var _calls: []
    property int _callIdx: 0
    property bool _expired: false
    property bool _avisado: false
    property int repairs: 0
    property double startedAt: 0
    property int ms: 0
    property int toolCalls: 0
    property var result: null            // el JSON comprobado, si lo hubo
    property string artifacts: ""
    property string lastTool: ""         // para la barra del panel

    signal finished(string report)

    readonly property var caps: TP.grantCaps(sub.grant)

    // El taller. Se monta antes de la primera ronda: el modelo tiene que saber
    // dónde está desde la primera palabra.
    readonly property AgentWorkspace ws: AgentWorkspace {
        agentId: sub.agentId
        home: AiService.toolCtx.home
        agentsDir: AiService.dataDir + "/agents"
        root: sub.workspace !== "" ? sub.workspace : AiService.toolCtx.home
        wantWrite: !!(sub.grant && sub.grant.write)
        onPrepared: sub._begin()
    }

    // Su vocabulario sale de la concesión, y de la MISMA lista que usa el
    // constructor de comandos: no puede haber una herramienta anunciada que
    // luego no se ejecute ni —lo que importa— una ejecutable sin anunciar.
    readonly property var toolDefs: AiService.subagentDefs(sub.grant)

    // El encargo concreto de cada papel: qué priorizar y cómo cerrar.
    readonly property var _roles: ({
        research: "Eres un subagente de INVESTIGACIÓN. Rastrea, lee y reúne los "
                + "hechos que pidió el encargo. Cierra con los hallazgos y sus "
                + "fuentes (archivo:línea, comando, URL).",
        review: "Eres un subagente REVISOR de código. Busca defectos concretos "
              + "—correctitud, seguridad, rendimiento, casos límite— antes que "
              + "estilo. Cita cada problema con archivo:línea y propón el arreglo. "
              + "Si no encuentras nada serio, dilo con claridad.",
        debug: "Eres un subagente de DIAGNÓSTICO. Acota una avería: reúne "
             + "síntomas (logs, estado de servicios, procesos, red, disco), "
             + "forma una hipótesis y señala la causa más probable con la prueba "
             + "que la sostiene. No propongas cambios destructivos: eso lo hará "
             + "el agente principal con aprobación.",
        build: "Eres un subagente CONSTRUCTOR. Produce lo que pide el encargo "
             + "—archivos, scripts, configuraciones— dentro de tu taller. "
             + "Trabaja pequeño y comprueba lo que escribes releyéndolo. Cierra "
             + "diciendo QUÉ has creado y por qué, no pegando el contenido: los "
             + "archivos ya están ahí."
    })

    // ── Arranque ─────────────────────────────────────────────────────────────
    function start() {
        sub.startedAt = Date.now()
        sub._trace({ t: "start", role: sub.role, label: sub.label,
                     caps: sub.caps, task: sub.task.slice(0, 400) })
        sub.ws.prepare()               // sigue en _begin()
    }

    function _begin() {
        sub.msgs = [
            // El prompt pasa por el perfil del modelo: hay familias que
            // encienden el pensamiento escribiendo aquí y no en la petición.
            { role: "system", content: AiService.systemFor(sub._system(),
                  sub.role === "review" ? "review" : "subagent") },
            { role: "user", content: sub._encargo() }
        ]
        sub._round(true)
    }

    // El prompt: quién es, qué alcanza, dónde está, cuánto le queda y qué se
    // espera de vuelta. En ese orden — un modelo pequeño obedece mejor la
    // primera y la última frase.
    function _system() {
        let s = (sub._roles[sub.role] || sub._roles.research)
            + " Estás dentro de un asistente de escritorio (Arch + Hyprland)."

        // Lo que alcanza, dicho como una lista y no como una promesa vaga: el
        // modelo que cree tener un shell pierde rondas intentándolo.
        s += " TUS PERMISOS: leer archivos y consultar el sistema y servidores"
        if (sub.grant && sub.grant.net)
            s += ", descargar páginas y buscar en la web"
        if (sub.grant && sub.grant.write)
            s += ", y escribir archivos DENTRO de tu taller"
        s += ". NO tienes shell, ni Python, ni depurador, ni puedes delegar en "
           + "otro subagente: si el encargo lo necesita, dilo en el informe y lo "
           + "hará el agente principal con la aprobación del usuario."

        if (sub.workspace !== "")
            s += " Tu área de trabajo se limita a " + sub.workspace + ": las "
               + "rutas relativas cuelgan de ahí y fuera no puedes mirar."
        if (sub.ws.note !== "")
            s += " " + sub.ws.note

        s += " PRESUPUESTO: " + sub.maxRounds + " rondas de herramientas y "
           + Math.round(sub.budgetMs / 1000) + " segundos. No los malgastes: "
           + "cuando necesites mirar en varios sitios, pídelo TODO en el mismo "
           + "turno con varias llamadas en paralelo."

        if (SC.usable(sub.outputSchema))
            s += " ENTREGA: tu última respuesta debe ser SOLO un JSON con esta "
               + "forma exacta, sin texto alrededor ni bloque de código:\n"
               + SC.skeleton(sub.outputSchema, 0)
        else if (sub.expectedOutput !== "")
            s += " ENTREGA: termina con un informe con esta forma: "
               + sub.expectedOutput
        else
            s += " ENTREGA: termina SIEMPRE con un informe claro y conciso en el "
               + "idioma del usuario. Es lo único que verá el agente que te "
               + "delegó: lo que no escribas ahí, se pierde."
        return s
    }

    function _encargo() {
        return sub.brief.trim() !== ""
            ? "Contexto que ya tiene el agente principal (no lo redescubras):\n"
              + sub.brief.trim() + "\n\nEncargo:\n" + sub.task
            : sub.task
    }

    // ── Cancelación ──────────────────────────────────────────────────────────
    // SIN señal: para cuando la conversación que esperaba el informe ya no
    // existe (limpiar, cambiar de hilo). Emitir finished aquí resolvería una
    // tarjeta muerta y relanzaría el bucle principal.
    function cancelSilent() {
        curl.running = false
        toolP.running = false
        sub.state = "error"
        sub._trace({ t: "cancel", rounds: sub.rounds })
        sub._flushTrace()
        // El taller se limpia suelto: este objeto muere en este mismo turno.
        sub.ws.discardDetached()
    }

    function cancel() {
        cancelSilent()
        sub.finished("(subagente cancelado por el usuario)")
    }

    // ── La ronda ─────────────────────────────────────────────────────────────
    function _round(withTools) {
        sub.rounds++
        const conHerr = withTools && sub.rounds < sub.maxRounds && !sub._expired
        // Si se le retira el vocabulario, hay que DECÍRSELO: un modelo al que
        // le desaparecen las herramientas sin explicación suele contestar que no
        // puede hacer nada, en vez de redactar lo que ya sabe.
        if (withTools && !conHerr && !sub._avisado) {
            sub._avisado = true
            sub.msgs = sub.msgs.concat([{ role: "user", content: sub._expired
                ? "Se acabó el tiempo del encargo. Redacta AHORA el informe con "
                  + "lo que tengas, diciendo con claridad qué te quedó sin mirar."
                : "Se acabaron las rondas de herramientas. Redacta AHORA el "
                  + "informe con lo que tengas, diciendo qué te quedó sin mirar." }])
        }
        const req = {
            model: AiService.model,
            messages: sub.msgs,
            temperature: 0.3,
            stream: false
        }
        if (conHerr)
            req.tools = sub.toolDefs
        // Lo que sepamos del modelo, igual que el agente principal. El papel
        // decide el esfuerzo: revisar código es donde un nivel más de
        // pensamiento se nota; rastrear y leer, no tanto.
        AiService.tuneRequest(req, sub.role === "review" ? "review" : "subagent")
        // El mismo constructor de curl que el agente principal: credenciales,
        // tiempos y opciones de red idénticos por construcción.
        curl.command = AiService.chatCommand(req, 120)
        curl.running = true
    }

    function _fail(msg) {
        sub.state = "error"
        sub._trace({ t: "fail", why: msg })
        sub._flushTrace()
        sub.ws.discardDetached()
        sub.finished("El subagente falló: " + msg)
    }

    readonly property Process _curl: Process {
        id: curl
        stdout: StdioCollector { id: curlOut }
        stderr: StdioCollector {}
        onExited: (code) => {
            if (sub.state !== "running")
                return
            let j = null
            try { j = JSON.parse(curlOut.text) } catch (e) {}
            if (!j || code !== 0) {
                sub._fail("respuesta ilegible (curl " + code + ")")
                return
            }
            if (j.error) {
                sub._fail(j.error.message || JSON.stringify(j.error))
                return
            }
            const m = j.choices && j.choices[0] && j.choices[0].message
            if (!m) {
                sub._fail("respuesta vacía")
                return
            }
            // Un Qwen tras un servidor sin parser escribe las llamadas EN EL
            // TEXTO (XML de Qwen3-Coder incluido): sin este rescate, el
            // subagente tomaría ese XML como si fuera el informe final.
            let llamadas = m.tool_calls || []
            let texto = m.content || ""
            if (llamadas.length === 0 && texto !== "") {
                const found = AiService.extractTextToolCalls(texto)
                if (found.calls.length > 0) {
                    texto = found.rest
                    llamadas = found.calls.map((c, k) => ({
                        id: "t" + sub.rounds + "_" + k, type: "function",
                        "function": { name: c.name, arguments: c.args } }))
                }
            }
            if (llamadas.length > 0) {
                // Se apunta el turno del asistente tal cual (el protocolo
                // exige devolverle luego un mensaje 'tool' por cada id) y se
                // ejecutan las llamadas EN SERIE.
                sub.msgs = sub.msgs.concat([{ role: "assistant",
                    content: texto, tool_calls: llamadas }])
                sub._calls = llamadas
                sub._callIdx = 0
                sub._execNext()
                return
            }
            // Sin herramientas: es la entrega. El <think> de Qwen y compañía no
            // pinta nada ahí.
            sub._entrega(TU.splitThink(String(m.content || "")).text.trim())
        }
    }

    // ── La entrega ───────────────────────────────────────────────────────────
    // Con esquema: se comprueba, y si falla se le devuelve el fallo. Un modelo
    // pequeño acierta el formato a la segunda casi siempre; a la tercera, se
    // entrega lo que haya con el aviso puesto — perder el trabajo por la forma
    // del formulario sería el peor de los desenlaces.
    function _entrega(texto) {
        if (!SC.usable(sub.outputSchema)) {
            sub._finish(texto !== "" ? texto
                                     : "(el subagente no redactó informe)")
            return
        }
        const crudo = SC.extractJsonText(texto)
        const obj = crudo !== "" ? TU.repairJson(crudo) : null
        const fallos = (obj === null || typeof obj !== "object")
            ? ["raíz: no encontré ningún JSON en tu respuesta"]
            : SC.validate(obj, sub.outputSchema)
        if (fallos.length === 0) {
            sub.result = obj
            sub._trace({ t: "typed", ok: true, repairs: sub.repairs })
            sub._finish(SC.pretty(obj))
            return
        }
        if (sub.repairs >= 2) {
            sub._trace({ t: "typed", ok: false, why: fallos.slice(0, 3) })
            sub._finish(texto + "\n\n[aviso: el subagente no consiguió cumplir "
                + "el formato pedido — " + fallos.slice(0, 3).join("; ")
                + ". Lo de arriba es su respuesta tal cual.]")
            return
        }
        sub.repairs++
        sub.msgs = sub.msgs.concat([
            { role: "assistant", content: texto },
            { role: "user", content: SC.errorsText(fallos) }])
        sub._round(false)
    }

    function _finish(cuerpo) {
        sub.state = "done"
        sub.ms = Date.now() - sub.startedAt
        // La recogida del taller también lo desmonta si quedó vacío.
        sub.ws.collect((resumen) => {
            sub.artifacts = resumen
            sub._trace({ t: "end", ms: sub.ms, tools: sub.toolCalls,
                         rounds: sub.rounds, artifacts: resumen.slice(0, 300) })
            sub._flushTrace()
            sub.finished(cuerpo + sub._pie(resumen))
        })
    }

    // El pie: qué papel, con qué permisos, cuánto tardó, qué gastó y qué dejó.
    // Es lo que permite al jefe (y al usuario en la tarjeta) medir el coste de
    // la delegación en vez de intuirlo.
    function _pie(resumen) {
        const seg = (sub.ms / 1000).toFixed(1)
        let f = "\n\n— subagente «" + sub.label + "» (" + sub.role + " · "
              + sub.caps.join("+") + "): " + sub.toolCalls + " herramientas · "
              + sub.rounds + " rondas · " + seg + " s"
        if (sub._expired)
            f += " · SE AGOTÓ EL TIEMPO"
        if (resumen !== "") {
            f += "\n  taller: " + (sub.ws.mode === "worktree"
                ? "rama " + sub.ws.branch + " en " + sub.ws.repo
                  + " → " + sub.ws.writeRoot
                : sub.ws.writeRoot)
            f += "\n" + resumen.split("\n").map(l => "  " + l).join("\n")
        } else if (sub.ws.writeRoot !== "") {
            f += "\n  taller: " + sub.ws.writeRoot + " (no escribió nada)"
        }
        return f + "\n  traza: " + sub.ws.tracePath
    }

    // ── Ejecución en serie de las herramientas de la ronda ───────────────────
    function _execNext() {
        if (sub._callIdx >= sub._calls.length) {
            sub._trim()
            sub._round(true)
            return
        }
        const tc = sub._calls[sub._callIdx]
        const name = String(tc["function"].name)
        sub.toolCalls++
        sub.lastTool = name
        // Los argumentos pasan por el mismo reparador que usa el harness: un
        // modelo local manda JSON roto a menudo, y aquí nadie mira para
        // corregir.
        const args = TU.repairJson(tc["function"].arguments) || ({})
        const crudos = String(tc["function"].arguments || "").slice(0, 300)
        // Un subagente ejecuta SIN tarjeta: con más razón queda en el registro
        // de auditoría del harness, y además en su propia traza.
        AiService.auditRecord({ src: "subagent", tool: name,
            args: tc["function"].arguments, decision: "auto",
            why: sub.role + ": " + sub.label })
        sub._trace({ t: "tool", n: name, a: crudos })

        // El lsp no es un comando sino una petición al servidor de lenguaje: se
        // acota la ruta al taller aquí, en su puerta, y se le niega el renombrado
        // —que es una escritura repartida por medio proyecto y no cabe en la
        // idea de "confinado".
        if (name === "lsp") {
            if (String(args.op || "") === "rename") {
                sub._pushResult(tc.id, "Para un subagente el lsp es de solo "
                    + "lectura: el renombrado lo hace el agente principal.")
                return
            }
            const lp = AiService.workPath(args.path, sub.ws.root)
            if (lp === "") {
                sub._pushResult(tc.id, "Ruta fuera de tu área de trabajo.")
                return
            }
            const la = Object.assign({}, args, { path: lp })
            AiService.lspRequest(la, (txt) => sub._pushResult(tc.id, txt))
            return
        }

        // El constructor es el MISMO que usa el agente principal, con la
        // concesión y el taller por delante: una sola jaula que auditar.
        const r = AiService.subagentCommand(name, args, sub.grant, sub.ws)
        if (r === null) {
            sub._pushResult(tc.id, "Herramienta fuera de tus permisos: " + name
                + ". Tienes: " + sub.toolDefs.map(d => d["function"].name).join(", "))
            return
        }
        if (r.error !== undefined) {
            sub._pushResult(tc.id, r.error)
            return
        }
        toolP.command = r.cmd
        toolP.environment = r.env || ({})
        toolP.running = true
    }

    // Lo que lee un subagente viaja al modelo igual que lo que lee su jefe:
    // pasa por el mismo tapado de secretos antes de salir de este equipo.
    function _pushResult(id, text) {
        const limpio = AiService.redactSecrets(String(text)).slice(0, 8000)
        sub._trace({ t: "res", head: limpio.slice(0, 200), len: limpio.length })
        sub.msgs = sub.msgs.concat([{ role: "tool", tool_call_id: id,
                                      content: limpio }])
        sub._callIdx++
        sub._execNext()
    }

    readonly property Process _toolP: Process {
        id: toolP
        stdout: StdioCollector { id: toolPOut }
        stderr: StdioCollector { id: toolPErr }
        onExited: (code) => {
            if (sub.state !== "running")
                return
            let out = toolPOut.text || ""
            if ((toolPErr.text || "").trim() !== "")
                out += (out !== "" ? "\n" : "") + "[stderr] " + toolPErr.text
            if (out.trim() === "")
                out = "(sin salida; código " + code + ")"
            sub._pushResult(sub._calls[sub._callIdx].id, out)
        }
    }

    // ── Contexto propio ──────────────────────────────────────────────────────
    // Un subagente que lee cuatro archivos grandes se queda sin sitio en la
    // ronda seis y el modelo empieza a olvidar el encargo. Se recortan los
    // resultados MÁS VIEJOS —los recientes son los que está usando ahora— y se
    // le dice que se recortaron, que si no vuelve a pedirlos.
    readonly property int _ctxCap: 90000
    function _trim() {
        let total = 0
        for (let i = 0; i < sub.msgs.length; i++)
            total += String(sub.msgs[i].content || "").length
        if (total <= sub._ctxCap)
            return
        const nuevos = sub.msgs.slice()
        const corte = Math.max(0, nuevos.length - 6)
        let n = 0
        for (let i = 0; i < corte && total > sub._ctxCap; i++) {
            const m = nuevos[i]
            if (m.role !== "tool")
                continue
            const c = String(m.content || "")
            if (c.length <= 1200)
                continue
            const nc = c.slice(0, 800) + "\n[… " + (c.length - 800)
                     + " caracteres recortados de este resultado antiguo; "
                     + "vuelve a pedirlo si lo necesitas]"
            total -= (c.length - nc.length)
            nuevos[i] = { role: "tool", tool_call_id: m.tool_call_id, content: nc }
            n++
        }
        if (n > 0) {
            sub.msgs = nuevos
            sub._trace({ t: "trim", n: n, total: total })
        }
    }

    // ── El reloj ─────────────────────────────────────────────────────────────
    readonly property Timer _reloj: Timer {
        interval: Math.max(30000, Math.min(600000, sub.budgetMs))
        running: sub.state === "running" && sub.startedAt > 0
        onTriggered: {
            sub._expired = true
            sub._trace({ t: "timeout", rounds: sub.rounds })
        }
    }

    // ── La traza ─────────────────────────────────────────────────────────────
    // Se acumula y se escribe de una vez al final, suelta: el subagente se
    // destruye en cuanto entrega, y un proceso a medias sobre un objeto que se
    // muere es la clase de carrera que solo aparece el día que estorba.
    property var _traza: []
    function _trace(o) {
        const linea = Object.assign({ ts: new Date().toISOString(),
                                      id: sub.agentId }, o)
        try {
            sub._traza.push(JSON.stringify(linea))
        } catch (e) {
            sub._traza.push('{"t":"?"}')
        }
    }
    function _flushTrace() {
        if (sub._traza.length === 0 || sub.ws.dir === "")
            return
        const texto = sub._traza.join("\n") + "\n"
        sub._traza = []
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p "$(dirname -- "$1")"; printf %s "$2" >> "$1"',
            "sh", sub.ws.tracePath, texto])
    }
}
