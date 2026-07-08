import QtQuick
import qs.Components
import qs.Config

// Toggle del modo cafeína. Con acento cuando está activo, atenuado si no.
Pill {
    id: root
    interactive: true
    onClicked: Globals.caffeine = !Globals.caffeine

    Item {
        implicitWidth: Theme.iconSize + 2
        implicitHeight: Theme.iconSize + 2

        Text {
            anchors.centerIn: parent
            text: "󰅶"   // taza de café
            color: Globals.caffeine ? Theme.accent : Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }
}
