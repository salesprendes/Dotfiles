import QtQuick
import qs.Config

// Píldora de barra con un único glifo y, opcionalmente, insignia contadora
// en la esquina superior derecha. Los widgets solo aportan icono, color y
// las señales heredadas de Pill (click, click derecho, rueda).
Pill {
    id: root

    property string icon: ""
    property color iconColor: Theme.fgDim
    // Suaviza los cambios de color del glifo (toggles tipo cafeína).
    property bool animateColor: false
    property int badgeCount: 0
    property color badgeColor: Theme.accent

    Item {
        implicitWidth: Theme.barIconSize + 2
        implicitHeight: Theme.barIconSize + 2

        Text {
            anchors.centerIn: parent
            text: root.icon
            color: root.iconColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.barIconSize
            Behavior on color {
                enabled: root.animateColor
                ColorAnimation { duration: Theme.animFast }
            }
        }

        CountBadge {
            count: root.badgeCount
            badgeColor: root.badgeColor
            anchors { right: parent.right; top: parent.top; rightMargin: -Theme.space4; topMargin: -Theme.space4 }
        }
    }
}
