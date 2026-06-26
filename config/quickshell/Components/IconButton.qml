import QtQuick
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Botón redondo con glifo (Nerd Font) y resaltado al pasar el
//  ratón. Unifica el patrón repetido por cabeceras de paneles.
//  Personalizable: color base/hover del fondo y del icono.
// ─────────────────────────────────────────────────────────────
Rectangle {
    id: btn

    property string icon: ""
    property real   diameter: Theme.controlM
    property int    iconPixelSize: Theme.iconSize
    property color  baseColor: Theme.surface
    property color  hoverColor: Theme.accent
    property color  iconColor: Theme.fgDim
    property color  hoverIconColor: Theme.bg
    readonly property bool hovered: ma.containsMouse

    signal clicked()

    implicitWidth: diameter
    implicitHeight: diameter
    radius: height / 2
    color: ma.containsMouse ? hoverColor : baseColor
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Text {
        anchors.centerIn: parent
        text: btn.icon
        color: ma.containsMouse ? btn.hoverIconColor : btn.iconColor
        font.family: Theme.fontFamily
        font.pixelSize: btn.iconPixelSize
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
