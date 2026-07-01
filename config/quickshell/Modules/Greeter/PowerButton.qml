//  Botón circular de energía con etiqueta deslizante e iconos animados.
import QtQuick
import Quickshell
import qs.Modules.Greeter

Rectangle {
    id: pb
    property string glyph: ""
    property string label: ""
    property var    cmd: []
    property bool   spin: false     // gira el icono al pasar el ratón

    width: Theme.dp(42); height: Theme.dp(42); radius: width / 2

    // Etiqueta que se desliza hacia arriba y aparece al hover.
    Text {
        id: pbLabel
        text: pb.label
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: Theme.dp(8)
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: Theme.sp(11)
        opacity: pbMa.containsMouse ? 1 : 0
        visible: opacity > 0.01
        property real slide: pbMa.containsMouse ? 0 : Theme.dp(6)
        transform: Translate { y: pbLabel.slide }
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on slide { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    color: pbMa.containsMouse ? Theme.alpha(Theme.surfaceHi, 0.9)
                              : Theme.alpha(Theme.surface, 0.6)
    border.width: 1
    border.color: pbMa.containsMouse ? Theme.alpha(Theme.accent, 0.5)
                                     : Theme.alpha(Theme.overlay, 0.45)
    // Escala: crece al hover, se hunde al pulsar (sin coste en reposo).
    scale: pbMa.pressed ? 0.9 : pbMa.containsMouse ? 1.12 : 1.0
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
    Behavior on color { ColorAnimation { duration: 130 } }
    Behavior on border.color { ColorAnimation { duration: 130 } }

    Text {
        id: pbIcon
        anchors.centerIn: parent
        text: pb.glyph
        color: pbMa.containsMouse ? Theme.accent : Theme.fgDim
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
