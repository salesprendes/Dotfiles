pragma Singleton

import QtQuick
import Quickshell

// Catálogo preparado una sola vez y compartido entre las distintas vidas del
// lanzador. El panel se destruye al cerrarse para ahorrar memoria, pero ordenar
// y normalizar todas las entradas en cada apertura era trabajo desperdiciado.
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

    // Los paquetes pueden instalar o quitar .desktop en ráfagas. Agrupamos
    // esos avisos y reconstruimos una sola vez cuando el modelo se estabiliza.
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
