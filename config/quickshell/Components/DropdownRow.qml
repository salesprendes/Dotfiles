import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.Config

// Desplegable reutilizable: etiqueta más selector con panel animado. La
// animación va por altura y opacidad, no por escala, para evitar artefactos.
//
// El panel FLOTA sobre el contenido y no ocupa sitio en el layout, así que
// abrirlo no empuja lo que venga después. La raíz es un Item y no un
// ColumnLayout precisamente por eso: en un layout, todo hijo visible reserva su
// espacio.
//
// El panel no cuelga de la fila sino de la capa de la página (ver hoistPanel),
// porque Qt deja de entregar el ratón a lo que asoma fuera de su contenedor.
// Sigue recortado por el borde del área visible, que es lo que gobiernan
// 'flipUp' y el ceñido de altura.
SettingsRow {
    id: root
    property string label: ""
    // Glifo de la insignia que abre la fila (ver Components/RowBadge.qml).
    property string glyph: ""
    property var options: []
    property var current
    property bool open: false
    property int maxVisibleItems: 6
    property string detailText: ""
    property int keyboardIndex: -1
    signal picked(var v)

    filterText: root.label

    // Grupo exclusivo opcional: si varios comparten el objeto 'group', abrir uno
    // cierra los demás.
    property QtObject group: null
    Connections {
        target: root.group
        enabled: root.group !== null
        function onOpenItemChanged() {
            if (root.open && root.group.openItem !== root)
                root.open = false
        }
    }

    // Colores derivados de Theme, sobrescribibles. El control va un peldaño de
    // la escalera de superficies por encima de la tarjeta que lo contiene, y la
    // lista desplegada otro más, porque flota sobre el control.
    property color controlColor: Theme.surfaceContainerHigh
    property color borderColor:  Theme.outlineVariant
    // Opaco y no translúcido: flotando por encima, los controles de debajo se
    // transparentarían a través de la lista. Un menú tiene que tapar lo que
    // cubre.
    property color cardColor:    Theme.surfaceContainerHighest
    property color hoverColor:   Theme.stateLayer(Theme.surfaceContainerHighest, Theme.fg, 0.08)

    // Panel flotante o acordeón que empuja. Lo segundo hace falta en
    // contenedores pequeños y recortados donde no hay sitio sobre el que flotar
    // y el recorte del propio contenedor se comería el panel.
    property bool floatingPanel: true

    // Flotando, solo la fila cuenta para el layout; en acordeón el panel sí
    // reserva su hueco.
    implicitHeight: headRow.implicitHeight
        + (root.floatingPanel || dropdownClip.height <= 0
           ? 0 : root.panelGap + dropdownClip.height)
    // Con el panel abierto la fila se pone por delante de sus hermanas, para que
    // el panel las tape en vez de colarse por debajo.
    z: root.open ? 10 : 0

    // Hueco entre el selector y el panel.
    readonly property int panelGap: Theme.space6

    // ¿Se abre hacia arriba? Se decide en el momento de abrir; al ser una
    // decisión puntual no hace falta que la posición sea un binding reactivo.
    property bool flipUp: false

    // Sitio libre a cada lado de la fila, medido al abrir. Arrancan en -1 para
    // que el panel no se recorte a cero antes de la primera medición.
    property real roomBelow: -1
    property real roomAbove: -1

    // Quién recorta de verdad al panel, que no es la ventana: el panel vive
    // dentro del área desplazable de Ajustes, que va con 'clip', y es su borde el
    // que corta. Medir contra la ventana daría sitio donde no lo hay, y lo que
    // cayera fuera del recorte no se vería ni se podría pulsar, porque un hijo
    // recortado tampoco recibe el ratón.
    function _viewport() {
        let it = root.parent
        for (let d = 0; d < 24 && it; d++) {
            if (it.clip === true) {
                const p = it.mapToItem(null, 0, 0)
                return { top: p.y, bottom: p.y + it.height }
            }
            it = it.parent
        }
        const win = root.Window.window
        return win ? { top: 0, bottom: win.height } : null
    }

    // Margen de respiro contra el borde del recorte.
    readonly property int panelMargin: Theme.space8

    // Se cuelga del contenido del área desplazable, que abarca la página entera y
    // por tanto siempre contiene al panel. Colgarlo de la fila lo dejaba
    // asomando fuera de su tarjeta, y lo que asoma no recibe el ratón.
    //
    // Como fila y panel viven los dos dentro de ese mismo contenido, al desplazar
    // la página se mueven juntos y la posición calculada al abrir sigue valiendo,
    // sin recalcular nada por fotograma.
    property Item panelHost: null
    property real hostX: 0
    property real hostY: 0

    function _findHost() {
        let it = root.parent
        for (let d = 0; d < 24 && it; d++) {
            // Un Flickable: es quien desplaza, y su contentItem es la capa que
            // acompaña al desplazamiento.
            if (it.contentHeight !== undefined && it.contentItem !== undefined)
                return it.contentItem
            it = it.parent
        }
        return null
    }

    // Recoloca el panel en la capa de la página. Se llama al abrir, cuando la
    // geometría de la fila ya es la definitiva.
    function hoistPanel() {
        if (!root.floatingPanel)
            return
        if (!root.panelHost)
            root.panelHost = root._findHost()
        const h = root.panelHost
        if (!h)
            return
        if (dropdownClip.parent !== h) {
            dropdownClip.parent = h
            panelShadow.parent = h
        }
        const p = root.mapToItem(h, 0, 0)
        root.hostX = p.x
        root.hostY = p.y
    }


    function measureRoom() {
        if (!root.floatingPanel) {          // acordeón: no flota, no se mide
            root.roomBelow = -1
            root.roomAbove = -1
            return
        }
        const v = root._viewport()
        if (!v) {
            root.roomBelow = -1
            root.roomAbove = -1
            return
        }
        const top = root.mapToItem(null, 0, 0).y
        const bottom = root.mapToItem(null, 0, root.height).y
        root.roomBelow = v.bottom - bottom - root.panelGap - root.panelMargin
        root.roomAbove = top - v.top - root.panelGap - root.panelMargin
    }

    // El selector se ciñe a su valor y el panel a la opción más larga, creciendo
    // hacia la izquierda: heredando el ancho del selector, una lista con nombres
    // largos saldría recortada y habría que elegir entre puntos suspensivos.
    //
    // Los dos anchos se calculan a partir de medidas propias —contenido y
    // tipografía— y nunca leyendo el ancho ya resuelto del layout, porque eso
    // cierra un ciclo y Qt abandona la colocación con "recursive rearrange".
    readonly property real selectorWidth:
        Math.min(Theme.dp(260), selRow.implicitWidth + Theme.space12 * 2)

    // La interfaz es monoespaciada, así que el número de caracteres de la opción
    // más larga da su ancho. En las listas de fuentes, que se pintan con la
    // tipografía de cada opción, la "M" sobreestima, que es el lado seguro.
    readonly property int optionChars: {
        let m = 1
        const o = options || []
        for (let i = 0; i < o.length; i++) {
            const t = o[i] && o[i].text !== undefined ? String(o[i].text) : ""
            if (t.length > m) m = t.length
        }
        return Math.min(m, 34)      // techo: un nombre absurdo no manda
    }
    TextMetrics {
        id: optTm
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        text: "M".repeat(Math.max(1, root.optionChars))
    }
    // Hueco del delegado: márgenes, marca de elegido y canal de la barra, más la
    // muestra de color cuando la lista la lleva.
    readonly property real optionPadding: Theme.dp(64)
        + (hasSwatches ? swatchSize + Theme.space8 : 0)
    readonly property real panelWidth:
        Math.max(root.selectorWidth, optTm.advanceWidth + root.optionPadding)

    // Las opciones entran una detrás de otra, en el sentido de lectura, para que
    // el panel se lea como algo que se despliega y no como un recorte que crece.
    property real reveal: root.open ? 1 : 0
    // Abrir y cerrar no son el mismo gesto: abrir es una presentación y se toma
    // su tiempo con la curva de entrada; cerrar es quitarse de en medio, más
    // corto y con la curva de salida.
    Behavior on reveal {
        NumberAnimation {
            duration: root.open ? Theme.animNormal : Math.round(Theme.animNormal * 0.55)
            easing.type: root.open ? Theme.enterEasing : Theme.exitEasing
        }
    }
    // Retardo por posición, saturado a las primeras: con listas largas el resto
    // entra con la última del escalonado, sin arrastrar la animación.
    //
    // La cascada arranca por la opción más cercana al selector —la primera hacia
    // abajo, la última hacia arriba— para que las opciones salgan del botón y no
    // vengan hacia él en contra del gesto.
    function appearAt(i) {
        const n = Math.max(1, (root.options || []).length)
        const pos = root.flipUp ? (n - 1 - i) : i
        const delay = Math.min(pos, 6) * 0.09
        return Math.max(0, Math.min(1, (root.reveal - delay) / 0.46))
    }

    function currentOption() {
        for (let i = 0; i < options.length; i++)
            if (options[i].value === current) return options[i]
        return options.length > 0 ? options[0] : ({ text: "", value: "" })
    }

    readonly property string currentText: {
        const opt = currentOption()
        return opt && opt.text !== undefined ? opt.text : ""
    }

    readonly property string currentFont: {
        const opt = currentOption()
        return opt && opt.font !== undefined ? opt.font : Theme.fontFamily
    }

    // Si una opción trae 'color' se dibuja su muestra delante del texto, en el
    // botón y en la lista: así el botón enseña el color elegido y la lista los
    // enseña todos solo al abrirse.
    readonly property bool hasSwatches: {
        const o = options || []
        for (let i = 0; i < o.length; i++)
            if (o[i] && o[i].color !== undefined) return true
        return false
    }
    readonly property color currentColor: {
        const opt = currentOption()
        return (opt && opt.color !== undefined) ? opt.color : Theme.accent
    }
    readonly property int swatchSize: Theme.dp(16)

    function currentOptionIndex() {
        for (let i = 0; i < options.length; i++)
            if (options[i].value === current) return i
        return options.length > 0 ? 0 : -1
    }

    function syncKeyboardIndex() {
        keyboardIndex = currentOptionIndex()
        optionList.currentIndex = keyboardIndex
    }

    function openForKeyboard() {
        root.open = true
        syncKeyboardIndex()
        if (keyboardIndex >= 0)
            optionList.positionViewAtIndex(keyboardIndex, ListView.Contain)
    }

    function moveKeyboard(delta) {
        if (options.length <= 0)
            return
        if (!root.open) {
            openForKeyboard()
            return
        }

        const start = keyboardIndex >= 0 ? keyboardIndex : currentOptionIndex()
        keyboardIndex = Math.max(0, Math.min(options.length - 1, start + delta))
        optionList.currentIndex = keyboardIndex
        optionList.positionViewAtIndex(keyboardIndex, ListView.Contain)
    }

    function pickKeyboard() {
        if (!root.open) {
            openForKeyboard()
            return
        }

        const idx = keyboardIndex >= 0 ? keyboardIndex : currentOptionIndex()
        if (idx >= 0 && idx < options.length)
            optionList.choose(options[idx].value)
    }

    function closeKeyboard() {
        if (root.open)
            root.open = false
        else
            Globals.closeAll()
    }


    onOpenChanged: {
        // La barra desplazable no se ve hasta que el panel termina de abrirse:
        // al arrancar un ciclo se apaga de golpe y solo vuelve si la apertura
        // llega a completarse.
        dropdownClip.settled = false
        if (open) {
            // Primero se mide el sitio real y se decide hacia dónde se abre. Se
            // baja solo si abajo cabe la lista entera; si no cabe en ninguno de
            // los dos lados se elige el más holgado y el panel se ciñe a él, que
            // es lo que garantiza que ninguna opción quede fuera del recorte.
            root.hoistPanel()
            root.measureRoom()
            root.flipUp = root.floatingPanel
                && root.roomBelow >= 0
                && root.roomBelow < dropdownClip.naturalHeight
                && root.roomAbove > root.roomBelow
            syncKeyboardIndex()
            settleTimer.restart()
            if (group) group.openItem = root   // reclama el grupo, cierra los demás
        }
    }

    // Etiqueta y selector en la misma línea, con el selector ceñido a su valor y
    // alineado a la derecha: apilarlos gastaría dos renglones por ajuste para un
    // valor de diez caracteres. Sin etiqueta, el selector recupera el ancho
    // completo.
    RowLayout {
        id: headRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.space10

        RowBadge {
            // Sin glifo no se dibuja disco: los usos compactos no quieren una
            // insignia vacía delante.
            visible: root.glyph !== ""
            Layout.alignment: Qt.AlignVCenter
            glyph: root.glyph
            offColor: root.controlColor
            offBorderColor: root.borderColor
        }

        ThemedText {
            Layout.fillWidth: true
            text: root.label
            visible: root.label !== ""
            color: Theme.fg
            elide: Text.ElideRight
        }

    Rectangle {
        id: selector
        readonly property bool inline: root.label !== ""
        Layout.fillWidth: !inline
        Layout.alignment: Qt.AlignVCenter
        // Se ciñe al contenido, con un mínimo para que un valor corto no encoja
        // la caja hasta parecer un botón y un techo para que uno largo no se coma
        // la etiqueta. El techo es una medida fija y no una proporción del ancho
        // de la fila; ver la nota de selectorWidth sobre "recursive rearrange".
        Layout.minimumWidth: inline ? Theme.dp(112) : 0
        // El techo es una medida fija, NO una proporción del ancho de la fila
        // (ver la nota de selectorWidth sobre el "recursive rearrange").
        Layout.preferredWidth: inline ? root.selectorWidth : -1
        implicitHeight: Theme.rowM
        activeFocusOnTab: enabled
        radius: Theme.pillRadius

        readonly property bool hot: selMa.containsMouse || root.open || activeFocus
        // Abierto o señalado, el selector se tiñe de acento: responde al puntero
        // en vez de quedarse inerte hasta que lo pulsan.
        color: root.open ? Theme.withAlpha(Theme.accent, Theme.isDark ? 0.13 : 0.16)
             : selMa.containsMouse ? root.hoverColor
             : root.controlColor
        border.width: activeFocus ? Theme.focusWidth : Theme.hairline
        border.color: activeFocus ? Theme.focusRing
                    : root.open ? Theme.accent
                    : selMa.containsMouse ? Theme.withAlpha(Theme.accent, 0.55)
                    : root.borderColor
        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        Keys.onReturnPressed: root.pickKeyboard()
        Keys.onEnterPressed: root.pickKeyboard()
        Keys.onSpacePressed: root.pickKeyboard()
        Keys.onDownPressed: root.moveKeyboard(1)
        Keys.onRightPressed: root.moveKeyboard(1)
        Keys.onUpPressed: root.moveKeyboard(-1)
        Keys.onLeftPressed: root.moveKeyboard(-1)
        Keys.onEscapePressed: root.closeKeyboard()

        // Al perder el foco se cierra: el panel tapa lo que hay debajo, así que
        // uno olvidado abierto esconde ajustes. Pulsar una opción no roba el
        // foco, así que elegir sigue funcionando.
        onActiveFocusChanged: if (!activeFocus) root.open = false

        RowLayout {
            id: selRow
            anchors.fill: parent
            anchors.leftMargin: Theme.space12
            anchors.rightMargin: Theme.space12
            spacing: Theme.space8

            // Muestra del color elegido dentro del propio botón.
            Rectangle {
                visible: root.hasSwatches
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: root.swatchSize
                implicitHeight: root.swatchSize
                radius: height / 2
                color: root.currentColor
                border.width: Theme.hairline
                border.color: Theme.withAlpha(Theme.fg, 0.30)
                Behavior on color { ColorAnimation { duration: Theme.animNormal } }
            }

            Text {
                Layout.fillWidth: true
                text: root.currentText
                color: Theme.fg
                font.family: root.currentFont
                font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
            }
            ThemedText {
                visible: root.detailText !== ""
                text: root.detailText
                color: Theme.fgMuted
                font.pixelSize: Theme.fontSize - 4
            }
            ThemedText {
                text: "󰅀"
                rotation: root.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
                color: Theme.fgMuted
                font.pixelSize: Theme.iconSize - 1
            }
        }

        MouseArea {
            id: selMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.open = !root.open
                selector.forceActiveFocus()
            }
        }
    }
    }   // fin de la fila etiqueta + selector

    // Sombra del panel flotante. Va antes que él, para dibujarse debajo, y fuera
    // de su recorte, que si no se la comería.
    //
    // Son tres anillos concéntricos de negro cada vez más tenue en lugar de un
    // desenfoque: sin el módulo de efectos gráficos de Qt no hay DropShadow. Con
    // bordes en vez de rellenos no hay superposición de capas, y a tres anillos
    // el degradado ya separa el panel del fondo.
    Item {
        id: panelShadow
        anchors.fill: dropdownClip
        // Reparentado fuera de la fila ya no hereda su visibilidad, así que hay
        // que atarla a mano o el panel sobreviviría a su propia fila oculta.
        visible: root.visible && root.floatingPanel && dropdownClip.height > 0.5
        z: dropdownClip.z - 1
        opacity: dropdownClip.opacity
        Repeater {
            model: 3
            delegate: Rectangle {
                required property int index
                readonly property int grow: (index + 1) * Theme.dp(2)
                anchors.fill: parent
                anchors.margins: -grow
                radius: Theme.pillRadius + grow
                color: "transparent"
                border.width: Theme.dp(2)
                border.color: Qt.rgba(0, 0, 0, 0.13 - index * 0.04)
            }
        }
    }

    Item {
        id: dropdownClip
        // Colocado a mano y no por el layout: cuelga del borde derecho del
        // selector y crece hacia la izquierda hasta que quepa la opción más
        // larga, sin pasarse del ancho de la fila. Las coordenadas son de la capa
        // de la página cuando está reparentado, y relativas a la fila si no.
        width: selector.inline ? Math.min(root.panelWidth, root.width) : root.width
        // Coordenadas de la capa de la página cuando está reparentado (ver
        // hoistPanel); relativas a la fila mientras no lo esté.
        x: root.panelHost ? root.hostX + root.width - width : root.width - width
        // Debajo del selector, o encima si abajo no cabía.
        y: root.panelHost
           ? (root.flipUp ? root.hostY - height - root.panelGap
                          : root.hostY + root.height + root.panelGap)
           : (root.flipUp ? -height - root.panelGap
                          : headRow.height + root.panelGap)
        // Por delante de las tarjetas de la página, que van a z 0.
        z: root.panelHost ? 100 : 0
        visible: root.panelHost ? root.visible : true
        clip: true
        readonly property int optionHeight: Theme.rowM
        // Alto que pide la lista, sacado del número de opciones y no de
        // contentHeight: como el panel se ciñe al sitio disponible, encogerlo
        // encogería la lista, y una lista más corta crea menos delegados y
        // devuelve un contentHeight menor, que volvería a encoger el panel.
        readonly property int rowCount: Math.max(1, Math.min(
            Math.max(1, root.maxVisibleItems), (root.options || []).length))
        readonly property int naturalHeight: rowCount * optionHeight + Theme.space4 * 2
        // Alto real: nunca más de lo que cabe en el lado hacia el que se abre.
        // Es lo que impide que una opción quede fuera del área visible, donde no
        // se vería ni se podría pulsar; si no cabe entera, la lista se desplaza
        // dentro del panel.
        readonly property real available: root.flipUp ? root.roomAbove : root.roomBelow
        readonly property int minHeight: Math.min(naturalHeight, optionHeight * 2 + Theme.space4 * 2)
        readonly property int panelHeight: available < 0
            ? naturalHeight
            : Math.max(minHeight, Math.min(naturalHeight, available))
        // Se enciende cuando termina de crecer: mientras el panel se abre, la
        // altura va de 0 al valor final, y decidir la barra con eso a medias es
        // un parpadeo desde el primer fotograma. Lo enciende un temporizador a la
        // par de la animación, y no un 'onFinished', que con Behavior no siempre
        // llega a dispararse si el destino cambia a media transición.
        property bool settled: false
        Timer {
            id: settleTimer
            interval: Theme.animNormal
            onTriggered: {
                dropdownClip.settled = root.open
                // Segunda medición, ya con todo quieto: la primera se toma al
                // abrir, y si la página está entrando con su animación de
                // desplazamiento el sitio medido no es el real.
                if (!root.open)
                    return
                root.hoistPanel()
                root.measureRoom()
                // El lado solo se corrige si de verdad no cabe en el elegido y sí
                // en el contrario: un salto puntual en ese caso raro es mejor que
                // media lista escondida, pero reubicar el panel a media apertura
                // se ve mal.
                const chosen = root.flipUp ? root.roomAbove : root.roomBelow
                const other = root.flipUp ? root.roomBelow : root.roomAbove
                if (root.floatingPanel && chosen >= 0
                        && chosen < dropdownClip.naturalHeight && other > chosen)
                    root.flipUp = !root.flipUp
            }
        }
        // Un único reloj para todo el panel: alto, opacidad y cascada de las
        // opciones salen los tres de 'reveal'. Con una animación propia por cada
        // uno se desincronizan, y el panel termina de crecer con las últimas
        // opciones aún entrando.
        //
        // La opacidad sube por delante del alto para que el panel esté opaco casi
        // desde el principio: si el fundido acompañara al crecimiento se vería el
        // contenido de debajo a través de la lista.
        implicitHeight: panelHeight * root.reveal
        // Sube por delante del alto (x2,5) para que el panel esté opaco casi
        // desde el principio: si el fundido acompañara al crecimiento se vería
        // el contenido de debajo a través de la lista mientras se abre.
        opacity: Math.min(1, root.reveal * 2.5)

        Rectangle {
            id: dropdownPanel
            anchors.fill: parent
            radius: Theme.pillRadius
            color: root.cardColor
            border.width: Theme.hairline
            border.color: root.borderColor

            ListView {
                id: optionList
                anchors.fill: parent
                anchors.margins: Theme.space4
                clip: true
                model: root.options
                boundsBehavior: Flickable.StopAtBounds
                // Se compara contra el hueco ya abierto del todo y no contra
                // 'height', que va animando de 0 al valor final y daría
                // 'scrollable' verdadero casi siempre mientras crece. Se mira el
                // alto real y no el tope de maxVisibleItems, porque el panel
                // puede salir más bajo si el sitio no da para más, y es justo ahí
                // cuando hace falta poder desplazar.
                readonly property bool scrollable:
                    (root.options || []).length * dropdownClip.optionHeight
                        > dropdownClip.panelHeight - Theme.space4 * 2 + 0.5
                readonly property real scrollGutter: scrollable ? Theme.dp(10) : 0

                ScrollBar.vertical: ThinScrollBar {
                    policy: optionList.scrollable ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                    // No se ve hasta que el panel termina de abrirse: antes se
                    // dibujaba con el tamaño y la posición a medio calcular.
                    opacity: dropdownClip.settled ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                    // Retranqueo vertical: lo que le falta al tirador para
                    // librar el redondeo de las esquinas del panel. Calculado y
                    // no estimado, para que siga valiendo con cualquier ajuste de
                    // redondeo.
                    rightPadding: Theme.dp(3)
                    topPadding: Math.max(Theme.dp(2), Theme.pillRadius - Theme.space4)
                    bottomPadding: Math.max(Theme.dp(2), Theme.pillRadius - Theme.space4)
                }

                function choose(value) {
                    root.picked(value)
                    root.open = false
                }

                delegate: Rectangle {
                    id: optionRow
                    required property var modelData
                    required property int index
                    readonly property bool sel: modelData.value === root.current
                    readonly property bool focused: ListView.isCurrentItem
                    width: ListView.view.width - optionList.scrollGutter
                    height: dropdownClip.optionHeight

                    // Entrada escalonada, solo al abrir; una vez abierto vale 1
                    // y no interviene.
                    //
                    // Se desliza en el eje en el que se abre el panel y no de
                    // lado: un movimiento horizontal dentro de una lista que crece
                    // en vertical son dos gestos a la vez.
                    readonly property real appear: root.appearAt(index)
                    opacity: appear
                    transform: Translate {
                        y: (1 - optionRow.appear) * Theme.dp(root.flipUp ? 9 : -9)
                    }
                    radius: Theme.pillRadius - Theme.space2
                    // El color base va de acento-tinte a "transparent"; el hover
                    // es una capa aparte que anima su opacidad, porque si no se
                    // interpolaría hacia el negro de "transparent".
                    color: sel ? Theme.withAlpha(Theme.accent, 0.18)
                               : focused ? Theme.focusBg : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }

                    border.width: focused ? Theme.focusWidth : 0
                    border.color: Theme.focusRing

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: root.hoverColor
                        opacity: rowMa.containsMouse && !optionRow.sel && !optionRow.focused ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space10
                        anchors.rightMargin: Theme.space10
                        spacing: Theme.space8

                        Rectangle {
                            visible: root.hasSwatches
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: root.swatchSize
                            implicitHeight: root.swatchSize
                            radius: height / 2
                            color: optionRow.modelData.color !== undefined
                                ? optionRow.modelData.color : "transparent"
                            border.width: Theme.hairline
                            border.color: Theme.withAlpha(Theme.fg, 0.30)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: optionRow.modelData.text
                            color: optionRow.sel ? Theme.fg : Theme.fgDim
                            font.family: optionRow.modelData.font !== undefined ? optionRow.modelData.font : Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: optionRow.sel
                            elide: Text.ElideRight
                        }
                        ThemedText {
                            visible: optionRow.sel
                            text: "󰄬"
                            color: Theme.accent
                            font.pixelSize: Theme.iconSize - 1
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.keyboardIndex = optionRow.index
                            optionList.currentIndex = optionRow.index
                            optionList.choose(optionRow.modelData.value)
                        }
                    }
                }
            }
        }
    }
}
