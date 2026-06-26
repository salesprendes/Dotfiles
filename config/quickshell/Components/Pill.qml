import QtQuick
import QtQuick.Layouts
import qs.Config

// Contenedor "pill" reutilizable. El contenido va a un RowLayout
// interno (centrado), cuyo ancho intrínseco dimensiona la pastilla
// → sin binding loops. Trae interacción integrada (click, click
// derecho, rueda) expuesta como señales.
Rectangle {
    id: pill

    property bool interactive: false
    property bool hoverHighlight: false
    property bool hoverCursor: false
    readonly property bool hovered: ma.containsMouse || hoverHandler.hovered
    property int spacing: Theme.spacing
    default property alias content: row.data

    signal clicked(var mouse)
    signal rightClicked()
    signal scrolled(real dy)

    implicitWidth: row.implicitWidth + Theme.pad * 2
    implicitHeight: Theme.barHeight - Theme.barMargin * 2

    radius: Theme.pillRadius
    color: (interactive || hoverHighlight) && hovered ? Theme.surfaceHi : Theme.pillBg
    border.width: Theme.hairline
    border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.35)

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: pill.spacing
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: pill.interactive
        hoverEnabled: pill.interactive
        cursorShape: pill.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
            if (m.button === Qt.RightButton) pill.rightClicked()
            else pill.clicked(m)
        }
    }

    HoverHandler {
        id: hoverHandler
        enabled: pill.hoverCursor || pill.hoverHighlight
        cursorShape: pill.hoverCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    WheelHandler {
        enabled: pill.interactive
        onWheel: (e) => pill.scrolled(e.angleDelta.y)
    }
}
