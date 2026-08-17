import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "../TextUtils.js" as TU
import "../tools/ToolPolicy.js" as TP
import "../core/Schema.js" as SC
import "Supervisor.js" as SV

// UN SEGUNDO MODELO MIRANDO AL PRIMERO. Dos papeles distintos, y separarlos es
// la mitad del diseño:
//
//   GUARDIÁN (síncrono, puede frenar). Mira UNA llamada antes de que corra.
//     Solo se le molesta cuando hay algo que mirar —nivel de riesgo 2 o más, un
//     comando marcado como destructivo, un enlace que se va de la carpeta
//     personal—, porque supervisar cada read_file con un modelo local es
//     duplicar la latencia de todo a cambio de nada.
//   CONSEJERO (asíncrono, no frena nada). Mira la RONDA y puede decir una cosa,
//     que viaja al modelo principal antes de su siguiente paso. Es la mitad que
//     caza "llevas tres intentos con lo mismo" y "cambiaste algo y no lo
//     comprobaste", que ninguna política puede ver.
//
// Y la invariante que lo sostiene todo: SOLO PUEDE ENDURECER. Su "ok" no
// aprueba nada — la tarjeta que tocaba se enseña igual. Ver Supervisor.js.
//
// La tarjeta ya está en pantalla mientras el guardián piensa (la crea el
// streaming, no el coordinador), así que para el usuario no hay espera: ve
// "mirándolo…" y luego el veredicto. El único que espera de verdad es lo que
// iba a ejecutarse solo, que es precisamente lo que interesa retener.
Scope {
    id: sup

    property var svc
    property var conv
    property var audit

    // off | risky | all. 'risky' es el que tiene sentido con un modelo local:
    // se lleva casi todo el valor por una fracción del coste.
    readonly property string modo:
        ["off", "risky", "all"].indexOf(Settings.aiSupervisor) !== -1
            ? Settings.aiSupervisor : "risky"
    // Otro modelo DEL MISMO SERVIDOR (vacío = el mismo que el agente). Que sea
    // del mismo servidor no es una limitación técnica que no supe resolver: un
    // supervisor en otro proveedor significaría mandar trozos de tus archivos a
    // una tercera empresa para que opine. Lo útil de verdad —uno pequeño y
    // rápido vigilando a uno grande— se hace en el mismo sitio.
    readonly property string modelo:
        String(Settings.aiSupervisorModel || "").trim() !== ""
            ? String(Settings.aiSupervisorModel).trim()
            : (svc ? svc.model : "")
    readonly property bool activo:
        modo !== "off" && !!svc && svc.agentMode && !svc.notConfigured

    // Presupuesto de frenazos por turno. Un supervisor que bloquea todo es peor
    // que no tener supervisor: el asistente deja de servir y se apaga entero.
    // Pasado el tope, deja de decidir el segundo modelo y decide el humano.
    property int bloqueos: 0
    readonly property int topeBloqueos: 2
    // Índice de la tarjeta que está mirando ahora mismo, para pintarlo.
    property int reviewing: -1
    // Veredictos ya emitidos en este turno, por firma (herramienta+argumentos):
    // el modelo repite llamadas, y pagar dos veces por la misma opinión es
    // tirar tiempo.
    property var _cache: ({})
    property bool _aconsejado: false

    // ── El guardián ──────────────────────────────────────────────────────────
    // ¿Merece esta llamada que se moleste a un segundo modelo?
    function wants(name, argsJson, danger, escapa) {
        if (!activo)
            return false
        // Preguntar y proponer plan ya son la pausa: supervisarlas es supervisar
        // al usuario.
        if (name === "ask_user" || name === "propose_plan")
            return false
        if (modo === "all")
            return true
        // Delegar es clase external (nivel 1) y se colaría por debajo del corte,
        // pero un subagente CON ESCRITURA es de lo más gordo que puede pasar en
        // un turno: se aprueba una vez y después escribe sin más tarjetas. Ese
        // sí se mira.
        if (name === "subagent")
            return TP.grantNeedsApproval(
                svc.subagentGrantFor(TU.repairJson(argsJson) || ({})))
        return TP.riskLevel(name) >= 2 || String(danger || "") !== ""
            || escapa === true
    }

    property var _gDone: null
    property string _gTool: ""
    property string _gFirma: ""

    // extra = { politica, danger, escapa }
    function review(index, m, extra, cb) {
        // La firma canonica agrupa las LECTURAS repetidas: un diagnostico son
        // treinta `kubectl get` distintos que merecen exactamente el mismo
        // veredicto. Cae a la firma exacta para todo lo demas: si
        // TP.verdictKey no reconoce el comando como de solo lectura devuelve
        // null y aqui no cambia nada. Medido: 21 veredictos identicos en una
        // sola sesion, con esperas de hasta 90 s cada uno.
        const firma = TP.verdictKey(m.toolName, m.toolArgs)
                   || (String(m.toolName) + "\u0000" + String(m.toolArgs || ""))
        if (sup._cache[firma] !== undefined) {
            cb(sup._cache[firma])
            return
        }
        sup.reviewing = index
        sup._gDone = cb
        sup._gTool = String(m.toolName)
        sup._gFirma = firma
        const ctx = ({
            peticion: sup._peticion(),
            plan: sup._plan(),
            pasos: sup._pasos(1200),
            tool: m.toolName,
            risk: TP.riskClass(m.toolName),
            level: TP.riskLevel(m.toolName),
            politica: extra.politica,
            danger: extra.danger,
            escapa: extra.escapa,
            // Lo que ve el supervisor pasa por el mismo tapado que lo que ve el
            // agente: es otro modelo, y una contraseña no se enseña dos veces
            // por buena intención.
            args: svc.redactSecrets(String(m.toolArgs || ""))
        })
        // Juzgar una llamada es una pregunta acotada: esfuerzo mínimo. Aquí la
        // latencia es el coste —hay una tarjeta esperando— y el veredicto no
        // mejora por rumiar.
        const t = svc.chatCommand(svc.tuneRequest(({
            model: sup.modelo, temperature: 0, stream: false,
            messages: [
                { role: "system", content: svc.systemFor(SV.SISTEMA_GUARDIAN,
                      "guard", true, sup.modelo) },
                { role: "user", content: SV.dossierGuardian(ctx)
                    + "\n\nDevuelve SOLO este JSON:\n"
                    + SC.skeleton(SV.ESQUEMA_GUARDIAN, 0) }]
        }), "guard", true, sup.modelo), 12)
        sup._gBody = t.body
        gProc.command = t.cmd
        gProc.environment = t.env
        gProc.stdinEnabled = true
        gProc.running = true
    }

    // Los dos cuerpos en vuelo. El cuerpo de la petición ya no viaja en el
    // comando —lo escribe cada proceso en su entrada estándar al arrancar—, y
    // hasta que el proceso no existe no hay tubería a la que escribir.
    property string _gBody: ""
    property string _aBody: ""

    readonly property Process _g: Process {
        id: gProc
        stdout: StdioCollector { id: gOut }
        stderr: StdioCollector {}
        onStarted: {
            gProc.write(sup._gBody)
            sup._gBody = ""
            gProc.stdinEnabled = false     // cerrar es lo que dispara el curl
        }
        onExited: (code) => {
            const cb = sup._gDone
            sup._gDone = null
            sup.reviewing = -1
            let v = sup._leer(code, gOut.text, SV.ESQUEMA_GUARDIAN)
            v = v === null
                // FALLO ABIERTO, y dicho. Si fallara cerrado, un servidor lento
                // dejaría el asistente inservible; y lo que de verdad protege
                // (la política, la tarjeta) sigue en pie de todas formas. Pero
                // se anota y se pinta: un supervisor mudo no puede parecer un
                // supervisor conforme.
                ? ({ veredicto: "ok", riesgo: "", irreversible: "", fallo: true,
                     ajuste: "el supervisor no contestó ("
                             + (sup.svc.transportError(code)
                                || "curl " + code) + ")" })
                : SV.degradar(v, sup.bloqueos, sup.topeBloqueos)
            if (v.veredicto === "bloqueo")
                sup.bloqueos++
            sup._cache[sup._gFirma] = v
            if (sup.audit)
                sup.audit.record({ src: "supervisor", tool: sup._gTool,
                    decision: v.veredicto,
                    why: (v.riesgo || "")
                         + (v.ajuste ? "  [" + v.ajuste + "]" : "") })
            if (cb)
                cb(v)
        }
    }

    // ── El consejero ─────────────────────────────────────────────────────────
    // Una vez por turno, y solo en turnos que ya se han hecho largos: dar
    // vueltas es un problema de la ronda tres, no de la primera, y en un turno
    // corto la llamada extra solo añadiría latencia.
    function observe() {
        if (!activo || sup._aconsejado || aProc.running)
            return
        if (!svc || svc.toolRounds < 2)
            return
        const pasos = sup._pasos(2000)
        if (pasos === "")
            return
        sup._aconsejado = true
        const t = svc.chatCommand(svc.tuneRequest(({
            model: sup.modelo, temperature: 0.2, stream: false,
            messages: [
                { role: "system", content: svc.systemFor(SV.SISTEMA_CONSEJERO,
                      "advise", true, sup.modelo) },
                { role: "user", content: SV.dossierConsejero(({
                    peticion: sup._peticion(), plan: sup._plan(), pasos: pasos }))
                    + "\n\nDevuelve SOLO este JSON:\n"
                    + SC.skeleton(SV.ESQUEMA_CONSEJERO, 0) }]
        }), "advise", true, sup.modelo), 20)
        sup._aBody = t.body
        aProc.command = t.cmd
        aProc.environment = t.env
        aProc.stdinEnabled = true
        aProc.running = true
    }

    readonly property Process _a: Process {
        id: aProc
        stdout: StdioCollector { id: aOut }
        stderr: StdioCollector {}
        onStarted: {
            aProc.write(sup._aBody)
            sup._aBody = ""
            aProc.stdinEnabled = false
        }
        onExited: (code) => {
            const v = sup._leer(code, aOut.text, SV.ESQUEMA_CONSEJERO)
            if (!v || v.importa !== true)
                return
            const obs = String(v.observacion || "").trim()
            if (obs === "")
                return
            if (sup.audit)
                sup.audit.record({ src: "supervisor", tool: "(ronda)",
                                   decision: "consejo", why: obs.slice(0, 300) })
            // Se ve Y se manda: el usuario lo lee en el hilo, y el modelo lo
            // recibe pegado a su prompt en la siguiente petición. Marcado como
            // opinión de otro modelo, no como voz del usuario.
            conv.pushInfo("󰭺 " + obs)
            svc.advisorNote = SV.notaConsejo(obs)
        }
    }

    // ── Común ────────────────────────────────────────────────────────────────
    // Una respuesta del servidor → el objeto, o null si no hubo manera. Sin
    // bucle de reparación a propósito: aquí la latencia es el coste, y un
    // supervisor que no acierta a la primera falla abierto y queda anotado.
    function _leer(code, salida, esquema) {
        if (code !== 0)
            return null
        let j = null
        try { j = JSON.parse(salida) } catch (e) { return null }
        const m = j && j.choices && j.choices[0] && j.choices[0].message
        if (!m)
            return null
        const texto = TU.splitThink(String(m.content || "")).text
        const crudo = SC.extractJsonText(texto)
        if (crudo === "")
            return null
        const o = TU.repairJson(crudo)
        if (o === null || typeof o !== "object")
            return null
        // El esquema no estaba solo para pintarle el molde al modelo: un
        // veredicto al que le falta el campo 'veredicto' se leería como
        // undefined y pasaría por "no es bloqueo", que es exactamente el error
        // que no puede cometer un supervisor. Si no cumple, no cuenta.
        //
        // Pero tolerante con la forma y estricto solo con el fondo: rechazar un
        // {"veredicto":"bloqueo"} por venir sin el campo 'riesgo' sería tirar el
        // único veredicto que importa y FALLAR ABIERTO por un descuido de
        // redacción. Las cadenas que falten se completan vacías; lo que no se
        // perdona es un tipo imposible o un veredicto que no existe.
        if (esquema && esquema.properties) {
            for (const k in esquema.properties)
                if (o[k] === undefined && esquema.properties[k].type === "string")
                    o[k] = ""
        }
        if (esquema && SC.validate(o, esquema).length > 0)
            return null
        return o
    }

    // El encargo, el plan y los pasos: lo que hace falta para juzgar si una
    // acción encaja con lo que se pidió. Sin esto el supervisor solo puede
    // opinar sobre la forma del comando, que es la parte fácil.
    function _peticion() {
        for (let i = conv.messages.count - 1; i >= 0; i--) {
            const m = conv.messages.get(i)
            if (m.role === "user")
                return String(m.content || "")
        }
        return ""
    }
    function _plan() {
        const t = svc ? (svc.todos || []) : []
        return t.map(x => (x.status === "completed" ? "[hecho] "
                         : x.status === "in_progress" ? "[en curso] " : "[ ] ")
                          + x.content).join("\n")
    }
    // Las herramientas ya resueltas DESDE el último mensaje del usuario: el
    // encargo en curso, no la historia entera.
    function _pasos(tope) {
        let ini = 0
        for (let i = conv.messages.count - 1; i >= 0; i--)
            if (conv.messages.get(i).role === "user") {
                ini = i
                break
            }
        const filas = []
        for (let i = ini; i < conv.messages.count; i++) {
            const m = conv.messages.get(i)
            if (m.role !== "tool" || m.toolStatus === "pending")
                continue
            filas.push("· " + m.toolName + " " + String(m.toolArgs || "").slice(0, 160)
                       + "\n    → " + String(m.toolResult || "").slice(0, 220)
                                        .replace(/\n/g, " "))
        }
        return filas.join("\n").slice(-tope)
    }

    // El presupuesto y la memoria de opiniones son del TURNO: lo que se bloqueó
    // en el encargo anterior no tiene por qué contar en este.
    function resetTurn() {
        sup.bloqueos = 0
        sup._aconsejado = false
        sup._cache = ({})
    }

    // El turno se ha interrumpido: el veredicto que estuviera pensando ya no
    // vale para nada —su tarjeta está cancelada— y dejarlo llegar reanimaría
    // una llamada que el usuario acaba de matar. Los veredictos ya emitidos se
    // conservan: siguen siendo ciertos para el turno siguiente.
    function cancel() {
        gProc.running = false
        aProc.running = false
        sup._gBody = ""
        sup._aBody = ""
        sup._gDone = null
        sup.reviewing = -1
    }
    function resetThread() {
        gProc.running = false
        aProc.running = false
        // Un cuerpo en vuelo pertenece a la conversación que se acaba de dejar:
        // no puede quedarse esperando a que arranque el siguiente proceso.
        sup._gBody = ""
        sup._aBody = ""
        sup._gDone = null
        sup.reviewing = -1
        resetTurn()
    }
}
