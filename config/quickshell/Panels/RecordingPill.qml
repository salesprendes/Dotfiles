import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

PanelWindow {
    id: win

    property var modelData
    screen: modelData

    readonly property bool onThisScreen: modelData && ScreenCapture.recordPillScreenName === modelData.name
    readonly property bool shown: ScreenCapture.isRecording
                                  && ScreenCapture.showRecordingPill
                                  && !ScreenCapture.pillSuppressed
                                  && onThisScreen

    visible: shown
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-recording-pill"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    // Solo la píldora captura el ratón; el resto de la ventana deja pasar los
    // clics a las apps de debajo. Sin la máscara, la capa Overlay se traga toda
    // la pantalla y no puedes seleccionar nada mientras grabas. La región sigue
    // a la píldora al moverse o cambiar de tamaño (usa su geometría, x/y incl.).
    mask: Region { item: pill }

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value))
    }

    function pillX() {
        const def = Math.max(Theme.space4, win.width - pill.width - Theme.space12)
        const x = ScreenCapture.recordPillX >= 0 ? ScreenCapture.recordPillX : def
        return clamp(x, Theme.space4, Math.max(Theme.space4, win.width - pill.width - Theme.space4))
    }

    function pillY() {
        return clamp(ScreenCapture.recordPillY, Theme.space4, Math.max(Theme.space4, win.height - pill.height - Theme.space4))
    }

    Rectangle {
        id: pill
        width: ScreenCapture.recordPillExpanded ? Theme.dp(382) : Theme.dp(178)
        height: Theme.dp(52)
        x: win.pillX()
        y: win.pillY()
        radius: height / 2
        color: Theme.withAlpha(Theme.bg, 0.92)
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.red, 0.58)
        antialiasing: true

        Behavior on width { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        Behavior on x { NumberAnimation { duration: dragArea.pressed ? 0 : Theme.animFast; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: dragArea.pressed ? 0 : Theme.animFast; easing.type: Easing.OutCubic } }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.OpenHandCursor
            property real startMouseX: 0
            property real startMouseY: 0
            property real startPillX: 0
            property real startPillY: 0
            property bool moved: false

            onPressed: (mouse) => {
                cursorShape = Qt.ClosedHandCursor
                startMouseX = mouse.x
                startMouseY = mouse.y
                startPillX = pill.x
                startPillY = pill.y
                moved = false
            }
            onPositionChanged: (mouse) => {
                if (!pressed) return
                const dx = mouse.x - startMouseX
                const dy = mouse.y - startMouseY
                if (Math.abs(dx) > 2 || Math.abs(dy) > 2)
                    moved = true
                ScreenCapture.recordPillX = win.clamp(Math.round(startPillX + dx), Theme.space4,
                                                       Math.max(Theme.space4, win.width - pill.width - Theme.space4))
                ScreenCapture.recordPillY = win.clamp(Math.round(startPillY + dy), Theme.space4,
                                                       Math.max(Theme.space4, win.height - pill.height - Theme.space4))
            }
            onReleased: {
                cursorShape = Qt.OpenHandCursor
                if (!moved)
                    ScreenCapture.recordPillExpanded = !ScreenCapture.recordPillExpanded
            }
            onCanceled: cursorShape = Qt.OpenHandCursor
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space12
            anchors.rightMargin: Theme.space8
            spacing: Theme.space8

            Rectangle {
                id: recDot
                Layout.preferredWidth: Theme.dp(10)
                Layout.preferredHeight: Theme.dp(10)
                radius: height / 2
                color: ScreenCapture.isPaused ? Theme.yellow : Theme.red

                SequentialAnimation on opacity {
                    id: pulse
                    // win.shown (incluye onThisScreen) y no isRecording a
                    // secas: la píldora existe por pantalla y solo una se ve;
                    // sin esto, las copias desmapeadas latían toda la grabación.
                    running: win.shown && !ScreenCapture.isPaused
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.42; duration: 720; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 720; easing.type: Easing.InOutSine }
                }
                Connections {
                    target: ScreenCapture
                    function onIsPausedChanged() {
                        if (ScreenCapture.isPaused)
                            recDot.opacity = 0.55
                        else
                            recDot.opacity = 1.0
                    }
                }
            }

            Text {
                Layout.preferredWidth: Theme.dp(58)
                text: ScreenCapture.formatElapsed(ScreenCapture.recordingElapsed)
                color: Theme.fg
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                visible: ScreenCapture.recordPillExpanded
                text: ScreenCapture.isPaused ? "Pausada" : "Grabando"
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                elide: Text.ElideRight
            }

            PillButton {
                visible: ScreenCapture.recordPillExpanded
                icon: "󰄀"
                accent: Theme.cyan
                onClicked: ScreenCapture.captureWhileRecording()
            }
            PillButton {
                visible: ScreenCapture.recordPillExpanded
                icon: ScreenCapture.isPaused ? "󰐊" : "󰏤"
                accent: Theme.yellow
                onClicked: ScreenCapture.isPaused ? ScreenCapture.resumeRecording()
                                                  : ScreenCapture.pauseRecording()
            }
            PillButton {
                visible: ScreenCapture.recordPillExpanded && Quickshell.screens.length > 1
                icon: "󰍹"
                accent: Theme.accent
                onClicked: ScreenCapture.cyclePillScreen()
            }
            PillButton {
                icon: "󰓛"
                accent: Theme.red
                onClicked: ScreenCapture.stopRecording()
            }
        }
    }

    component PillButton: Rectangle {
        id: btn
        property string icon: ""
        property color accent: Theme.accent
        signal clicked()

        readonly property bool hovered: ma.containsMouse || activeFocus
        activeFocusOnTab: enabled
        Layout.preferredWidth: Theme.controlM
        Layout.preferredHeight: Theme.controlM
        radius: height / 2
        color: hovered ? btn.accent : Theme.withAlpha(btn.accent, 0.20)
        border.width: Theme.hairline
        border.color: Theme.withAlpha(btn.accent, 0.55)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Text {
            anchors.centerIn: parent
            text: btn.icon
            color: btn.hovered ? Theme.bg : btn.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
