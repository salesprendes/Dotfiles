import QtQuick
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Píldora pulsable: exportar, compactar, actualizar, un arranque del estado
// vacío. Estaba declarada dentro del panel y hacía falta también en la lámina
// de ajustes, así que vive aquí — misma píldora en los dos sitios en vez de
// dos que se parecen.
Rectangle {
    id: chip

    property string label: ""
    property var onDo: null
    property bool danger: false

    implicitWidth: txt.implicitWidth + Theme.space12 * 2
    implicitHeight: Theme.dp(30)
    radius: height / 2
    color: !enabled ? SettingsPalette.settingsControl
         : ma.containsMouse ? (danger ? Theme.withAlpha(Theme.red, 0.16)
                                      : SettingsPalette.accentSoft)
         : SettingsPalette.settingsControl
    border.width: Theme.hairline
    border.color: SettingsPalette.settingsBorder
    // Entra casi instantáneo y sale con calma: el fondo sigue al
    // puntero, y los 100 ms de una transición normal se notan
    // como retraso (ver Theme.animHover).
    Behavior on color {
        ColorAnimation {
            duration: ma.containsMouse ? Theme.animHover
                                       : Theme.animHoverOut
            easing.type: ma.containsMouse ? Easing.OutCubic
                                          : Easing.InQuad
        }
    }
    scale: ma.pressed ? 0.96 : 1
    Behavior on scale {
        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }
    clip: true

    Ripple { id: ripple }

    Text {
        id: txt
        anchors.centerIn: parent
        text: chip.label
        color: !chip.enabled ? Theme.fgMuted
             : ma.containsMouse ? (chip.danger ? Theme.red : Theme.accentText)
             : Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.typeLabelMedium
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: chip.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (e) => ripple.press(e.x, e.y)
        onClicked: if (chip.onDo) chip.onDo()
    }
}
