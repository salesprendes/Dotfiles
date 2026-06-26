import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.Components
import qs.Config

// Volumen del sink por defecto. Click = silenciar · rueda = ±5%.
Pill {
    id: root
    interactive: true

    readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
    readonly property bool muted: audio?.muted ?? false
    readonly property int volume: Math.round((audio?.volume ?? 0) * 100)

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    onClicked: { if (audio) audio.muted = !audio.muted }
    onScrolled: (dy) => {
        if (!audio) return
        const dir = dy > 0 ? 1 : -1
        audio.volume = Math.max(0, Math.min(1, audio.volume + dir * 0.05))
    }

    Text {
        text: root.muted ? "󰝟"
             : root.volume === 0 ? "󰖁"
             : root.volume < 34 ? "󰕿"
             : root.volume < 67 ? "󰖀"
             : "󰕾"
        color: root.muted ? Theme.fgMuted : Theme.green
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize
    }
    Text {
        text: root.muted ? "off" : root.volume + "%"
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
