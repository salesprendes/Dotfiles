import QtQuick
import QtQuick.Layouts
import qs.Config

// Slider con cabecera (icono + título + valor) para el Centro de control.
// La pista la pone la base reutilizable `Slider` (sin duplicar lógica).
ColumnLayout {
    id: root

    property string icon: ""
    property string title: ""
    property string valueText: ""
    property real value: 0
    property color accent: Theme.accent

    signal moved(real v)

    spacing: Theme.space6

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8

        Text {
            text: root.icon
            visible: root.icon !== ""
            color: root.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize + 1
            Layout.preferredWidth: Theme.controlXS
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            Layout.fillWidth: true
            text: root.title
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            text: root.valueText
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
    }

    Slider {
        Layout.fillWidth: true
        accent: root.accent
        trackColor: Theme.bgAlt
        value: root.value
        onMoved: (v) => root.moved(v)
    }
}
