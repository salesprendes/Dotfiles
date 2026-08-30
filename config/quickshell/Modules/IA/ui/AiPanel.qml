import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Panels.SettingsPages
import qs.Modules.IA.core

// Panel del asistente IA (estilo Material 3, mismo lenguaje que el resto de
// popouts del shell). La lógica vive en AiService: aquí burbujas, entrada,
// adjuntos, conversaciones y la lámina de configuración de proveedores.
Popout {
    id: panel
    ns: "qs-ai"
    // Dos anchos: el de leer una respuesta y el de leer CÓDIGO. El botón de
    // la cabecera lo conmuta y el ajuste lo recuerda.
    cardWidth: Settings.aiWide ? 660 : 480
    cardMinWidth: 340
    shown: Globals.aiOpen
    // El contenido puede superar el alto máximo de la tarjeta —primer arranque con
    // la lámina de configuración abierta, por ejemplo—, y sin esto se recorta en
    // silencio dejando el cajetín de entrada fuera de alcance.
    scrollable: true
    // Sin Behavior sobre cardWidth a propósito: animar el ancho re-maqueta la
    // conversación entera fotograma a fotograma, porque cada burbuja re-envuelve su
    // Markdown. El cambio de ancho es un salto seco.

    // ESC primero para y después cierra: con el agente trabajando, cerrar el panel
    // dejaría el turno corriendo por detrás, y es el gesto que la mano busca sin
    // pensar. La segunda pulsación, ya sin nada que cortar, cierra.
    escapeAction: () => AiService.interrupt()

    property bool configOpen: AiService.notConfigured && AiService.messages.count === 0
    property bool convOpen: false
    property bool modelOpen: false







    // El servicio pide reescribir un mensaje (Editar / ↑): a la entrada.
    Connections {
        target: AiService
        function onEditRequest(text) {
            input.text = text
            input.cursorPosition = input.length
            input.forceActiveFocus()
        }
    }

    // Cabecera
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space10

        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: Theme.dp(34)
            implicitHeight: Theme.dp(34)
            radius: width / 2
            color: SettingsPalette.accentSoft
            // Respira mientras el modelo trabaja: la vida del panel se ve desde
            // la primera mirada, sin leer nada.
            SequentialAnimation on scale {
                running: AiService.busy
                loops: Animation.Infinite
                NumberAnimation { to: 1.12; duration: Math.round(Theme.animLoop / 2); easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: Math.round(Theme.animLoop / 2); easing.type: Easing.InOutSine }
            }
            onScaleChanged: if (!AiService.busy && scale !== 1) scale = 1
            ThemedText {
                anchors.centerIn: parent
                text: "󱙺"
                color: Theme.accentText
                font.pixelSize: Theme.sp(18)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space2
            ThemedText {
                Layout.fillWidth: true
                text: I18n.tr("AI assistant")
                color: Theme.fg
                font.pixelSize: Theme.typeTitleMedium
                font.bold: true
                elide: Text.ElideRight
            }
            // Selector de modelo: enseña el nombre, el proveedor y el semáforo de
            // la conexión, y la lista con buscador se despliega bajo la cabecera.
            ModelChip {
                Layout.alignment: Qt.AlignLeft
                Layout.maximumWidth: parent.width
                Layout.leftMargin: -Theme.space10   // alinea el texto con el título
                open: panel.modelOpen
                onToggled: {
                    panel.modelOpen = !panel.modelOpen
                    if (panel.modelOpen) {
                        panel.convOpen = false
                        panel.configOpen = false
                    }
                }
            }
        }

        // Modo: Chat (solo conversación) ↔ Agente (herramientas con
        // aprobación). Tab en la entrada también lo conmuta.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            width: modeRow.implicitWidth + Theme.space10 * 2
            height: Theme.controlM
            radius: height / 2
            color: AiService.agentMode ? SettingsPalette.accentSoft
                                       : SettingsPalette.settingsControl
            border.width: Theme.hairline
            border.color: AiService.agentMode
                ? Theme.withAlpha(Theme.accent, 0.5) : SettingsPalette.settingsBorder
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            scale: modeMa.pressed ? 0.96 : 1
            Behavior on scale {
                NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
            }
            clip: true

            Ripple { id: modeRipple }

            RowLayout {
                id: modeRow
                anchors.centerIn: parent
                spacing: Theme.space4
                ThemedText {
                    text: AiService.agentMode ? "󰚩" : "󰭹"
                    color: AiService.agentMode ? Theme.accentText : Theme.fgMuted
                    font.pixelSize: Theme.sp(13)
                }
                ThemedText {
                    text: AiService.agentMode ? I18n.tr("Agent") : I18n.tr("Chat")
                    color: AiService.agentMode ? Theme.accentText : Theme.fgDim
                    font.pixelSize: Theme.typeLabelSmall
                    font.bold: true
                }
            }
            MouseArea {
                id: modeMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: (e) => modeRipple.press(e.x, e.y)
                // Dos estados: charlar o actuar. Planificar no es un modo, lo
                // decide el agente al leer el encargo.
                onClicked: panel.cycleMode()
            }
        }

        // Ancho del panel: estrecho para charlar, ancho para leer código.
        IconButton {
            Layout.alignment: Qt.AlignTop
            icon: Settings.aiWide ? "󰊔" : "󰊓"
            diameter: Theme.controlM
            baseColor: "transparent"
            iconColor: Settings.aiWide ? Theme.accentText : Theme.fgDim
            onClicked: Settings.aiWide = !Settings.aiWide
        }
        // Historial de conversaciones.
        IconButton {
            Layout.alignment: Qt.AlignTop
            icon: "󰋚"
            diameter: Theme.controlM
            baseColor: panel.convOpen ? SettingsPalette.accentSoft : "transparent"
            iconColor: panel.convOpen ? Theme.accentText : Theme.fgDim
            onClicked: {
                panel.convOpen = !panel.convOpen
                if (panel.convOpen) {
                    panel.configOpen = false
                    panel.modelOpen = false
                }
            }
        }
        // Nueva conversación.
        IconButton {
            Layout.alignment: Qt.AlignTop
            icon: "󰐕"
            diameter: Theme.controlM
            baseColor: "transparent"
            visible: AiService.messages.count > 0
            onClicked: AiService.newConversation()
        }
        // Configuración de proveedores. Se tiñe de rojo cuando la conexión falla,
        // así que el problema se ve desde la cabecera sin abrir nada.
        IconButton {
            Layout.alignment: Qt.AlignTop
            icon: "󰒓"
            diameter: Theme.controlM
            baseColor: panel.configOpen ? SettingsPalette.accentSoft : "transparent"
            iconColor: AiService.connState === "fail" && !panel.configOpen ? Theme.red
                     : panel.configOpen ? Theme.accentText : Theme.fgDim
            onClicked: {
                panel.configOpen = !panel.configOpen
                if (panel.configOpen) {
                    panel.convOpen = false
                    panel.modelOpen = false
                }
            }
        }
    }

    // Filete bajo la cabecera + medidor de contexto: la línea se va tiñendo
    // de acento según se llena el presupuesto que viaja al modelo, y avisa en
    // rojo cerca del tope, que es el momento de /compactar.
    Item {
        Layout.fillWidth: true
        implicitHeight: Theme.hairline * 2

        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.overlay, Theme.isDark ? 0.5 : 0.35)
        }
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * AiService.contextFill
            color: AiService.contextFill > 0.85 ? Theme.red
                 : Theme.withAlpha(Theme.accent, 0.8)
            Behavior on width { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Theme.animNormal } }
        }
    }

    // Selector de modelo (lámina)
    ExpandableDetail {
        open: panel.modelOpen
        sourceComponent: modelComp
    }

    Component {
        id: modelComp
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: modelCol.implicitHeight + Theme.space12 * 2
            radius: Theme.shapeMd
            color: SettingsPalette.groupFill

            ModelSheet {
                id: modelCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.space12
                onChosen: panel.modelOpen = false
            }
        }
    }

    // Conversaciones (lámina)
    ExpandableDetail {
        open: panel.convOpen
        sourceComponent: convComp
    }

    Component {
        id: convComp
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: convCol.implicitHeight + Theme.space10 * 2
            radius: Theme.shapeMd
            color: SettingsPalette.groupFill

            ColumnLayout {
                id: convCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.space10
                spacing: Theme.space2

                // Acciones sobre la conversación actual: exportarla como Markdown
                // o compactarla en un resumen.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.space6
                    spacing: Theme.space8
                    visible: AiService.messages.count > 0

                    Chip {
                        label: "󰈝 " + I18n.tr("Export")
                        onDo: () => AiService.exportMarkdown()
                    }
                    Chip {
                        label: "󰍃 " + (AiService.compacting
                            ? I18n.tr("Compacting…") : I18n.tr("Compact now"))
                        enabled: !AiService.busy && !AiService.compacting
                                 && !AiService.notConfigured
                        opacity: enabled ? 1 : 0.4
                        onDo: () => {
                            AiService.compact()
                            panel.convOpen = false
                        }
                    }
                    Item { Layout.fillWidth: true }
                    // Lo que lleva gastado esta conversación.
                    ThemedText {
                        visible: AiService.convTokens > 0 || AiService.convMs > 0
                        text: (AiService.convTokens > 0 ? AiService.convTokens + " tok · " : "")
                              + (AiService.convMs / 1000).toFixed(0) + " s"
                        color: Theme.fgMuted
                        font.pixelSize: Theme.typeLabelSmall
                    }
                }

                EmptyNote {
                    visible: AiService.conversations.length === 0
                    text: I18n.tr("No conversations yet.")
                }

                Repeater {
                    model: AiService.conversations
                    delegate: Rectangle {
                        id: convRow
                        required property var modelData
                        readonly property bool current: modelData.id === AiService.currentId
                        Layout.fillWidth: true
                        implicitHeight: Theme.dp(42)
                        color: "transparent"
                        clip: true

                        RowHighlight {
                            id: convRealce
                            hovered: convMa.containsMouse
                            selected: convRow.current
                        }

                        // Debajo de la fila entera; el botón de borrar, declarado
                        // después, gana los clics que le caen.
                        MouseArea {
                            id: convMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: (e) => convRealce.press(e.x, e.y)
                            onClicked: {
                                AiService.switchTo(convRow.modelData.id)
                                panel.convOpen = false
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space10
                            anchors.rightMargin: Theme.space6
                            spacing: Theme.space8

                            ThemedText {
                                text: "󰭹"
                                color: convRow.current ? Theme.accentText : Theme.fgMuted
                                font.pixelSize: Theme.sp(13)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                ThemedText {
                                    Layout.fillWidth: true
                                    text: convRow.modelData.title
                                    color: convRow.current ? Theme.fg : Theme.fgDim
                                    font.pixelSize: Theme.typeLabelLarge
                                    font.bold: convRow.current
                                    elide: Text.ElideRight
                                }
                                // Cuándo y cuánto: fecha del último mensaje y
                                // tamaño del hilo, para reconocerlo sin abrirlo.
                                ThemedText {
                                    Layout.fillWidth: true
                                    text: new Date(convRow.modelData.updated)
                                              .toLocaleDateString(Qt.locale(), "d MMM")
                                          + " · " + convRow.modelData.entries.length
                                          + " msg"
                                    color: Theme.fgMuted
                                    font.pixelSize: Theme.typeLabelSmall
                                    elide: Text.ElideRight
                                }
                            }
                            RowDelete {
                                diameter: Theme.dp(24)
                                iconPixelSize: Theme.sp(12)
                                onClicked: AiService.deleteConversation(convRow.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // Vive entera en AiSettings.qml: la lámina es tan larga como el resto del
    // panel junto, y mezclar "cómo se ve una conversación" con "qué permisos tiene
    // el agente" en un solo archivo no ayuda.
    ExpandableDetail {
        open: panel.configOpen
        sourceComponent: configComp
    }

    Component {
        id: configComp
        AiSettings {}
    }


    // Conversación
    ListView {
        id: chat
        Layout.fillWidth: true
        // Alto adaptativo: se ciñe a la conversación y crece con ella hasta el
        // tope, donde empieza a desplazar. Con el panel ancho se estira también a
        // lo alto, porque quien lo abre para leer código quiere ver más. Sin
        // conversación manda la invitación, cuyos chips piden lo que piden: con un
        // alto fijo, el último quedaría cortado por la mitad.
        //
        // Va a saltos y no al píxel: mientras el modelo escribe, contentHeight
        // cambia en cada token, y con un vínculo exacto cada token forzaría una
        // redisposición de la columna entera. Redondear hacia arriba a múltiplos de
        // ocho corta ese trabajo por ocho, y el salto es menor que el interlineado.
        Layout.preferredHeight: AiService.messages.count === 0 && !AiService.busy
            ? Math.max(Theme.dp(250), emptyCol.implicitHeight + Theme.space16 * 2)
            : Math.max(Theme.dp(250), Math.ceil(
                Math.min(Settings.aiWide ? Theme.dp(560) : Theme.dp(460),
                         contentHeight + Theme.space8) / 8) * 8)
        // Sin Behavior sobre este alto: el alto de la lista entra en la cuenta del
        // final (_finY = contentHeight - height), así que animarlo movería el
        // destino del seguimiento en cada fotograma mientras el modelo escribe, y
        // el pegado perseguiría un blanco que no para. El escalón de ocho píxeles
        // es menor que un interlineado; el temblor no.
        clip: true
        spacing: Theme.space12
        model: AiService.messages
        boundsBehavior: Flickable.StopAtBounds

        // Los mensajes entran fundiendo y asentándose desde un poco más
        // pequeños: apareciendo de golpe ya colocados, una conversación con
        // herramientas —donde cada ronda añade varias tarjetas seguidas— se lee
        // como una lista que da tirones.
        //
        // Y entran en fila, no en montón: cada una espera un poco más que la
        // anterior dentro de su lote (targetIndexes son las que entran en este
        // mismo movimiento), así que una ronda de tres herramientas cae en
        // cascada en vez de aparecer como un bloque.
        //
        // El retardo se acota a tres: con seis tarjetas, esperar seis turnos haría
        // que la última llegara cuando ya no se mira.
        add: Transition {
            id: entrada
            SequentialAnimation {
                PauseAnimation {
                    duration: {
                        const t = entrada.ViewTransition.targetIndexes
                        const k = t ? t.indexOf(entrada.ViewTransition.index) : 0
                        return Math.min(3, Math.max(0, k))
                               * Math.round(Theme.animFast * 0.5)
                    }
                }
                ParallelAnimation {
                    NumberAnimation {
                        property: "opacity"; from: 0; to: 1
                        duration: Theme.animNormal; easing.type: Theme.enterEasing
                    }
                    NumberAnimation {
                        property: "scale"; from: 0.96; to: 1
                        duration: Theme.animNormal; easing.type: Theme.enterEasing
                    }
                    // Y suben a su sitio: un fundido a secas no tiene dirección,
                    // la tarjeta simplemente está. Naciendo unos píxeles más abajo
                    // se lee como algo que llega por el pie de la conversación, que
                    // es de donde llega.
                    NumberAnimation {
                        property: "y"
                        from: entrada.ViewTransition.destination.y + Theme.dp(12)
                        duration: Theme.animNormal; easing.type: Theme.enterEasing
                    }
                }
            }
        }
        // Y los de al lado se apartan en vez de teletransportarse.
        displaced: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: Theme.animNormal; easing.type: Theme.reflowEasing
            }
        }

        // Volver abajo es un viaje y no un corte: el botón flotante desliza hasta
        // el final para que se vea de dónde se venía.
        NumberAnimation {
            id: scrollToEnd
            target: chat
            property: "contentY"
            duration: Theme.animNormal
            easing.type: Theme.reflowEasing
            // Al llegar, el remate exacto: durante el viaje el contenido puede
            // haber crecido, así que el destino calculado al salir ya no es el
            // final. Sin esto, el botón
            onStopped: {
                if (chat.moving || chat.dragging)
                    return
                // El remate es INCONDICIONAL, no pasa por _pegarAbajo: quien
                // pulsó el botón quiere el final, y el guardián de "te has ido
                // arriba" no pinta nada aquí — de hecho, con una estimación
                // corta el propio viaje podía dejar la vista por encima del
                // umbral y soltar el seguimiento justo al llegar.
                chat.follow = true
                chat._alFinal()
            }
        }

        // Visible en reposo y no solo al usarla: con conversación larga, la barra
        // dice de un vistazo cuánto hay por encima.
        //
        // Se dibuja encima del contenido —es un decorado del Flickable y no ocupa
        // sitio—, así que se le reserva un carril y las tarjetas se ciñen a él,
        // solo cuando la barra está, para que sin desplazamiento se aproveche todo
        // el ancho. Sin Behavior: animarlo cambiaría el ancho de todas las tarjetas
        // fotograma a fotograma, que es rehacer la maqueta entera.
        //
        // Y medido, no vinculado: el vínculo directo es un bucle (contentHeight →
        // carril → ancho de tarjetas → alturas → contentHeight) que Qt denuncia en
        // cada carga. Converge solo —añadir carril estrecha, y estrechar solo puede
        // alargar el contenido—, pero el motor no lo sabe, así que se mide después
        // del pase de disposición con Qt.callLater y el ciclo desaparece.
        property int carril: 0
        function _mideCarril() {
            const quiere = contentHeight > height + 1 ? Theme.dp(5) + Theme.space6 : 0
            if (quiere !== carril)
                carril = quiere
        }

        ScrollBar.vertical: ThinScrollBar {
            id: barra
            policy: chat.contentHeight > chat.height + 1
                ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            rightPadding: 0
            restOpacity: 0.35
        }

        // Un solo escritor de contentY, y nunca durante la disposición. Con dos
        // —el seguimiento automático que pega la vista abajo y la animación del
        // botón flotante— y el modelo escribiendo, ambos se pelean dentro del mismo
        // pase de disposición; y como el alto de la lista depende de contentHeight,
        // la cosa se realimenta hasta colgar el hilo gráfico.
        //
        // Dos reglas:
        //   · Mientras el viaje del botón está en marcha, el seguimiento no
        //     escribe. Manda el que empezó.
        //   · La escritura se aplaza con Qt.callLater, así ocurre después del pase
        //     de disposición en curso y no dentro de él.
        property bool follow: true
        // El final de verdad lleva 'originY'. Una lista de alturas variables no
        // guarda su contenido en el intervalo [0, contentHeight]: lo que aún no se
        // ha creado se estima por la media de lo que sí, y el motor absorbe esa
        // corrección moviendo el origen. El tope real de contentY es
        // 'originY + contentHeight - height'.
        //
        // Sin ese sumando fallan las dos direcciones: con origen positivo el pegado
        // se queda corto y la vista deja de bajar aunque la conversación crezca; con
        // origen negativo se pasa de largo, y como escribir contentY a mano no
        // recorta contra los límites, la vista queda clavada en el vacío de debajo
        // del último mensaje.
        readonly property real _finY: originY + Math.max(0, contentHeight - height)
        readonly property bool atBottom: contentY >= _finY - Theme.dp(48)

        // ¿Se ha movido alguien o se ha movido la maqueta? El contenedor solo marca
        // estas banderas cuando el movimiento viene de fuera —rueda, arrastre,
        // tirador—; una recolocación por cambio de contenido no las levanta, que es
        // la diferencia que un umbral en píxeles no sabe hacer.
        readonly property bool _gesto: dragging || flicking || moving || barra.pressed

        // Al engancharse se toma la foto de dónde está la vista y dónde el final:
        // es el punto de partida con el que compara onContentYChanged.
        onFollowChanged: if (follow) { _prevY = contentY; _prevFin = _finY }

        // La ventana del traspaso. Al acabar el turno pasan dos cosas seguidas: el
        // pie se vacía y la tarjeta entra en la lista. Entre medias el contenido
        // encoge y el contenedor sube la vista solo para no salirse.
        //
        // Las dos ocurren en el mismo ciclo, así que el pegado —que va en diferido y
        // funde varias notificaciones en una pasada— no llega a ver el encogido:
        // solo ve "la vista está más arriba", indistinguible de haber subido con la
        // rueda. Mientras dura el traspaso no se suelta el enganche por nada.
        property bool _traspaso: false

        // Cerrojo de reentrada. Escribir contentY notifica, y notificar puede acabar
        // llamando aquí otra vez: sin el pestillo, una pasada que no converja se
        // convierte en un bucle que se come el hilo gráfico.
        property bool _pegando: false

        // Quién suelta el enganche, y por qué se decide aquí y no en el pegado. El
        // pegado va en diferido y funde varias notificaciones del mismo ciclo en una
        // pasada, así que cuando se ejecuta el encogido y el recrecido ya han pasado
        // y lo único visible es "la vista está más arriba".
        //
        // Esta señal llega en el momento de cada cambio, con el estado de al lado
        // todavía en su valor anterior, así que las tres situaciones se distinguen:
        //
        //   · Lo ha escrito el propio pegado (_pegando) → no es gesto de nadie.
        //   · El contenido encoge y el contenedor recoloca para no salirse (fin de
        //     turno) → tampoco.
        //   · La vista sube sin que el final se mueva → eso sí es el usuario.
        //
        // Y además tiene que ser un gesto (_gesto): el umbral en píxeles no
        // distingue una rueda hacia arriba de un reajuste del origen, que mueve la
        // vista sin que nadie la toque.
        property real _prevY: 0
        property real _prevFin: 0
        onContentYChanged: {
            if (!_pegando && follow && !_traspaso && _gesto
                    && _prevY - contentY > Theme.dp(4)
                    && !(_finY < _prevFin - 1))
                follow = false
            _prevY = contentY
            _prevFin = _finY
        }

        function _pegarAbajo() {
            if (_pegando || scrollToEnd.running)
                return
            // Rescate del limbo, antes que nada y con el enganche puesto o no.
            // Escribir contentY a mano no pasa por los límites del contenedor,
            if (!_gesto && (contentY > _finY + Theme.dp(4)
                            || contentY < originY - Theme.dp(4))) {
                _pegando = true
                contentY = Math.max(originY, Math.min(_finY, contentY))
                _pegando = false
            }
            if (!follow)
                return
            // Sin heurísticos: si el enganche sigue puesto, al fondo. Quién lo
            // quita se decide arriba, en el instante del gesto. Media décima de
            // píxel no es un movimiento: escribirla solo dispara otra vuelta de
            // notificaciones.
            //
            // Se escribe contentY a secas y no positionViewAtEnd(): ese crea los
            // delegates que le faltan para medir el final de verdad, con lo que la
            // altura vuelve a cambiar y se llama otra vez a este pegado, y como el
            // sitio donde aterriza no es el 'contentHeight - height' estimado, la
            // condición nunca se apaga. El posicionado exacto se reserva para el
            // botón de bajar, que se pulsa una vez y no se realimenta.
            if (Math.abs(contentY - _finY) > 0.5) {
                _pegando = true
                contentY = _finY
                _pegando = false
            }
        }

        // El final exacto, solo bajo petición. 'contentHeight' en una lista de
        // alturas variables es una estimación: los delegates aún no creados se
        // cuentan por la media de los que sí, y con mensajes muy desiguales se pasa
        // de largo, dejando el limbo por debajo del último mensaje.
        //
        // positionViewAtEnd() no estima: crea lo que haga falta y coloca el final
        // real al pie de la vista. Cuesta esa creación de delegates, así que se usa
        // una vez al aterrizar el botón y jamás en el camino caliente.
        function _alFinal() {
            if (_pegando)
                return
            _pegando = true
            positionViewAtEnd()
            if (contentY > _finY)
                contentY = _finY
            _prevY = contentY
            _prevFin = _finY
            _pegando = false
        }
        onContentHeightChanged: { Qt.callLater(_pegarAbajo); Qt.callLater(_mideCarril) }
        onHeightChanged: { Qt.callLater(_pegarAbajo); Qt.callLater(_mideCarril) }
        // El origen también mueve el final, y lo hace sin tocar contentHeight: la
        // lista reajusta su media al crear o soltar tarjetas y desplaza el contenido
        // entero. Sin escuchar esto, el pegado se enteraría del nuevo final solo al
        // llegar el siguiente token, o nunca si el turno ya acabó.
        onOriginYChanged: Qt.callLater(_pegarAbajo)
        // Una tarjeta nueva es contenido nuevo, y de eso trata seguir la
        // conversación. No basta con contentHeight: una tarjeta entra con su
        // animación, así que su altura llega a plazos y el pegado de ese momento se
        // queda corto. Al terminar la transición se vuelve a pegar.
        onCountChanged: { Qt.callLater(_pegarAbajo); repegar.restart() }
        Timer {
            id: repegar
            // Lo bastante para que la tarjeta nueva haya terminado de entrar, con
            // su animación y el retardo escalonado de las que llegan en lote.
            interval: Theme.animNormal * 2 + 80
            onTriggered: {
                chat._pegarAbajo()
                // Se cierra la ventana después del último pegado: a partir de aquí,
                // si la vista se aleja del fondo es que la ha movido el usuario.
                chat._traspaso = false
            }
        }
        // Soltar el enganche es cosa del usuario y no de cualquier meneo: al acabar
        // el turno la respuesta pasa del footer a la lista, el contenido encoge por
        // un instante y el Flickable se recoloca solo. Solo cuenta como marcharse si
        // de verdad se ha subido respecto al último pegado.
        //
        // Llegar al fondo por su propio pie vuelve a enganchar. Soltarlo ya no se
        // decide aquí (ver onContentYChanged): este aviso llega cuando el movimiento
        // ha terminado, y para entonces la maqueta puede haberse movido sola.
        onMovementEnded: if (atBottom) follow = true
        // Arrastrar o usar la rueda cancela el viaje: si no, el botón seguiría
        // tirando de la vista mientras el usuario intenta subir.
        onMovementStarted: scrollToEnd.stop()

        // Preguntar es querer ver la respuesta: si el usuario se había ido a leer
        // algo de más arriba el seguimiento se soltó, pero en cuanto arranca un
        // turno nuevo se vuelve a enganchar solo.
        Connections {
            target: AiService
            function onBusyChanged() {
                // Fin de turno: lo que se estaba escribiendo vivía en el footer y
                // nace como tarjeta de la lista con su animación, así que la altura
                // definitiva llega unos fotogramas después. Un solo pegado aquí
                // mediría el hueco intermedio, así que se pega ahora y otra vez
                // cuando la entrada ha terminado.
                if (!AiService.busy) {
                    if (chat.follow) {
                        chat._traspaso = true
                        Qt.callLater(chat._pegarAbajo)
                        repegar.restart()
                    }
                    return
                }
                scrollToEnd.stop()
                // 'follow' no se toca aquí: re-engancharlo con atBottom haría lo
                // contrario de lo que parece, porque al arrancar el turno el mensaje
                // del usuario ya está puesto y el contenido ya ha crecido, así que
                // atBottom daría falso y el seguimiento se apagaría para todo el
                // turno. Quien decide es el usuario, y ya lo ha dicho al enviar.
                Qt.callLater(chat._pegarAbajo)
            }
        }

        // Estado vacío: la invitación
        Item {
            // Un Item declarado dentro de un Flickable se reparenta a su
            // contentItem, cuyo alto es contentHeight y con cero mensajes vale
            // cero: la invitación quedaría centrada en y=0, medio cortada por el
            // clip. Se re-cuelga del propio ListView para que las anclas midan
            // contra el viewport.
            parent: chat
            anchors.fill: parent
            visible: AiService.messages.count === 0 && !AiService.busy

            ColumnLayout {
                id: emptyCol
                anchors.centerIn: parent
                width: Math.min(parent.width, Theme.dp(340))
                spacing: Theme.space12

                // Saludo según la hora: un panel que sabe si es de día.
                ThemedText {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        const h = new Date().getHours()
                        return h < 7 ? I18n.tr("Good night") : h < 14 ? I18n.tr("Good morning")
                             : h < 21 ? I18n.tr("Good afternoon") : I18n.tr("Good night")
                    }
                    color: Theme.fg
                    font.pixelSize: Theme.typeTitleMedium
                    font.weight: Font.Medium
                }
                ThemedText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󱙺"
                    color: Theme.withAlpha(Theme.accent, 0.55)
                    font.pixelSize: Theme.sp(52)
                }
                ThemedText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: AiService.urlMissing
                        ? I18n.tr("Point the panel at your server to start.")
                        : AiService.keyMissing
                        ? I18n.tr("Pick a provider and add its key to start.")
                        : I18n.tr("Ask anything. Attach your clipboard or screen for context.")
                    color: Theme.fgMuted
                    font.pixelSize: Theme.typeBodyMedium
                    wrapMode: Text.WordWrap
                }

                // Sin configurar, un solo camino a la vista: abrir la conexión.
                Chip {
                    Layout.alignment: Qt.AlignHCenter
                    visible: AiService.notConfigured
                    label: "󰒋  " + I18n.tr("Set up the connection")
                    onDo: () => {
                        panel.configOpen = true
                        panel.convOpen = false
                    }
                }

                // Arranques que enseñan lo que el panel sabe hacer.
                Flow {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    spacing: Theme.space8
                    visible: !AiService.notConfigured

                    Chip {
                        label: I18n.tr("Summarize my clipboard")
                        onDo: () => {
                            AiService.attachClipboard()
                            input.text = I18n.tr("Summarize this:")
                            input.forceActiveFocus()
                        }
                    }
                    Chip {
                        label: I18n.tr("What's on my screen?")
                        onDo: () => {
                            input.text = I18n.tr("What's on my screen?")
                            AiService.draft = input.text
                            AiService.attachScreenshot()
                        }
                    }
                    Chip {
                        label: I18n.tr("Explain this command:")
                        onDo: () => {
                            input.text = I18n.tr("Explain this command:") + " "
                            input.cursorPosition = input.length
                            input.forceActiveFocus()
                        }
                    }
                }
            }
        }

        // Se puentea por 'model.*' explícitamente: las propiedades propias de
        // MessageBubble taparían los roles inyectados del ListModel.
        delegate: MessageBubble {
            width: chat.width - chat.carril
            role: model.role
            content: model.content
            reasoning: model.reasoning
            modelName: model.modelName
            ms: model.ms
            tokens: model.tokens
            toolName: model.toolName
            toolArgs: model.toolArgs
            toolResult: model.toolResult
            toolStatus: model.toolStatus
            attachNote: model.attachNote
            ts: model.ts
            undoPath: model.undoPath
            msgIndex: model.index
            isLast: model.index === chat.count - 1
        }

        // Burbuja en vivo en el footer: no reconstruye la lista por token.
        //
        // El 'spacing' del ListView separa delegates y al footer no le llega, así
        // que el hueco va arriba: reservado abajo, la respuesta nacería pegada al
        // último mensaje hasta que la lista se rehiciera.
        footer: Item {
            width: chat.width - chat.carril
            height: AiService.busy ? liveCol.implicitHeight + Theme.space12 : 0

            ColumnLayout {
                id: liveCol
                y: Theme.space12
                width: parent.width
                visible: AiService.busy
                spacing: Theme.space6

                MessageBubble {
                    Layout.fillWidth: true
                    visible: AiService.liveText !== ""
                    // 'busy' y no 'true': con live fijo, sus animaciones de "sigue
                    // trabajando" girarían en bucle desde que el panel se
                    // construye, y con keepAlive el panel no muere al cerrarse.
                    live: AiService.busy
                    role: "assistant"
                    content: AiService.liveText
                    modelName: AiService.model
                }

                // Razonamiento EN VIVO, atenuado: se ve pensar sin robar
                // protagonismo.
                RowLayout {
                    visible: AiService.liveText === "" && AiService.liveThink !== ""
                    Layout.leftMargin: Theme.dp(36)
                    Layout.rightMargin: Theme.space8
                    spacing: Theme.space8

                    Rectangle {
                        Layout.fillHeight: true
                        Layout.topMargin: Theme.space2
                        Layout.bottomMargin: Theme.space2
                        implicitWidth: Theme.dp(2)
                        radius: width / 2
                        color: Theme.withAlpha(Theme.accent, 0.5)
                    }
                    ThemedText {
                        Layout.fillWidth: true
                        text: AiService.liveThink.slice(-280)
                        color: Theme.fgMuted
                        font.pixelSize: Theme.typeBodySmall
                        font.italic: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                        elide: Text.ElideLeft
                    }
                }

                // Paso del agente y cola de mensajes: el estado del harness,
                // dicho en voz baja bajo la burbuja viva.
                RowLayout {
                    Layout.leftMargin: Theme.dp(36)
                    spacing: Theme.space10
                    visible: (AiService.agentMode && AiService.toolRounds > 0)
                             || AiService.sendQueue.length > 0
                    ThemedText {
                        visible: AiService.agentMode && AiService.toolRounds > 0
                        text: I18n.tr("Step %1 of %2")
                            .arg(AiService.toolRounds).arg(AiService.maxToolRounds)
                        color: Theme.fgMuted
                        font.pixelSize: Theme.typeLabelSmall
                    }
                    ThemedText {
                        visible: AiService.sendQueue.length > 0
                        text: I18n.tr("Queued: %1").arg(AiService.sendQueue.length)
                        color: Theme.accentText
                        font.pixelSize: Theme.typeLabelSmall
                        font.bold: true
                    }
                }

                // Tres puntos respirando mientras aún no ha dicho nada.
                RowLayout {
                    visible: AiService.liveText === "" && AiService.liveThink === ""
                    spacing: Theme.space4
                    Layout.leftMargin: Theme.dp(36)
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: Theme.dp(7); height: width; radius: width / 2
                            color: Theme.accent
                            opacity: 0.25
                            SequentialAnimation on opacity {
                                running: AiService.busy
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * Math.round(Theme.animLoop / 9) }
                                NumberAnimation { to: 0.9; duration: Math.round(Theme.animLoop / 3) }
                                NumberAnimation { to: 0.25; duration: Math.round(Theme.animLoop / 3) }
                            }
                        }
                    }
                }
            }
        }

        // Botón de "volver abajo".
        IconButton {
            // Mismo caso que la invitación: dentro del Flickable acabaría en el
            // contentItem, anclado al fondo del contenido y por tanto fuera de
            // pantalla justo cuando toca verlo. Del viewport, como corresponde a un
            // control flotante.
            parent: chat
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.space8
            icon: "󰅀"
            diameter: Theme.dp(30)
            baseColor: SettingsPalette.accentSoft
            iconColor: Theme.accentText
            // Durante el viaje se queda: desapareciendo al cruzar el umbral de
            // "abajo" se esfumaría bajo el puntero a mitad de pulsación.
            visible: chat.contentHeight > chat.height
                     && (!chat.atBottom || scrollToEnd.running)
            onClicked: {
                // Se corta cualquier inercia y cualquier viaje anterior antes de
                // empezar el nuevo: dos animaciones sobre contentY, o una animación
                // contra un flick, es la pelea que cuelga el panel.
                chat.cancelFlick()
                scrollToEnd.stop()
                chat.follow = true
                scrollToEnd.from = chat.contentY
                // El destino es la estimación, y por eso el viaje se remata con
                // _alFinal() al llegar: el trayecto se ve, pero quien decide dónde
                // para es el contenido medido y no una media.
                scrollToEnd.to = chat._finY
                scrollToEnd.start()
            }
        }
    }

    // Adjuntos: acciones + chips de lo pendiente
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8

        AttachButton { icon: "󰅍"; onDo: () => AiService.attachClipboard() }
        AttachButton { icon: "󰒉"; onDo: () => AiService.attachSelection() }
        AttachButton {
            icon: "󰹑"
            onDo: () => {
                AiService.draft = input.text     // sobrevive al cierre del panel
                AiService.attachScreenshot()
            }
        }

        Flow {
            id: attFlow
            Layout.fillWidth: true
            spacing: Theme.space6

            Repeater {
                model: AiService.pendingAtts
                delegate: Rectangle {
                    id: attChip
                    required property var modelData
                    required property int index
                    // Con tope: una etiqueta larga haría la píldora más ancha que
                    // el panel. Solo con el Flow ya medido, porque contra un ancho
                    // 0 la píldora se quedaría en nada.
                    readonly property real natural:
                        attRow.implicitWidth + Theme.space10 * 2
                    width: attFlow.width > 0
                           ? Math.min(natural, attFlow.width) : natural
                    height: Theme.dp(26)
                    radius: height / 2
                    color: SettingsPalette.accentSoft
                    // Entra creciendo: pegar el portapapeles o una captura es una
                    // acción a ciegas, así que el chip tiene que acusar el golpe
                    // para confirmarla.
                    ParallelAnimation {
                        running: true
                        NumberAnimation {
                            target: attChip; property: "scale"; from: 0.6; to: 1
                            duration: Theme.animNormal; easing.type: Theme.enterEasing
                        }
                        NumberAnimation {
                            target: attChip; property: "opacity"; from: 0; to: 1
                            duration: Theme.animNormal
                        }
                    }

                    RowLayout {
                        id: attRow
                        anchors.centerIn: parent
                        spacing: Theme.space4
                        ThemedText {
                            text: attChip.modelData.kind === "image" ? "󰋩" : "󰈙"
                            color: Theme.accentText
                            font.pixelSize: Theme.sp(12)
                        }
                        ThemedText {
                            // La etiqueta es lo único que puede crecer aquí, así
                            // que es lo único que se recorta. Nunca por debajo de
                            // cero: con un ancho negativo el elide no recorta y el
                            // texto se sale por los dos lados.
                            Layout.maximumWidth: Math.max(0, attFlow.width
                                - Theme.space10 * 2 - Theme.dp(38))
                            elide: Text.ElideMiddle
                            text: attChip.modelData.label
                            color: Theme.accentText
                            font.pixelSize: Theme.typeLabelSmall
                            font.bold: true
                        }
                        ThemedText {
                            text: "󰅖"
                            color: Theme.fgMuted
                            font.pixelSize: Theme.sp(11)
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -Theme.space4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: AiService.removeAttachment(attChip.index)
                            }
                        }
                    }
                }
            }
        }
    }

    // Mientras un subagente investiga, el principal está callado: esta línea dice
    // qué está pasando y ofrece el freno de mano.
    RevealBar {
        id: subBar
        want: AiService.activeSub !== null
        barHeight: Theme.dp(36)
        radius: Theme.shapeSm
        color: SettingsPalette.accentSoft

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: subBar.barHeight
            anchors.leftMargin: Theme.space10
            anchors.rightMargin: Theme.space6
            spacing: Theme.space8

            ThemedText {
                id: subSpin
                text: "󰳆"
                color: Theme.accentText
                font.pixelSize: Theme.sp(14)
                RotationAnimation on rotation {
                    running: AiService.activeSub !== null
                    from: 0; to: 360
                    duration: Theme.animLoop * 2
                    loops: Animation.Infinite
                }
                onRotationChanged: if (!AiService.activeSub && rotation !== 0) rotation = 0
            }
            ThemedText {
                Layout.fillWidth: true
                // Uno: su etiqueta y su ronda. Varios: cuántos y qué hacen, que no
                // caben tres líneas de detalle.
                text: AiService.activeSubs.length > 1
                    ? I18n.tr("%1 subagents working…").arg(AiService.activeSubs.length)
                      + "  " + AiService.activeSubs.map(s => s.label).join(" · ")
                    : AiService.activeSub
                        ? I18n.tr("Subagent: %1 — round %2 of %3")
                              .arg(AiService.activeSub.label)
                              .arg(AiService.activeSub.rounds)
                              .arg(AiService.activeSub.maxRounds)
                          // Qué está haciendo ahora. Un subagente corre sin
                          // tarjetas: si la barra solo cuenta rondas, lo que hace
                          // es invisible mientras lo hace.
                          + (AiService.activeSub.lastTool !== ""
                             ? "  ·  " + AiService.activeSub.lastTool : "")
                        : ""
                color: Theme.accentText
                font.pixelSize: Theme.typeLabelMedium
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            IconButton {
                icon: "󰓛"
                diameter: Theme.dp(26)
                iconPixelSize: Theme.sp(12)
                baseColor: "transparent"
                iconColor: Theme.red
                // Para a TODOS: el freno de mano no distingue cuál.
                onClicked: {
                    const subs = AiService.activeSubs.slice()
                    for (let i = 0; i < subs.length; i++)
                        subs[i].cancel()
                }
            }
        }
    }

    // Un trabajo largo corriendo no puede ser invisible: si algo sigue vivo detrás
    // de la conversación, aquí se ve y desde aquí se corta.
    RevealBar {
        id: jobBar
        want: AiService.runningJobs.length > 0
        barHeight: Theme.dp(36)
        radius: Theme.shapeSm
        color: SettingsPalette.accentSoft

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: jobBar.barHeight
            anchors.leftMargin: Theme.space10
            anchors.rightMargin: Theme.space6
            spacing: Theme.space8

            ThemedText {
                text: "󱜯"
                color: Theme.accentText
                font.pixelSize: Theme.sp(14)
                RotationAnimation on rotation {
                    running: AiService.runningJobs.length > 0
                    from: 0; to: 360
                    duration: Theme.animLoop * 3
                    loops: Animation.Infinite
                }
                // El mismo reset que su gemelo del supervisor: al acabar el último
                // trabajo la animación se corta donde esté y el glifo se quedaría
                // torcido en un ángulo arbitrario.
                onRotationChanged: if (AiService.runningJobs.length === 0 && rotation !== 0) rotation = 0
            }
            ThemedText {
                Layout.fillWidth: true
                text: AiService.runningJobs.length === 0 ? ""
                    : I18n.tr("%1 running in the background")
                          .arg(AiService.runningJobs.length)
                      + "  " + AiService.runningJobs.map(j => j.label).join(" · ")
                color: Theme.accentText
                font.pixelSize: Theme.typeLabelMedium
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            IconButton {
                icon: "󰓛"
                diameter: Theme.dp(26)
                iconPixelSize: Theme.sp(12)
                baseColor: "transparent"
                iconColor: Theme.red
                onClicked: {
                    const vivos = AiService.runningJobs.slice()
                    for (let i = 0; i < vivos.length; i++)
                        AiService.stopJob(vivos[i].jobId)
                }
            }
        }
    }

    // El harness ha decidido que estas instrucciones vienen a cuento y se las ha
    // dado al modelo sin que las pidiera. Se dice: una ayuda invisible es
    // indistinguible de un modelo que se comporta raro.
    RevealBar {
        id: skillBar
        want: AiService.autoSkill !== null && AiService.agentMode
        barHeight: Theme.dp(28)
        radius: Theme.shapeSm
        color: SettingsPalette.settingsControl

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: skillBar.barHeight
            anchors.leftMargin: Theme.space10
            anchors.rightMargin: Theme.space10
            spacing: Theme.space8

            ThemedText {
                text: "󰠮"
                color: Theme.accentText
                font.pixelSize: Theme.sp(12)
            }
            ThemedText {
                Layout.fillWidth: true
                text: I18n.tr("Skill in use: %1")
                    .arg(AiService.autoSkill ? AiService.autoSkill.name : "")
                color: Theme.fgDim
                font.pixelSize: Theme.typeLabelSmall
                elide: Text.ElideRight
            }
        }
    }

    // La lista de todo_write, pintada donde se ve el trabajo: encima de la
    // entrada. Se actualiza sola con cada llamada del modelo y desaparece al
    // cambiar o limpiar la conversación.
    RevealBar {
        want: AiService.todos.length > 0
        barHeight: planCol.implicitHeight + Theme.space10 * 2
        radius: Theme.shapeMd
        color: SettingsPalette.groupFill
        border.width: Theme.hairline
        border.color: SettingsPalette.settingsBorder

        ColumnLayout {
            id: planCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.space10
            spacing: Theme.space4

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                ThemedText {
                    text: "󰝖"
                    color: Theme.accentText
                    font.pixelSize: Theme.sp(13)
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: I18n.tr("Plan")
                    color: Theme.fgDim
                    font.pixelSize: Theme.typeLabelMedium
                    font.weight: Font.Medium
                }
                ThemedText {
                    text: AiService.todos.filter(t => t.status === "completed").length
                          + "/" + AiService.todos.length
                    color: Theme.fgMuted
                    font.pixelSize: Theme.typeLabelSmall
                }
            }

            Repeater {
                model: AiService.todos
                delegate: RowLayout {
                    id: todoRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.space8
                    ThemedText {
                        text: todoRow.modelData.status === "completed" ? "󰄲"
                            : todoRow.modelData.status === "in_progress" ? "󰥔" : "󰄱"
                        color: todoRow.modelData.status === "completed" ? Theme.green
                             : todoRow.modelData.status === "in_progress" ? Theme.accentText
                             : Theme.fgMuted
                        font.pixelSize: Theme.sp(12)
                    }
                    ThemedText {
                        Layout.fillWidth: true
                        text: todoRow.modelData.content
                        color: todoRow.modelData.status === "in_progress" ? Theme.fg
                             : todoRow.modelData.status === "completed" ? Theme.fgMuted
                             : Theme.fgDim
                        font.pixelSize: Theme.typeLabelMedium
                        font.strikeout: todoRow.modelData.status === "completed"
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // Al escribir "/" el panel enseña lo que hay, en vez de esconderlo en un
    // mensaje de ayuda que solo aparece al equivocarse. Se filtra al teclear, Tab
    // completa el primero y el clic lo lanza.
    // Cada comando entero en una línea: cómo se llama, su alias en inglés, qué
    // icono lleva, qué dice de sí mismo y qué hace. Una sola tabla para lo que
    // se pinta y lo que se ejecuta, para que no puedan desincronizarse.
    readonly property var slashCommands: [
        { cmd: "/nueva", alias: "/new", glyph: "󰐕", arg: false,
          desc: I18n.tr("New conversation"),
          run: () => AiService.newConversation() },
        { cmd: "/limpiar", alias: "/clear", glyph: "󰃢", arg: false,
          desc: I18n.tr("Wipe the conversation and its context"),
          run: () => AiService.clearConversation() },
        { cmd: "/podar", alias: "/prune", glyph: "󰩹", arg: false,
          desc: I18n.tr("Drop stale tool output without summarizing"),
          run: () => AiService.prune() },
        { cmd: "/sacudir", alias: "/shake", glyph: "󰑮", arg: false,
          desc: I18n.tr("Archive oversized blocks to files and leave their path"),
          run: () => AiService.shake() },
        { cmd: "/compactar", alias: "/compact", glyph: "󰍃", arg: false,
          desc: I18n.tr("Summarize the context so far"),
          run: () => AiService.compact() },
        { cmd: "/traspaso", alias: "/handoff", glyph: "󰗇", arg: false,
          desc: I18n.tr("Hand off to a fresh conversation"),
          run: () => AiService.handoff() },
        { cmd: "/exportar", alias: "/export", glyph: "󰈝", arg: false,
          desc: I18n.tr("Save the conversation as Markdown"),
          run: () => AiService.exportMarkdown() },
        { cmd: "/modelo", alias: "/model", glyph: "󰍜", arg: true,
          desc: I18n.tr("Switch model (provider:model)"),
          run: (a) => { if (a !== "") AiService.setModel(a) } },
        { cmd: "/agente", alias: "/agent", glyph: "󰚩", arg: false,
          desc: I18n.tr("Tools with approval"),
          run: () => Settings.aiMode = "agent" },
        { cmd: "/chat", alias: "/chat", glyph: "󰭹", arg: false,
          desc: I18n.tr("Conversation only"),
          run: () => Settings.aiMode = "chat" }
    ]
    readonly property var slashMatches: {
        const t = input.text.trim().toLowerCase()
        if (!t.startsWith("/") || t.indexOf(" ") !== -1)
            return []
        // También por el nombre en inglés: quien escribe /clear encuentra /limpiar
        // en vez de quedarse mirando una lista vacía.
        return panel.slashCommands.filter(c => c.cmd.startsWith(t)
                                            || c.alias.startsWith(t))
    }

    Rectangle {
        Layout.fillWidth: true
        visible: panel.slashMatches.length > 0
        implicitHeight: slashCol.implicitHeight + Theme.space8 * 2
        radius: Theme.shapeMd
        color: SettingsPalette.groupFill
        border.width: Theme.hairline
        border.color: SettingsPalette.settingsBorder
        // Entra desde abajo, como si subiera de la propia entrada.
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

        ColumnLayout {
            id: slashCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.space8
            spacing: Theme.space2

            Repeater {
                model: panel.slashMatches
                delegate: Rectangle {
                    id: cmdRow
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: Theme.dp(30)
                    color: "transparent"
                    clip: true

                    // La primera es la que se lleva el Enter: se pinta como
                    // ELEGIDA, no como si el ratón estuviera encima. Antes
                    // compartían tono y no había forma de saber cuál era cuál.
                    RowHighlight {
                        id: cmdRealce
                        hovered: cmdMa.containsMouse
                        selected: cmdRow.index === 0 && !cmdMa.containsMouse
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space8
                        anchors.rightMargin: Theme.space8
                        spacing: Theme.space8
                        ThemedText {
                            text: cmdRow.modelData.glyph
                            color: Theme.accentText
                            font.pixelSize: Theme.sp(13)
                        }
                        Text {
                            text: cmdRow.modelData.cmd
                            color: Theme.fg
                            font.family: Theme.monoFontFamily
                            font.pixelSize: Theme.typeLabelMedium
                            font.bold: true
                        }
                        ThemedText {
                            Layout.fillWidth: true
                            text: cmdRow.modelData.desc
                            color: Theme.fgMuted
                            font.pixelSize: Theme.typeLabelSmall
                            elide: Text.ElideRight
                        }
                        ThemedText {
                            visible: cmdRow.index === 0
                            text: "Tab"
                            color: Theme.fgMuted
                            font.pixelSize: Theme.typeLabelSmall
                        }
                    }
                    MouseArea {
                        id: cmdMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: (e) => cmdRealce.press(e.x, e.y)
                        onClicked: panel.runSlash(cmdRow.modelData)
                    }
                }
            }
        }
    }

    // Entrada
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(Theme.dp(42),
                Math.min(input.implicitHeight + Theme.space10 * 2, Theme.dp(120)))
            radius: Theme.shapeLg
            color: SettingsPalette.settingsControl
            border.width: input.activeFocus ? Theme.focusWidth : Theme.hairline
            border.color: input.activeFocus ? Theme.accent : SettingsPalette.settingsBorder
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

            Flickable {
                anchors.fill: parent
                anchors.leftMargin: Theme.space12
                anchors.rightMargin: Theme.space12
                anchors.topMargin: Theme.space10
                anchors.bottomMargin: Theme.space10
                contentWidth: width
                contentHeight: input.implicitHeight
                clip: true
                interactive: contentHeight > height

                TextEdit {
                    id: input
                    width: parent.width
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    selectionColor: Theme.accent
                    // Enter envía; Shift+Enter, línea nueva; ↑ en vacío, edita
                    // tu último mensaje (como recuperar la orden en un shell).
                    Keys.onReturnPressed: (e) => {
                        if (e.modifiers & Qt.ShiftModifier) {
                            e.accepted = false
                            return
                        }
                        panel.submit()
                    }
                    Keys.onUpPressed: (e) => {
                        if (input.text === "" && !AiService.busy)
                            AiService.editLast()
                        else
                            e.accepted = false
                    }
                    // Tab completa el comando resaltado si la paleta está
                    // abierta; si no, conmuta Chat ↔ Agente.
                    Keys.onTabPressed: {
                        if (panel.slashMatches.length > 0)
                            panel.runSlash(panel.slashMatches[0])
                        else
                            panel.cycleMode()
                    }
                    onTextChanged: AiService.draft = text
                    Component.onCompleted: {
                        text = AiService.draft
                        cursorPosition = length
                        forceActiveFocus()
                    }

                    Text {
                        anchors.top: parent.top
                        visible: input.text === ""
                        text: I18n.tr("Ask anything…")
                        color: Theme.fgMuted
                        font: input.font
                    }
                }
            }
        }

        // Enviar / Detener: mismo botón, dos papeles. Late suave mientras
        // trabaja, a juego con el avatar.
        IconButton {
            icon: AiService.busy ? "󰓛" : "󰒊"
            diameter: Theme.dp(42)
            SequentialAnimation on scale {
                running: AiService.busy
                loops: Animation.Infinite
                NumberAnimation { to: 1.07; duration: Math.round(Theme.animLoop / 2); easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: Math.round(Theme.animLoop / 2); easing.type: Easing.InOutSine }
            }
            onScaleChanged: if (!AiService.busy && scale !== 1) scale = 1
            baseColor: AiService.busy
                ? Theme.withAlpha(Theme.red, 0.16)
                : SettingsPalette.accentSoft
            hoverColor: AiService.busy ? Theme.red : Theme.accent
            iconColor: AiService.busy ? Theme.red : Theme.accentText
            onClicked: AiService.busy ? AiService.stop() : panel.submit()
        }
    }

    function submit() {
        const t = input.text.trim()
        if (t.startsWith("/")) {
            handleSlash(t)
            input.text = ""
            AiService.draft = ""
            return
        }
        if (t === "" && AiService.pendingAtts.length === 0)
            return
        // PREGUNTAR ES QUERER VER LA RESPUESTA: enviar re-engancha el
        // seguimiento aunque te hubieras ido a leer más arriba. Es el único
        // gesto que dice sin lugar a dudas "mira aquí abajo", y va antes del
        // envío para que el mensaje propio ya entre con la vista pegada.
        chat.follow = true
        Qt.callLater(chat._pegarAbajo)
        // Ocupado incluido: el servicio lo encola y sale al terminar.
        AiService.send(t)
        input.text = ""
        AiService.draft = ""
    }

    // Charlar o actuar. Nada más: si la tarea merece un plan, lo propone el
    // agente sobre la marcha, no se elige de antemano.
    function cycleMode() {
        Settings.aiMode = AiService.agentMode ? "chat" : "agent"
    }

    // Elegido de la paleta: los que piden argumento se quedan escritos en la
    // entrada esperándolo; el resto se ejecutan en el acto.
    function runSlash(c) {
        if (c.arg) {
            input.text = c.cmd + " "
            input.cursorPosition = input.length
            input.forceActiveFocus()
            return
        }
        handleSlash(c.cmd)
        input.text = ""
        AiService.draft = ""
        input.forceActiveFocus()
    }

    // Comandos slash: acciones de sesión sin soltar el
    // teclado. La entrada los intercepta ANTES de enviar nada al modelo. La
    // ayuda se escribe sola con lo que hay, así que no puede mentir.
    function handleSlash(t) {
        const parts = t.split(/\s+/)
        const name = parts[0].toLowerCase()
        const c = panel.slashCommands.find(x => x.cmd === name || x.alias === name)
        if (!c) {
            AiService.pushInfo(I18n.tr("Commands:") + " "
                + panel.slashCommands.map(x => x.cmd + (x.arg ? " <…>" : "")).join(" · "))
            return
        }
        c.run(parts.slice(1).join(" ").trim())
    }

    // Barra que entra y sale SIN dar un salto. Es el mismo escalar 0→1 que
    // despliega las láminas (ver Components/ExpandableDetail.qml), aplicado a
    // una barra de alto fijo: el alto hace de barrido y la opacidad se deriva
    // del mismo valor. Estas tres —subagente, habilidad en uso y plan—
    // aparecían de golpe en mitad de una respuesta y empujaban la conversación
    // de un fotograma al siguiente, que es justo cuando peor sienta.
    component RevealBar: Rectangle {
        id: bar
        property bool want: false
        property real barHeight: Theme.dp(36)
        property real rev: bar.want ? 1 : 0
        Behavior on rev {
            NumberAnimation {
                duration: Theme.animNormal
                easing.type: bar.want ? Theme.enterEasing : Theme.exitEasing
            }
        }
        Layout.fillWidth: true
        implicitHeight: bar.barHeight * bar.rev
        opacity: Theme.revealOpacity(bar.rev)
        visible: bar.rev > 0.001
        clip: true
    }

    // Botón pequeño de adjuntar.
    component AttachButton: IconButton {
        property var onDo: null
        diameter: Theme.dp(30)
        iconPixelSize: Theme.sp(14)
        baseColor: "transparent"
        iconColor: Theme.fgMuted
        hoverColor: SettingsPalette.accentSoft
        hoverIconColor: Theme.accentText
        onClicked: if (onDo) onDo()
    }

}
