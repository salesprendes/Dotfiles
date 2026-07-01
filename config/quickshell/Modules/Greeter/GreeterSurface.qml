//  Una superficie (ventana normal, cage la maximiza) por monitor. Fondo +
//  reloj en todos; tarjeta de login y energía solo en el principal.
//  Nota: cage no soporta wlr-layer-shell, por eso no se usa PanelWindow.
import QtQuick
import Quickshell
import qs.Modules.Greeter

FloatingWindow {
    id: win
    required property var modelData
    screen: modelData
    readonly property bool primary: Quickshell.screens.length > 0
                                    && modelData === Quickshell.screens[0]

    color: Theme.bg

    // ── Fondo con leve zoom de entrada (one-shot) ────────────
    Image {
        id: wall
        anchors.fill: parent
        source: Config.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize: Qt.size(win.screen ? win.screen.width : 1920,
                            win.screen ? win.screen.height : 1080)
        visible: status === Image.Ready
        transformOrigin: Item.Center
        Component.onCompleted: zoomIn.start()
        NumberAnimation {
            id: zoomIn
            target: wall; property: "scale"
            from: 1.06; to: 1.0; duration: 1200; easing.type: Easing.OutCubic
        }
    }
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Theme.bg
        opacity: 0
        Component.onCompleted: scrimIn.start()
        NumberAnimation {
            id: scrimIn
            target: scrim; property: "opacity"
            from: 0; to: 0.55; duration: 700; easing.type: Easing.OutCubic
        }
    }

    // ── Reloj (todos los monitores) ──────────────────────────
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Column {
        id: clockCol
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(parent.height * 0.15)
        spacing: Theme.dp(6)
        opacity: 0
        Component.onCompleted: clockIn.start()
        NumberAnimation {
            id: clockIn
            target: clockCol; property: "opacity"
            from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.sp(64)
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: clock.date.toLocaleDateString(Theme.locale, "dddd, d 'de' MMMM")
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.sp(15)
        }
    }

    // ── Tarjeta (solo en el monitor principal) ───────────────
    Item {
        id: card
        visible: win.primary
        width: Theme.dp(380)
        readonly property bool pwStage: GreeterState.selectedUser !== ""
        height: (pwStage ? pwv.implicitHeight : up.implicitHeight) + Theme.dp(56)
        anchors.centerIn: parent
        Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        // Entrada de la tarjeta.
        opacity: 0
        property real shake: 0
        property real enterY: Theme.dp(26)
        transform: Translate { x: card.shake; y: card.enterY }
        Component.onCompleted: cardIn.start()
        ParallelAnimation {
            id: cardIn
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "enterY"; from: Theme.dp(26); to: 0; duration: 560; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "scale"; from: 0.98; to: 1; duration: 560; easing.type: Easing.OutCubic }
        }
        // Sacudida al fallar.
        Connections {
            target: GreeterState
            function onFailed() { if (win.primary) shakeAnim.restart() }
        }
        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: card; property: "shake"; to: -Theme.dp(10); duration: 50 }
            NumberAnimation { target: card; property: "shake"; to: Theme.dp(9);   duration: 60 }
            NumberAnimation { target: card; property: "shake"; to: -Theme.dp(6);  duration: 60 }
            NumberAnimation { target: card; property: "shake"; to: 0;             duration: 60; easing.type: Easing.OutCubic }
        }

        // Fondo de la tarjeta.
        Rectangle {
            anchors.fill: parent
            radius: Theme.dp(18)
            color: Theme.alpha(Theme.surface, 0.72)
            border.width: 1
            border.color: Theme.alpha(Theme.overlay, 0.45)
            antialiasing: true
        }

        // Botón "atrás" (volver al selector).
        Rectangle {
            id: backBtn
            readonly property bool canBack: card.pwStage && GreeterState.users.length > 1
            width: Theme.dp(34); height: Theme.dp(34); radius: width / 2
            anchors { left: parent.left; top: parent.top; margins: Theme.dp(12) }
            opacity: canBack ? 1 : 0
            visible: opacity > 0.02
            enabled: canBack
            color: backMa.containsMouse ? Theme.alpha(Theme.surfaceHi, 0.9) : "transparent"
            Behavior on opacity { NumberAnimation { duration: 220 } }
            Behavior on color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent
                text: "󰁍"
                color: backMa.containsMouse ? Theme.accent : Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.sp(16)
            }
            MouseArea {
                id: backMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: GreeterState.backToUsers()
            }
        }

        // PASO 1 · Selector de usuario.
        UserPicker {
            id: up
            anchors.centerIn: parent
            width: parent.width - Theme.dp(44)
            focus: !card.pwStage && win.primary
            enabled: !card.pwStage
            opacity: card.pwStage ? 0 : 1
            visible: opacity > 0.02
            property real off: card.pwStage ? -Theme.dp(26) : 0
            transform: Translate { x: up.off }
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on off { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }

        // PASO 2 · Contraseña.
        PasswordPrompt {
            id: pwv
            primary: win.primary
            anchors.centerIn: parent
            width: parent.width - Theme.dp(44)
            enabled: card.pwStage
            opacity: card.pwStage ? 1 : 0
            visible: opacity > 0.02
            property real off: card.pwStage ? 0 : Theme.dp(26)
            transform: Translate { x: pwv.off }
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on off { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }
    }

    // ── Acciones de energía (abajo a la derecha) ─────────────
    PowerBar {
        visible: win.primary
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.dp(28)
    }
}
