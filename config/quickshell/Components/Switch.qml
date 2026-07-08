import QtQuick
import qs.Config

// Interruptor on/off reutilizable (pista + bolita deslizante).
// onColor: acento de la pista encendida (BT usa accent2). offColor: pista apagada.
// offBorderColor: borde cuando está apagado.
Rectangle {
    id: sw

    property bool  checked: false
    property color onColor: Theme.accent
    property color offColor: Theme.surface
    property color offBorderColor: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)
    signal toggled()

    activeFocusOnTab: enabled
    implicitWidth: Theme.dp(44)
    implicitHeight: Theme.dp(24)
    radius: height / 2
    color: checked ? onColor : offColor
    border.width: activeFocus ? Theme.focusWidth : Theme.hairline
    border.color: activeFocus ? Theme.focusRing : (checked ? onColor : offBorderColor)
    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    Keys.onReturnPressed: sw.toggled()
    Keys.onEnterPressed: sw.toggled()
    Keys.onSpacePressed: sw.toggled()
    Keys.onEscapePressed: Globals.closeAll()

    // Bolita deslizante.
    Rectangle {
        width: parent.height - Theme.dp(6)
        height: width
        radius: height / 2
        y: Theme.dp(3)
        x: sw.checked ? parent.width - width - Theme.dp(3) : Theme.dp(3)
        color: sw.checked ? Theme.bg : Theme.fgDim
        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled()
    }
}
