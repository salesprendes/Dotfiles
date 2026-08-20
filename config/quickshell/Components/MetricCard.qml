import QtQuick
import QtQuick.Layouts
import qs.Config

// Tarjeta de métrica del monitor de sistema: icono + etiqueta + porcentaje
// grande, barra de progreso y un pie descriptivo. Hermana de DetailCard (que
// resuelve las tarjetas de los paneles de detalle), con la forma que piden las
// medidas continuas: CPU, memoria y las que vengan.
//
// La barra se anima solo cuando el panel está a la vista ('animate'): con el
// panel cerrado la animación no se ve y solo cuesta pasadas de composición.
Rectangle {
    id: card

    property string icon: ""
    property string label: ""
    property real ratio: 0            // 0..1, lo que llena la barra
    property string value: ""         // texto grande de la derecha
    property string caption: ""       // pie bajo la barra
    property bool animate: true

    Layout.fillWidth: true
    Layout.preferredWidth: 0
    Layout.fillHeight: true
    radius: Theme.pillRadius
    color: Theme.withAlpha(Theme.bgAlt, 0.7)
    border.width: Theme.hairline
    border.color: Theme.withAlpha(Theme.overlay, 0.5)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space10
        spacing: Theme.space8

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space8
            ThemedText {
                text: card.icon
                color: Theme.accent
                font.pixelSize: Theme.iconSize + 3
                Layout.preferredWidth: 22
                horizontalAlignment: Text.AlignHCenter
            }
            ThemedText {
                text: card.label
                color: Theme.fgDim
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            ThemedText {
                text: card.value
                color: Theme.accent
                font.pixelSize: Theme.fontSize + 4
                font.bold: true
                Layout.preferredWidth: 54
                horizontalAlignment: Text.AlignRight
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.dp(9)
            radius: 5
            color: Theme.withAlpha(Theme.overlay, 0.32)
            Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.max(0, Math.min(1, card.ratio))
                color: Theme.accent
                Behavior on width {
                    enabled: card.animate
                    NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
                }
            }
        }

        ThemedText {
            Layout.fillWidth: true
            text: card.caption
            color: Theme.fgMuted
            font.pixelSize: Theme.fontSize - 2
            elide: Text.ElideRight
        }
    }
}
