pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Catálogo de emojis y su búsqueda.
//
// El catálogo (Modules/Emoji/emoji.json) se genera a partir de la base de datos
// Unicode del sistema, no se escribe a mano ni se descarga: cada entrada es
// {c: carácter, n: nombre en minúsculas, g: grupo}. Ver tests/emoji.py, que es
// el guion que lo regenera cuando Unicode saca una versión nueva.
//
// Se carga PEREZOSAMENTE, la primera vez que se abre el selector: son 136 kB de
// JSON y 2.500 objetos, y la inmensa mayoría de las sesiones no abren el
// selector ni una vez. Cargarlo al arrancar sería pagarlo siempre para el caso
// raro.
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

    // Recientes: se guardan en settings.json, así que sobreviven al reinicio
    // del shell. Es lo que convierte el selector en útil de verdad — la
    // mayoría de la gente usa las mismas veinte caras.
    readonly property var recent: Settings.emojiRecent

    readonly property var filtered: {
        if (!root.loaded)
            return []
        const q = root.query.trim().toLowerCase()
        const g = root.group

        // Sin búsqueda ni grupo, los recientes van primero: es lo que se busca
        // el 90 % de las veces.
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

    // Copia al portapapeles y lo apunta como reciente. Se usa wl-copy directo
    // y no Clipboard.copy(): aquello decodifica una entrada de cliphist, que es
    // otra cosa. El emoji entra en el historial igual, porque el vigilante de
    // cliphist ve el cambio de selección.
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
        // Lectura BLOQUEANTE, y a propósito: son 136 kB leídos UNA vez en toda
        // la sesión, la primera que se abre el selector. Un cuarto de
        // milisegundo de disco a cambio de que el panel abra ya poblado, en
        // lugar de aparecer vacío y rellenarse un fotograma después.
        blockLoading: true
        printErrors: false
    }
}
