import QtQuick
import QtQuick.Layouts
import qs.Config

// Casilla cuadrada de una plantilla (Ajustes → Plantillas). Toda la casilla
// es el área de toque; no lleva interruptor aparte. 'active' solo decide el
// aspecto (rellena de acento o solo con borde) — el significado del toque
// (activar o desactivar) lo decide quien la usa, vía 'toggled'.
Rectangle {
    id: chip

    property string glyph: ""
    property string label: ""
    property bool active: false
    signal toggled()

    Layout.preferredHeight: Theme.dp(60)
    radius: Theme.pillRadius
    border.width: Theme.hairline
    border.color: chip.active ? SettingsPalette.tileBorder : SettingsPalette.settingsBorder
    color: chip.active
           ? (chipMa.containsMouse ? Theme.withAlpha(Theme.accent, Theme.isDark ? 0.32 : 0.36) : SettingsPalette.accentSoft)
           : (chipMa.containsMouse ? SettingsPalette.settingsHover : SettingsPalette.settingsControl)

    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    MouseArea {
        id: chipMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.toggled()
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Theme.space2

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: chip.glyph
            color: chip.active ? Theme.accent : Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize + 1
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: chip.width - Theme.space8
            text: chip.label
            color: chip.active ? Theme.fg : Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
            font.bold: chip.active
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
