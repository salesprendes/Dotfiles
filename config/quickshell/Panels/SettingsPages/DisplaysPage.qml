import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Services

// Pantallas
ColumnLayout {
    spacing: Theme.space12

    // Orden / alineación (con 2+ monitores).
    SettingsCard {
        title: I18n.tr("Arrangement"); glyph: "󰍹"
        visible: Displays.monitors.length > 1
        MonitorArrangement { Layout.fillWidth: true }
    }

    // Una tarjeta por monitor: resolución, escala, rotación…
    Repeater {
        model: Displays.monitors
        delegate: MonitorCard {
            required property var modelData
            monitor: modelData
        }
    }

    Text {
        Layout.fillWidth: true
        visible: Displays.monitors.length === 0
        text: I18n.tr("No displays found")
        color: Theme.fgMuted
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
    }
}
