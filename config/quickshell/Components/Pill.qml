import QtQuick
import QtQuick.Layouts
import qs.Config

// Contenedor "pill" reutilizable. El contenido va a un RowLayout interno centrado,
// cuyo ancho intrínseco dimensiona la pastilla (sin binding loops).
// Click, click derecho y rueda expuestos como señales.
//
// Lenguaje visual: superficie tonal SIN borde (el borde queda reservado al
// anillo de foco de teclado). La interacción se comunica con movimiento: la
// píldora se eleva un pelo bajo el ratón, se hunde al pulsar y muestra un
// punto de acento debajo cuando el panel que gobierna está abierto ('active').
Rectangle {
    id: pill

    property bool interactive: false
    property bool hoverHighlight: false
    property bool hoverCursor: false
    // El panel que abre esta píldora está abierto: enciende el punto inferior.
    property bool active: false
    readonly property bool hovered: ma.containsMouse || hoverHandler.hovered || activeFocus
    property int spacing: Theme.spacing
    default property alias content: row.data

    signal clicked(var mouse)
    signal rightClicked()
    signal scrolled(real dy)

    implicitWidth: row.implicitWidth + Theme.pad * 2
    implicitHeight: Theme.barPillHeight

    activeFocusOnTab: interactive
    radius: Theme.pillRadius
    color: (interactive || hoverHighlight) && hovered ? Theme.surfaceHi : Theme.pillBg
    border.width: activeFocus ? Theme.focusWidth : 0
    border.color: Theme.focusRing

    // Elevación al pasar y hundimiento al pulsar: escala visual pura (no
    // afecta a la disposición de la barra).
    scale: ma.pressed ? 0.95
         : (interactive || hoverHighlight) && hovered ? 1.04
         : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    // Punto indicador de "panel abierto": nace y muere con un pop de escala.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.dp(2)
        width: Theme.dp(4); height: Theme.dp(4)
        radius: width / 2
        color: Theme.accent
        scale: pill.active ? 1 : 0
        opacity: pill.active ? 1 : 0
        Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    Keys.onReturnPressed: pill.clicked({ x: -999999, y: -999999, button: Qt.LeftButton })
    Keys.onEnterPressed: pill.clicked({ x: -999999, y: -999999, button: Qt.LeftButton })
    Keys.onSpacePressed: pill.clicked({ x: -999999, y: -999999, button: Qt.LeftButton })
    Keys.onEscapePressed: Globals.closeAll()

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: pill.interactive || pill.hoverCursor
        hoverEnabled: pill.interactive || pill.hoverCursor
        cursorShape: (pill.interactive || pill.hoverCursor) ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: pill.interactive ? (Qt.LeftButton | Qt.RightButton) : Qt.NoButton
        onClicked: (m) => {
            if (m.button === Qt.RightButton) pill.rightClicked()
            else pill.clicked(m)
        }
        // La rueda se gestiona aquí y no con un WheelHandler: al MouseArea le
        // llegan los eventos por propagación aunque el cursor esté sobre un
        // hijo con su propio MouseArea (los puntos de Workspaces); el handler
        // no los recibía en esa situación. Si la píldora no es interactiva, el
        // evento se deja pasar sin consumir.
        onWheel: (e) => {
            if (pill.interactive) pill.scrolled(e.angleDelta.y)
            else e.accepted = false
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: pill.spacing
    }

    HoverHandler {
        id: hoverHandler
        enabled: pill.hoverCursor || pill.hoverHighlight
        cursorShape: pill.hoverCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

}
