import QtQuick
import QtQuick.Layouts
import qs.Config

RowLayout {
    id: root

    property string icon: ""
    property real value: 0.0
    property color accent: Theme.accent
    property color trackColor: Theme.surface
    signal moved(real v)

    activeFocusOnTab: enabled
    spacing: Theme.spacing + Theme.space2

    function nudge(delta) {
        const step = 0.05
        root.moved(Math.max(0, Math.min(1, root.value + delta * step)))
    }

    Keys.onLeftPressed: nudge(-1)
    Keys.onDownPressed: nudge(-1)
    Keys.onRightPressed: nudge(1)
    Keys.onUpPressed: nudge(1)
    Keys.onEscapePressed: Globals.closeAll()

    Text {
        text: root.icon
        visible: root.icon !== ""
        color: root.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize + 1
        // Sin icono → sin hueco (la pista usa todo el ancho).
        Layout.preferredWidth: root.icon !== "" ? Theme.dp(20) : 0
        horizontalAlignment: Text.AlignHCenter
    }

    Rectangle {
        id: track
        Layout.fillWidth: true
        implicitHeight: Theme.space8
        radius: height / 2
        color: root.trackColor
        border.width: root.activeFocus ? Theme.focusWidth : 0
        border.color: Theme.focusRing
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        Rectangle {
            id: fill
            width: Math.max(height, root.value * parent.width)
            height: parent.height
            radius: parent.radius
            color: root.accent
            // Suavizado global del relleno (token compartido Theme.animFast:
            // 0 = sin animación si el usuario lo desactiva en ajustes).
            Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: handle
            width: Theme.space16
            height: Theme.space16
            radius: height / 2
            color: Theme.fg
            border.width: Math.max(2, Theme.dp(3))
            border.color: root.accent
            y: (parent.height - height) / 2
            x: Math.min(parent.width - width, Math.max(0, root.value * parent.width - width / 2))
            // Glide del agarre + leve crecida táctil al arrastrar.
            scale: ma.pressed || root.activeFocus ? 1.18 : 1.0
            Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            anchors.margins: -Theme.space6
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            function update(mx) {
                const v = Math.max(0, Math.min(1, mx / track.width))
                root.moved(v)
            }
            onPressed: (m) => update(m.x)
            onPositionChanged: (m) => { if (pressed) update(m.x) }
        }
    }
}
