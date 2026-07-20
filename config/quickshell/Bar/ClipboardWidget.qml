import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Boton de historial de portapapeles.
IconPill {
    id: root
    interactive: true
    active: Globals.clipboardOpen
    icon: "󰅌"
    iconColor: Globals.clipboardOpen ? Theme.accent : (Clipboard.available ? Theme.fgDim : Theme.fgMuted)
    badgeCount: Clipboard.count
    badgeColor: Theme.accent
    onClicked: Globals.toggleClipboard()
    onRightClicked: Clipboard.refresh()
}
