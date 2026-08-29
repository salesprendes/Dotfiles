import QtQuick
import qs.Components
import qs.Config

// Abre el selector de emojis. Elegir uno lo copia al portapapeles.
IconPill {
    id: root
    interactive: true
    active: Globals.emojiOpen
    icon: "󰞅"
    iconColor: Globals.emojiOpen ? Theme.accent : Theme.fgMuted
    animateColor: true
    onClicked: Globals.toggleEmoji()
}
