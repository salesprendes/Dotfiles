pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Familias tipográficas instaladas (vía fc-list). Prioriza monoespaciadas y
// Nerd Font (las que llevan iconos), que van bien para barra/paneles.
Singleton {
    id: root

    property var list: []
    property var monoList: []
    property bool _loaded: false

    // Carga perezosa: fc-list solo se ejecuta al entrar en una página de
    // ajustes que lo necesite. Con force se re-escanea aunque ya esté cargado.
    function refresh(force) {
        if (_loaded && !force)
            return
        _loaded = true
        proc.running = true
    }

    // Dos listados planos de fc-list; el recorte de la primera coma, la
    // deduplicación, el orden y el añadido de las "Nerd Font" a la lista mono
    // se hacen aquí, sin sed/sort/grep.
    property var _allRaw: null
    property var _monoRaw: null

    function _families(txt) {
        const out = []
        const lines = (txt || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const fam = lines[i].split(",")[0].trim()
            if (fam !== "") out.push(fam)
        }
        return out
    }

    function _uniqueSorted(arr) {
        const seen = {}
        const out = []
        for (let i = 0; i < arr.length; i++)
            if (!seen[arr[i]]) { seen[arr[i]] = true; out.push(arr[i]) }
        out.sort()
        return out
    }

    function _finish() {
        if (_allRaw === null || _monoRaw === null)
            return
        const all = _uniqueSorted(_families(_allRaw))
        const nerd = all.filter(n => /nerd font/i.test(n))
        root.list = all
        root.monoList = _uniqueSorted(_families(_monoRaw).concat(nerd))
        _allRaw = null
        _monoRaw = null
    }

    Process {
        id: proc
        // El ':' es el patrón "todas las fuentes"; sin él, "family" se
        // interpreta como patrón de búsqueda y la lista sale vacía (bug que
        // arrastraba también la versión con shell).
        command: ["fc-list", ":", "family"]
        onRunningChanged: if (running) monoProc.running = true
        stdout: StdioCollector {
            onStreamFinished: { root._allRaw = this.text; root._finish() }
        }
    }
    Process {
        id: monoProc
        command: ["fc-list", ":spacing=mono", "family"]
        stdout: StdioCollector {
            onStreamFinished: { root._monoRaw = this.text; root._finish() }
        }
    }
}

