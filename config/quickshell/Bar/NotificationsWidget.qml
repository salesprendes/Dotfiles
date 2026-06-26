import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Campana con contador. Click → centro de notificaciones ·
// click derecho → alternar "No molestar".
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

        Rectangle {
            visible: NotifService.count > 0
            anchors { right: parent.right; top: parent.top; rightMargin: -Theme.space4; topMargin: -Theme.space4 }
            width: Theme.dp(14); height: Theme.dp(14); radius: height / 2
            color: Theme.red
            Text {
                anchors.centerIn: parent
                text: NotifService.count > 9 ? "9+" : NotifService.count
                color: Theme.bg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(9)
                font.bold: true
            }
        }
    }
}
