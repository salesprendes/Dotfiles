pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Historial de portapapeles compatible con cliphist/wl-clipboard.
Singleton {
    id: clip

    // Detección centralizada en Deps (reactivo: se re-evalúa al terminar).
    readonly property bool cliphistAvailable: Deps.has("cliphist")
    readonly property bool wlCopyAvailable: Deps.has("wl-copy")
    readonly property bool wlPasteAvailable: Deps.has("wl-paste")
    readonly property bool available: cliphistAvailable && wlCopyAvailable && wlPasteAvailable
    property bool _watcherStarted: false
    property bool loading: false
    property string search: ""
    property string status: ""
    property var entries: []
    property var filteredEntries: []
    // Conteo para el badge de la barra. Independiente de 'entries' para que
    // en reposo (panel cerrado) baste un recuento barato, sin cargar ni
    // retener el historial completo en memoria.
    property int count: 0
    readonly property string missingTools: {
        const missing = []
        if (!cliphistAvailable) missing.push("cliphist")
        if (!wlCopyAvailable || !wlPasteAvailable) missing.push("wl-clipboard")
        return missing.join(", ")
    }

    function _preview(raw) {
        const tab = raw.indexOf("\t")
        let text = tab >= 0 ? raw.substring(tab + 1) : raw
        text = text.replace(/\s+/g, " ").trim()
        return text.length > 0 ? text : I18n.tr("Content without preview")
    }

    function _entryType(raw, preview) {
        const lower = (raw + " " + preview).toLowerCase()
        if (lower.indexOf("image") >= 0 || lower.indexOf("binary") >= 0)
            return "image"
        if (preview.length > 180)
            return "long"
        return "text"
    }

    function _parseList(text) {
        const lines = (text || "").split("\n").filter(line => line.trim().length > 0)
        const list = []
        for (let i = 0; i < lines.length; i++) {
            const raw = lines[i]
            const preview = _preview(raw)
            list.push({
                id: i,
                raw: raw,
                preview: preview,
                type: _entryType(raw, preview)
            })
        }
        entries = list
        count = list.length
        updateFilter()
    }

    function updateFilter() {
        const q = search.trim().toLowerCase()
        if (q.length === 0) {
            filteredEntries = entries
            return
        }
        filteredEntries = entries.filter(entry => entry.preview.toLowerCase().indexOf(q) >= 0)
    }

    onSearchChanged: updateFilter()

    function refresh() {
        if (!available) {
            entries = []
            filteredEntries = []
            count = 0
            return
        }
        if (listProc.running)
            return
        loading = true
        listProc.running = true
    }

    // Arranca el vigilante una sola vez, cuando Deps termina la detección.
    // Cubre ambos órdenes: Deps ya listo al crearse este singleton, o la
    // señal loaded() llegando después.
    function _startWatcher() {
        if (!available) {
            status = I18n.tr("Missing %1").arg(missingTools)
            return
        }
        if (_watcherStarted)
            return
        _watcherStarted = true
        status = ""
        watcher.running = true
    }

    Component.onCompleted: if (Deps.ready) _startWatcher()
    Connections {
        target: Deps
        function onLoaded() { clip._startWatcher() }
    }

    function copy(entry) {
        if (!available || !entry)
            return
        Quickshell.execDetached([
            "sh", "-c",
            "printf '%s\\n' " + Utils.shellQuote(entry.raw) + " | cliphist decode | wl-copy"
        ])
        status = I18n.tr("Copied to clipboard")
        Globals.closeAll()
    }

    function remove(entry) {
        if (!cliphistAvailable || !entry)
            return
        Quickshell.execDetached([
            "sh", "-c",
            "printf '%s\\n' " + Utils.shellQuote(entry.raw) + " | cliphist delete"
        ])
        // Baja local optimista: el ScriptModel del panel ve un único borrado
        // y las filas de debajo suben animadas (el refresh completo de antes
        // recreaba todos los objetos y la lista se reconstruía de golpe,
        // perdiendo además la posición de scroll). OJO: comparar por VALOR
        // ('raw' es la línea única de cliphist), nunca por identidad — el
        // modelData del delegate llega como copia (QVariantMap) tras pasar
        // por ScriptModel, así que 'e !== entry' no encontraba nada y el
        // borrado no llegaba al modelo. El watcher no emite nada con
        // 'cliphist delete', así que el estado local queda en sincronía.
        entries = entries.filter(e => e.raw !== entry.raw)
        count = entries.length
        updateFilter()
        status = I18n.tr("Entry deleted")
    }

    function clear() {
        if (!cliphistAvailable)
            return
        Quickshell.execDetached(["cliphist", "wipe"])
        status = I18n.tr("History cleared")
        entries = []
        filteredEntries = []
        count = 0
    }

    // Vigila el portapapeles: en cada copia/corte real almacena con cliphist
    // y emite el recuento por stdout (un solo proceso). También emite un
    // recuento inicial para el badge al arrancar. Con el panel abierto recarga
    // además la lista completa.
    Process {
        id: watcher
        running: false
        command: ["sh", "-c",
            "cliphist list 2>/dev/null | wc -l; " +
            "exec wl-paste --watch sh -c 'cliphist store; cliphist list 2>/dev/null | wc -l'"]
        stdout: SplitParser {
            onRead: line => {
                const n = parseInt(line)
                if (!isNaN(n))
                    clip.count = n
                if (Globals.clipboardOpen)
                    clip.refresh()
            }
        }
        // Si el vigilante muere (p. ej. reinicio del compositor) se relanza a los 2 s.
        onExited: if (clip.available) watcherRestart.restart()
    }
    Timer {
        id: watcherRestart
        interval: 2000
        onTriggered: if (clip.available && !watcher.running) watcher.running = true
    }

    Process {
        id: listProc
        running: false
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: clip._parseList(this.text)
        }
        onExited: {
            clip.loading = false
        }
    }

    // Suelta el historial un rato después de cerrar el panel (no de inmediato,
    // para que la animación de cierre no se vea vaciarse). Al reabrir, el
    // panel llama a refresh() y lo recarga.
    Timer {
        id: purgeTimer
        interval: 600
        onTriggered: {
            clip.entries = []
            clip.filteredEntries = []
        }
    }
    Connections {
        target: Globals
        function onClipboardOpenChanged() {
            if (Globals.clipboardOpen)
                purgeTimer.stop()
            else
                purgeTimer.restart()
        }
    }
}
