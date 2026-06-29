import QtQuick
import QtQuick.Layouts
import qs.Config

Rectangle {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property bool expandable: false
    property bool expanded: false
    property color accent: Theme.accent

    signal toggled()
    signal expand()

    activeFocusOnTab: enabled
    implicitHeight: Theme.tileL
    radius: Theme.pillRadius + Theme.space4

    color: (bodyMa.containsMouse || activeFocus) ? Theme.surfaceHi
                                : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.82)
    border.width: activeFocus ? Theme.focusWidth : Theme.hairline
    border.color: activeFocus ? Theme.focusRing : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.38)

    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    Keys.onReturnPressed: root.expandable ? root.expand() : root.toggled()
    Keys.onEnterPressed: root.expandable ? root.expand() : root.toggled()
    Keys.onSpacePressed: root.expandable ? root.expand() : root.toggled()
    Keys.onRightPressed: if (root.expandable) root.expand()
    Keys.onEscapePressed: Globals.closeAll()

    // Pulsar el cuerpo: expande (o alterna si no es expandible).
    MouseArea {
        id: bodyMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expandable ? root.expand() : root.toggled()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.space8
        anchors.rightMargin: Theme.space12
        spacing: Theme.space10

        // ── Botón del icono (on/off) ─────────────────────────────
        Rectangle {
            id: iconTile
            implicitWidth: Theme.controlL
            implicitHeight: Theme.controlL
            radius: Theme.pillRadius
            // Activo: tinte suave de acento (para que el icono de acento se
            // vea encima). Inactivo: superficie neutra.
            color: root.active
                   ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, iconMa.containsMouse ? 0.30 : 0.22)
                   : (iconMa.containsMouse ? Theme.surfaceHi
                                           : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.48))
            border.width: Theme.hairline
            border.color: root.active ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
                                      : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.42)
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

            Text {
                anchors.centerIn: parent
                text: root.icon
                // Activo: color de acento (resaltado).
                // Inactivo: atenuado, para que se vea "apagado".
                color: root.active ? root.accent : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize + 2
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }

            MouseArea {
                id: iconMa
                anchors.fill: parent
                z: 5
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggled()
            }
        }

        // ── Texto del cuerpo (neutro siempre) ────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space2
            Text {
                Layout.fillWidth: true
                text: root.title
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: root.subtitle !== ""
                text: root.subtitle
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                elide: Text.ElideRight
            }
        }
    }
}
