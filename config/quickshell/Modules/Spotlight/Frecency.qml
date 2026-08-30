pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Memoria de uso de Spotlight: cuántas veces has abierto cada cosa y CUÁNDO.
//
// Vive en su propio archivo y no en settings.json a propósito. Son datos que
// cambian en cada uso, y meterlos en el archivo de ajustes significaría
// reescribir los ciento y pico ajustes cada vez que abres una app — y que un
// `git diff` de tu configuración saliera lleno de ruido que no has decidido tú.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/state/quickshell/frecency.json"

    // { id: { count, last } }
    property var stats: ({})
    property bool loaded: false

    function statsFor(id) {
        return root.stats[id] ?? null
    }

    function remember(id) {
        if (!id)
            return
        const prev = root.stats[id]
        const next = Object.assign({}, root.stats)
        next[id] = {
            count: (prev ? prev.count : 0) + 1,
            last: Date.now()
        }
        root.stats = next
        saveTimer.restart()
    }

    function forget(id) {
        if (!root.stats[id])
            return
        const next = {}
        for (const k in root.stats)
            if (k !== id)
                next[k] = root.stats[k]
        root.stats = next
        saveTimer.restart()
    }

    function clear() {
        root.stats = ({})
        saveTimer.restart()
    }

    function load() {
        if (root.loaded)
            return
        root.loaded = true
        try {
            const raw = file.text()
            if (!raw || raw.trim() === "")
                return
            const parsed = JSON.parse(raw)
            // Saneado: un archivo tocado a mano no debe poder meter basura en
            // la puntuación. Solo entran entradas con un contador que es un
            // número; el resto se descarta en silencio.
            const clean = {}
            for (const k in parsed) {
                const v = parsed[k]
                if (v && typeof v.count === "number" && isFinite(v.count) && v.count > 0)
                    clean[k] = { count: Math.floor(v.count),
                                 last: typeof v.last === "number" && isFinite(v.last) ? v.last : 0 }
            }
            root.stats = clean
            // Podar AQUÍ, una vez por sesión: es el único momento en que el
            // mapa entero ya está en memoria y no se está usando para nada.
            // Sin esta llamada, prune() era código muerto y el archivo crecía
            // para siempre con cosas abiertas una vez hace dos años.
            root.prune()
        } catch (e) {
            console.warn("Frecency: archivo ilegible, se empieza de cero:", e)
            root.stats = ({})
        }
    }

    // Poda: sin esto el archivo crece para siempre con cosas que se usaron una
    // vez hace dos años. Se tiran las entradas de un solo uso muy antiguas —
    // las que ya no pueden influir en el orden de todos modos.
    function prune() {
        const limite = Date.now() - 180 * 86400000
        const next = {}
        let tirados = 0
        for (const k in root.stats) {
            const v = root.stats[k]
            if (v.count <= 1 && v.last < limite) { tirados++; continue }
            next[k] = v
        }
        if (tirados > 0) {
            root.stats = next
            saveTimer.restart()
        }
    }

    function save() {
        file.setText(JSON.stringify(root.stats))
    }

    // Se agrupa: abrir algo desde Spotlight puede tocar esto dos veces seguidas
    // (el uso y la poda) y no hace falta escribir el archivo dos veces.
    Timer {
        id: saveTimer
        interval: 400
        onTriggered: root.save()
    }

    FileView {
        id: file
        path: root.path
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }
}
