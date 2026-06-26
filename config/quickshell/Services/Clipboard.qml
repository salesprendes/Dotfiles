pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Historial de portapapeles compatible con cliphist/wl-clipboard.
Singleton {
    id: clip

    property bool cliphistAvailable: false
    property bool wlCopyAvailable: false
    property bool wlPasteAvailable: false
    readonly property bool available: cliphistAvailable && wlCopyAvailable && wlPasteAvailable
    property bool loading: false
    property string search: ""
    property string status: ""
    property var entries: []
    property var filteredEntries: []
    readonly property int count: entries.length
    readonly property string missingTools: {
        const missing = []
        if (!cliphistAvailable) missing.push("cliphist")
        if (!wlCopyAvailable || !wlPasteAvailable) missing.push("wl-clipboard")
        return missing.join(", ")
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
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
            return
        }
        if (listProc.running)
            return
        loading = true
        listProc.running = true
    }

    function copy(entry) {
        if (!available || !entry)
            return
        Quickshell.execDetached([
            "sh", "-c",
            "printf '%s\\n' " + shellQuote(entry.raw) + " | cliphist decode | wl-copy"
        ])
        status = I18n.tr("Copied to clipboard")
        Globals.closeAll()
    }

    function remove(entry) {
        if (!cliphistAvailable || !entry)
            return
        Quickshell.execDetached([
            "sh", "-c",
            "printf '%s\\n' " + shellQuote(entry.raw) + " | cliphist delete"
        ])
        status = I18n.tr("Entry deleted")
        refreshLater.restart()
    }

    function clear() {
        if (!cliphistAvailable)
            return
        Quickshell.execDetached(["cliphist", "wipe"])
        status = I18n.tr("History cleared")
        entries = []
        filteredEntries = []
    }

    Process {
        id: deps
        running: true
        command: ["sh", "-c",
            "printf 'cliphist='; command -v cliphist >/dev/null 2>&1 && echo yes || echo no; " +
            "printf 'wl-copy='; command -v wl-copy >/dev/null 2>&1 && echo yes || echo no; " +
            "printf 'wl-paste='; command -v wl-paste >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").trim().split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const parts = lines[i].split("=")
                    if (parts[0] === "cliphist") clip.cliphistAvailable = parts[1] === "yes"
                    else if (parts[0] === "wl-copy") clip.wlCopyAvailable = parts[1] === "yes"
                    else if (parts[0] === "wl-paste") clip.wlPasteAvailable = parts[1] === "yes"
                }
                if (clip.available) {
                    clip.status = ""
                    watcher.running = true
                    clip.refresh()
                } else {
                    clip.status = I18n.tr("Missing %1").arg(clip.missingTools)
                }
            }
        }
    }

    // Vigila el portapapeles: en cada copia/corte real, almacena con
    // cliphist y emite una marca por stdout. Así el refresco es dirigido
    // por eventos (solo cuando de verdad cambia el portapapeles), sin
    // sondeo en reposo: el número del badge se mantiene al día aunque el
    // panel esté cerrado, y la lista se actualiza si está abierto.
    Process {
        id: watcher
        running: false
        command: ["sh", "-c",
            "command -v wl-paste >/dev/null 2>&1 && command -v cliphist >/dev/null 2>&1 && " +
            "wl-paste --watch sh -c 'cliphist store; echo .'"]
        stdout: SplitParser {
            onRead: clip.refresh()
        }
    }

    Process {
        id: listProc
        running: false
        command: ["sh", "-c", "cliphist list 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: clip._parseList(this.text)
        }
        onExited: {
            clip.loading = false
        }
    }

    Timer {
        id: refreshLater
        interval: 250
        onTriggered: clip.refresh()
    }
}
