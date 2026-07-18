//  PASO 2 · Contraseña. Puntos nítidos + caret propio, botón "ver",
//  botón Enter, estado de error / indicador de login y selector de sesión.
import QtQuick
import Quickshell
import Quickshell.Widgets
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

    // Envía lo tecleado (mismo camino que Enter): solo limpia si se cursó.
    function _sendPassword() {
        if (GreeterState.submit(pwInput.text)) pwInput.text = ""
        pwInput.forceActiveFocus()
    }

    // El cursor que parpadea. Sirve tanto cuando la clave va tapada con puntos
    // como cuando se ve; lo único que cambia es la altura.
    component BlinkCaret: Rectangle {
        width: Theme.dp(2)
        radius: width / 2
        color: Theme.accent
        SequentialAnimation on opacity {
            running: visible
            loops: Animation.Infinite
            NumberAnimation { to: 0.15; duration: 480; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1;    duration: 480; easing.type: Easing.InOutQuad }
        }
    }

    Column {
        id: pwCol
        width: parent.width
        spacing: Theme.dp(14)

        // Avatar: inicial en círculo tonal y, si hay foto legible en
        // Config.avatarPath, esa imagen recortada en círculo encima. La
        // inicial va SIEMPRE debajo: si la foto no existe o no carga, no
        // queda hueco (fallback seguro, nada que pueda romper el login).
        Rectangle {
            id: avatarBox
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

            ClippingRectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                visible: avatarImg.status === Image.Ready
                Image {
                    id: avatarImg
                    anchors.fill: parent
                    // Avatar del usuario seleccionado (vacío = sin foto → inicial).
                    source: {
                        const p = Config.avatarFor(GreeterState.selectedUser)
                        return p !== "" ? "file://" + p : ""
                    }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize.width: Math.round(parent.width * 2)
                    sourceSize.height: Math.round(parent.height * 2)
                }
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

        // Campo de contraseña + botón Enter, en una fila.
        Row {
            id: fieldRow
            width: parent.width
            spacing: Theme.dp(10)

            // Campo de contraseña.
            Rectangle {
                id: field
                width: parent.width - enterBtn.width - parent.spacing
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
                    // Resalte del fondo: entra/sale con suavidad; más marcado y
                    // teñido de acento al pulsar.
                    color: revealMa.pressed ? Theme.alpha(Theme.accent, 0.22)
                         : revealMa.containsMouse ? Theme.alpha(Theme.surfaceHi, 0.9)
                         : "transparent"
                    Behavior on color { ColorAnimation { duration: 170; easing.type: Easing.OutCubic } }
                    // Pequeño "pop" elástico: crece al pasar el ratón, se hunde al
                    // pulsar.
                    scale: revealMa.pressed ? 0.86 : revealMa.containsMouse ? 1.10 : 1
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                    Text {
                        id: eyeIcon
                        anchors.centerIn: parent
                        text: GreeterState.revealSecret ? "󰈈" : "󰈉"
                        color: GreeterState.revealSecret ? Theme.accent
                             : revealMa.containsMouse ? Theme.fg : Theme.fgMuted
                        font.family: Theme.font
                        font.pixelSize: Theme.sp(15)
                        // El color del icono transiciona suave, sin saltos.
                        Behavior on color { ColorAnimation { duration: 170; easing.type: Easing.OutCubic } }
                        transform: Scale {
                            id: eyeScale
                            origin.x: eyeIcon.width / 2
                            origin.y: eyeIcon.height / 2
                        }
                    }
                    // Parpadeo del ojo al alternar mostrar/ocultar: se cierra un
                    // instante (encoge en vertical) y vuelve con un rebote suave.
                    Connections {
                        target: GreeterState
                        function onRevealSecretChanged() { eyeBlink.restart() }
                    }
                    SequentialAnimation {
                        id: eyeBlink
                        NumberAnimation { target: eyeScale; property: "yScale"
                                          to: 0.15; duration: 100; easing.type: Easing.InQuad }
                        NumberAnimation { target: eyeScale; property: "yScale"
                                          to: 1;    duration: 190; easing.type: Easing.OutBack }
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
                        BlinkCaret {
                            anchors.verticalCenter: parent.verticalCenter
                            height: Theme.dp(18)
                            visible: pwInput.activeFocus && !GreeterState.busy
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
                        cursorDelegate: BlinkCaret {
                            height: pwInput.cursorRectangle.height
                            visible: !GreeterState.masked && pwInput.activeFocus
                                     && !GreeterState.busy
                        }
                        font.family: Theme.font
                        font.pixelSize: Theme.sp(15)
                        clip: true
                        enabled: !GreeterState.busy && GreeterState.selectedUser !== ""
                        echoMode: GreeterState.masked ? TextInput.Password : TextInput.Normal
                        selectByMouse: false
                        // Tab recorre los controles con la cadena de foco de Qt:
                        // contraseña, botón entrar, selector de sesión, botones de
                        // energía y vuelve aquí (Shift+Tab, al revés).
                        activeFocusOnTab: true
                        // ESC, en orden: cierra el desplegable de sesiones (si se
                        // abrió con el ratón), borra lo tecleado, y vuelve al
                        // selector de usuarios (solo si hay más de uno).
                        Keys.onEscapePressed: {
                            if (GreeterState.busy) return
                            if (sessionSel.open) { sessionSel.open = false; return }
                            if (text.length > 0) { text = ""; GreeterState.error = ""; return }
                            if (GreeterState.users.length > 1) GreeterState.backToUsers()
                        }
                        onAccepted: pw._sendPassword()
                    }
                }
            }

            // Botón Enter: círculo con flecha. En reposo, contorno sutil sobre
            // relleno translúcido; al poder enviar, se rellena de acento (se
            // aclara al pasar el ratón, se oscurece al pulsar). Enfocable con
            // Tab: al recibir foco muestra un anillo y se activa con Enter o
            // Espacio.
            Rectangle {
                id: enterBtn
                width: Theme.dp(46); height: Theme.dp(46)
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                property bool active: pwInput.text.length > 0 && !GreeterState.busy
                                      && GreeterState.selectedUser !== ""

                // Se coge con el tabulador y se pulsa con Enter, como cualquier
                // botón. Mientras esté apagado (sin escribir nada) el tabulador
                // pasa de largo.
                activeFocusOnTab: enterBtn.active
                Keys.onReturnPressed: if (active) pw._sendPassword()
                Keys.onEnterPressed:  if (active) pw._sendPassword()
                Keys.onSpacePressed:  if (active) pw._sendPassword()

                color: !active ? Theme.alpha(Theme.surfaceHi, 0.55)
                     : enterMa.pressed ? Qt.darker(Theme.accent, 1.12)
                     : enterMa.containsMouse ? Qt.lighter(Theme.accent, 1.08)
                     : Theme.accent
                Behavior on color { ColorAnimation { duration: 120 } }
                border.width: active ? 0 : 1
                border.color: Theme.alpha(Theme.overlay, 0.7)
                scale: enterMa.pressed && active ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

                // Anillo de foco al llegar con Tab.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -Theme.dp(3)
                    radius: width / 2
                    color: "transparent"
                    border.width: Theme.dp(2)
                    border.color: Theme.alpha(Theme.accent, 0.55)
                    visible: enterBtn.activeFocus
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰁔"                          // flecha →
                    color: enterBtn.active ? Theme.bg : Theme.fgMuted
                    font.family: Theme.font
                    font.pixelSize: Theme.sp(18)
                    font.bold: true
                }
                MouseArea {
                    id: enterMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: enterBtn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (enterBtn.active) pw._sendPassword()
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
                spacing: Theme.dp(8)
                visible: GreeterState.busy
                // Etiqueta "Cargando" seguida de los 3 puntos que laten como
                // animación de progreso mientras se comprueba la clave / arranca
                // la sesión.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Cargando", "Loading")
                    color: Theme.fgMuted
                    font.family: Theme.font
                    font.pixelSize: Theme.sp(12)
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.dp(6)
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
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
        }

        // Selector de sesión (solo si hay más de una).
        SessionPicker {
            id: sessionSel
            anchors.horizontalCenter: parent.horizontalCenter
            onRequestFocus: if (pw.primary) pwInput.forceActiveFocus()
        }
    }
}
