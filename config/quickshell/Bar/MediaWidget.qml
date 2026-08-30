import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Píldora del reproductor. Quién es "el reproductor activo" —y sobre todo si
// hay alguno de verdad— lo decide Services/Media.qml: aquí se elegía con un
// `si nadie reproduce, coge el primero`, y el primero siempre acababa siendo el
// reproductor fantasma que el navegador deja registrado mientras esté abierto.
// La píldora no se iba nunca.
Pill {
    id: root
    spacing: Theme.space4

    readonly property var player: Media.active
    readonly property bool playing: Media.playing

    shown: Media.hasMedia

    MediaEqualizer {
        Layout.alignment: Qt.AlignVCenter
        playing: root.playing
    }

    // Botón de control compacto: IconButton transparente donde solo el glifo
    // reacciona al ratón; se atenúa cuando el reproductor no admite la acción.
    component CtrlButton: IconButton {
        Layout.alignment: Qt.AlignVCenter
        diameter: Theme.barIconSize + Theme.space4
        iconPixelSize: Theme.barIconSize
        baseColor: "transparent"
        hoverColor: "transparent"
        iconColor: Theme.fgDim
        hoverIconColor: Theme.accent
        opacity: enabled ? 1 : 0.4
    }

    CtrlButton {
        icon: "󰒮"
        enabled: root.player?.canGoPrevious ?? false
        onClicked: root.player?.previous()
    }
    CtrlButton {
        icon: (root.player?.isPlaying ?? false) ? "󰏤" : "󰐊"
        enabled: root.player?.canTogglePlaying ?? false
        onClicked: root.player?.togglePlaying()
    }
    CtrlButton {
        icon: "󰒭"
        enabled: root.player?.canGoNext ?? false
        onClicked: root.player?.next()
    }

    PillSeparator {}

    // Título, solo informativo.
    BarLabel {
        Layout.alignment: Qt.AlignVCenter
        Layout.maximumWidth: Theme.dp(170)
        text: root.player?.trackTitle || root.player?.trackArtist || ""
        elide: Text.ElideRight
    }
}
