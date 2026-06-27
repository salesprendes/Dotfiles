import QtQuick
import qs.Components
import qs.Config

// Indicador + toggle del modo cafeína. Acento cuando está activo
// (no se suspende ni bloquea); atenuado cuando está inactivo.
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
