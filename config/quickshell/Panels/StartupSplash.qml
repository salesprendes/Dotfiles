import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config

PanelWindow {
    id: splash

    property var modelData
    screen: modelData

    property bool shown: true
    property bool mapped: true
    property real loadProgress: 0
    property real displayedProgress: 0
    property bool ready: false
    property bool minHoldDone: false
    // Coreografía de entrada en dos tiempos: primero el conjunto del logo
    // (entered), un instante después la barra y el pie (trailIn). Ninguno
    // toca el diseño del logo ni de la barra: solo cuándo y cómo aparecen.
    property bool entered: false
    property bool trailIn: false

    // Cuando esto ya no se ve, avisamos para que shell.qml lo tire a la basura.
    // Solo sale al arrancar; no pinta nada ocupando memoria por cada monitor
    // durante toda la sesión.
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

    function _clampProgress(value) {
        return Math.max(0, Math.min(1, Number(value) || 0))
    }

    function advanceTo(value) {
        const next = Math.max(displayedProgress, _clampProgress(value))
        if (next > displayedProgress)
            displayedProgress = next
    }

    function finishIfReady(force) {
        if (!shown || (!minHoldDone && !force))
            return
        if (force || ready || displayedProgress >= 0.995) {
            advanceTo(1)
            shown = false
            unmapTimer.restart()
        }
    }

    onLoadProgressChanged: {
        advanceTo(loadProgress)
        finishIfReady(false)
    }

    onReadyChanged: {
        if (ready)
            advanceTo(1)
        finishIfReady(false)
    }

    Component.onCompleted: {
        advanceTo(loadProgress)
        minHoldTimer.start()
        maxHoldTimer.start()
        enterTimer.start()
        finishIfReady(false)
    }

    // Dispara la entrada escalonada un frame después de mapear: así los
    // Behaviors ven el cambio y animan desde el estado inicial.
    Timer {
        id: enterTimer
        interval: 60
        repeat: false
        onTriggered: { splash.entered = true; trailTimer.start() }
    }
    Timer {
        id: trailTimer
        interval: 260
        repeat: false
        onTriggered: splash.trailIn = true
    }

    Timer {
        id: minHoldTimer
        interval: 650
        repeat: false
        onTriggered: {
            splash.minHoldDone = true
            splash.finishIfReady(false)
        }
    }

    Timer {
        id: maxHoldTimer
        interval: 3600
        repeat: false
        onTriggered: splash.finishIfReady(true)
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
        // Fondo del splash: en modo claro usa el mismo color que la barra
        // (Theme.barBg); con cristal ese barBg ya trae la transparencia, así
        // que la aplica sola. En oscuro no-cristal, fondo casi opaco.
        color: !Theme.isDark ? Theme.barBg
                                              : Theme.withAlpha(Theme.bg, 0.96)
        opacity: splash.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 500; easing.type: Easing.InOutCubic }
        }
    }

    Item {
        id: wordmark
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.82, Theme.dp(760))
        height: Math.max(Theme.dp(260), Math.min(parent.height * 0.38, Theme.dp(360)))
        // Entrada: sube unos puntos mientras funde y asienta la escala.
        // Salida: sigue el mismo camino hacia arriba, con una leve crecida.
        opacity: !splash.shown ? 0 : (splash.entered ? 1 : 0)
        scale: !splash.shown ? 1.03 : (splash.entered ? 1 : 0.985)
        anchors.verticalCenterOffset: !splash.shown ? -Theme.dp(10)
                                     : (splash.entered ? 0 : Theme.dp(14))

        Behavior on opacity {
            NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 560; easing.type: Easing.OutCubic }
        }
        Behavior on anchors.verticalCenterOffset {
            NumberAnimation { duration: 560; easing.type: Easing.OutCubic }
        }

        // Halo del acento respirando tras el logo: gradiente radial muy
        // tenue con un pulso lento. Ambientación alrededor del logo, sin
        // tocar el logo en sí.
        Canvas {
            id: glow
            anchors.centerIn: logoMark
            width: Theme.dp(430)
            height: width
            z: -1
            opacity: splash.shown && splash.entered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const r = width / 2
                const g = ctx.createRadialGradient(r, r, 0, r, r, r)
                const a = Theme.accent
                g.addColorStop(0,    Qt.rgba(a.r, a.g, a.b, Theme.isDark ? 0.14 : 0.10))
                g.addColorStop(0.55, Qt.rgba(a.r, a.g, a.b, Theme.isDark ? 0.05 : 0.04))
                g.addColorStop(1,    Qt.rgba(a.r, a.g, a.b, 0))
                ctx.fillStyle = g
                ctx.fillRect(0, 0, width, height)
            }
            SequentialAnimation on scale {
                running: splash.mapped
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 1.1; duration: 2600; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.1; to: 1.0; duration: 2600; easing.type: Easing.InOutSine }
            }
        }

        AppLogo {
            id: logoMark
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            box: Math.min(parent.height * 0.42, Theme.dp(148))
            animate: splash.mapped
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
            // El rótulo entra con el tracking abierto y lo va cerrando hasta
            // su valor final (0): el clásico asentamiento de marca. El
            // aspecto en reposo no cambia.
            font.letterSpacing: splash.entered ? 0 : Theme.dp(12)
            Behavior on font.letterSpacing {
                NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
            }
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            id: progressTrack
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: logoText.bottom
                topMargin: Theme.dp(10)
            }
            width: wordmark.width * 0.46
            height: Math.max(3, Theme.dp(5))
            // Entra un instante después del logo (trailIn) y funde suave.
            opacity: !splash.shown ? 0 : (splash.trailIn ? 0.94 : 0)
            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Theme.withAlpha(Theme.overlay, 0.28)
            }

            Rectangle {
                id: progressFill
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                width: Math.max(height, parent.width * splash.displayedProgress)
                radius: height / 2
                color: Theme.accent

                Behavior on width {
                    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                }
            }

            Rectangle {
                width: progressTrack.width * 0.24
                height: progressTrack.height
                radius: height / 2
                color: Theme.withAlpha(Theme.fg, 0.28)
                opacity: splash.ready ? 0 : 0.65
                x: progressFill.width - width * 0.35
                visible: progressFill.width > height && splash.shown

                Behavior on x {
                    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                }
            }
        }

    }

    // Pie discreto anclado abajo: da contexto ("algo está arrancando") sin
    // competir con el logo. Entra con la barra y se va con todo lo demás.
    Text {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: Theme.dp(48)
        }
        text: I18n.tr("Starting the desktop…")
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        font.letterSpacing: Theme.dp(2)
        opacity: !splash.shown ? 0 : (splash.trailIn ? 0.75 : 0)
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
    }
}
