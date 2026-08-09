import QtQuick
import QtQuick.Layouts
import qs.Config

RowLayout {
    id: root

    property string icon: ""
    property real value: 0.0
    property color accent: Theme.accent
    property color trackColor: Theme.sliderTrack
    signal moved(real v)

    // Lógica de arrastre/teclado compartida (ver Components/SliderDrag.qml).
    SliderDrag { id: drag; control: root }

    activeFocusOnTab: enabled
    spacing: Theme.spacing + Theme.space2

    Keys.onLeftPressed: drag.nudge(-1)
    Keys.onDownPressed: drag.nudge(-1)
    Keys.onRightPressed: drag.nudge(1)
    Keys.onUpPressed: drag.nudge(1)
    Keys.onEscapePressed: Globals.closeAll()

    Text {
        text: root.icon
        visible: root.icon !== ""
        color: root.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize + 1
        // Sin icono, sin hueco: la pista usa todo el ancho.
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

        Rectangle {
            id: fill
            width: Math.max(height, drag.shownValue * parent.width)
            height: parent.height
            radius: parent.radius
            color: root.accent
            // Suaviza cambios externos/teclado, pero NO al arrastrar (ahí sigue al dedo).
            // Theme.animFast 0 = sin animación.
            Behavior on width { enabled: !drag.dragging; NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
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
            x: Math.min(parent.width - width, Math.max(0, drag.shownValue * parent.width - width / 2))
            // Glide del agarre + leve crecida al arrastrar. El glide en X se apaga al
            // arrastrar para seguir al puntero 1:1.
            scale: ma.pressed || root.activeFocus ? 1.18 : 1.0
            Behavior on x { enabled: !drag.dragging; NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            anchors.margins: -Theme.space6
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            function ratio(mx) {
                // El MouseArea sobresale del track (margins negativos): hay que mapear
                // a coordenadas del track para no descuadrar.
                return mapToItem(track, mx, 0).x / track.width
            }
            onPressed: (m) => drag.press(ratio(m.x))
            onPositionChanged: (m) => { if (pressed) drag.update(ratio(m.x)) }
            onReleased: drag.release()
            onCanceled: drag.release()
        }
    }
}
