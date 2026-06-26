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

    // Ecualizador: 4 barras que rebotan al sonar; planas al pausar.
    Item {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Theme.dp(16)
        implicitHeight: Theme.iconSize

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
                    readonly property real maxH: Theme.iconSize
                    readonly property real minH: Theme.dp(3)
                    height: root.playing ? animH : minH
                    property real animH: minH
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Behavior on height { enabled: !root.playing; NumberAnimation { duration: Theme.animFast } }
                    SequentialAnimation on animH {
                        running: root.playing
                        loops: Animation.Infinite
                        NumberAnimation { to: bar.maxH; duration: 260 + bar.index * 70; easing.type: Easing.InOutSine }
                        NumberAnimation { to: bar.minH; duration: 300 + bar.index * 55; easing.type: Easing.InOutSine }
                    }
                }
            }
        }
    }

    // Botón de icono interno reutilizable.
    component CtrlButton: Item {
        id: cbtn
        property string glyph: ""
        property bool can: true
        signal tapped()
        implicitWidth: Theme.iconSize + Theme.space4
        implicitHeight: Theme.iconSize + Theme.space4
        Layout.alignment: Qt.AlignVCenter

        Text {
            anchors.centerIn: parent
            text: cbtn.glyph
            color: cma.containsMouse && cbtn.can ? Theme.accent : Theme.fgDim
            opacity: cbtn.can ? 1 : 0.4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
        MouseArea {
            id: cma
            anchors.fill: parent
            hoverEnabled: true
            enabled: cbtn.can
            cursorShape: Qt.PointingHandCursor
            onClicked: cbtn.tapped()
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

    // Título (solo informativo, sin abrir nada).
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
