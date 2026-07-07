import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.Config

PanelWindow {
    id: osd

    property var modelData
    screen: modelData

    readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
    readonly property bool muted: audio?.muted ?? false
    readonly property int volume: Math.round((audio?.volume ?? 0) * 100)

    property bool revealed: false
    property bool armed: false   // evita mostrarlo al arrancar

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-osd-volume"

    // Anclado solo abajo → el compositor lo centra horizontalmente.
    anchors { bottom: true }
    margins.bottom: Theme.dp(72)
    implicitWidth: Theme.panelWidth(screen, 280, 240, 0.72)
    implicitHeight: Theme.dp(56)

    // Mantiene el sink vivo/actualizado aunque no haya paneles abiertos.
    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    // La ventana se mapea mientras se revela o mientras se desvanece.
    visible: revealed || offTimer.running

    function reveal() {
        if (!armed) return
        if (Globals.controlCenterOpen) return   // no, si viene del panel
        revealed = true
        hideTimer.restart()
    }

    Component.onCompleted: armTimer.start()
    Timer { id: armTimer; interval: 1200; onTriggered: osd.armed = true }
    Timer { id: hideTimer; interval: 1600; onTriggered: { osd.revealed = false; offTimer.restart() } }
    Timer { id: offTimer; interval: Theme.animNormal + 80 }

    // Detecta cambios de volumen / silencio.
    Connections {
        target: osd.audio
        ignoreUnknownSignals: true
        function onVolumeChanged() { osd.reveal() }
        function onMutedChanged()  { osd.reveal() }
    }

    // ── Tarjeta ──────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: Theme.barRadius
        color: Theme.popupBg
        border.width: Theme.hairline
        border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.5)

        opacity: osd.revealed ? 1 : 0
        transform: Translate {
            y: osd.revealed ? 0 : 12
            Behavior on y { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        }
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space16
            anchors.rightMargin: Theme.space16
            spacing: Theme.space12

            Text {
                text: osd.muted ? "󰝟"
                     : osd.volume === 0 ? "󰖁"
                     : osd.volume < 34 ? "󰕿"
                     : osd.volume < 67 ? "󰖀"
                     : "󰕾"
                color: osd.muted ? Theme.fgMuted : Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize + 6
                Layout.preferredWidth: Theme.controlS
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.space8
                radius: height / 2
                color: Theme.surface
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: parent.width * Math.min(1, (osd.muted ? 0 : osd.volume) / 100)
                    color: osd.muted ? Theme.fgMuted : Theme.accent
                    Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                }
            }

            Text {
                text: osd.muted ? "" : osd.volume + "%"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
