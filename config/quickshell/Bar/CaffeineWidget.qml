import QtQuick
import qs.Components
import qs.Config

// Toggle del modo cafeína. Con acento cuando está activo, atenuado si no.
IconPill {
    id: root
    interactive: true
    icon: "󰅶"   // taza de café
    iconColor: Settings.caffeine ? Theme.accent : Theme.fgMuted
    animateColor: true
    onClicked: Settings.caffeine = !Settings.caffeine
}
