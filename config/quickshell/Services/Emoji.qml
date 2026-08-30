pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Catálogo de emojis y su búsqueda. El catálogo se genera a partir de la base
// de datos Unicode del sistema —cada entrada es {c: carácter, n: nombre, g:
// grupo}— y no se escribe a mano ni se descarga.
//
// Se carga perezosamente, la primera vez que se abre el selector: son más de cien
// kB de JSON y miles de objetos, y la mayoría de las sesiones no lo abren nunca.
Singleton {
    id: root

    property var all: []
    property bool loaded: false
    property bool loading: false

    property string query: ""
    property string group: ""

    readonly property var groups: {
        const out = []
        for (const e of root.all)
            if (out.indexOf(e.g) === -1)
                out.push(e.g)
        return out
    }

    // Recientes, guardados en settings.json para que sobrevivan al reinicio del
    // shell: es lo que convierte el selector en útil, porque casi todo el uso son
    // las mismas veinte caras.
    readonly property var recent: Settings.emojiRecent

    readonly property var filtered: {
        if (!root.loaded)
            return []
        const q = root.query.trim().toLowerCase()
        const g = root.group

        // Sin búsqueda ni grupo, los recientes van primero.
        if (q === "" && g === "") {
            if (root.recent.length === 0)
                return root.all
            const rec = []
            for (const c of root.recent)
                for (const e of root.all)
                    if (e.c === c) { rec.push(e); break }
            return rec.concat(root.all.filter(e => root.recent.indexOf(e.c) === -1))
        }

        const out = []
        for (const e of root.all) {
            if (g !== "" && e.g !== g)
                continue
            if (q !== "" && e.n.indexOf(q) === -1)
                continue
            out.push(e)
        }
        return out
    }

    function load() {
        if (root.loaded || root.loading)
            return
        root.loading = true
        try {
            root.all = JSON.parse(catalogue.text())
            root.loaded = true
        } catch (e) {
            console.warn("Emoji: catálogo ilegible:", e)
            root.all = []
        }
        root.loading = false
    }

    // Copia al portapapeles y lo apunta como reciente. Usa wl-copy directo y no
    // Clipboard.copy(), que decodifica una entrada de cliphist. El emoji entra
    // en el historial igual, porque el vigilante ve el cambio de selección.
    function copy(character) {
        if (!character)
            return
        Quickshell.execDetached(["sh", "-c",
            "printf '%s' " + Utils.shellQuote(character) + " | wl-copy"])
        remember(character)
    }

    function remember(character) {
        const list = Settings.emojiRecent.filter(c => c !== character)
        list.unshift(character)
        // Tope: una lista de recientes que no olvida deja de serlo.
        Settings.emojiRecent = list.slice(0, 40)
    }

    FileView {
        id: catalogue
        path: Quickshell.shellPath("Modules/Emoji/emoji.json")
        // Lectura bloqueante a propósito: se leen una vez en toda la sesión, la
        // primera que se abre el selector, y a cambio el panel abre ya poblado en
        // vez de aparecer vacío y rellenarse un fotograma después.
        blockLoading: true
        printErrors: false
    }
}
