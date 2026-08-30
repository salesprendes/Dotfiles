import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Hoja de reposo: el calendario. Es a donde lleva un clic en la isla cuando no
// hay nada más pasando — el gesto de "mira, un reloj; ¿y el mes?".
ColumnLayout {
    id: root
    spacing: Theme.space12
    // Sin implicitWidth: un ColumnLayout se lo reescribe él solo en cada
    // pasada de medida, así que el que había puesto aquí a mano no valía
    // nada. El ancho de una hoja lo pone la ranura de Island.qml, que es
    // quien sabe cuánto mide la hoja.

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            ThemedText {
                text: Qt.formatDateTime(Time.now, Time.clockFormat)
                color: Theme.fg
                font.pixelSize: Theme.sp(28)
                font.weight: Font.Light
            }
            ThemedText {
                text: Time.now.toLocaleDateString(I18n.locale(), Locale.LongFormat)
                color: Theme.fgDim
                font.pixelSize: Theme.typeBodySmall
            }
        }

        ColumnLayout {
            visible: Weather.enabled && Weather.ready
            spacing: 0
            ThemedText {
                Layout.alignment: Qt.AlignRight
                text: Weather.icon + "  " + Weather.temp
                color: Theme.fg
                font.pixelSize: Theme.sp(15)
            }
            ThemedText {
                Layout.alignment: Qt.AlignRight
                text: Weather.location
                color: Theme.fgMuted
                font.pixelSize: Theme.typeLabelSmall
                elide: Text.ElideRight
                Layout.maximumWidth: Theme.dp(140)
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.hairline
        color: Theme.withAlpha(Theme.overlay, 0.45)
    }

    Calendar {
        Layout.fillWidth: true
        showWeekNumbers: false
    }
}
