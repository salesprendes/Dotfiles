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
    // El contenido puede superar el alto máximo de la tarjeta (primer arranque
    // con la lámina de configuración abierta, p.ej.): sin esto se recortaba en
    // silencio y el cajetín de entrada quedaba fuera, inalcanzable.
    scrollable: true
    // SIN Behavior sobre cardWidth, a propósito: animar el ancho re-maqueta la
    // conversación ENTERA fotograma a fotograma (cada burbuja re-envuelve su
    // Markdown) — la misma pelea que el carril de la barra evita midiendo en
    // diferido. El cambio de ancho es un salto seco, y así debe quedarse.

    // ESC: primero PARA, después cierra. Con el agente trabajando, cerrar el
    // panel no era lo que se pedía —el turno seguía por detrás—, y era el
    // único gesto que la mano busca sin pensar. Segunda pulsación (ya sin nada
    // que cortar) cierra como siempre.
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

    // ── Cabecera ─────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space10

        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: Theme.dp(34)
            implicitHeight: Theme.dp(34)
            radius: width / 2
            color: SettingsPalette.accentSoft
            // Respira mientras el modelo trabaja: la vida del panel se ve
            // desde la primera mirada, sin leer nada.
            SequentialAnimation on scale {
                running: AiService.busy
                loops: Animation.Infinite
                NumberAnimation { to: 1.12; duration: Math.round(Theme.animLoop / 2); easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: Math.round(Theme.animLoop / 2); easing.type: Easing.InOutSine }
            }
            onScaleChanged: if (!AiService.busy && scale !== 1) scale = 1
            Text {
                anchors.centerIn: parent
                text: "󱙺"
                color: Theme.accentText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(18)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space2
            Text {
                Layout.fillWidth: true
                text: I18n.tr("AI assistant")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.typeTitleMedium
                font.bold: true
                elide: Text.ElideRight
            }
            // Selector de modelo: cambiar de cerebro sin abrir la config.
            // Enseña el nombre, el proveedor y el semáforo de la conexión; la
            // lista con buscador se despliega bajo la cabecera.
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
        // aprobación). Tab en la entrada también lo conmuta, como el
        // plan/build de opencode.
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
                Text {
                    text: AiService.agentMode ? "󰚩" : "󰭹"
                    color: AiService.agentMode ? Theme.accentText : Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(13)
                }
                Text {
                    text: AiService.agentMode ? I18n.tr("Agent") : I18n.tr("Chat")
                    color: AiService.agentMode ? Theme.accentText : Theme.fgDim
                    font.family: Theme.fontFamily
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
                // Dos estados: charlar o actuar. Planificar no es un modo — lo
                // decide el agente al leer el encargo (propose_plan).
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
        // Configuración de proveedores. Se tiñe de rojo cuando la conexión
        // falla: el problema se ve desde la cabecera, sin abrir nada.
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
    // rojo cerca del tope — el momento de /compactar (el medidor de contexto
    // de Claude Code, reducido a un hilo de luz).
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

    // ── Selector de modelo (lámina) ──────────────────────────────────────────
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

    // ── Conversaciones (lámina) ──────────────────────────────────────────────
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

                // Acciones sobre la conversación ACTUAL: exportarla como
                // Markdown (entregable) o compactarla en un resumen.
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
                    // Lo que lleva gastado esta conversación (estilo aider).
                    Text {
                        visible: AiService.convTokens > 0 || AiService.convMs > 0
                        text: (AiService.convTokens > 0 ? AiService.convTokens + " tok · " : "")
                              + (AiService.convMs / 1000).toFixed(0) + " s"
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
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

                        // Debajo de la fila entera; el botón de borrar,
                        // declarado después, gana los clics que le caen.
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

                            Text {
                                text: "󰭹"
                                color: convRow.current ? Theme.accentText : Theme.fgMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.sp(13)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: convRow.modelData.title
                                    color: convRow.current ? Theme.fg : Theme.fgDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.typeLabelLarge
                                    font.bold: convRow.current
                                    elide: Text.ElideRight
                                }
                                // Cuándo y cuánto: fecha del último mensaje y
                                // tamaño del hilo, para reconocerlo sin abrirlo.
                                Text {
                                    Layout.fillWidth: true
                                    text: new Date(convRow.modelData.updated)
                                              .toLocaleDateString(Qt.locale(), "d MMM")
                                          + " · " + convRow.modelData.entries.length
                                          + " msg"
                                    color: Theme.fgMuted
                                    font.family: Theme.fontFamily
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

    // ── Configuración (lámina) ───────────────────────────────────────────────
    // Vive entera en AiSettings.qml: la lámina se hizo tan larga como el resto
    // del panel junto, y mezclar "cómo se ve una conversación" con "qué
    // permisos tiene el agente" en un solo archivo ya no ayudaba a nadie.
    ExpandableDetail {
        open: panel.configOpen
        sourceComponent: configComp
    }

    Component {
        id: configComp
        AiSettings {}
    }


    // ── Conversación ─────────────────────────────────────────────────────────
    ListView {
        id: chat
        Layout.fillWidth: true
        // Alto ADAPTATIVO: se ciñe a la conversación y crece con ella hasta
        // el tope, donde empieza a desplazar.
        // Con el panel ancho también se estira a lo alto: quien lo abre para
        // leer código quiere ver más de cinco líneas.
        // Sin conversación manda la INVITACIÓN: el saludo, el icono y los
        // arranques piden lo que pidan, y se les da. Con 250 px fijos, el
        // tercer chip quedaba cortado por la mitad — la primera impresión del
        // panel era una lista recortada.
        //
        // A SALTOS, no al píxel. Mientras el modelo escribe, contentHeight
        // cambia en CADA token; con un vínculo exacto, cada token forzaba una
        // redisposición de la columna entera —y la lista, cuyo alto sale de ahí,
        // volvía a medirse—. Redondear hacia arriba a múltiplos de ocho corta
        // ese trabajo por ocho y en pantalla no se nota: el salto es menor que
        // el interlineado.
        Layout.preferredHeight: AiService.messages.count === 0 && !AiService.busy
            ? Math.max(Theme.dp(250), emptyCol.implicitHeight + Theme.space16 * 2)
            : Math.max(Theme.dp(250), Math.ceil(
                Math.min(Settings.aiWide ? Theme.dp(560) : Theme.dp(460),
                         contentHeight + Theme.space8) / 8) * 8)
        // SIN Behavior sobre este alto, y no por falta de ganas: se probó a
        // interpolar los saltos de ocho píxeles para que el crecimiento se
        // leyera continuo, y el remedio fue peor. El alto de la lista entra en
        // la cuenta del final (_finY = contentHeight - height), así que
        // animarlo mueve el destino del seguimiento en CADA fotograma
        // mientras el modelo escribe: el pegado persigue un blanco que no
        // para, y eso en pantalla es exactamente el temblor que se veía. El
        // escalón de ocho píxeles es menor que un interlineado; el temblor no.
        clip: true
        spacing: Theme.space12
        model: AiService.messages
        boundsBehavior: Flickable.StopAtBounds

        // Los mensajes ENTRAN: funden y se asientan desde un pelín más
        // pequeños. Aparecían de golpe, ya colocados, y en una conversación
        // con herramientas —donde cada ronda añade varias tarjetas seguidas—
        // el efecto era el de una lista que da tirones.
        // Y ENTRAN EN FILA, NO EN MONTÓN. Antes las varias tarjetas de una
        // misma ronda arrancaban su animación a la vez: aparecían fundidas
        // pero simultáneas, que se lee como un bloque que aparece de golpe y
        // no como cosas que van llegando. Ahora cada una espera un pelín más
        // que la anterior DENTRO de su lote (targetIndexes son las que entran
        // en este mismo movimiento), así que una ronda de tres herramientas
        // cae en cascada.
        //
        // El retardo se acota a tres: con seis tarjetas, esperar seis turnos
        // haría que la última llegara cuando ya no la miras. Después de la
        // tercera entran todas juntas y el ojo no lo distingue.
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
                    // Y SUBEN A SU SITIO. Un fundido a secas no tiene
                    // dirección: la tarjeta simplemente está. Naciendo doce
                    // píxeles más abajo se lee como algo que llega por el pie
                    // de la conversación, que es de donde llega de verdad.
                    NumberAnimation {
                        property: "y"
                        from: entrada.ViewTransition.destination.y + Theme.dp(12)
                        duration: Theme.animNormal; easing.type: Theme.enterEasing
                    }
                }
            }
        }
        // Y los de al lado se APARTAN en vez de teletransportarse (al borrar
        // una tarjeta, al rehacer una respuesta).
        displaced: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: Theme.animNormal; easing.type: Theme.reflowEasing
            }
        }

        // Volver abajo es un viaje, no un corte: el botón flotante desliza
        // hasta el final para que se vea DE DÓNDE venías.
        NumberAnimation {
            id: scrollToEnd
            target: chat
            property: "contentY"
            duration: Theme.animNormal
            easing.type: Theme.reflowEasing
            // Al llegar, el remate exacto: durante el viaje el contenido puede
            // haber crecido (el modelo sigue escribiendo), así que el destino
            // que se calculó al salir ya no es el final. Sin esto, el botón
            // dejaba la vista a unos píxeles del fondo y volvía a aparecer.
            //
            // SOLO si el parón es por llegada: onMovementStarted también
            // dispara stop(), y rematar ahí escribía contentY contra el gesto
            // del usuario — el primer toque de rueda durante el viaje te
            // devolvía al fondo de un tirón.
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

        // Visible en reposo (no solo al usarla): con conversación larga, la
        // barra dice de un vistazo cuánto hay por encima.
        // ── El carril de la barra ────────────────────────────────────────────
        // La barra se dibuja ENCIMA del contenido (es un decorado del
        // Flickable, no ocupa sitio), y con rightPadding a cero quedaba pegada
        // al borde derecho. Mientras las respuestas eran texto suelto no se
        // notaba; desde que tienen superficie propia con filete, la barra
        // aterriza justo sobre ese filete y se ven chocar.
        //
        // Se le reserva su carril y las tarjetas se ciñen a él — solo cuando la
        // barra está, para que sin desplazamiento se aproveche todo el ancho.
        // Sin Behavior: animarlo cambiaría el ancho de TODAS las tarjetas
        // fotograma a fotograma, que es rehacer la maqueta de la conversación
        // entera.
        //
        // Y MEDIDO, no vinculado: el vínculo directo era un bucle en toda
        // regla (contentHeight → carril → ancho de tarjetas → alturas →
        // contentHeight) que Qt denunciaba en cada carga del panel y se
        // pagaba en pasadas de maquetación de más. Converge solo —añadir
        // carril estrecha, estrechar solo puede ALARGAR el contenido, así
        // que la condición no se deshace—, pero el motor no lo sabe: se
        // mide DESPUÉS del pase de disposición (Qt.callLater, abajo con
        // _pegarAbajo) y el ciclo desaparece.
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

        // ── Quién escribe contentY ───────────────────────────────────────────
        // UNO SOLO, Y NUNCA DURANTE LA DISPOSICIÓN. Aquí había dos escritores
        // sobre la misma propiedad: el seguimiento automático (que pegaba la
        // vista abajo en cuanto el contenido crecía) y la animación del botón
        // flotante. Con el modelo escribiendo —que hace crecer contentHeight en
        // CADA token— pulsar el botón ponía a los dos a pelearse dentro del
        // mismo pase de disposición, y como el alto de la lista depende a su
        // vez de contentHeight, la cosa se realimentaba. El panel se quedaba
        // clavado, y como Quickshell ES el escritorio, se lo llevaba por
        // delante: de ahí el "hay que reiniciar".
        //
        // Dos reglas y se acabó:
        //   · Mientras el viaje del botón está en marcha, el seguimiento NO
        //     escribe. El que manda es el que empezó.
        //   · La escritura se aplaza con Qt.callLater, así ocurre DESPUÉS del
        //     pase de disposición en curso y no dentro de él. Es lo que rompe
        //     la reentrada.
        property bool follow: true
        // EL FINAL DE VERDAD LLEVA 'originY'. Una lista de alturas variables no
        // guarda su contenido en el intervalo [0, contentHeight]: lo que aún no
        // se ha creado se estima por la media de lo que sí, y el motor absorbe
        // esa corrección moviendo el ORIGEN del contenido. El tope real de
        // contentY es 'originY + contentHeight - height'.
        //
        // Faltando ese sumando fallaban las dos cosas a la vez, y con el mismo
        // origen:
        //   · Origen POSITIVO → el pegado se quedaba corto y la vista dejaba de
        //     bajar aunque la conversación siguiera creciendo. Se notaba justo
        //     cuando entran dos tarjetas de golpe, que es cuando la media —y
        //     con ella el origen— pega el salto más gordo.
        //   · Origen NEGATIVO → el pegado se pasaba de largo. Y escribir
        //     contentY a mano NO recorta contra los límites (eso solo lo hace
        //     el gesto), así que la vista se quedaba clavada en el vacío de
        //     debajo del último mensaje: el "limbo" sin nada que mirar.
        readonly property real _finY: originY + Math.max(0, contentHeight - height)
        readonly property bool atBottom: contentY >= _finY - Theme.dp(48)

        // ¿SE HA MOVIDO ALGUIEN, O SE HA MOVIDO LA MAQUETA? El contenedor solo
        // marca estas banderas cuando el movimiento viene de fuera —rueda,
        // arrastre, tirador de la barra—; una recolocación por cambio de
        // contenido no las levanta. Es la diferencia que el umbral en píxeles
        // nunca supo hacer solo.
        readonly property bool _gesto: dragging || flicking || moving || barra.pressed

        // Al engancharse se toma la foto de dónde está la vista y dónde el
        // final: es el punto de partida con el que compara onContentYChanged.
        onFollowChanged: if (follow) { _prevY = contentY; _prevFin = _finY }

        // LA VENTANA DEL TRASPASO. Al acabar el turno pasan dos cosas seguidas:
        // el pie se vacía (la respuesta deja de estar ahí) y la tarjeta entra
        // en la lista. Entre medias el contenido encoge y el contenedor sube la
        // vista él solo para no salirse.
        //
        // Y las dos ocurren en el MISMO ciclo, así que el pegado —que va en
        // diferido y se funde en una sola pasada— no llega a ver el encogido:
        // solo ve el resultado, "la vista está más arriba", que es idéntico a
        // haber subido con la rueda. De ahí que el enganche se soltara justo al
        // aparecer la respuesta.
        //
        // Mientras dura el traspaso no se suelta por nada: cualquier movimiento
        // de aquí es de la maqueta, no del usuario.
        property bool _traspaso: false

        // CERROJO DE REENTRADA. Escribir contentY notifica, y notificar puede
        // acabar llamando aquí otra vez: sin este pestillo, una sola pasada
        // que no converja se convierte en un bucle que se come el hilo
        // gráfico — y como Quickshell ES el escritorio, se lo lleva por
        // delante. Ya pasó una vez; no se vuelve a tocar este archivo sin él.
        property bool _pegando: false

        // QUIÉN SUELTA EL ENGANCHE, y por qué se decide AQUÍ y no en el pegado.
        //
        // El pegado va en diferido (Qt.callLater) y varias notificaciones del
        // mismo ciclo se funden en UNA pasada: cuando se ejecuta, el encogido
        // del fin de turno y el recrecido posterior ya han pasado los dos, y
        // lo único que se ve es "la vista está más arriba" — indistinguible de
        // haber subido con la rueda. Por eso el enganche se soltaba justo al
        // aparecer la respuesta por más vueltas que le diera al heurístico.
        //
        // Esta señal, en cambio, llega en el MOMENTO de cada cambio, así que
        // el estado de al lado todavía es el de antes y las tres situaciones se
        // distinguen sin ambigüedad:
        //
        //   · Lo hemos escrito nosotros (_pegando) → no es gesto de nadie.
        //   · El contenido ENCOGE y el contenedor recoloca la vista para no
        //     salirse (fin de turno) → tampoco.
        //   · La vista sube sin que el final se mueva → ese SÍ eres tú.
        property real _prevY: 0
        property real _prevFin: 0
        //
        // Y ADEMÁS TIENE QUE SER UN GESTO (_gesto). El umbral en píxeles por sí
        // solo no distinguía una rueda hacia arriba de un reajuste del origen
        // —que mueve la vista sin que nadie la toque—, y cada reajuste soltaba
        // el enganche a media respuesta.
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
            // RESCATE DEL LIMBO, antes que nada y con el enganche puesto o no.
            // Escribir contentY a mano no pasa por los límites del contenedor,
            // así que basta con que la estimación del final se acorte DESPUÉS
            // de haber escrito para que la vista se quede colgada en el vacío
            // de debajo del último mensaje, sin nada que mirar y sin nadie que
            // la devuelva. Solo si no hay gesto en marcha: recortar contra el
            // dedo del usuario es peor que el limbo.
            if (!_gesto && (contentY > _finY + Theme.dp(4)
                            || contentY < originY - Theme.dp(4))) {
                _pegando = true
                contentY = Math.max(originY, Math.min(_finY, contentY))
                _pegando = false
            }
            if (!follow)
                return
            // Sin heurísticos: si el enganche sigue puesto, al fondo. Quién lo
            // quita se decide arriba, en el instante del gesto.
            // Media décima de píxel no es un movimiento: escribirla solo
            // dispara otra vuelta de notificaciones.
            //
            // Y se escribe contentY A SECAS, que es la operación que no
            // sorprende a nadie: fija un número y termina. Aquí llegó a
            // llamarse a positionViewAtEnd() en cada cambio de contenido y
            // eso CONGELÓ el escritorio: crea los delegates que le faltan
            // para medir el final de verdad, con lo que la altura vuelve a
            // cambiar, lo que llama otra vez a este pegado… y como el sitio
            // donde aterriza no es exactamente el 'contentHeight - height'
            // estimado, la condición de arriba nunca se apagaba. Bucle
            // infinito en el hilo gráfico. El posicionado exacto se reserva
            // para el botón de bajar, que se pulsa una vez y no se realimenta.
            if (Math.abs(contentY - _finY) > 0.5) {
                _pegando = true
                contentY = _finY
                _pegando = false
            }
        }

        // EL FINAL EXACTO, SOLO BAJO PETICIÓN. 'contentHeight' en una lista de
        // alturas variables es una ESTIMACIÓN: los delegates que aún no se han
        // creado se cuentan por la media de los que sí, y con mensajes muy
        // desiguales (una tarjeta de tres líneas y un informe de cien) se pasa
        // de largo — el "limbo" por debajo del último mensaje.
        //
        // positionViewAtEnd() no estima: crea lo que haga falta y coloca el
        // final real —footer incluido— al pie de la vista. Cuesta esa creación
        // de delegates, así que se usa UNA vez al aterrizar el botón, jamás en
        // el camino caliente del seguimiento (ver arriba por qué).
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
        // EL ORIGEN TAMBIÉN MUEVE EL FINAL, y lo hace sin tocar contentHeight:
        // la lista reajusta su media al crear o soltar tarjetas y desplaza el
        // contenido entero. Sin escuchar esto, el pegado se enteraba del nuevo
        // final solo cuando llegaba el siguiente token — o nunca, si el turno
        // ya había acabado.
        onOriginYChanged: Qt.callLater(_pegarAbajo)
        // UNA TARJETA NUEVA ES CONTENIDO NUEVO, y de eso trata seguir la
        // conversación. No basta con contentHeight: una tarjeta entra con su
        // animación de entrada, así que su altura llega a plazos y el pegado
        // de aquel momento se quedaba corto — la conversación avanzaba y la
        // vista se iba quedando atrás tarjeta a tarjeta. Al terminar la
        // transición se vuelve a pegar, que es cuando el sitio ya es el
        // definitivo.
        onCountChanged: { Qt.callLater(_pegarAbajo); repegar.restart() }
        Timer {
            id: repegar
            // Lo bastante para que la tarjeta nueva haya terminado de entrar
            // (su animación, más el retardo escalonado de las que llegan en
            // lote): antes de eso su altura aún no es la definitiva.
            interval: Theme.animNormal * 2 + 80
            onTriggered: {
                chat._pegarAbajo()
                // Se cierra la ventana DESPUÉS del último pegado: a partir de
                // aquí, si la vista se aleja del fondo es que la has movido tú.
                chat._traspaso = false
            }
        }
        // Soltar el enganche es cosa del USUARIO, no de cualquier meneo. Al
        // acabar el turno, la respuesta pasa del footer a la lista: por un
        // instante el contenido ENCOGE, el Flickable se recoloca dentro de sus
        // límites solo, y ese movimiento —que nadie ha pedido— llegaba aquí
        // como "ya no está abajo" y apagaba el seguimiento. Resultado: la
        // vista se quedaba arriba justo al aparecer la tarjeta de la
        // respuesta. Solo cuenta como marcharse si de verdad se ha SUBIDO
        // respecto al último pegado.
        // Llegar al fondo por tu propio pie vuelve a enganchar: es lo que uno
        // hace cuando quiere volver a ver lo que va saliendo. Soltarlo ya no
        // se decide aquí (ver onContentYChanged): este aviso llega cuando el
        // movimiento ha terminado, y para entonces la maqueta puede haberse
        // movido por su cuenta.
        onMovementEnded: if (atBottom) follow = true
        // Arrastrar con el dedo o la rueda cancela el viaje: si no, el botón
        // seguiría tirando de la vista mientras el usuario intenta subir.
        onMovementStarted: scrollToEnd.stop()

        // PREGUNTAR ES QUERER VER LA RESPUESTA. Si te habías ido a leer algo de
        // más arriba, el seguimiento se había soltado (y eso está bien: nadie
        // quiere que la vista le dé un tirón mientras lee). Pero en cuanto
        // arranca un turno nuevo, lo que quieres es lo que va a llegar: se
        // vuelve a enganchar solo, sin tener que buscar el botón.
        Connections {
            target: AiService
            function onBusyChanged() {
                // FIN DE TURNO: el traspaso. Lo que se estaba escribiendo vivía
                // en el footer y ahora nace como tarjeta de la lista, con su
                // animación de entrada — o sea que la altura definitiva llega
                // unos fotogramas después. Un solo pegado en este instante mide
                // el hueco intermedio y deja la vista arriba, que es justo el
                // salto que se veía al aparecer la respuesta. Se pega ahora y
                // otra vez cuando la entrada ha terminado.
                if (!AiService.busy) {
                    if (chat.follow) {
                        chat._traspaso = true
                        Qt.callLater(chat._pegarAbajo)
                        repegar.restart()
                    }
                    return
                }
                scrollToEnd.stop()
                // 'follow' NO se toca aquí. Se probó a re-engancharlo con
                // atBottom y era justo lo contrario de lo que parece: cuando
                // el turno arranca, el mensaje del usuario YA está puesto y el
                // contenido ya ha crecido, así que atBottom daba falso y el
                // seguimiento se apagaba para todo el turno — el modelo
                // escribía y la vista no se movía.
                //
                // Quien decide es el usuario y ya lo ha dicho antes: al enviar
                // se engancha (ver submit()), y al subir a leer se suelta. Una
                // vuelta más de herramientas dentro del mismo turno no cambia
                // ninguna de las dos cosas.
                Qt.callLater(chat._pegarAbajo)
            }
        }

        // ── Estado vacío: la invitación ──────────────────────────────────────
        Item {
            // Un Item declarado dentro de un Flickable se reparenta a su
            // contentItem, cuyo alto es contentHeight — que con cero mensajes
            // vale CERO: la invitación quedaba centrada en y=0, medio cortada
            // por el clip. Se re-cuelga del propio ListView para que las
            // anclas midan contra el viewport, que es lo que se ve.
            parent: chat
            anchors.fill: parent
            visible: AiService.messages.count === 0 && !AiService.busy

            ColumnLayout {
                id: emptyCol
                anchors.centerIn: parent
                width: Math.min(parent.width, Theme.dp(340))
                spacing: Theme.space12

                // Saludo según la hora: un panel que sabe si es de día.
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        const h = new Date().getHours()
                        return h < 7 ? I18n.tr("Good night") : h < 14 ? I18n.tr("Good morning")
                             : h < 21 ? I18n.tr("Good afternoon") : I18n.tr("Good night")
                    }
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.typeTitleMedium
                    font.weight: Font.Medium
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󱙺"
                    color: Theme.withAlpha(Theme.accent, 0.55)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(52)
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: AiService.urlMissing
                        ? I18n.tr("Point the panel at your server to start.")
                        : AiService.keyMissing
                        ? I18n.tr("Pick a provider and add its key to start.")
                        : I18n.tr("Ask anything. Attach your clipboard or screen for context.")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
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

        // Burbuja EN VIVO en el footer: no reconstruye la lista por token.
        //
        // El 'spacing' del ListView separa DELEGATES; al footer no le llega, y
        // el hueco que se reservaba aquí abajo dejaba la respuesta naciendo
        // pegada al último mensaje —renglón contra renglón— hasta que la lista
        // se rehacía y saltaba a su sitio. El hueco va ARRIBA, que es donde
        // hace falta, y así la burbuja viva nace ya separada y no se mueve
        // después.
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
                    // 'busy', no 'true': con live fijo, sus animaciones de
                    // "sigue trabajando" (el aro que respira, el filo viajero)
                    // giraban en bucle infinito desde que el panel se construía
                    // — y con keepAlive el panel ya no muere al cerrarse, así
                    // que giraban PARA SIEMPRE, panel oculto incluido.
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
                    Text {
                        Layout.fillWidth: true
                        text: AiService.liveThink.slice(-280)
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
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
                    Text {
                        visible: AiService.agentMode && AiService.toolRounds > 0
                        text: I18n.tr("Step %1 of %2")
                            .arg(AiService.toolRounds).arg(AiService.maxToolRounds)
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.typeLabelSmall
                    }
                    Text {
                        visible: AiService.sendQueue.length > 0
                        text: I18n.tr("Queued: %1").arg(AiService.sendQueue.length)
                        color: Theme.accentText
                        font.family: Theme.fontFamily
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
            // Mismo caso que la invitación: dentro del Flickable acababa en el
            // contentItem, o sea anclado al fondo del CONTENIDO — fuera de
            // pantalla justo cuando toca verlo, y bajando con cada token. Del
            // viewport, como corresponde a un control flotante.
            parent: chat
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.space8
            icon: "󰅀"
            diameter: Theme.dp(30)
            baseColor: SettingsPalette.accentSoft
            iconColor: Theme.accentText
            // Durante el viaje se queda: si desapareciera al cruzar el umbral
            // de "abajo", se esfumaría bajo el puntero a mitad de pulsación.
            visible: chat.contentHeight > chat.height
                     && (!chat.atBottom || scrollToEnd.running)
            onClicked: {
                // Se corta cualquier inercia y cualquier viaje anterior ANTES
                // de empezar el nuevo: dos animaciones sobre contentY, o una
                // animación contra un flick, es justo la pelea que colgaba
                // el panel.
                chat.cancelFlick()
                scrollToEnd.stop()
                chat.follow = true
                scrollToEnd.from = chat.contentY
                // El destino es la ESTIMACIÓN, y por eso el viaje se remata
                // con _alFinal() al llegar (ver onStopped): así el trayecto se
                // ve, pero quien decide dónde para es el contenido medido, no
                // una media. Sin el remate, una estimación larga dejaba el
                // viaje en el vacío de debajo del último mensaje.
                scrollToEnd.to = chat._finY
                scrollToEnd.start()
            }
        }
    }

    // ── Adjuntos: acciones + chips de lo pendiente ───────────────────────────
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
                    // Con tope: una etiqueta larga (el nombre de un archivo
                    // adjuntado) hacía la píldora más ancha que el panel.
                    // Solo con el Flow ya medido: contra un ancho 0 la píldora
                    // se quedaría en nada (ver la nota de las opciones en
                    // MessageBubble).
                    readonly property real natural:
                        attRow.implicitWidth + Theme.space10 * 2
                    width: attFlow.width > 0
                           ? Math.min(natural, attFlow.width) : natural
                    height: Theme.dp(26)
                    radius: height / 2
                    color: SettingsPalette.accentSoft
                    // Entra creciendo: pegar el portapapeles o una captura es
                    // una acción a ciegas (el contenido no se ve), así que el
                    // chip tiene que ACUSAR el golpe para confirmarla.
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
                        Text {
                            text: attChip.modelData.kind === "image" ? "󰋩" : "󰈙"
                            color: Theme.accentText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.sp(12)
                        }
                        Text {
                            // La etiqueta es lo único que puede crecer aquí (un
                            // nombre de archivo largo), así que es lo único que
                            // se recorta. Nunca por debajo de cero: con un ancho
                            // negativo el elide no recorta nada y el texto se
                            // sale por los dos lados.
                            Layout.maximumWidth: Math.max(0, attFlow.width
                                - Theme.space10 * 2 - Theme.dp(38))
                            elide: Text.ElideMiddle
                            text: attChip.modelData.label
                            color: Theme.accentText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.typeLabelSmall
                            font.bold: true
                        }
                        Text {
                            text: "󰅖"
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
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

    // ── Subagente en marcha ──────────────────────────────────────────────────
    // Mientras un subagente investiga, el principal está callado: esta línea
    // dice qué está pasando y ofrece el freno de mano.
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

            Text {
                id: subSpin
                text: "󰳆"
                color: Theme.accentText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(14)
                RotationAnimation on rotation {
                    running: AiService.activeSub !== null
                    from: 0; to: 360
                    duration: Theme.animLoop * 2
                    loops: Animation.Infinite
                }
                onRotationChanged: if (!AiService.activeSub && rotation !== 0) rotation = 0
            }
            Text {
                Layout.fillWidth: true
                // Uno: su etiqueta y su ronda. Varios (fan-out en paralelo):
                // cuántos y qué hacen, que no caben tres líneas de detalle.
                text: AiService.activeSubs.length > 1
                    ? I18n.tr("%1 subagents working…").arg(AiService.activeSubs.length)
                      + "  " + AiService.activeSubs.map(s => s.label).join(" · ")
                    : AiService.activeSub
                        ? I18n.tr("Subagent: %1 — round %2 of %3")
                              .arg(AiService.activeSub.label)
                              .arg(AiService.activeSub.rounds)
                              .arg(AiService.activeSub.maxRounds)
                          // Qué está haciendo AHORA. Un subagente corre sin
                          // tarjetas: si la barra solo cuenta rondas, lo que
                          // hace es invisible mientras lo hace.
                          + (AiService.activeSub.lastTool !== ""
                             ? "  ·  " + AiService.activeSub.lastTool : "")
                        : ""
                color: Theme.accentText
                font.family: Theme.fontFamily
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

    // ── Trabajos en segundo plano ────────────────────────────────────────────
    // Un `make` corriendo no puede ser invisible: si algo sigue vivo detrás de
    // la conversación, aquí se ve y desde aquí se corta.
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

            Text {
                text: "󱜯"
                color: Theme.accentText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(14)
                RotationAnimation on rotation {
                    running: AiService.runningJobs.length > 0
                    from: 0; to: 360
                    duration: Theme.animLoop * 3
                    loops: Animation.Infinite
                }
                // El mismo reset que su gemelo del supervisor: al acabar el
                // último trabajo la animación se corta donde esté y el glifo
                // se quedaba torcido en un ángulo arbitrario.
                onRotationChanged: if (AiService.runningJobs.length === 0 && rotation !== 0) rotation = 0
            }
            Text {
                Layout.fillWidth: true
                text: AiService.runningJobs.length === 0 ? ""
                    : I18n.tr("%1 running in the background")
                          .arg(AiService.runningJobs.length)
                      + "  " + AiService.runningJobs.map(j => j.label).join(" · ")
                color: Theme.accentText
                font.family: Theme.fontFamily
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

    // ── Habilidad cargada sola ───────────────────────────────────────────────
    // El harness ha decidido que estas instrucciones vienen a cuento y se las
    // ha dado al modelo sin que las pidiera. Se dice: una ayuda invisible es
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

            Text {
                text: "󰠮"
                color: Theme.accentText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(12)
            }
            Text {
                Layout.fillWidth: true
                text: I18n.tr("Skill in use: %1")
                    .arg(AiService.autoSkill ? AiService.autoSkill.name : "")
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.typeLabelSmall
                elide: Text.ElideRight
            }
        }
    }

    // ── El plan del agente ───────────────────────────────────────────────────
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
                Text {
                    text: "󰝖"
                    color: Theme.accentText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(13)
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Plan")
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.typeLabelMedium
                    font.weight: Font.Medium
                }
                Text {
                    text: AiService.todos.filter(t => t.status === "completed").length
                          + "/" + AiService.todos.length
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
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
                    Text {
                        text: todoRow.modelData.status === "completed" ? "󰄲"
                            : todoRow.modelData.status === "in_progress" ? "󰥔" : "󰄱"
                        color: todoRow.modelData.status === "completed" ? Theme.green
                             : todoRow.modelData.status === "in_progress" ? Theme.accentText
                             : Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.sp(12)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: todoRow.modelData.content
                        color: todoRow.modelData.status === "in_progress" ? Theme.fg
                             : todoRow.modelData.status === "completed" ? Theme.fgMuted
                             : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.typeLabelMedium
                        font.strikeout: todoRow.modelData.status === "completed"
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── Paleta de comandos ───────────────────────────────────────────────────
    // Al escribir "/" el panel ENSEÑA lo que hay en vez de esconderlo en un
    // mensaje de ayuda que solo aparece cuando te equivocas. Se filtra según
    // tecleas; Tab completa el primero y el clic lo lanza.
    // Cada comando, entero, en una línea: cómo se llama, cómo se llama en
    // inglés, qué icono lleva, qué dice de sí mismo y QUÉ HACE. Antes la lista
    // que se pinta y el switch que ejecuta eran dos, y ya se habían
    // desincronizado: la paleta ofrecía /limpiar y la ayuda hablaba de /clear.
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
        // También por el nombre en inglés: quien escribe /clear encuentra
        // /limpiar en vez de quedarse mirando una lista vacía.
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
                        Text {
                            text: cmdRow.modelData.glyph
                            color: Theme.accentText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.sp(13)
                        }
                        Text {
                            text: cmdRow.modelData.cmd
                            color: Theme.fg
                            font.family: Theme.monoFontFamily
                            font.pixelSize: Theme.typeLabelMedium
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: cmdRow.modelData.desc
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.typeLabelSmall
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: cmdRow.index === 0
                            text: "Tab"
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
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

    // ── Entrada ──────────────────────────────────────────────────────────────
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
                    // abierta; si no, conmuta Chat ↔ Agente (como opencode).
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

    // Comandos slash, al estilo opencode: acciones de sesión sin soltar el
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

    // ── Piezas propias del panel ─────────────────────────────────────────────
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
