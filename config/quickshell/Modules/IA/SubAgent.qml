import QtQuick
import Quickshell.Io
import qs.Config
import "TextUtils.js" as TU

// Un SUBAGENTE (el AgentTool de Claude Code, en pequeño): una conversación
// aparte con el mismo modelo, que investiga por su cuenta y devuelve un
// informe al agente principal. Dos decisiones de diseño lo hacen seguro:
//
//   · SOLO LECTURA. Sus herramientas (leer, listar, buscar, glob, descargar)
//     se auto-ejecutan sin tarjetas — por eso puede ser autónomo — y nada de
//     lo que puede hacer toca el disco ni ejecuta comandos. Si la tarea
//     necesita escribir, eso le toca al agente principal con su aprobación.
//   · TOPE DE RONDAS. Al llegar al máximo se le retira el vocabulario de
//     herramientas y no le queda otra que redactar el informe.
//
// Habla el mismo /chat/completions que el harness pero SIN streaming: aquí
// nadie mira la pantalla, y un JSON entero es más simple que un SSE.
QtObject {
    id: sub

    property string label: ""
    property string task: ""
    // El PAPEL moldea el encargo (la idea de roles de oh-my-pi, a nivel de
    // subagente): un investigador rastrea, un revisor busca defectos, un
    // diagnosticador acota una avería. Los tres son de solo lectura — lo que
    // cambia es dónde miran y cómo redactan.
    property string role: "research"    // research | review | debug
    // La forma esperada del informe (el "yield tipado" de oh-my-pi, en versión
    // ligera: no se valida un esquema —un modelo local no es de fiar para eso—
    // pero se le pide la estructura y el jefe la lee directa).
    property string expectedOutput: ""
    property int rounds: 0
    property int maxRounds: 8            // configurable por llamada (1..12)
    property string state: "running"    // running | done | error
    property var msgs: []
    property var _calls: []             // tool_calls pendientes de la ronda
    property int _callIdx: 0

    // Seguimiento para la tarjeta y el pie del informe (los "status cards con
    // coste y duración" de oh-my-pi): cuándo empezó, cuánto llevó, cuántas
    // herramientas gastó.
    property double startedAt: 0
    property int ms: 0
    property int toolCalls: 0

    signal finished(string report)

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
             + "el agente principal con aprobación."
    })

    // Su vocabulario es EL del harness, filtrado a lo que no cambia nada:
    // leer archivos, consultar el sistema y consultar servidores remotos (así
    // puede diagnosticar una máquina entera por su cuenta). No lleva copia
    // propia de los esquemas a propósito — cuando la llevaba, ya había
    // divergido: anunciaba un read_file sin offset/limit que el harness sí
    // sabía hacer, y el subagente leía peor que su jefe sin motivo.
    readonly property var roToolDefs: AiService.readOnlyDefs

    function start() {
        sub.startedAt = Date.now()
        const papel = _roles[sub.role] || _roles.research
        let system = papel
            + " Estás dentro de un asistente de escritorio (Arch + Hyprland). "
            + "MODO SOLO LECTURA: tus herramientas no modifican nada y no puedes "
            + "crear ni editar archivos. Trabaja rápido: busca, lee y responde. "
            + "Tienes un máximo de " + sub.maxRounds + " rondas de herramientas; "
            + "no las malgastes. Cuando necesites mirar varios sitios, pídelo "
            + "TODO en el mismo turno con varias llamadas en paralelo. Termina "
            + "SIEMPRE con un informe claro y conciso en el idioma del usuario: "
            + "es lo único que verá el agente que te delegó."
        if (sub.expectedOutput !== "")
            system += " El informe DEBE tener esta forma: " + sub.expectedOutput
        sub.msgs = [
            { role: "system", content: system },
            { role: "user", content: sub.task }
        ]
        sub._round(true)
    }

    // Cancelación SIN señal: para cuando la conversación que esperaba el
    // informe ya no existe (limpiar, cambiar de hilo). Emitir finished aquí
    // resolvería una tarjeta muerta y relanzaría el bucle principal.
    function cancelSilent() {
        curl.running = false
        toolP.running = false
        sub.state = "error"
    }

    // Cancelación del usuario: lo mismo, pero avisando a quien esperaba.
    function cancel() {
        cancelSilent()
        sub.finished("(subagente cancelado por el usuario)")
    }

    function _round(withTools) {
        sub.rounds++
        const req = {
            model: AiService.model,
            messages: sub.msgs,
            temperature: 0.3,
            stream: false
        }
        // Última ronda: sin herramientas, solo queda redactar.
        if (withTools && sub.rounds < sub.maxRounds)
            req.tools = sub.roToolDefs
        // El mismo constructor de curl que el agente principal: credenciales,
        // tiempos y opciones de red idénticos por construcción.
        curl.command = AiService.chatCommand(req, 120)
        curl.running = true
    }

    function _fail(msg) {
        sub.state = "error"
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
            // Sin herramientas: es el informe. El <think> de Qwen y compañía
            // no pinta nada ahí.
            const report = TU.splitThink(String(m.content || "")).text.trim()
            sub.state = "done"
            sub.finished(sub._withFooter(
                report !== "" ? report : "(el subagente no redactó informe)"))
        }
    }

    // El pie del informe: qué papel, cuánto tardó y qué gastó. Es lo que hace
    // al jefe (y al usuario en la tarjeta) medir el coste de la delegación.
    function _withFooter(report) {
        sub.ms = Date.now() - sub.startedAt
        const seg = (sub.ms / 1000).toFixed(1)
        return report + "\n\n— subagente «" + sub.label + "» ("
             + sub.role + "): " + sub.toolCalls + " herramientas · "
             + sub.rounds + " rondas · " + seg + " s"
    }

    // ── Ejecución en serie de las herramientas de la ronda ──────────────────
    function _execNext() {
        if (sub._callIdx >= sub._calls.length) {
            sub._round(true)
            return
        }
        const tc = sub._calls[sub._callIdx]
        sub.toolCalls++
        // Los argumentos pasan por el mismo reparador que usa el harness: un
        // modelo local manda JSON roto a menudo, y aquí nadie mira para
        // corregir.
        const args = TU.repairJson(tc["function"].arguments) || ({})
        // El constructor es el MISMO que usa el agente principal: una sola
        // jaula que auditar. Si devuelve null, la herramienta no es de solo
        // lectura y un subagente no la toca.
        const r = AiService.readOnlyCommand(tc["function"].name, args)
            || { error: "Herramienta no disponible para un subagente: "
                        + tc["function"].name }
        if (r.error !== undefined) {
            sub._pushResult(tc.id, r.error)
            return
        }
        toolP.command = r.cmd
        toolP.environment = r.env
        toolP.running = true
    }

    // Lo que lee un subagente viaja al modelo igual que lo que lee su jefe:
    // pasa por el mismo tapado de secretos antes de salir de este equipo.
    function _pushResult(id, text) {
        sub.msgs = sub.msgs.concat([{ role: "tool", tool_call_id: id,
            content: AiService.redactSecrets(String(text)).slice(0, 8000) }])
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
}
