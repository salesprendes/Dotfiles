import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Fila con etiqueta (y descripción opcional) + interruptor a la derecha.
RowLayout {
    id: sr
    property string label: ""
    property string desc: ""
    property bool checked: false
    signal toggled()
    Layout.fillWidth: true
    spacing: Theme.space10
    ColumnLayout {
        Layout.fillWidth: true; spacing: 0
        Text {
            Layout.fillWidth: true
            text: sr.label; color: Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
        }
        Text {
            Layout.fillWidth: true
            visible: sr.desc !== ""
            text: sr.desc; color: Theme.fgMuted
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
            wrapMode: Text.WordWrap
        }
    }
    Switch {
        checked: sr.checked
        offColor: SettingsPalette.settingsControl
        offBorderColor: SettingsPalette.settingsBorder
        onToggled: sr.toggled()
    }
}
