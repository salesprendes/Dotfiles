pragma Singleton

import QtQuick
import Quickshell
import qs.Config

// Índice de ajustes buscables, construido solo. Monta cada página fuera de
// pantalla una a una con el mismo Loader que usa la ventana, recorre su árbol de
// objetos buscando filas con 'skey' + 'label' —el mismo contrato que usa
// SettingsFilter.accepts()— y las destruye antes de montar la siguiente.
//
// Un ajuste nuevo en cualquier página aparece solo en la próxima construcción:
// no hay una lista aparte que mantener sincronizada.
Singleton {
    id: root

    readonly property var pageSources: ({
        "theme":     "../Panels/SettingsPages/ThemePage.qml",
        "font":      "../Panels/SettingsPages/FontPage.qml",
        "terminal":  "../Panels/SettingsPages/TerminalPage.qml",
        "wallpaper": "../Panels/SettingsPages/WallpaperPage.qml",
        "bar":       "../Panels/SettingsPages/BarPage.qml",
        "dock":      "../Panels/SettingsPages/DockPage.qml",
        "clock":     "../Panels/SettingsPages/ShellPage.qml",
        "displays":  "../Panels/SettingsPages/DisplaysPage.qml",
        "network":   "../Panels/SettingsPages/NetworkPage.qml",
        "notif":     "../Panels/SettingsPages/NotifPage.qml"
    })
    readonly property var _catKeys: Object.keys(pageSources)

    property var entries: []
    property bool built: false
    property bool _building: false
    property int _buildAt: 0
    property var _collected: []

    // Se dispara la primera vez que se abre Ajustes o Spotlight, no al arrancar
    // el shell: sin usar ninguna de las dos cosas no vale la pena montar once
    // páginas. Spotlight cuenta porque, si no, los ajustes no aparecen en el
    // buscador hasta haber abierto la ventana una vez por sesión.
    //
    // La construcción es asíncrona y de una página cada vez, así que abrir
    // Spotlight no se frena; al terminar, 'built' cambia y la lista de
    // candidatos se rehace sola.
    Connections {
        target: Globals
        function onSettingsOpenChanged() {
            if (Globals.settingsOpen)
                root.beginBuild()
        }
        function onSpotlightOpenChanged() {
            if (Globals.spotlightOpen)
                root.beginBuild()
        }
    }

    // QML no crea un singleton hasta que alguien lo toca, así que el Connections
    // de arriba no existe todavía cuando Spotlight se abre por primera vez:
    // quien toca este singleton es el propio Spotlight al leer 'built', o sea
    // después de que la señal haya pasado. Por eso, al nacer, hay que mirar si
    // el motivo ya se ha dado.
    Component.onCompleted: {
        if (Globals.spotlightOpen || Globals.settingsOpen)
            root.beginBuild()
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

    // Recorre el árbol real de objetos instanciados, así que da igual cuántos
    // contenedores haya de por medio o si una fila vive dentro de un Repeater:
    // si llegó a existir, se encuentra.
    function _walk(item, cat, out) {
        if (!item)
            return
        if (item.skey !== undefined && item.skey !== "" && item.label !== undefined && item.label !== "")
            out.push({
                cat: cat,
                skey: item.skey,
                label: item.label,
                desc: (item.desc !== undefined ? item.desc : ""),
                // Los alias de la fila viajan con la entrada, así que el mismo
                // texto encuentra el ajuste dentro de la ventana y desde
                // Spotlight.
                alias: (Array.isArray(item.aliases) ? item.aliases.join(" ") : "")
            })
        const kids = item.children || []
        for (let i = 0; i < kids.length; i++)
            _walk(kids[i], cat, out)
    }

    // Página de usar y tirar: monta, recoge, descarga y pasa a la siguiente.
    // Nunca hay más de una fuera de pantalla a la vez.
    Loader {
        id: scanLoader
        property string cat: ""
        // Carga asíncrona: esto se dispara justo cuando la ventana se está
        // abriendo, y de forma síncrona se nota un tirón.
        asynchronous: true
        onLoaded: {
            const found = []
            root._walk(item, cat, found)
            root._collected = root._collected.concat(found)
            source = ""
            root._buildAt++
            root._buildNext()
        }

        // Si una página no carga hay que seguir igualmente: parándose ahí,
        // '_buildAt' no avanza, '_building' se queda en true y 'built' no llega
        // a ser cierto nunca, con lo que ningún ajuste aparecería en el
        // buscador y sin ningún error que lo explique.
        onStatusChanged: {
            if (scanLoader.status !== Loader.Error)
                return
            console.warn("SettingsSearchIndex: no se pudo montar la página '"
                         + scanLoader.cat + "', se indexa sin ella")
            scanLoader.source = ""
            root._buildAt++
            root._buildNext()
        }
    }

    // Comparación plegada, la misma que usa el filtro de la página activa, para
    // que ambos buscadores encuentren "Posición" escribiendo "posicion".
    function matches(entry, q) {
        return SettingsFilter.fold(entry.label + " " + entry.desc + " "
                                   + (entry.alias || "")).indexOf(q) !== -1
    }

    // Resultados para una consulta; excludeCat deja fuera una categoría, la que
    // ya se ve filtrada debajo, para no duplicarla.
    function search(query, excludeCat) {
        const q = SettingsFilter.fold(String(query || "").trim())
        if (q === "")
            return []
        return root.entries.filter(e => (excludeCat === undefined || e.cat !== excludeCat) && root.matches(e, q))
    }
}
