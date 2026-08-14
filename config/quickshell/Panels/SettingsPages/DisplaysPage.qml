import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Services

// Pantallas
SettingsPage {

    // Orden / alineación (con 2+ monitores).
    SettingsCard {
        title: I18n.tr("Arrangement"); glyph: "󰍹"
        shown: Displays.monitors.length > 1
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

    EmptyNote {
        visible: Displays.monitors.length === 0
        text: I18n.tr("No displays found")
    }
}
