import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config

// Clima — opciones agrupadas en una tarjeta, como el resto de páginas.
SettingsPage {

    SettingsCard {
        title: I18n.tr("Weather widget"); glyph: "󰖕"

        SwitchRow { glyph: "󰖐"; skey: "weatherEnabled"; label: I18n.tr("Enable weather"); checked: Settings.weatherEnabled
            onToggled: Settings.weatherEnabled = !Settings.weatherEnabled }
        SegRow {
            glyph: "󰔏"
            skey: "weatherMetric"
            label: I18n.tr("Temperature unit")
            options: [ { text: "°C", value: true }, { text: "°F", value: false } ]
            current: Settings.weatherMetric
            onPicked: (v) => Settings.weatherMetric = v
        }
        SegRow {
            glyph: "󰑖"
            skey: "weatherRefreshMin"
            label: I18n.tr("Refresh interval")
            options: [ { text: "15 min", value: 15 }, { text: "30 min", value: 30 },
                       { text: "60 min", value: 60 } ]
            current: Settings.weatherRefreshMin
            onPicked: (v) => Settings.weatherRefreshMin = v
        }
        SwitchRow { glyph: "󰖎"; skey: "weatherShowDetails"; label: I18n.tr("Feels like and humidity")
            checked: Settings.weatherShowDetails
            onToggled: Settings.weatherShowDetails = !Settings.weatherShowDetails }
        SwitchRow { glyph: "󰖝"; skey: "weatherShowWind"; label: I18n.tr("Wind")
            desc: I18n.tr("Adds current wind speed")
            checked: Settings.weatherShowWind
            onToggled: Settings.weatherShowWind = !Settings.weatherShowWind }
        SwitchRow { glyph: "󰖙"; skey: "weatherShowSun"; label: I18n.tr("Sunrise and sunset")
            checked: Settings.weatherShowSun
            onToggled: Settings.weatherShowSun = !Settings.weatherShowSun }
        // "Mostrar en la barra" ya no vive aquí: el clima es un widget más y
        // se pone o se quita desde el editor de la barra, como todos.
        Hint {
            text: I18n.tr("To show the weather in the bar, add its widget from Settings ▸ Bar.")
        }
        TextField {
            skey: "weatherLocation"
            Layout.fillWidth: true
            label: I18n.tr("Location"); placeholder: I18n.tr("Automatic (by IP)")
            value: Settings.weatherLocation
            onEdited: (t) => Settings.weatherLocation = t
        }
        Hint {
            skey: "weatherLocation"
            text: I18n.tr("Empty = automatic detection. Enter a city to pin it.")
        }
    }

    SettingsCard {
        title: I18n.tr("Forecast"); glyph: "󰨳"

        SwitchRow { glyph: "󰼶"; skey: "weatherShowForecast"; label: I18n.tr("Show forecast")
            checked: Settings.weatherShowForecast
            onToggled: Settings.weatherShowForecast = !Settings.weatherShowForecast }
        SegRow {
            glyph: "󰃭"
            skey: "weatherForecastDays"
            label: I18n.tr("Forecast days")
            shown: Settings.weatherShowForecast
            options: [ { text: "3", value: 3 }, { text: "5", value: 5 }, { text: "7", value: 7 } ]
            current: Settings.weatherForecastDays
            onPicked: (v) => Settings.weatherForecastDays = v
        }
        SwitchRow { glyph: "󰖗"; skey: "weatherShowRain"; label: I18n.tr("Chance of rain")
            desc: I18n.tr("Daily precipitation probability")
            shown: Settings.weatherShowForecast
            checked: Settings.weatherShowRain
            onToggled: Settings.weatherShowRain = !Settings.weatherShowRain }
    }
}
