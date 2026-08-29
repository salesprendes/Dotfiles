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

    // Ecualizador: 4 barras que rebotan al sonar, planas al pausar.
    // Uso un Timer a ~7 pasos/s en vez de animaciones a 60 fps para no
    // tener la escena repintando sin parar mientras suena música.
    Item {
        id: eq
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Theme.dp(16)
        implicitHeight: Theme.barIconSize

        property int tick: 0
        Timer {
            interval: 140
            // 'visible' además de 'playing': la píldora puede estar escondida
            // con algo sonando —el clima y el reloj comparten centro y el
            // widget puede no estar puesto en la barra—, y sin este guardia el
            // tick seguiría reevaluando las cuatro barras de algo que no se ve.
            running: root.playing && root.visible
            repeat: true
            onTriggered: eq.tick++
        }

        Row {
            anchors.centerIn: parent
            spacing: Theme.dp(2)
            Repeater {
                model: 4
                Rectangle {
                    id: bar
                    required property int index
                    width: Theme.dp(2.5)
                    radius: width / 2
                    color: root.playing ? Theme.accent : Theme.fgMuted
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property real maxH: Theme.barIconSize
                    readonly property real minH: Theme.dp(3)
                    // Dos senos desfasados por barra: movimiento que no se ve
                    // periódico, sin gastar Math.random en cada tick.
                    readonly property real level: 0.5
                        + 0.3 * Math.sin((eq.tick + bar.index * 1.7) * 0.9)
                        + 0.2 * Math.sin((eq.tick * 1.31 + bar.index * 2.3))
                    height: root.playing ? minH + (maxH - minH) * Math.max(0, Math.min(1, level)) : minH
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Behavior on height { enabled: !root.playing; NumberAnimation { duration: Theme.animFast } }
                }
            }
        }
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
