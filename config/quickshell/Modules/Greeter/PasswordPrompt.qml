//  PASO 2 · Contraseña. Puntos nítidos + caret propio, botón "ver",
//  estado de error / indicador de login y selector de sesión.
import QtQuick
import Quickshell
import qs.Modules.Greeter

Item {
    id: pw
    property bool primary: false
    implicitHeight: pwCol.implicitHeight

    Connections {
        target: GreeterState
        function onSelectedUserChanged() {
            if (GreeterState.selectedUser === "") { pwInput.text = ""; return }
            if (pw.primary) Qt.callLater(function () { pwInput.forceActiveFocus() })
        }
    }

    Column {
        id: pwCol
        width: parent.width
        spacing: Theme.dp(14)

        // Avatar con inicial.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.dp(76); height: Theme.dp(76); radius: width / 2
            color: Theme.alpha(Theme.accent, 0.16)
            border.width: 1
            border.color: Theme.alpha(Theme.accent, 0.55)
            Text {
                anchors.centerIn: parent
                text: GreeterState.selectedUser.charAt(0).toUpperCase()
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.sp(32)
                font.bold: true
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: GreeterState.selectedUser
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.sp(18)
            font.bold: true
        }

        // Campo de contraseña.
        Rectangle {
            id: field
            width: parent.width
            height: Theme.dp(46)
            radius: Theme.dp(12)
            color: Theme.alpha(Theme.bg, 0.55)
            border.width: pwInput.activeFocus ? 2 : 1
            border.color: GreeterState.error !== "" ? Theme.red
                        : pwInput.activeFocus ? Theme.accent
                        : Theme.alpha(Theme.overlay, 0.5)
            Behavior on border.color { ColorAnimation { duration: 150 } }

            Text {
                id: lockIcon
                anchors.left: parent.left
                anchors.leftMargin: Theme.dp(14)
                anchors.verticalCenter: parent.verticalCenter
                text: "󰌾"
                color: pwInput.activeFocus ? Theme.accent : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.sp(16)
            }

            // Botón "ver contraseña" (ojo) a la derecha.
            Rectangle {
                id: revealBtn
                visible: Config.allowReveal && GreeterState.secret
                width: Theme.dp(30); height: Theme.dp(30); radius: width / 2
                anchors.right: parent.right
                anchors.rightMargin: Theme.dp(8)
                anchors.verticalCenter: parent.verticalCenter
                color: revealMa.containsMouse ? Theme.alpha(Theme.surfaceHi, 0.9) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: GreeterState.revealSecret ? "󰈈" : "󰈉"
                    color: GreeterState.revealSecret ? Theme.accent
                         : revealMa.containsMouse ? Theme.fg : Theme.fgMuted
                    font.family: Theme.font
                    font.pixelSize: Theme.sp(15)
                }
                MouseArea {
                    id: revealMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        GreeterState.revealSecret = !GreeterState.revealSecret
                        pwInput.forceActiveFocus()
                    }
                }
            }

            // Zona de entrada. En modo oculto, el TextInput es transparente y
            // dibujamos puntos + caret propios (nítidos, bien alineados).
            Item {
                id: inputCell
                anchors.left: lockIcon.right
                anchors.leftMargin: Theme.dp(10)
                anchors.right: revealBtn.visible ? revealBtn.left : parent.right
                anchors.rightMargin: Theme.dp(10)
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                clip: true

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pwInput.text.length === 0 && !pwInput.activeFocus
                    text: GreeterState.prompt
                    color: Theme.fgMuted
                    font.family: Theme.font
                    font.pixelSize: Theme.sp(15)
                }
                Row {
                    id: dotsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.dp(7)
                    visible: GreeterState.masked
                    // Si los puntos desbordan la celda, la fila se desplaza para
                    // mantener el caret visible en el borde derecho; cada punto
                    // nuevo empuja la fila con un deslizamiento suave.
                    x: Math.min(0, inputCell.width - width)
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Repeater {
                        model: pwInput.text.length
                        delegate: Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.dp(9); height: Theme.dp(9)
                            radius: width / 2
                            color: Theme.fg
                            antialiasing: true
                        }
                    }
                    Rectangle {
                        id: caret
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.dp(2); height: Theme.dp(18)
                        radius: width / 2
                        color: Theme.accent
                        visible: pwInput.activeFocus && !GreeterState.busy
                        SequentialAnimation on opacity {
                            running: caret.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.15; duration: 480; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1;    duration: 480; easing.type: Easing.InOutQuad }
                        }
                    }
                }
                TextInput {
                    id: pwInput
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    color: GreeterState.masked ? "transparent" : Theme.fg
                    // Qt fuerza cursorVisible=true al recibir foco, así que un
                    // "cursorVisible: false" no basta y se veía el cursor nativo
                    // (negro) junto al caret propio (azul). Con un delegate
                    // propio el cursor nativo nunca se dibuja: nada en modo
                    // oculto (ya está el caret de los puntos) y un caret a
                    // juego cuando la contraseña es visible.
                    cursorDelegate: Rectangle {
                        visible: !GreeterState.masked && pwInput.activeFocus
                                 && !GreeterState.busy
                        width: Theme.dp(2)
                        height: pwInput.cursorRectangle.height
                        radius: width / 2
                        color: Theme.accent
                        SequentialAnimation on opacity {
                            running: visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.15; duration: 480; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1;    duration: 480; easing.type: Easing.InOutQuad }
                        }
                    }
                    font.family: Theme.font
                    font.pixelSize: Theme.sp(15)
                    clip: true
                    enabled: !GreeterState.busy && GreeterState.selectedUser !== ""
                    echoMode: GreeterState.masked ? TextInput.Password : TextInput.Normal
                    selectByMouse: false
                    // Tab recorre los controles con la cadena de foco de Qt:
                    // contraseña → selector de sesión → botones de energía →
                    // y vuelve aquí al completar el ciclo (Shift+Tab, al revés).
                    activeFocusOnTab: true
                    // ESC, en orden: cierra el desplegable de sesiones (si se
                    // abrió con el ratón) → borra lo tecleado → vuelve al
                    // selector de usuarios (solo si hay más de uno).
                    Keys.onEscapePressed: {
                        if (GreeterState.busy) return
                        if (sessionSel.open) { sessionSel.open = false; return }
                        if (text.length > 0) { text = ""; GreeterState.error = ""; return }
                        if (GreeterState.users.length > 1) GreeterState.backToUsers()
                    }
                    // Solo se limpia si el envío se cursó; si se descartó (aún
                    // sin sesión PAM lista), se conserva para reintentar.
                    onAccepted: { if (GreeterState.submit(text)) text = "" }
                }
            }
        }

        // Estado: error o indicador de login (3 puntos que laten).
        Item {
            width: parent.width
            height: Theme.dp(16)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: GreeterState.error !== "" && !GreeterState.busy
                text: GreeterState.error
                color: Theme.red
                font.family: Theme.font
                font.pixelSize: Theme.sp(12)
                elide: Text.ElideRight
            }
            Row {
                anchors.centerIn: parent
                spacing: Theme.dp(6)
                visible: GreeterState.busy
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        width: Theme.dp(7); height: Theme.dp(7)
                        radius: width / 2
                        color: Theme.accent
                        opacity: 0.25
                        SequentialAnimation on opacity {
                            running: GreeterState.busy
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 160 }
                            NumberAnimation { to: 1;    duration: 300; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.25; duration: 300; easing.type: Easing.InOutSine }
                            PauseAnimation { duration: (2 - index) * 160 }
                        }
                    }
                }
            }
        }

        // Selector de sesión (solo si hay más de una).
        SessionPicker {
            id: sessionSel
            anchors.horizontalCenter: parent.horizontalCenter
            onRequestFocus: if (pw.primary) pwInput.forceActiveFocus()
        }
    }
}
