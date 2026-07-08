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

    // Manejo por teclado. Tab trae el foco aquí (anillo de acento en la
    // píldora). Espacio o Enter abren el menú; abierto: ↑/↓ recorren,
    // Espacio/Enter eligen y ESC cierra sin cambiar. Al cerrarse, el foco
    // vuelve solo a la contraseña.
    activeFocusOnTab: true
    property int hi: 0
    function kbToggle() {
        if (GreeterState.busy) return
        if (!open) {
            hi = GreeterState.sessionIndex
            open = true
        } else {
            GreeterState.sessionIndex = hi
            open = false
        }
    }
    Keys.onSpacePressed:  kbToggle()
    Keys.onReturnPressed: kbToggle()
    Keys.onEnterPressed:  kbToggle()
    Keys.onUpPressed:     if (open) hi = Math.max(0, hi - 1)
    Keys.onDownPressed:   if (open) hi = Math.min(GreeterState.sessions.length - 1, hi + 1)
    Keys.onEscapePressed: {
        if (open) open = false
        else requestFocus()   // sin menú: devuelve el foco a la contraseña
    }
    // Tab con el menú abierto: recorre las opciones; al pasar de la última
    // el menú se cierra solo y el foco salta directo a los botones de
    // energía (sin quedarse en el limbo). Shift+Tab, lo simétrico.
    property bool _skipRefocus: false
    Keys.onTabPressed: (event) => {
        if (!open) { event.accepted = false; return } // cerrado: cadena normal
        if (hi < GreeterState.sessions.length - 1) {
            hi++
        } else {
            _skipRefocus = true
            open = false
            const nxt = nextItemInFocusChain(true)
            if (nxt) nxt.forceActiveFocus(Qt.TabFocusReason)
            _skipRefocus = false
        }
    }
    Keys.onBacktabPressed: (event) => {
        if (!open) { event.accepted = false; return }
        if (hi > 0) hi--
        else open = false     // al principio: cierra y vuelve a la contraseña
    }

    // Se cierra si el usuario cambia o empieza la autenticación.
    Connections {
        target: GreeterState
        function onBusyChanged()          { if (GreeterState.busy) sp.open = false }
        function onSelectedUserChanged()  { sp.open = false }
    }
    onOpenChanged: if (!open && !_skipRefocus) sp.requestFocus()

    // Capa para descartar al hacer clic fuera (solo mientras abierto)
    MouseArea {
        anchors.centerIn: trigger
        width: 4000; height: 4000
        z: 5
        visible: sp.open
        enabled: sp.open
        onClicked: sp.open = false
    }

    // Disparador (píldora con la sesión actual)
    Rectangle {
        id: trigger
        // 'lit' = resaltado (hover/abierto/foco); 'focused' = solo abierto/foco.
        readonly property bool lit: trigMa.containsMouse || sp.open || sp.activeFocus
        readonly property bool focused: sp.open || sp.activeFocus
        height: Theme.dp(32)
        width: trigRow.implicitWidth + Theme.dp(26)
        radius: height / 2
        color: trigger.lit ? Theme.alpha(Theme.surfaceHi, 0.9)
                           : Theme.alpha(Theme.surface, 0.5)
        border.width: 1
        border.color: trigger.focused ? Theme.alpha(Theme.accent, 0.6)
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
                color: trigger.lit ? Theme.accent : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.sp(13)
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: GreeterState.currentSession ? GreeterState.currentSession.name : I18n.tr("Sesión", "Session")
                color: trigger.lit ? Theme.fg : Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.sp(12)
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰅀"
                color: trigger.lit ? Theme.accent : Theme.fgMuted
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

    // Panel desplegable (se abre hacia arriba)
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
                        // Resaltado compartido ratón/teclado: el hover mueve
                        // el índice hi (mismo que ↑/↓), así solo hay una fila
                        // marcada. Resalte instantáneo: animar hacia
                        // "transparent" (negro con alfa 0) dejaba un rastro
                        // oscuro al mover el ratón rápido entre filas.
                        readonly property bool hilite: index === sp.hi
                        color: hilite ? Theme.alpha(Theme.surfaceHi, 0.9)
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
                                 : row.hilite ? Theme.fg : Theme.fgDim
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
                            onEntered: sp.hi = row.index
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
