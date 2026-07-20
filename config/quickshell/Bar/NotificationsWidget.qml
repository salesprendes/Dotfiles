import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Campana con contador. Click abre el centro de notificaciones,
// click derecho alterna "No molestar".
IconPill {
    id: root
    interactive: true
    active: Globals.notifCenterOpen
    icon: Globals.dnd ? "󰂛" : "󰂚"
    iconColor: Globals.dnd ? Theme.fgMuted : Theme.yellow
    badgeCount: NotifService.count
    badgeColor: Theme.red
    onClicked: Globals.toggleNotifCenter()
    onRightClicked: Globals.dnd = !Globals.dnd
}
