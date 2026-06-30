import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config

PanelWindow {
    id: splash

    property var modelData
    screen: modelData

    property bool shown: true
    property bool mapped: true

    // Se emite cuando el splash ha terminado (ya invisible). El cargador
    // perezoso de shell.qml lo escucha para liberar la ventana y su árbol
    // de escena: solo se usa una vez al arrancar, no tiene sentido que
    // siga residente por monitor el resto de la sesión.
    signal finished()

    visible: mapped
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-startup-splash"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Component.onCompleted: holdTimer.start()

    Timer {
        id: holdTimer
        interval: 2200
        repeat: false
        onTriggered: {
            splash.shown = false
            unmapTimer.start()
        }
    }

    Timer {
        id: unmapTimer
        interval: 520
        repeat: false
        onTriggered: {
            splash.mapped = false
            splash.finished()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: splash.shown ? 0.96 : 0
        Behavior on opacity {
            NumberAnimation { duration: 500; easing.type: Easing.InOutCubic }
        }
    }

    Item {
        id: wordmark
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.82, Theme.dp(760))
        height: Math.max(Theme.dp(260), Math.min(parent.height * 0.38, Theme.dp(360)))
        opacity: splash.shown ? 1 : 0
        scale: splash.shown ? 1 : 1.025

        Behavior on opacity {
            NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
        }

        Item {
            id: logoMark
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            width: Math.min(parent.height * 0.42, Theme.dp(148))
            height: width

            Rectangle {
                anchors.fill: parent
                anchors.margins: Theme.dp(8)
                radius: Theme.dp(18)
                color: Theme.withAlpha(Theme.surface, 0.28)
                border.width: Math.max(2, Theme.dp(2))
                border.color: Theme.withAlpha(Theme.accent, 0.78)
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: Theme.dp(22)
                radius: Theme.dp(10)
                color: "transparent"
                border.width: Math.max(1, Theme.dp(1))
                border.color: Theme.withAlpha(Theme.overlay, 0.44)
            }

            Text {
                anchors {
                    left: parent.left
                    leftMargin: Theme.dp(20)
                    verticalCenter: parent.verticalCenter
                }
                text: "<"
                color: Theme.accent
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.dp(50)
                font.bold: true
            }

            Text {
                anchors.centerIn: parent
                text: "A"
                color: Theme.fg
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.dp(64)
                font.bold: true
            }

            Text {
                anchors {
                    right: parent.right
                    rightMargin: Theme.dp(16)
                    verticalCenter: parent.verticalCenter
                }
                text: "/>"
                color: Theme.cyan
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.dp(38)
                font.bold: true
            }

            Rectangle {
                x: parent.width * 0.18
                y: parent.height * 0.28
                width: parent.width * 0.2
                height: Math.max(1, Theme.dp(2))
                radius: height / 2
                color: Theme.withAlpha(Theme.accent, 0.64)
            }

            Rectangle {
                x: parent.width * 0.62
                y: parent.height * 0.72
                width: parent.width * 0.2
                height: Math.max(1, Theme.dp(2))
                radius: height / 2
                color: Theme.withAlpha(Theme.cyan, 0.64)
            }

            Rectangle {
                x: parent.width * 0.5 - width / 2
                y: parent.height * 0.12
                width: Math.max(1, Theme.dp(2))
                height: parent.height * 0.18
                radius: width / 2
                color: Theme.withAlpha(Theme.yellow, 0.54)
            }

            Repeater {
                model: [
                    { x: 0.16, y: 0.28, c: Theme.accent, d: 0 },
                    { x: 0.50, y: 0.12, c: Theme.yellow, d: 220 },
                    { x: 0.84, y: 0.72, c: Theme.cyan, d: 440 }
                ]

                delegate: Rectangle {
                    required property var modelData
                    width: Theme.dp(10)
                    height: width
                    radius: width / 2
                    x: logoMark.width * modelData.x - width / 2
                    y: logoMark.height * modelData.y - height / 2
                    color: modelData.c
                    opacity: 0.82

                    SequentialAnimation on opacity {
                        running: splash.mapped
                        loops: Animation.Infinite
                        PauseAnimation { duration: modelData.d }
                        NumberAnimation { from: 0.38; to: 1; duration: 420; easing.type: Easing.OutCubic }
                        NumberAnimation { from: 1; to: 0.38; duration: 620; easing.type: Easing.InOutCubic }
                    }
                }
            }
        }

        Text {
            id: logoText
            anchors {
                left: parent.left
                right: parent.right
                top: logoMark.bottom
                topMargin: Theme.dp(18)
            }
            height: Math.max(Theme.dp(82), parent.height * 0.34)
            text: "ALVARO"
            color: Theme.fg
            font.family: Theme.monoFontFamily
            font.pixelSize: Theme.dp(124)
            fontSizeMode: Text.Fit
            minimumPixelSize: Theme.dp(42)
            font.bold: true
            font.letterSpacing: 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            id: accentLine
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: logoText.bottom
                topMargin: Theme.dp(10)
            }
            width: wordmark.width * 0.46
            height: Math.max(2, Theme.dp(4))
            radius: height / 2
            color: Theme.accent
            transformOrigin: Item.Left
            scale: splash.shown ? 1 : 0
            opacity: splash.shown ? 0.94 : 0

            SequentialAnimation on scale {
                running: splash.mapped
                loops: Animation.Infinite
                NumberAnimation { from: 0.72; to: 1; duration: 620; easing.type: Easing.OutCubic }
                PauseAnimation { duration: 840 }
                NumberAnimation { from: 1; to: 0.72; duration: 520; easing.type: Easing.InOutCubic }
                PauseAnimation { duration: 220 }
            }
        }

    }
}
