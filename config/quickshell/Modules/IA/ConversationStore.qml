import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "Payload.js" as PL

// El HILO y su historial: las burbujas de la conversación activa, las
// conversaciones archivadas, los contadores y el guardado en disco.
//
// La conversación activa vive en un ListModel (append añade UNA burbuja en vez
// de reconstruirlas todas) y el resto, serializadas en 'conversations'. Roles de
// cada fila — siempre todos, que un ListModel fija los suyos con la primera:
//   role: user | assistant | error | info | tool
//   content, reasoning, modelName, ms, tokens
//   toolName, toolArgs, toolId, toolResult, toolStatus (pending|done|rejected)
//   attachNote: etiqueta de adjuntos ("captura", …) para pintarla en la burbuja
//   undoPath: copia previa a una edición (es lo que permite Deshacer)
//   toolBatch: qué tarjetas nacieron en la misma ronda del modelo
Scope {
    id: store

    property var svc

    property ListModel messages: ListModel {}
    property var conversations: []      // [{id, title, updated, entries:[…]}]
    property string currentId: ""

    // Totales de la conversación (los muestra el cajón, estilo aider).
    property int convTokens: 0
    property real convMs: 0
    // Llenado aproximado del contexto que viaja al modelo (0..1), medido contra
    // el presupuesto de caracteres — que sale de la ventana real del modelo.
    property real contextFill: 0

    // El historial ya está en pie y con su contenido: el harness lo usa para
    // disparar session_start y recolocar la habilidad del hilo restaurado.
    signal restored()

    function recountTotals() {
        let tok = 0, ms = 0, chars = 0
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i)
            tok += m.tokens
            ms += m.ms
            if (m.role === "user" || m.role === "assistant")
                chars += m.content.length
            // Las herramientas también viajan al modelo (argumentos y
            // resultado): en modo agente son LA mayor parte del contexto, y un
            // medidor que las ignore dice "medio vacío" con la ventana
            // desbordando. Debe medir lo mismo que el recorte del historial
            // manda.
            else if (m.role === "tool" && m.toolStatus !== "pending")
                chars += m.toolArgs.length + m.toolResult.length
        }
        convTokens = tok
        convMs = ms
        contextFill = Math.min(1, chars / (svc ? svc.charBudget : 1))
    }

    // ── Añadir ───────────────────────────────────────────────────────────────
    function append(m) {
        messages.append({
            role: m.role || "user", content: m.content || "",
            reasoning: m.reasoning || "", modelName: m.modelName || "",
            ms: m.ms || 0, tokens: m.tokens || 0,
            toolName: m.toolName || "", toolArgs: m.toolArgs || "",
            toolId: m.toolId || "", toolResult: m.toolResult || "",
            toolStatus: m.toolStatus || "", attachNote: m.attachNote || "",
            ts: m.ts || "", undoPath: m.undoPath || "", toolBatch: m.toolBatch || ""
        })
    }

    function push(m) {
        // Hora del mensaje: se estampa al nacer, no se deriva luego.
        if (!m.ts)
            m.ts = new Date().toLocaleTimeString(Qt.locale(), "HH:mm")
        append(m)
        save()
        // Con el panel cerrado, la llegada se avisa por el sistema de
        // notificaciones (el del propio shell): pediste algo, te fuiste, y el
        // resultado te encuentra.
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
        push({ role: "info", content: text })
    }

    // ── Título e instantánea ─────────────────────────────────────────────────
    readonly property string newTitle: I18n.tr("New conversation")
    function title() {
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).role === "user") {
                const t = messages.get(i).content.split("\n")[0]
                return t.length > 42 ? t.slice(0, 42) + "…" : t
            }
        return newTitle
    }

    function snapshot() {
        if (currentId === "")
            currentId = String(Date.now())
        const entries = []
        for (let i = 0; i < messages.count; i++)
            entries.push(PL.plainMsg(messages.get(i)))
        const rest = conversations.filter(c => c.id !== currentId)
        // Una conversación vacía no merece hueco en la lista.
        if (entries.length > 0)
            rest.unshift({ id: currentId, title: title(),
                           updated: Date.now(), entries: entries })
        conversations = rest
    }

    // El último mensaje del usuario del hilo actual (""), que es la consulta
    // contra la que todo lo demás mide relevancia.
    function lastUserText() {
        for (let i = messages.count - 1; i >= 0; i--)
            if (messages.get(i).role === "user")
                return messages.get(i).content
        return ""
    }

    // ── Guardado con freno ───────────────────────────────────────────────────
    // Antes cada mensaje reescribía todo el JSON a disco (instantánea de N
    // mensajes + serialización + escritura); en un hilo largo y con streaming eso
    // es mucha E/S en el camino caliente. Ahora el recuento para el medidor es
    // inmediato (barato, y la UI lo necesita en vivo), pero el volcado a disco se
    // agrupa: varias mutaciones seguidas se funden en una sola escritura. Las
    // transiciones que no admiten pérdida (cambiar de conversación, cerrar)
    // fuerzan un volcado con saveNow.
    function save() {
        recountTotals()
        saveTimer.restart()
    }
    function saveNow() {
        saveTimer.stop()
        snapshot()
        hist.convs = conversations
        hist.current = currentId
        recountTotals()
    }
    Timer {
        id: saveTimer
        interval: 500
        onTriggered: store.saveNow()
    }
    // El shell se recarga con cada cambio de un .qml: si pillaba al freno de
    // guardado a medio contar, los últimos mensajes se esfumaban con la recarga.
    // Al morir, lo pendiente se vuelca.
    Component.onDestruction: if (saveTimer.running) saveNow()

    // La carpeta de estado se crea al arrancar: en una instalación recién clonada
    // 'data/' no existe (solo lleva .gitkeep) y FileView no crea el directorio
    // padre al escribir, así que sin esto el primer guardado fallaría en
    // silencio.
    Process {
        running: true
        command: ["mkdir", "-p", store.svc ? store.svc.dataDir : "/tmp"]
    }

    FileView {
        path: store.svc ? store.svc.dataDir + "/ai-history.json" : ""
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            if (store.messages.count > 0)
                return
            // Formato viejo (una sola conversación plana): se migra.
            if ((!hist.convs || hist.convs.length === 0) && hist.entries
                    && hist.entries.length > 0)
                hist.convs = [{ id: String(Date.now()),
                                title: store.newTitle,
                                updated: Date.now(), entries: hist.entries }]
            store.conversations = hist.convs || []
            const target = store.conversations.find(c => c.id === hist.current)
                        || store.conversations[0]
            if (target) {
                store.currentId = target.id
                for (let i = 0; i < target.entries.length; i++)
                    store.append(target.entries[i])
            } else {
                store.currentId = String(Date.now())
            }
            store.recountTotals()
            store.restored()
        }

        JsonAdapter {
            id: hist
            property var convs: []
            property string current: ""
            property var entries: []    // solo para leer el formato viejo
        }
    }
}
