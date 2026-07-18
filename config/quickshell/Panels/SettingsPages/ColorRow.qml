import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Panels.SettingsPages

// Selector de color con muestras (swatches) y etiqueta.
ColumnLayout {
    id: cr
    property string label: ""
    property var colors: []
    property color current: Theme.accent
    property string currentName: ""
    signal picked(var c)

    // Filtro de la ventana de Ajustes (buscador + "solo modificados").
    // OPT-IN: sin 'skey' la fila no se filtra nunca, así el mismo componente
    // sigue funcionando fuera de Ajustes. 'shown' es la condición propia de la
    // página (p. ej. "solo si hay batería"), que se combina con el filtro.
    property string skey: ""
    property string cardTitle: ""
    property bool shown: true
    readonly property bool matches: SettingsFilter.accepts(
        cr.label + " " + cr.cardTitle, cr.skey)
    visible: cr.shown && cr.matches
    Layout.fillWidth: true
    spacing: Theme.space6

    // Helpers null-safe: un modelData transitorio indefinido reventaría Qt.colorEqual.
    function _hexOf(m) {
        if (m === undefined || m === null) return ""
        return Settings.colorHex(m && m.color !== undefined ? m.color : m).toLowerCase()
    }
    function _nameOf(m) { return (m && m.name !== undefined) ? m.name : "" }
    function _isSel(m) {
        return currentName !== "" ? currentName === _nameOf(m)
                                  : Settings.colorHex(current).toLowerCase() === _hexOf(m)
    }

    // Dedup aquí (no por-delegado) para que los delegados no toquen 'index'
    // y no salte "index is not defined". Precomputa hex/nombres una sola vez.
    readonly property var visibleSwatches: {
        const arr = colors || []
        const n = arr.length
        const hexes = new Array(n)
        const names = new Array(n)
        for (let i = 0; i < n; i++) { hexes[i] = _hexOf(arr[i]); names[i] = _nameOf(arr[i]) }
        const selHex = currentName === "" ? Settings.colorHex(current).toLowerCase() : ""
        const out = []
        for (let i = 0; i < n; i++) {
            let dup = false
            for (let j = 0; j < i; j++)
                if (hexes[j] === hexes[i]) { dup = true; break }
            let selAfter = false
            for (let j = i + 1; j < n; j++)
                if (names[j] === currentName && hexes[j] === hexes[i]) { selAfter = true; break }
            const isSel = currentName !== "" ? names[i] === currentName : hexes[i] === selHex
            if ((!dup && !selAfter) || isSel)
                out.push(arr[i])
        }
        return out
    }

    Text {
        text: cr.label; color: Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
    }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.space8
        Repeater {
            model: cr.visibleSwatches
            delegate: Rectangle {
                id: swatch
                required property var modelData
                readonly property string swatchName: cr._nameOf(modelData)
                readonly property string swatchLabel: (modelData && modelData.label !== undefined) ? modelData.label : swatchName
                readonly property color swatchColor: (modelData && modelData.color !== undefined) ? modelData.color
                                                   : ((modelData !== undefined && modelData !== null) ? modelData : Theme.accent)
                readonly property bool sel: cr._isSel(modelData)
                width: Theme.dp(76)
                height: Theme.dp(62)
                radius: Theme.pillRadius
                color: sel ? Qt.rgba(swatchColor.r, swatchColor.g, swatchColor.b, 0.22)
                           : swMa.containsMouse ? SettingsPalette.settingsHover : SettingsPalette.settingsControl
                border.width: sel ? Math.max(1, Theme.dp(2)) : Theme.hairline
                border.color: sel ? swatchColor : SettingsPalette.settingsBorder
                scale: swMa.containsMouse ? 1.08 : 1
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on scale { NumberAnimation { duration: Theme.animFast } }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Theme.space4

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: Theme.controlS
                        height: Theme.controlS
                        radius: height / 2
                        color: swatch.swatchColor
                        border.width: Theme.hairline
                        border.color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.45)
                        Text {
                            anchors.centerIn: parent
                            visible: swatch.sel
                            text: "󰄬"; color: Theme.bg
                            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize - 2
                        }
                    }

                    Text {
                        Layout.preferredWidth: swatch.width - Theme.space8
                        Layout.alignment: Qt.AlignHCenter
                        text: I18n.tr(swatch.swatchLabel)
                        color: swatch.sel ? Theme.fg : Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 5
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: swMa
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cr.picked(modelData)
                }
            }
        }
    }
}
