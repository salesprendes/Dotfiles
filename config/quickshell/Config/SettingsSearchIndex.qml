pragma Singleton

import QtQuick
import Quickshell
import qs.Config

// Índice de ajustes buscables — construido SOLO, nada a mano. Al abrir
// Ajustes por primera vez (ver Connections a Globals.settingsOpen), monta
// cada página fuera de pantalla una a una (mismo Loader que usa la propia
// ventana para mostrarlas), recorre su árbol de objetos buscando filas con
// 'skey' + 'label' — el mismo contrato que ya usa SettingsFilter.accepts()
// para decidir qué fila esconder — y las destruye antes de montar la
// siguiente. Si se añade un ajuste nuevo a cualquier página, aparece solo en
// la próxima construcción del índice: no hay una lista aparte que
// mantener sincronizada a mano.
Singleton {
    id: root

    readonly property var pageSources: ({
        "theme":     "../Panels/SettingsPages/ThemePage.qml",
        "font":      "../Panels/SettingsPages/FontPage.qml",
        "terminal":  "../Panels/SettingsPages/TerminalPage.qml",
        "templates": "../Panels/SettingsPages/TemplatesPage.qml",
        "wallpaper": "../Panels/SettingsPages/WallpaperPage.qml",
        "bar":       "../Panels/SettingsPages/BarPage.qml",
        "clock":     "../Panels/SettingsPages/ShellPage.qml",
        "displays":  "../Panels/SettingsPages/DisplaysPage.qml",
        "network":   "../Panels/SettingsPages/NetworkPage.qml",
        "weather":   "../Panels/SettingsPages/WeatherPage.qml",
        "notif":     "../Panels/SettingsPages/NotifPage.qml"
    })
    readonly property var _catKeys: Object.keys(pageSources)

    property var entries: []
    property bool built: false
    property bool _building: false
    property int _buildAt: 0
    property var _collected: []

    // Se dispara sola la primera vez que se abre Ajustes (no al arrancar el
    // shell: si el usuario nunca abre Ajustes, no vale la pena montar once
    // páginas por nada).
    Connections {
        target: Globals
        function onSettingsOpenChanged() {
            if (Globals.settingsOpen)
                root.beginBuild()
        }
    }

    function beginBuild() {
        if (built || _building)
            return
        _building = true
        _buildAt = 0
        _collected = []
        _buildNext()
    }

    function _buildNext() {
        if (_buildAt >= _catKeys.length) {
            entries = _collected
            built = true
            _building = false
            return
        }
        scanLoader.cat = _catKeys[_buildAt]
        scanLoader.source = pageSources[scanLoader.cat]
    }

    // Recorre el árbol real de objetos instanciados (item.children): así da
    // igual cuántos SettingsCard/ColumnLayout haya de por medio, o si una
    // fila vive dentro de un Repeater — si llegó a existir, se encuentra.
    function _walk(item, cat, out) {
        if (!item)
            return
        if (item.skey !== undefined && item.skey !== "" && item.label !== undefined && item.label !== "")
            out.push({
                cat: cat,
                skey: item.skey,
                label: item.label,
                desc: (item.desc !== undefined ? item.desc : "")
            })
        const kids = item.children || []
        for (let i = 0; i < kids.length; i++)
            _walk(kids[i], cat, out)
    }

    // Página "de usar y tirar": monta, recoge, descarga, pasa a la
    // siguiente. Nunca hay más de una página fuera de pantalla a la vez.
    Loader {
        id: scanLoader
        property string cat: ""
        // Igual que pageLoader en Settings.qml: sin esto se nota un tirón
        // (esto se dispara justo cuando la ventana está abriéndose).
        asynchronous: true
        onLoaded: {
            const found = []
            root._walk(item, cat, found)
            root._collected = root._collected.concat(found)
            source = ""
            root._buildAt++
            root._buildNext()
        }
    }

    // Comparación plegada (minúsculas, sin diacríticos), la misma que usa el
    // filtro de la página activa (SettingsFilter.fold): ambos buscadores
    // encuentran "Posición" escribiendo "posicion".
    function matches(entry, q) {
        return SettingsFilter.fold(entry.label + " " + entry.desc).indexOf(q) !== -1
    }

    // Resultados para una consulta, ya filtrados; excludeCat (opcional) deja
    // fuera una categoría (la que ya se ve filtrada debajo, para no
    // duplicarla).
    function search(query, excludeCat) {
        const q = SettingsFilter.fold(String(query || "").trim())
        if (q === "")
            return []
        return root.entries.filter(e => (excludeCat === undefined || e.cat !== excludeCat) && root.matches(e, q))
    }
}
