import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Reposo: hora, fecha y, si hay, el tiempo. Es lo que la isla enseña cuando no
// pasa nada, así que ocupa el sitio que ocupaba el reloj de la barra.
RowLayout {
    id: root
    spacing: Theme.space10

    ThemedText {
        text: Qt.formatDateTime(Time.now, Time.clockFormat)
        color: Theme.fg
        font.pixelSize: Theme.fontSize
        font.bold: true
    }
    ThemedText {
        visible: Settings.clockShowDate
        text: Time.dateString
        color: Theme.fgDim
        font.pixelSize: Theme.typeBodySmall
    }
    // El separador solo cuando hay dos cosas que separar.
    Rectangle {
        visible: Settings.islandShowWeather && Weather.enabled && Weather.ready
        Layout.preferredWidth: Theme.hairline
        Layout.preferredHeight: Theme.dp(12)
        color: Theme.withAlpha(Theme.overlay, 0.6)
    }
    RowLayout {
        visible: Settings.islandShowWeather && Weather.enabled && Weather.ready
        spacing: Theme.space4
        ThemedText {
            text: Weather.icon
            color: Theme.yellow
            font.pixelSize: Theme.barIconSize
        }
        ThemedText {
            text: Weather.temp
            color: Theme.fgDim
            font.pixelSize: Theme.typeBodySmall
        }
    }
}
