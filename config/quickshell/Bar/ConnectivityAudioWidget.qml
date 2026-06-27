import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.Components
import qs.Config
import qs.Services

// Acceso compacto al Centro de control: WiFi + Bluetooth + audio.
Pill {
    id: root
    spacing: Theme.space10
    interactive: true
    hoverHighlight: true

    readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
    readonly property bool muted: audio?.muted ?? false
    readonly property int volume: Math.round((audio?.volume ?? 0) * 100)

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    function containsIcon(item, mouse) {
        const margin = 6
        const point = item.mapFromItem(root, mouse.x, mouse.y)
        return item.visible
            && point.x >= -margin
            && point.x <= item.width + margin
            && point.y >= -margin
            && point.y <= item.height + margin
    }

    onClicked: (m) => {
        if (containsIcon(volumeIcon, m)) {
            if (root.audio) root.audio.muted = !root.audio.muted
            return
        }

        Globals.toggleControlCenter()
    }
    onRightClicked: {
        if (BT.available) BT.toggle()
        else if (root.audio) root.audio.muted = !root.audio.muted
    }
    onScrolled: (dy) => {
        if (!root.audio) return
        const dir = dy > 0 ? 1 : -1
        root.audio.volume = Math.max(0, Math.min(1, root.audio.volume + dir * 0.05))
    }

    Text {
        text: Net.icon
        color: Net.online ? Theme.accent : Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize
    }

    Text {
        visible: BT.available
        text: BT.icon
        color: BT.enabled ? Theme.accent : Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize
    }

    Text {
        id: volumeIcon
        text: root.muted ? "󰝟"
             : root.volume === 0 ? "󰖁"
             : root.volume < 34 ? "󰕿"
             : root.volume < 67 ? "󰖀"
             : "󰕾"
        color: root.audio && !root.muted && root.volume > 0 ? Theme.accent : Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize
    }
}
