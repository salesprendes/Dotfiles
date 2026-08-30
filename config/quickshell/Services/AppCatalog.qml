pragma Singleton

import QtQuick
import Quickshell

// Catálogo preparado una sola vez y compartido entre las distintas vidas del
// lanzador, que se destruye al cerrarse para ahorrar memoria: ordenar y
// normalizar todas las entradas en cada apertura sería trabajo desperdiciado.
Singleton {
    id: root

    property var entries: []
    property bool ready: false

    function searchableText(entry) {
        const kw = Array.isArray(entry.keywords) ? entry.keywords.join(" ")
                 : (typeof entry.keywords === "string" ? entry.keywords : "")
        return ((entry.name || "") + " " + (entry.genericName || "") + " "
              + (entry.comment || "") + " " + kw).toLowerCase()
    }

    function rebuild() {
        const source = DesktopEntries.applications?.values ?? []
        root.entries = source
            .filter(entry => !(entry.noDisplay ?? false))
            .sort((a, b) => (a.name || "").localeCompare(b.name || ""))
            .map(entry => ({ entry: entry, searchText: root.searchableText(entry) }))
        root.ready = true
    }

    // Los paquetes instalan o quitan .desktop en ráfagas, así que los avisos se
    // agrupan y se reconstruye una sola vez cuando el modelo se estabiliza.
    Timer {
        id: rebuildDebounce
        interval: 200
        onTriggered: root.rebuild()
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { rebuildDebounce.restart() }
    }

    Component.onCompleted: rebuild()
}
