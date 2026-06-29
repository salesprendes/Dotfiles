import QtQuick
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Botón con texto en forma de píldora. Unifica los botones que
//  antes se recreaban inline en los modales (Cancel / Connect /
//  Apply…). 'primary' = relleno de acento (acción principal);
//  si no, superficie neutra. Respeta 'enabled' (atenúa y bloquea).
// ─────────────────────────────────────────────────────────────
Rectangle {
    id: btn

    property string text: ""
    property bool   primary: false
    readonly property bool hovered: ma.containsMouse || activeFocus
    signal clicked()

    activeFocusOnTab: enabled
    implicitWidth: label.implicitWidth + Theme.controlS
    implicitHeight: Theme.dp(32)
    radius: Theme.pillRadius
    opacity: enabled ? 1 : 0.5
    color: primary
           ? (hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
           : (hovered ? Theme.surfaceHi : Theme.surface)
    border.width: activeFocus ? Theme.focusWidth : 0
    border.color: Theme.focusRing
    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    Keys.onReturnPressed: btn.clicked()
    Keys.onEnterPressed: btn.clicked()
    Keys.onSpacePressed: btn.clicked()
    Keys.onEscapePressed: Globals.closeAll()

    Text {
        id: label
        anchors.centerIn: parent
        text: btn.text
        color: btn.primary ? Theme.bg : Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: btn.primary
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
