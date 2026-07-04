//  Botón circular de energía con etiqueta deslizante e iconos animados.
//  Alcanzable con Tab (el foco se pinta igual que el hover); Espacio o
//  Enter lo activan, igual que un click.
import QtQuick
import Quickshell
import qs.Modules.Greeter

Rectangle {
    id: pb
    property string glyph: ""
    property string label: ""
    property var    cmd: []
    property bool   spin: false     // gira el icono al pasar el ratón

    // Resaltado unificado ratón/teclado.
    readonly property bool hl: pbMa.containsMouse || pb.activeFocus

    activeFocusOnTab: true
    Keys.onSpacePressed:  Quickshell.execDetached(pb.cmd)
    Keys.onReturnPressed: Quickshell.execDetached(pb.cmd)
    Keys.onEnterPressed:  Quickshell.execDetached(pb.cmd)
    onActiveFocusChanged: if (activeFocus && pb.spin) spinAnim.restart()

    width: Theme.dp(42); height: Theme.dp(42); radius: width / 2

    // Etiqueta que se desliza hacia arriba y aparece al hover/foco.
    Text {
        id: pbLabel
        text: pb.label
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: Theme.dp(8)
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: Theme.sp(11)
        opacity: pb.hl ? 1 : 0
        visible: opacity > 0.01
        property real slide: pb.hl ? 0 : Theme.dp(6)
        transform: Translate { y: pbLabel.slide }
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on slide { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    color: pb.hl ? Theme.alpha(Theme.surfaceHi, 0.9)
                 : Theme.alpha(Theme.surface, 0.6)
    border.width: 1
    border.color: pb.hl ? Theme.alpha(Theme.accent, 0.5)
                        : Theme.alpha(Theme.overlay, 0.45)
    // Escala: crece al hover/foco, se hunde al pulsar (sin coste en reposo).
    scale: pbMa.pressed ? 0.9 : pb.hl ? 1.12 : 1.0
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
    Behavior on color { ColorAnimation { duration: 130 } }
    Behavior on border.color { ColorAnimation { duration: 130 } }

    Text {
        id: pbIcon
        anchors.centerIn: parent
        text: pb.glyph
        color: pb.hl ? Theme.accent : Theme.fgDim
        font.family: Theme.font
        font.pixelSize: Theme.sp(18)
        Behavior on color { ColorAnimation { duration: 130 } }
        RotationAnimation {
            id: spinAnim
            target: pbIcon
            from: 0; to: 360
            duration: 520
            easing.type: Easing.InOutCubic
        }
    }
    MouseArea {
        id: pbMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (pb.spin) spinAnim.restart()
        onClicked: Quickshell.execDetached(pb.cmd)
    }
}
