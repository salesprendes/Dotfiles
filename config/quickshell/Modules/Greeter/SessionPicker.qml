//  Selector de sesión: desplegable flotante que se abre hacia arriba con
//  animación fluida (fade + escala desde la base + cascada por fila).
//  Lee /usr/share/wayland-sessions.
import QtQuick
import Quickshell
import qs.Modules.Greeter

Item {
    id: sp
    implicitWidth: trigger.width
    implicitHeight: trigger.height
    visible: GreeterState.sessions.length > 0
    enabled: visible && !GreeterState.busy

    property bool open: false
    signal requestFocus()

    // Se cierra si el usuario cambia o empieza la autenticación.
    Connections {
        target: GreeterState
        function onBusyChanged()          { if (GreeterState.busy) sp.open = false }
        function onSelectedUserChanged()  { sp.open = false }
    }
    onOpenChanged: if (!open) sp.requestFocus()

    // ── Capa para descartar al hacer clic fuera (solo mientras abierto) ─
    MouseArea {
        anchors.centerIn: trigger
        width: 4000; height: 4000
        z: 5
        visible: sp.open
        enabled: sp.open
        onClicked: sp.open = false
    }

    // ── Disparador (píldora con la sesión actual) ────────────────────
    Rectangle {
        id: trigger
        height: Theme.dp(32)
        width: trigRow.implicitWidth + Theme.dp(26)
        radius: height / 2
        color: (trigMa.containsMouse || sp.open) ? Theme.alpha(Theme.surfaceHi, 0.9)
                                                 : Theme.alpha(Theme.surface, 0.5)
        border.width: 1
        border.color: sp.open ? Theme.alpha(Theme.accent, 0.6)
                              : Theme.alpha(Theme.overlay, 0.4)
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }

        Row {
            id: trigRow
            anchors.centerIn: parent
            spacing: Theme.dp(8)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰧨"
                color: sp.open || trigMa.containsMouse ? Theme.accent : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.sp(13)
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: GreeterState.currentSession ? GreeterState.currentSession.name : "Sesión"
                color: sp.open || trigMa.containsMouse ? Theme.fg : Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.sp(12)
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰅀"
                color: sp.open || trigMa.containsMouse ? Theme.accent : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.sp(11)
                rotation: sp.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 140 } }
            }
        }
        MouseArea {
            id: trigMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sp.open = !sp.open
        }
    }

    // ── Panel desplegable (se abre hacia arriba) ─────────────────────
    Item {
        id: menu
        z: 6
        // 0→1 impulsa toda la animación de apertura/cierre.
        property real shown: sp.open ? 1 : 0
        Behavior on shown { NumberAnimation { duration: 210; easing.type: Easing.OutCubic } }

        width: Math.max(trigger.width, Theme.dp(190))
        height: menuBg.height
        anchors.horizontalCenter: trigger.horizontalCenter
        anchors.bottom: trigger.top
        anchors.bottomMargin: Theme.dp(10)

        visible: shown > 0.01
        opacity: shown
        transformOrigin: Item.Bottom
        scale: 0.94 + 0.06 * shown

        Rectangle {
            id: menuBg
            width: parent.width
            height: menuCol.implicitHeight + Theme.dp(10)
            radius: Theme.dp(14)
            color: Theme.alpha(Theme.surface, 0.97)
            border.width: 1
            border.color: Theme.alpha(Theme.overlay, 0.5)
            antialiasing: true

            Column {
                id: menuCol
                width: parent.width - Theme.dp(10)
                anchors.centerIn: parent
                spacing: Theme.dp(2)

                Repeater {
                    model: GreeterState.sessions
                    delegate: Rectangle {
                        id: row
                        required property int index
                        required property var modelData
                        width: menuCol.width
                        height: Theme.dp(36)
                        radius: Theme.dp(10)
                        readonly property bool current: index === GreeterState.sessionIndex
                        // Resalte instantáneo: animar hacia "transparent" (negro
                        // con alfa 0) dejaba un rastro oscuro al mover el ratón
                        // rápido entre filas.
                        color: rowMa.containsMouse ? Theme.alpha(Theme.surfaceHi, 0.9)
                             : current ? Theme.alpha(Theme.accent, 0.14)
                             : "transparent"

                        // Cascada: cada fila se revela un pelín tras la anterior.
                        readonly property real rp: Math.max(0, Math.min(1,
                            (menu.shown - index * 0.08) / 0.55))
                        opacity: rp
                        transform: Translate { x: (1 - row.rp) * Theme.dp(12) }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.dp(12)
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.dp(40)
                            text: row.modelData.name
                            elide: Text.ElideRight
                            color: row.current ? Theme.accent
                                 : rowMa.containsMouse ? Theme.fg : Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: Theme.sp(12)
                            font.bold: row.current
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.dp(12)
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.current
                            text: "󰄬"
                            color: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: Theme.sp(13)
                        }
                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                GreeterState.sessionIndex = row.index
                                sp.open = false
                            }
                        }
                    }
                }
            }
        }
    }
}
