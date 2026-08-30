import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.Config
import qs.Components

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

    // Anclado a un solo borde → el compositor lo centra en el otro eje.
    // Arriba estorba menos cuando lo que miras vive en la parte baja de la
    // pantalla (un vídeo a pantalla completa, un terminal largo).
    readonly property bool atTop: Settings.osdPosition === "top"
    anchors { top: osd.atTop; bottom: !osd.atTop }
    margins.top: osd.atTop ? Theme.dp(72) : 0
    margins.bottom: osd.atTop ? 0 : Theme.dp(72)
    implicitWidth: Theme.panelWidth(screen, 280, 240, 0.72)
    implicitHeight: Theme.dp(56)

    // Mantiene el sink vivo/actualizado aunque no haya paneles abiertos.
    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    // La ventana se mapea mientras se revela o mientras se desvanece.
    visible: (revealed || offTimer.running) && !remapGuard.remapping
    // Superficie de vida larga: se remapea si el monitor cambia de sitio en el
    // layout. Ver Components/ScreenMoveRemap.qml.
    ScreenMoveRemap { id: remapGuard; window: osd }

    function reveal() {
        if (!armed) return
        if (!Settings.osdEnabled) return        // apagado en Ajustes
        if (Globals.controlCenterOpen) return   // no, si viene del panel
        revealed = true
        hideTimer.restart()
    }

    Component.onCompleted: armTimer.start()
    Timer { id: armTimer; interval: 1200; onTriggered: osd.armed = true }
    // Tiempo real, no decoración: no lo modula la velocidad de animaciones.
    Timer {
        id: hideTimer
        interval: Math.max(300, Math.round(Settings.osdTimeout * 1000))
        onTriggered: { osd.revealed = false; offTimer.restart() }
    }
    Timer { id: offTimer; interval: Theme.animNormal + 80 }

    // Detecta cambios de volumen / silencio.
    Connections {
        target: osd.audio
        ignoreUnknownSignals: true
        function onVolumeChanged() { osd.reveal() }
        function onMutedChanged()  { osd.reveal() }
    }

    // Tarjeta
    Rectangle {
        anchors.fill: parent
        radius: Theme.barRadius
        color: Theme.popupBg
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.5)

        opacity: osd.revealed ? 1 : 0
        transform: Translate {
            y: osd.revealed ? 0 : 12
            Behavior on y { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
        }
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space16
            anchors.rightMargin: Theme.space16
            spacing: Theme.space12

            ThemedText {
                text: Utils.volumeGlyph(osd.volume / 100, osd.muted)
                color: osd.muted ? Theme.fgMuted : Theme.accent
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
                    Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
                }
            }

            ThemedText {
                text: osd.muted ? "" : osd.volume + "%"
                color: Theme.fg
                font.bold: true
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
