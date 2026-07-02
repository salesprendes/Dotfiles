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
    readonly property bool hovered: ma.containsMouse || activeFocus

    signal clicked()

    activeFocusOnTab: enabled
    implicitWidth: diameter
    implicitHeight: diameter
    radius: height / 2
    // Si el fondo base es transparente, funde hacia el tono del hover con
    // alfa 0: "transparent" es negro con alfa 0 y el fundido de salida
    // pasaba por una sombra oscura.
    color: hovered ? hoverColor
         : (baseColor.a === 0 ? Qt.rgba(hoverColor.r, hoverColor.g, hoverColor.b, 0) : baseColor)
    border.width: activeFocus ? Theme.focusWidth : 0
    border.color: Theme.focusRing
    Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

    Keys.onReturnPressed: btn.clicked()
    Keys.onEnterPressed: btn.clicked()
    Keys.onSpacePressed: btn.clicked()
    Keys.onEscapePressed: Globals.closeAll()

    Text {
        anchors.centerIn: parent
        text: btn.icon
        color: btn.hovered ? btn.hoverIconColor : btn.iconColor
        font.family: Theme.fontFamily
        font.pixelSize: btn.iconPixelSize
        // El glifo funde a la vez que el fondo; antes saltaba de golpe.
        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
