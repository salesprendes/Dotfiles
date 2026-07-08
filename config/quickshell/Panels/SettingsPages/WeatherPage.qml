import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config

// Clima
ColumnLayout {
    spacing: Theme.space14

    SwitchRow { label: I18n.tr("Enable weather"); checked: Settings.weatherEnabled
        onToggled: Settings.weatherEnabled = !Settings.weatherEnabled }
    SegRow {
        label: I18n.tr("Temperature unit")
        options: [ { text: "°C", value: true }, { text: "°F", value: false } ]
        current: Settings.weatherMetric
        onPicked: (v) => Settings.weatherMetric = v
    }
    SegRow {
        label: I18n.tr("Refresh interval")
        options: [ { text: "15 min", value: 15 }, { text: "30 min", value: 30 },
                   { text: "60 min", value: 60 } ]
        current: Settings.weatherRefreshMin
        onPicked: (v) => Settings.weatherRefreshMin = v
    }
    TextField {
        Layout.fillWidth: true
        label: I18n.tr("Location"); placeholder: I18n.tr("Automatic (by IP)")
        value: Settings.weatherLocation
        onEdited: (t) => Settings.weatherLocation = t
    }
    Hint {
        text: I18n.tr("Empty = automatic detection. Enter a city to pin it.")
    }
}
