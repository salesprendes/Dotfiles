import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Campana con contador. Click abre las notificaciones —el centro clásico, o la
// hoja de la isla si está encendida, lo decide Globals.toggleNotifCenter— y
// click derecho alterna "No molestar".
IconPill {
    id: root
    interactive: true
    // Encendida según DÓNDE se hayan abierto los avisos, que depende de la isla.
    active: Settings.islandEnabled ? IslandState.destination === "notifs"
                                   : Globals.notifCenterOpen
    icon: Settings.dnd ? "󰂛" : "󰂚"
    iconColor: Settings.dnd ? Theme.fgMuted : Theme.yellow
    badgeCount: NotifService.count
    badgeColor: Theme.red
    onClicked: Globals.toggleNotifCenter()
    onRightClicked: Settings.dnd = !Settings.dnd
}
