import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Campana con contador. Click abre el centro de notificaciones,
// click derecho alterna "No molestar".
Pill {
    id: root
    interactive: true
    onClicked: Globals.toggleNotifCenter()
    onRightClicked: Globals.dnd = !Globals.dnd

    Item {
        implicitWidth: Theme.iconSize + 2
        implicitHeight: Theme.iconSize + 2

        Text {
            anchors.centerIn: parent
            text: Globals.dnd ? "󰂛" : "󰂚"
            color: Globals.dnd ? Theme.fgMuted : Theme.yellow
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
        }

        CountBadge {
            count: NotifService.count
            badgeColor: Theme.red
            anchors { right: parent.right; top: parent.top; rightMargin: -Theme.space4; topMargin: -Theme.space4 }
        }
    }
}
