import QtQuick
import qs.Config

// Botón Material 3 en tres variantes:
//
//   primary  → relleno de acento. La acción principal, una por diálogo.
//   outlined → solo contorno. Acción secundaria con peso.
//   (nada)   → relleno tonal neutro. El resto.
//
// La diferencia con lo que había: al señalar o pulsar, el botón NO cambia de
// color de fondo. Se le superpone una capa del color de su propio contenido
// con una opacidad fija (ver Theme.stateHover / statePressed). Es lo que hace
// M3, y tiene una ventaja concreta sobre aclarar el fondo: funciona igual
// sobre cualquier color, así que el botón de acento y el neutro reaccionan
// con la misma intensidad en vez de cada uno a su manera.
Rectangle {
    id: btn

    property string text: ""
    property bool   primary: false
    property bool   outlined: false
    readonly property bool hovered: ma.containsMouse || activeFocus
    signal clicked()

    activeFocusOnTab: enabled
    implicitWidth: label.implicitWidth + Theme.dp(32)
    implicitHeight: Theme.dp(36)
    radius: height / 2
    opacity: enabled ? 1 : 0.38          // M3 usa 38 % para lo deshabilitado

    color: primary ? Theme.accent
         : outlined ? "transparent"
                    : Theme.withAlpha(Theme.surfaceHi, 0.9)
    border.width: activeFocus ? Theme.focusWidth
                : outlined ? Math.max(1, Theme.hairline) : 0
    border.color: activeFocus ? Theme.focusRing : Theme.withAlpha(Theme.overlay, 0.55)
    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    // Encogida al pulsar: acuse físico del clic, corto para que no distraiga.
    scale: ma.pressed ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

    Keys.onReturnPressed: btn.clicked()
    Keys.onEnterPressed: btn.clicked()
    Keys.onSpacePressed: btn.clicked()
    Keys.onEscapePressed: Globals.closeAll()

    // Capa de estado, por encima del fondo y por debajo del texto.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: btn.primary ? Theme.bg : Theme.fg
        opacity: !btn.enabled ? 0
               : ma.pressed ? Theme.statePressed
               : btn.hovered ? Theme.stateHover : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    ThemedText {
        id: label
        anchors.centerIn: parent
        text: btn.text
        color: btn.primary ? Theme.bg : (btn.outlined ? Theme.accent : Theme.fgDim)
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
