import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.Components
import qs.Config

Pill {
    id: root
    interactive: false
    spacing: Theme.space4

    readonly property var players: Mpris.players?.values ?? []
    readonly property var player: {
        if (players.length === 0)
            return null
        for (let i = 0; i < players.length; i++)
            if (players[i].isPlaying)
                return players[i]
        return players[0]
    }
    readonly property bool hasMedia: player !== null
                                     && ((player.trackTitle || "") !== "" || (player.trackArtist || "") !== "")
    readonly property bool playing: player?.isPlaying ?? false

    visible: hasMedia

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
            // visible además de playing: un reproductor sin metadatos deja la
            // píldora oculta (hasMedia false) con playing true, y el tick
            // seguía reevaluando las barras de un widget que no se ve.
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

    // Botón de icono reutilizable.
    component CtrlButton: Item {
        id: cbtn
        property string glyph: ""
        property bool can: true
        signal tapped()
        implicitWidth: Theme.barIconSize + Theme.space4
        implicitHeight: Theme.barIconSize + Theme.space4
        Layout.alignment: Qt.AlignVCenter

        Text {
            anchors.centerIn: parent
            text: cbtn.glyph
            color: cma.containsMouse && cbtn.can ? Theme.accent : Theme.fgDim
            opacity: cbtn.can ? 1 : 0.4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.barIconSize
            scale: cma.containsMouse && cbtn.can ? 1.2 : 1
            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
        MouseArea {
            id: cma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (cbtn.can) cbtn.tapped()
        }
    }

    CtrlButton {
        glyph: "󰒮"
        can: root.player?.canGoPrevious ?? false
        onTapped: root.player?.previous()
    }
    CtrlButton {
        glyph: (root.player?.isPlaying ?? false) ? "󰏤" : "󰐊"
        can: root.player?.canTogglePlaying ?? false
        onTapped: root.player?.togglePlaying()
    }
    CtrlButton {
        glyph: "󰒭"
        can: root.player?.canGoNext ?? false
        onTapped: root.player?.next()
    }

    // Separador fino.
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Theme.hairline
        implicitHeight: Theme.dp(14)
        color: Theme.overlay
    }

    // Título, solo informativo.
    Text {
        Layout.alignment: Qt.AlignVCenter
        Layout.maximumWidth: Theme.dp(170)
        text: root.player?.trackTitle || root.player?.trackArtist || ""
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        elide: Text.ElideRight
    }
}
