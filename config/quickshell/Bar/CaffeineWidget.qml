import QtQuick
import qs.Components
import qs.Config

// Toggle del modo cafeína. Con acento cuando está activo, atenuado si no.
Pill {
    id: root
    interactive: true
    onClicked: Settings.caffeine = !Settings.caffeine

    Item {
        implicitWidth: Theme.barIconSize + 2
        implicitHeight: Theme.barIconSize + 2

        Text {
            anchors.centerIn: parent
            text: "󰅶"   // taza de café
            color: Settings.caffeine ? Theme.accent : Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.barIconSize
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }
}
