import QtQuick
import QtQuick.Layouts
import qs.Config

// Tarjeta de los paneles de detalle (audio, micro, WiFi, Bluetooth, energía):
// contorno y cabecera icono+título compartidos. Los extras de cabecera
// (estado, spinner, interruptor…) se añaden vía 'header'; el cuerpo de la
// tarjeta son los hijos normales.
Rectangle {
    id: card

    property string title: ""
    property string icon: ""
    property color iconColor: Theme.accent
    default property alias content: body.data
    property alias header: headerRow.data

    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + Theme.space16 * 2
    radius: Theme.barRadius
    color: Theme.withAlpha(Theme.surface, 0.62)
    border.width: Theme.hairline
    border.color: Theme.withAlpha(Theme.overlay, 0.34)

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: Theme.space14
        spacing: Theme.space10

        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: Theme.space8
            ThemedText {
                text: card.icon
                color: card.iconColor
                font.pixelSize: Theme.iconSize + 1
            }
            ThemedText {
                Layout.fillWidth: true
                text: card.title
                color: Theme.fg
                font.bold: true
                elide: Text.ElideRight
            }
        }
    }
}
