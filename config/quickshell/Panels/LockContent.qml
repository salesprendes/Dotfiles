import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Services

// El CONTENIDO de la pantalla de bloqueo: reloj, tarjeta de autenticación,
// botones de sesión y pista. La superficie de Wayland que lo hospeda está en
// Panels/LockScreen.qml, y la lógica (PAM, estado, respaldo a hyprlock) en
// Services/Lock.qml.
//
// POR QUÉ EN UN ARCHIVO APARTE Y NO DENTRO DE LA SUPERFICIE. Porque así se
// puede PROBAR. Un WlSessionLockSurface solo lo crea el compositor cuando la
// sesión está bloqueada de verdad, así que meter aquí dentro trescientas
// líneas de interfaz significa que la única forma de comprobar que montan es
// bloquearse la sesión — y si algo no carga, te quedas fuera. Siendo un Item
// normal, tests/logica.qml lo instancia en una ventana invisible y comprueba
// que el árbol entero se construye antes de que llegue a usarse en serio.
//
// ── EL REPARTO ──────────────────────────────────────────────────────────────
// Reloj grande arriba, en TODAS las pantallas. La tarjeta de autenticación,
// solo en la principal: dos campos de contraseña compitiendo por el teclado es
// el problema que ya se resolvió con los modales de red.
//
// Dentro de la tarjeta, de arriba abajo: quién eres (avatar y nombre) y el
// tiempo · el campo con su botón de entrar · los avisos de teclado (Bloq Mayús
// y distribución) · el mensaje de PAM · y, separada por un filete, la fila de
// contexto (reproductor, red y batería). Debajo de la tarjeta, los botones de
// sesión y la pista de desbloqueo.
//
// El orden no es arbitrario: lo que necesitas para entrar está arriba y en el
// centro óptico, y lo que solo es información útil de un vistazo —qué suena,
// cuánta batería queda— vive debajo del filete, donde no compite con el campo.
Item {
    id: content

    // La pantalla que hospeda esto. En la sesión de verdad la pone la
    // superficie; en las pruebas, un stub.
    property var screen: null
    // ¿Es el monitor principal? Solo ahí van la tarjeta y los botones: dos
    // campos de contraseña compitiendo por el teclado es el problema que ya se
    // resolvió con los modales de red.
    readonly property bool primary: Quickshell.screens.length > 0
                                    && content.screen === Quickshell.screens[0]
    // Si el bloqueo está activo. Se pasa desde fuera para que las pruebas
    // puedan montar el árbol sin bloquear nada.
    property bool active: Lock.locked

    // ── Fondo ────────────────────────────────────────────────────────────
    // El mismo fondo de escritorio, desenfocado y atenuado. Que sea el
    // mismo importa: desbloquear no es un corte de plano, la imagen ya está
    // donde estaba.
    //
    // El desenfoque va con MultiEffect y no pintando un rectángulo translúcido
    // encima: un velo oscuro apaga la foto entera, mientras que desenfocar
    // mata el DETALLE —que es lo que compite con el texto— y deja el color y
    // la composición. Encima, un texto sobre una superficie desenfocada se
    // lee sin necesidad de tanta oscuridad.
    Image {
        id: wall
        anchors.fill: parent
        source: Wallpaper.current !== "" ? "file://" + Wallpaper.current : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize: Qt.size(content.width, content.height)
        // Se queda VISIBLE debajo del efecto a propósito. MultiEffect es un
        // shader, y un shader puede no ejecutarse: con el renderizador por
        // software —o si el driver falla al reanudar tras suspender— el efecto
        // no pinta nada. Si la imagen estuviera oculta, el resultado sería una
        // pantalla de bloqueo de color plano, sin fondo y sin avisar de por
        // qué. Dejándola debajo, lo peor que pasa es que el fondo salga
        // nítido en vez de desenfocado.
        //
        // El coste de pintarla dos veces cuando el efecto SÍ funciona es un
        // blit de pantalla completa, y solo mientras la sesión está bloqueada.
        visible: status === Image.Ready
    }

    MultiEffect {
        anchors.fill: parent
        source: wall
        // Sin desenfoque no se instancia el efecto: se vería exactamente igual
        // que la imagen de debajo, pintada una segunda vez para nada.
        visible: wall.status === Image.Ready && Settings.lockBlur > 0.001
        blurEnabled: true
        blur: Settings.lockBlur
        // El radio se mide en píxeles, así que un valor fijo desenfoca mucho
        // menos en 4K que en 1080p: se ata al alto de la pantalla para que se
        // vea igual en cualquier monitor.
        //
        // Pero CON TOPE en 64, que es el máximo que Qt da por razonable para
        // MultiEffect: por encima, cada escalón añade otra pasada de
        // reducción y el coste sube sin que la imagen cambie apenas. Sin el
        // tope, un 1440p pedía 72 y un 4K, 108 — justo lo contrario de lo que
        // hace la configuración de Hyprland de esta máquina, que baja el blur
        // a tamaño 2 y una sola pasada precisamente porque es lo que más
        // cuesta en su APU.
        //
        // Aun así esto solo se paga mientras la sesión está bloqueada. Si en
        // este equipo se notara, Ajustes ▸ Shell ▸ En la pantalla de bloqueo
        // ▸ Desenfoque a 0 no lo baja: no llega a instanciar el efecto.
        blurMax: Math.max(16, Math.min(64, Math.round(content.height * 0.05)))
        // Multipasada: con una sola, un radio grande deja bandas.
        blurMultiplier: 1.0
        autoPaddingEnabled: false
    }

    // Atenuado, por encima del desenfoque. Menos que antes (0,45 frente a
    // 0,62) porque el desenfoque ya hace la mitad del trabajo de separar el
    // texto del fondo.
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: wall.status === Image.Ready ? Settings.lockDim : 1
    }

    // ── Reloj (en todas las pantallas) ───────────────────────────────────
    Column {
        id: clockCol
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(content.height * 0.14)
        spacing: Theme.dp(4)

        ThemedText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(Time.now, Time.clockFormat)
            color: Theme.fg
            // Escala con la altura de la pantalla, con tope: en un monitor
            // 4K un tamaño fijo se ve minúsculo y en uno pequeño, enorme.
            font.pixelSize: Math.max(Theme.sp(40),
                                     Math.min(Theme.sp(96),
                                              Math.round(content.height * 0.105)))
            // Ligera, no negrita: a este tamaño el peso fuerte se convierte
            // en una mancha. Es lo que hace que un reloj grande se lea como
            // tipografía y no como un cartel.
            font.weight: Font.Light
        }
        // Fecha LARGA, no la abreviada de la barra: aquí hay sitio de sobra y
        // "sábado, 29 de agosto" se lee de un vistazo desde lejos, que es la
        // distancia a la que se mira una pantalla de bloqueo.
        ThemedText {
            anchors.horizontalCenter: parent.horizontalCenter
            // LongFormat y no un patrón escrito a mano: "d MMMM" da
            // "29 agosto" en castellano, cuando lo natural es "29 de agosto" —
            // y esa preposición cambia en cada idioma (en catalán además se
            // apostrofa: "29 d'agost"). El formato largo de la locale ya sabe
            // todo eso; escribirlo a mano es acertar en uno y fallar en los
            // otros dos.
            text: Time.now.toLocaleDateString(I18n.locale(), Locale.LongFormat)
            color: Theme.fgDim
            font.pixelSize: Math.max(Theme.sp(12),
                                     Math.min(Theme.sp(18),
                                              Math.round(content.height * 0.024)))
        }
    }

    // ── Tarjeta de autenticación (solo en el monitor principal) ──────────
    Item {
        id: card

        visible: content.primary
        // Ancho "regular": lo bastante para que la fila de contexto respire
        // sin que el campo de contraseña quede perdido en medio de un
        // panel gigante.
        width: Math.min(Theme.dp(560), content.width - Theme.dp(64))
        height: cardCol.implicitHeight + Theme.dp(44)
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(clockCol.y + clockCol.height + Theme.dp(48),
                    Math.round((content.height - height) / 2))

        // Sacudida al fallar: el acuse físico de "no". Va en un transform,
        // no en 'x', para no recalcular la posición de la tarjeta en cada
        // fotograma de la animación.
        property real shake: 0
        transform: Translate { x: card.shake }
        Connections {
            target: Lock
            function onFailed() {
                if (content.primary)
                    shakeAnim.restart()
            }
        }
        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: card; property: "shake"; to: -Theme.dp(10); duration: 50 }
            NumberAnimation { target: card; property: "shake"; to: Theme.dp(9);   duration: 60 }
            NumberAnimation { target: card; property: "shake"; to: -Theme.dp(6);  duration: 60 }
            NumberAnimation { target: card; property: "shake"; to: 0;             duration: 60; easing.type: Easing.OutCubic }
        }

        // Entrada: sube un poco y aparece. Al bloquear, la tarjeta llega
        // después del fondo en vez de estar ya puesta.
        opacity: 0
        property real enterY: Theme.dp(18)
        Component.onCompleted: enterAnim.start()
        ParallelAnimation {
            id: enterAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "enterY"; from: Theme.dp(18); to: 0; duration: 480; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            y: card.enterY
            radius: Theme.shapeLg
            color: Theme.withAlpha(Theme.surface, 0.82)
            border.width: Math.max(1, Theme.hairline)
            border.color: Theme.withAlpha(Theme.overlay, 0.45)
            antialiasing: true
        }

        ColumnLayout {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.dp(22)
            anchors.rightMargin: Theme.dp(22)
            spacing: Theme.space12

            // ── Identidad + tiempo ───────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space12

                Avatar {
                    diameter: Theme.dp(56)
                    source: Settings.avatarPath
                    initial: (Quickshell.env("USER") ?? "?").charAt(0).toUpperCase()
                    initialPixelSize: Theme.sp(24)
                    tint: Theme.accent
                    initialColor: Theme.accent
                    fontFamily: Theme.fontFamily
                    isDark: Theme.isDark
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    ThemedText {
                        Layout.fillWidth: true
                        text: Quickshell.env("USER") ?? ""
                        color: Theme.fg
                        font.pixelSize: Theme.sp(17)
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    ThemedText {
                        Layout.fillWidth: true
                        visible: Settings.lockShowWeather && Weather.enabled && Weather.ready
                        text: Weather.icon + "  " + Weather.temp
                              + (Weather.location !== "" ? "  ·  " + Weather.location : "")
                        color: Theme.fgMuted
                        font.pixelSize: Theme.typeBodySmall
                        elide: Text.ElideRight
                    }
                }
            }

            // ── Campo de contraseña + botón de entrar ────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8

                Rectangle {
                    id: field
                    Layout.fillWidth: true
                    implicitHeight: Theme.dp(46)
                    radius: Theme.shapeMd
                    color: Theme.withAlpha(Theme.bg, 0.6)
                    border.width: Math.max(1, Theme.hairline)
                    border.color: Lock.messageIsError ? Theme.withAlpha(Theme.red, 0.8)
                                : pwInput.activeFocus ? Theme.focusRing
                                                      : Theme.withAlpha(Theme.overlay, 0.5)
                    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                    ThemedText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.dp(16)
                        text: "󰌾"
                        color: pwInput.activeFocus ? Theme.accent : Theme.fgMuted
                        font.pixelSize: Theme.sp(14)
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }

                    TextInput {
                        id: pwInput
                        anchors.fill: parent
                        anchors.leftMargin: Theme.dp(42)
                        anchors.rightMargin: Theme.dp(16)
                        verticalAlignment: TextInput.AlignVCenter
                        // El campo se apaga mientras PAM trabaja: seguir
                        // escribiendo durante la comprobación solo sirve
                        // para mandar media contraseña con el siguiente
                        // Enter.
                        enabled: !Lock.busy
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        // Sin retardo: el enmascarado inmediato es lo que
                        // se espera de una pantalla de bloqueo, y lo que
                        // evita enseñar la última letra a quien mire por
                        // encima del hombro.
                        passwordMaskDelay: 0
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.sp(15)
                        selectByMouse: true
                        selectionColor: Theme.withAlpha(Theme.accent, 0.45)
                        // Es el único sitio donde se escribe, así que se
                        // declara como el item con foco DENTRO de la
                        // superficie. Es la mitad declarativa del asunto;
                        // la otra mitad —insistir hasta que el compositor
                        // nos dé el foco de teclado— la hace focusKeeper.
                        focus: true

                        onAccepted: pwInput.send()

                        function send() {
                            if (Lock.submit(pwInput.text))
                                pwInput.text = ""
                        }

                        ThemedText {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            visible: pwInput.text === "" && !Lock.busy
                            text: I18n.tr("Password")
                            color: Theme.fgMuted
                            font.pixelSize: Theme.sp(15)
                        }
                    }

                    Spinner {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.dp(14)
                        visible: Lock.busy
                        font.pixelSize: Theme.sp(14)
                    }
                }

                // Botón de entrar. Redundante con Enter a propósito: en una
                // pantalla de bloqueo con el ratón a mano, no todo el mundo
                // da por hecho que Enter valga.
                Rectangle {
                    implicitWidth: Theme.dp(46)
                    implicitHeight: Theme.dp(46)
                    radius: Theme.shapeMd
                    enabled: !Lock.busy && pwInput.text !== ""
                    opacity: enabled ? 1 : 0.4
                    color: Theme.stateLayer(Theme.accent, Theme.bg,
                                            Theme.stateAlpha(loginMa.containsMouse, loginMa.pressed, false))
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                    ThemedText {
                        anchors.centerIn: parent
                        text: "󰌑"
                        color: Theme.isDark ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.sp(16)
                    }
                    MouseArea {
                        id: loginMa
                        anchors.fill: parent
                        enabled: parent.enabled
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pwInput.send()
                    }
                }
            }

            // ── Avisos de teclado ────────────────────────────────────────
            // Bloq Mayús es la causa número uno de "me sé la contraseña y
            // no entra", y una contraseña enmascarada no deja verlo. La
            // distribución, lo mismo cuando tienes dos: se puede cambiar
            // desde aquí sin salir del bloqueo.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                visible: Keyboard.capsLock || (Keyboard.available && Keyboard.multiple)

                Badge {
                    visible: Keyboard.capsLock
                    glyph: "󰪛"
                    label: I18n.tr("Caps Lock")
                    warn: true
                }
                Badge {
                    visible: Keyboard.available && Keyboard.multiple
                    glyph: "󰌌"
                    label: Keyboard.short
                    clickable: true
                    onActivated: {
                        Keyboard.cycle()
                        // Cambiar de distribución con el ratón se lleva el
                        // foco del campo; se devuelve, o la siguiente tecla
                        // se pierde.
                        pwInput.forceActiveFocus()
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // ── Mensaje de PAM ───────────────────────────────────────────
            ThemedText {
                Layout.fillWidth: true
                visible: Lock.message !== ""
                text: Lock.message
                color: Lock.messageIsError ? Theme.red : Theme.fgDim
                font.pixelSize: Theme.typeBodySmall
                wrapMode: Text.WordWrap
            }

            // Salida de emergencia, y solo cuando hace falta: si la
            // autenticación no arranca (PAM mal configurado), una pantalla
            // de bloqueo sin salida deja la sesión inaccesible. Los TTY
            // siguen ahí y conviene recordarlo en ese momento exacto, no
            // como aviso permanente que nadie lee.
            ThemedText {
                Layout.fillWidth: true
                visible: Lock.messageIsError && Lock.failures === 0
                text: I18n.tr("If authentication cannot start, switch to a TTY with Ctrl+Alt+F2.")
                color: Theme.fgMuted
                font.pixelSize: Theme.typeBodySmall
                wrapMode: Text.WordWrap
            }

            // ── Fila de contexto ─────────────────────────────────────────
            // Bajo el filete: información, no acción. Solo aparece si hay
            // algo que contar, para que la tarjeta se encoja hasta lo justo
            // cuando no lo hay.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space4
                implicitHeight: Theme.hairline
                color: Theme.withAlpha(Theme.overlay, 0.45)
                visible: contextRow.visible
            }

            RowLayout {
                id: contextRow
                Layout.fillWidth: true
                spacing: Theme.space12
                visible: mediaBlock.visible || statusBlock.visible

                // Reproductor. Usa el mismo criterio que la barra
                // (Services/Media.qml), así que aquí tampoco aparece el
                // reproductor fantasma que deja registrado el navegador.
                RowLayout {
                    id: mediaBlock
                    Layout.fillWidth: true
                    spacing: Theme.space8
                    visible: Settings.lockShowMedia && Media.hasMedia

                    ThemedText {
                        text: Media.playing ? "󰝚" : "󰏤"
                        color: Media.playing ? Theme.accent : Theme.fgMuted
                        font.pixelSize: Theme.sp(14)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        ThemedText {
                            Layout.fillWidth: true
                            text: Media.active?.trackTitle || I18n.tr("Untitled")
                            color: Theme.fgDim
                            font.pixelSize: Theme.typeBodySmall
                            elide: Text.ElideRight
                        }
                        ThemedText {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: Media.active?.trackArtist || ""
                            color: Theme.fgMuted
                            font.pixelSize: Theme.typeLabelSmall
                            elide: Text.ElideRight
                        }
                    }
                    // Controlar la música sin desbloquear es justo lo que se
                    // espera de una pantalla de bloqueo.
                    LockIconButton {
                        glyph: "󰒮"
                        enabled: Media.active?.canGoPrevious ?? false
                        onActivated: { Media.active?.previous(); pwInput.forceActiveFocus() }
                    }
                    LockIconButton {
                        glyph: Media.playing ? "󰏤" : "󰐊"
                        enabled: Media.active?.canTogglePlaying ?? false
                        onActivated: { Media.active?.togglePlaying(); pwInput.forceActiveFocus() }
                    }
                    LockIconButton {
                        glyph: "󰒭"
                        enabled: Media.active?.canGoNext ?? false
                        onActivated: { Media.active?.next(); pwInput.forceActiveFocus() }
                    }
                }

                // El empujón a la derecha solo cuando hay música: la fila es
                // "lo que suena · el estado", y sin lo primero un icono de red
                // solo, pegado al canto derecho con medio panel vacío a su
                // izquierda, se lee como algo que se ha quedado a medias. Sin
                // música, el estado arranca a la izquierda y la línea parece lo
                // que es: una línea de estado.
                Item { Layout.fillWidth: true; visible: mediaBlock.visible }

                // Red y batería.

                RowLayout {
                    id: statusBlock
                    spacing: Theme.space10
                    visible: Settings.lockShowStatus

                    RowLayout {
                        spacing: Theme.space6
                        ThemedText {
                            text: Net.icon
                            color: Net.online ? Theme.fgDim : Theme.fgMuted
                            font.pixelSize: Theme.sp(14)
                        }
                        // Con el nombre, no solo el icono: un glifo de wifi
                        // suelto en la esquina no dice nada — la pregunta que
                        // se hace uno al bloquear es "¿sigo conectado a la de
                        // casa?", y para eso hace falta el nombre.
                        ThemedText {
                            Layout.maximumWidth: Theme.dp(150)
                            text: Net.label
                            color: Theme.fgMuted
                            font.pixelSize: Theme.typeLabelSmall
                            elide: Text.ElideRight
                        }
                    }
                    RowLayout {
                        spacing: Theme.space4
                        visible: Battery.present
                        ThemedText {
                            text: Battery.charging ? "󰂄"
                                : Battery.percent >= 80 ? "󰁹"
                                : Battery.percent >= 50 ? "󰁿"
                                : Battery.percent >= 20 ? "󰁽" : "󰁻"
                            color: Battery.percent <= Settings.batteryLowThreshold && !Battery.charging
                                   ? Theme.red : Theme.fgDim
                            font.pixelSize: Theme.sp(14)
                        }
                        ThemedText {
                            text: Battery.percent + "%"
                            color: Theme.fgMuted
                            font.pixelSize: Theme.typeLabelSmall
                        }
                    }
                }
            }
        }
    }

    // ── Botones de sesión ────────────────────────────────────────────────
    // Fuera de la tarjeta: no son parte de entrar, son la alternativa a
    // entrar. Mezclarlos con el campo invita a pulsar "apagar" buscando
    // "aceptar".
    RowLayout {
        visible: content.primary && Settings.lockShowSessionButtons
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: card.bottom
        anchors.topMargin: Theme.dp(28)
        spacing: Theme.space12

        SessionButton { glyph: "󰤄"; label: I18n.tr("Suspend");  action: "suspend" }
        SessionButton { glyph: "󰜉"; label: I18n.tr("Restart");  action: "reboot" }
        SessionButton { glyph: "󰐥"; label: I18n.tr("Shut down"); action: "poweroff" }
    }

    // Pista de desbloqueo. Se esconde en cuanto empiezas a escribir: ya no
    // hace falta, y una línea de texto que sobra bajo el campo distrae.
    ThemedText {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.dp(40)
        visible: content.primary && pwInput.text === "" && !Lock.busy
        text: I18n.tr("Type your password and press Enter")
        color: Theme.fgDim
        font.pixelSize: Theme.typeBodySmall
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
    }

    // ── El foco del campo ────────────────────────────────────────────────
    // Un forceActiveFocus() en Component.onCompleted NO basta, y esa era la
    // razón de que hubiera que hacer clic antes de escribir: la superficie
    // se construye antes de que el compositor le entregue el foco de
    // teclado, así que la petición se hace sobre una ventana que todavía no
    // puede tenerlo y se pierde sin avisar.
    //
    // Aquí se insiste hasta que agarra, con tope para no dejar un temporizador
    // corriendo para siempre si algo va mal. En cuanto pwInput.activeFocus es
    // true, el temporizador se apaga solo (su 'running' lo mira).
    Timer {
        id: focusKeeper
        interval: 60
        repeat: true
        running: content.primary && content.active && !pwInput.activeFocus
                 && focusKeeper.attempts < 100
        property int attempts: 0
        onTriggered: {
            focusKeeper.attempts++
            pwInput.forceActiveFocus()
        }
    }

    // Cada intento de autenticación deja el campo deshabilitado un momento
    // (enabled: !Lock.busy), y un item deshabilitado PIERDE el foco. Sin
    // esto, tras un fallo había que volver a hacer clic para reintentar.
    Connections {
        target: Lock
        function onBusyChanged() {
            if (!Lock.busy && content.primary) {
                focusKeeper.attempts = 0
                Qt.callLater(() => pwInput.forceActiveFocus())
            }
        }
    }

    // ── Piezas locales ───────────────────────────────────────────────────

    // Etiqueta con glifo para los avisos de teclado.
    component Badge: Rectangle {
        id: badge
        property string glyph: ""
        property string label: ""
        property bool warn: false
        property bool clickable: false
        signal activated()

        implicitWidth: badgeRow.implicitWidth + Theme.space10 * 2
        implicitHeight: Theme.dp(26)
        radius: height / 2
        color: badge.warn ? Theme.withAlpha(Theme.orange, 0.20)
             : Theme.stateLayer(Theme.withAlpha(Theme.overlay, 0.22), Theme.fg,
                                Theme.stateAlpha(badgeMa.containsMouse && badge.clickable,
                                                 badgeMa.pressed, false))
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            id: badgeRow
            anchors.centerIn: parent
            spacing: Theme.space6
            ThemedText {
                text: badge.glyph
                color: badge.warn ? Theme.orange : Theme.fgDim
                font.pixelSize: Theme.sp(12)
            }
            ThemedText {
                text: badge.label
                color: badge.warn ? Theme.orange : Theme.fgDim
                font.pixelSize: Theme.typeLabelSmall
            }
        }

        MouseArea {
            id: badgeMa
            anchors.fill: parent
            enabled: badge.clickable
            hoverEnabled: badge.clickable
            cursorShape: Qt.PointingHandCursor
            onClicked: badge.activated()
        }
    }

    // Botón de glifo pequeño (controles del reproductor).
    component LockIconButton: Rectangle {
        id: lib
        property string glyph: ""
        signal activated()

        implicitWidth: Theme.dp(28)
        implicitHeight: Theme.dp(28)
        radius: width / 2
        opacity: enabled ? 1 : 0.35
        color: Theme.withAlpha(Theme.fg,
                               Theme.stateAlpha(libMa.containsMouse, libMa.pressed, false))
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        ThemedText {
            anchors.centerIn: parent
            text: lib.glyph
            color: Theme.fgDim
            font.pixelSize: Theme.sp(13)
        }
        MouseArea {
            id: libMa
            anchors.fill: parent
            enabled: lib.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lib.activated()
        }
    }

    // Botón de sesión: glifo en círculo y etiqueta debajo. Pide
    // confirmación con un segundo clic — apagar el equipo por un clic
    // perdido en una pantalla de bloqueo es una forma tonta de perder lo
    // que tuvieras abierto.
    component SessionButton: ColumnLayout {
        id: sb
        property string glyph: ""
        property string label: ""
        property string action: ""
        property bool armed: false

        spacing: Theme.space4

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Theme.dp(48)
            implicitHeight: Theme.dp(48)
            radius: width / 2
            color: sb.armed ? Theme.withAlpha(Theme.red, 0.28)
                 : Theme.stateLayer(Theme.withAlpha(Theme.surface, 0.8), Theme.fg,
                                    Theme.stateAlpha(sbMa.containsMouse, sbMa.pressed, false))
            border.width: sb.armed ? Math.max(1, Theme.hairline) : 0
            border.color: Theme.withAlpha(Theme.red, 0.8)
            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            ThemedText {
                anchors.centerIn: parent
                text: sb.glyph
                color: sb.armed ? Theme.red : Theme.fgDim
                font.pixelSize: Theme.sp(18)
            }
            MouseArea {
                id: sbMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (sb.armed) {
                        Globals.runPowerAction(sb.action)
                        return
                    }
                    sb.armed = true
                    disarm.restart()
                }
            }
            // El armado caduca: si te has quedado a medias, no se queda un
            // botón rojo esperando a que alguien lo roce.
            Timer {
                id: disarm
                interval: 3000
                onTriggered: sb.armed = false
            }
        }
        // Más contraste que dentro de la tarjeta: aquí el fondo es el fondo de
        // pantalla desenfocado, no una superficie controlada, y 'fgMuted'
        // desaparece sobre una foto clara.
        ThemedText {
            Layout.alignment: Qt.AlignHCenter
            text: sb.armed ? I18n.tr("Confirm") : sb.label
            color: sb.armed ? Theme.red : Theme.fgDim
            font.pixelSize: Theme.typeLabelSmall
        }
    }
}
