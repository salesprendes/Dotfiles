import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.Config

// Desplegable reutilizable (etiqueta + selector con panel animado).
// La animación va por altura + opacidad (no scale) para evitar artefactos de fondo.
//
// El panel FLOTA sobre el contenido: no ocupa sitio en el layout, así que al
// abrirlo no empuja hacia abajo lo que venga después. La raíz es un Item, no
// un ColumnLayout, precisamente por eso — en un layout todo hijo visible
// reserva su espacio, y el panel no debe reservar ninguno.
//
// El panel no cuelga de la fila sino de la capa de la página (ver hoistPanel):
// asomando fuera de su contenedor dejaba de recibir el ratón. Sigue recortado
// por el borde del área visible, que es lo que gobiernan 'flipUp' —abrir hacia
// arriba cuando abajo no cabe— y el ceñido de altura.
// El filtro del buscador y la marca de fila vienen de la base (SettingsRow).
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

    // Grupo exclusivo opcional: si varios DropdownRow comparten el objeto 'group'
    // (con propiedad 'openItem'), solo uno queda abierto; abrir uno cierra los demás.
    property QtObject group: null
    Connections {
        target: root.group
        enabled: root.group !== null
        function onOpenItemChanged() {
            if (root.open && root.group.openItem !== root)
                root.open = false
        }
    }

    // Colores derivados de Theme (sobreescribibles).
    property color controlColor: Theme.withAlpha(Theme.surface, 0.86)
    property color borderColor:  Theme.withAlpha(Theme.overlay, 0.28)
    // OPACO, no translúcido. Cuando el panel se desplegaba empujando el
    // contenido no había nada detrás y un 72 % de alfa pasaba desapercibido;
    // flotando por encima, los interruptores y botones de debajo se
    // transparentaban a través de la lista y el panel parecía roto. Un menú
    // tiene que tapar lo que cubre.
    property color cardColor:    Theme.surfaceHi
    property color hoverColor:   Theme.withAlpha(Theme.surfaceHi, 0.74)

    // Panel flotante (por defecto) o acordeón que empuja. Lo segundo hace
    // falta en contenedores pequeños y recortados —la barra de captura de
    // pantalla— donde no hay sitio sobre el que flotar: allí el recorte del
    // propio contenedor se comería el panel, y es mejor que crezca la caja.
    property bool floatingPanel: true

    // Flotando, solo la fila cuenta para el layout y el panel es una capa
    // aparte. En modo acordeón el panel sí reserva su hueco, como antes.
    implicitHeight: headRow.implicitHeight
        + (root.floatingPanel || dropdownClip.height <= 0
           ? 0 : root.panelGap + dropdownClip.height)
    // Con el panel abierto, la fila se pone por delante de sus hermanas para
    // que el panel las tape en vez de colarse por debajo.
    z: root.open ? 10 : 0

    // Hueco entre el selector y el panel.
    readonly property int panelGap: Theme.space6

    // ¿Se abre hacia arriba? Se decide en el momento de abrir; al ser una
    // decisión puntual no hace falta que la posición en pantalla sea un binding
    // reactivo (que en QML no lo sería).
    property bool flipUp: false

    // Sitio libre a cada lado de la fila, medido en el momento de abrir.
    // Arrancan en -1 ("sin medir") para que el panel no se recorte a cero antes
    // de la primera medición.
    property real roomBelow: -1
    property real roomAbove: -1

    // Quién recorta de verdad al panel. NO es la ventana: el panel vive dentro
    // del área desplazable de Ajustes, que va con 'clip', y es SU borde el que
    // corta. Medir contra la ventana daba sitio de sobra donde no lo había, el
    // panel se colocaba fuera del recorte y las opciones que caían ahí no se
    // veían NI se podían pulsar (un hijo recortado tampoco recibe el ratón).
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

    // ── Dónde cuelga el panel ────────────────────────────────────────────────
    // NO de la fila. Colgado de la fila, el panel sobresalía por debajo de la
    // tarjeta de ajustes que la contiene, y Qt deja de entregar el ratón a lo
    // que asoma fuera de su contenedor: las opciones que caían por debajo del
    // borde de la tarjeta se veían perfectamente y no respondían ni al pasar
    // por encima. Medido: tarjeta 293..609, opciones a 482/526/570 vivas y las
    // de 614/658/702 muertas, con el corte clavado en el borde.
    //
    // Así que se cuelga del CONTENIDO del área desplazable, que abarca la
    // página entera y por tanto siempre lo contiene. Y sigue cumpliendo lo que
    // buscaba colgarlo de la fila: como la fila y el panel viven los dos dentro
    // de ese mismo contenido, al desplazar la página se mueven juntos y la
    // posición calculada al abrir sigue valiendo, sin recalcular nada por
    // fotograma.
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

    // ── Anchos ───────────────────────────────────────────────────────────────
    // El selector se ciñe a su valor; el PANEL, en cambio, se ciñe a la opción
    // más larga y crece hacia la izquierda.
    //
    // Antes el panel heredaba el ancho del selector, y como el selector solo
    // mide lo que mide el valor elegido, una lista con nombres largos salía
    // toda recortada: "Dinám…", "Catppuc…". Elegir a ciegas entre puntos
    // suspensivos es exactamente lo que un desplegable no debe pedirte.
    //
    // Los dos anchos se calculan a partir de medidas propias (contenido y
    // tipografía), NUNCA leyendo el ancho ya resuelto del layout: hacerlo
    // cerraba un ciclo y Qt abandonaba la colocación avisando de "recursive
    // rearrange".
    readonly property real selectorWidth:
        Math.min(Theme.dp(260), selRow.implicitWidth + Theme.space12 * 2)

    // La interfaz es monoespaciada, así que el número de caracteres de la
    // opción más larga da su ancho. Las listas de fuentes se pintan con la
    // tipografía de cada opción (proporcional): ahí la "M" sobreestima, que es
    // el lado seguro — el panel sale holgado, nunca recortado.
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
    // Hueco del delegado: márgenes + marca de elegido + canal de la barra,
    // más la muestra de color cuando la lista la lleva.
    readonly property real optionPadding: Theme.dp(64)
        + (hasSwatches ? swatchSize + Theme.space8 : 0)
    readonly property real panelWidth:
        Math.max(root.selectorWidth, optTm.advanceWidth + root.optionPadding)

    // ── Cascada de apertura ──────────────────────────────────────────────────
    // Las opciones no aparecen de golpe: entran una detrás de otra, de arriba
    // abajo. Da el sentido de lectura de la lista y hace que el panel se lea
    // como algo que se despliega, no como un recorte que crece.
    property real reveal: root.open ? 1 : 0
    // Abrir y cerrar NO son el mismo gesto. Abrir es una presentación: se toma
    // su tiempo y aterriza con la curva de entrada del shell (OutQuint, que
    // cubre casi todo el recorrido enseguida y dedica el resto a asentarse).
    // Cerrar es quitarse de en medio: más corto y con la curva de salida. Antes
    // los dos iban con la misma curva y la misma duración, y por eso el panel
    // se cerraba con la misma parsimonia con la que se abría.
    Behavior on reveal {
        NumberAnimation {
            duration: root.open ? Theme.animNormal : Math.round(Theme.animNormal * 0.55)
            easing.type: root.open ? Theme.enterEasing : Theme.exitEasing
        }
    }
    // Retardo por posición, saturado a las 7 primeras: con listas largas el
    // resto entra ya con la última del escalonado, sin arrastrar la animación.
    //
    // La cascada arranca por la opción MÁS CERCANA al selector: hacia abajo es
    // la primera, hacia arriba la última. Iba siempre desde arriba, así que un
    // panel abierto hacia arriba desplegaba al revés — las opciones brotaban
    // del extremo lejano y venían hacia el botón, en contra del gesto.
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

    // ── Opciones con color ───────────────────────────────────────────────────
    // Si una opción trae 'color', se dibuja su muestra —un disco del color—
    // delante del texto, tanto en el botón como en la lista. Sirve para elegir
    // un acento sin desplegar seis discos con su nombre debajo ocupando media
    // tarjeta: el botón ENSEÑA el color elegido y la lista los enseña todos
    // solo cuando la abres.
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
        // La barra desplazable no se ve hasta que termina de abrirse (ver
        // dropdownClip.settled): al arrancar un ciclo nuevo (abrir o cerrar)
        // se apaga de golpe, y solo vuelve a encenderse si la apertura llega
        // a completarse (settleTimer, temporizada a la par de la animación
        // de altura — no depende de que la animación emita 'finished').
        dropdownClip.settled = false
        if (open) {
            // Antes de nada: medir el sitio real y decidir hacia dónde se abre.
            // Se baja solo si abajo cabe la lista entera; si no cabe en ninguno
            // de los dos lados, se elige el lado más holgado y el panel se ciñe
            // a él (ver dropdownClip.panelHeight), que es lo que garantiza que
            // ninguna opción quede fuera del recorte.
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

    // Etiqueta y selector en la MISMA línea (el selector se ciñe a su valor y
    // se alinea a la derecha), no apilados: un valor de diez caracteres no
    // necesita una caja de ancho completo debajo de su etiqueta, y apilarlos
    // gastaba dos renglones por ajuste. Sin etiqueta (usos fuera de Ajustes)
    // el selector recupera el ancho completo.
    RowLayout {
        id: headRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.space10

        RowBadge {
            // Sin glifo, sin disco: los usos compactos (p. ej. el selector de
            // modelo del panel de IA) no quieren una insignia vacía delante.
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
        // Se ciñe al contenido, con un mínimo para que un valor corto no
        // encoja la caja hasta parecer un botón, y un techo para que uno largo
        // no se coma la etiqueta.
        Layout.minimumWidth: inline ? Theme.dp(112) : 0
        // El techo es una medida fija, NO una proporción del ancho de la fila
        // (ver la nota de selectorWidth sobre el "recursive rearrange").
        Layout.preferredWidth: inline ? root.selectorWidth : -1
        implicitHeight: Theme.rowM
        activeFocusOnTab: enabled
        radius: Theme.pillRadius

        readonly property bool hot: selMa.containsMouse || root.open || activeFocus
        // Abierto o señalado, el selector se tiñe de acento: el control
        // responde al puntero en vez de quedarse inerte hasta que lo pulsas.
        color: root.open ? Theme.withAlpha(Theme.accent, Theme.isDark ? 0.13 : 0.16)
             : selMa.containsMouse ? root.hoverColor
             : root.controlColor
        border.width: activeFocus ? Theme.focusWidth : Theme.hairline
        border.color: activeFocus ? Theme.focusRing
                    : root.open ? Theme.accent
                    : selMa.containsMouse ? Theme.withAlpha(Theme.accent, 0.55)
                    : root.borderColor
        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        Keys.onReturnPressed: root.pickKeyboard()
        Keys.onEnterPressed: root.pickKeyboard()
        Keys.onSpacePressed: root.pickKeyboard()
        Keys.onDownPressed: root.moveKeyboard(1)
        Keys.onRightPressed: root.moveKeyboard(1)
        Keys.onUpPressed: root.moveKeyboard(-1)
        Keys.onLeftPressed: root.moveKeyboard(-1)
        Keys.onEscapePressed: root.closeKeyboard()

        // Al perder el foco se cierra. Antes el panel empujaba el contenido y
        // dejarlo abierto solo estorbaba; ahora TAPA lo que hay debajo, así que
        // uno olvidado abierto esconde ajustes. Pulsar una opción no roba el
        // foco (los MouseArea no lo hacen), así que elegir sigue funcionando.
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
                Behavior on rotation { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
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

    // Sombra del panel flotante. Va ANTES que él (se dibuja debajo) y fuera
    // de su recorte, que si no se la comería.
    //
    // Son tres anillos concéntricos de negro cada vez más tenue en lugar de un
    // desenfoque de verdad: este equipo no tiene el módulo de efectos gráficos
    // de Qt, así que no hay DropShadow disponible. Con bordes en vez de
    // rellenos no hay superposición de capas, y a tres anillos el degradado ya
    // engaña al ojo lo suficiente para separar el panel del fondo.
    Item {
        id: panelShadow
        anchors.fill: dropdownClip
        // Reparentado fuera de la fila, ya no hereda su visibilidad: hay que
        // atarla a mano o el panel sobreviviría a su propia fila oculta.
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
        // Colocado a mano, no por el layout: cuelga del borde derecho del
        // selector y crece hacia la IZQUIERDA hasta que quepa la opción más
        // larga (ver panelWidth), sin pasarse del ancho de la fila.
        width: selector.inline ? Math.min(root.panelWidth, root.width) : root.width
        // Coordenadas de la capa de la página cuando está reparentado (ver
        // hoistPanel); relativas a la fila mientras no lo esté.
        x: root.panelHost ? root.hostX + root.width - width : root.width - width
        // Debajo del selector, o encima si abajo no cabía (ver flipUp).
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
        // Alto que PIDE la lista (con su tope de maxVisibleItems). Se saca del
        // NÚMERO DE OPCIONES, no de optionList.contentHeight: como el panel
        // ahora se ciñe al sitio disponible, encogerlo encogía la lista, y una
        // lista más corta crea menos delegados y devuelve un contentHeight
        // menor — que volvía a encoger el panel. El bucle lo dejaba en 10 px.
        readonly property int rowCount: Math.max(1, Math.min(
            Math.max(1, root.maxVisibleItems), (root.options || []).length))
        readonly property int naturalHeight: rowCount * optionHeight + Theme.space4 * 2
        // Alto REAL: nunca más de lo que cabe en el lado hacia el que se abre.
        // Es lo que impide que una opción quede fuera del área visible, donde
        // no se vería ni se podría pulsar; si no cabe entera, la lista se
        // desplaza dentro del panel y todas siguen siendo alcanzables.
        readonly property real available: root.flipUp ? root.roomAbove : root.roomBelow
        readonly property int minHeight: Math.min(naturalHeight, optionHeight * 2 + Theme.space4 * 2)
        readonly property int panelHeight: available < 0
            ? naturalHeight
            : Math.max(minHeight, Math.min(naturalHeight, available))
        // Se enciende cuando termina de crecer, no antes: mientras el panel
        // todavía se está abriendo, optionList.height va de 0 al valor
        // final, así que decidir la barra con eso a medias se veía como un
        // parpadeo feo desde el primer fotograma. settleTimer (temporizado a
        // la par de la animación de altura) la enciende al terminar — no un
        // 'onFinished' de la animación, que con Behavior no siempre llega a
        // dispararse si el destino cambia a media transición.
        property bool settled: false
        Timer {
            id: settleTimer
            interval: Theme.animNormal
            onTriggered: {
                dropdownClip.settled = root.open
                // Segunda medición, ya con todo quieto. La primera se toma en el
                // instante de abrir, y la página entra con una animación de
                // desplazamiento: abrir mientras corre daba 230 px de sitio
                // donde en realidad había 917, y el panel se colocaba fuera del
                // área visible.
                if (!root.open)
                    return
                root.hoistPanel()
                root.measureRoom()
                // El lado solo se corrige si de verdad NO cabe en el elegido y
                // sí en el contrario. Un salto puntual en ese caso raro es
                // mejor que media lista escondida; fuera de ahí no se toca,
                // que reubicar el panel a media apertura se ve fatal.
                const chosen = root.flipUp ? root.roomAbove : root.roomBelow
                const other = root.flipUp ? root.roomBelow : root.roomAbove
                if (root.floatingPanel && chosen >= 0
                        && chosen < dropdownClip.naturalHeight && other > chosen)
                    root.flipUp = !root.flipUp
            }
        }
        // Un ÚNICO reloj para todo el panel: alto, opacidad y la cascada de las
        // opciones salen los tres de 'reveal'. Antes cada uno llevaba su propia
        // animación con su duración y su curva —alto en animNormal/OutCubic,
        // opacidad en animFast, cascada sobre reveal— y al no compartir reloj
        // se desincronizaban: el panel terminaba de crecer con las últimas
        // opciones aún entrando, y al cerrar se quedaba un rectángulo vacío
        // encogiéndose después de que el contenido ya hubiera desaparecido.
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
                // Contra el hueco YA ABIERTO del todo (panelHeight, que es el
                // destino), no contra 'height': ese va animando de 0 al valor
                // final según se abre, y compararse con eso hacía que
                // 'scrollable' fuera true casi siempre mientras crecía (falso
                // positivo, no un parpadeo de verdad). Se mira el alto real y
                // no el tope de maxVisibleItems porque ahora el panel puede
                // salir más bajo si el sitio no da para más: justo ahí es
                // cuando hace falta poder desplazar.
                readonly property bool scrollable:
                    (root.options || []).length * dropdownClip.optionHeight
                        > dropdownClip.panelHeight - Theme.space4 * 2 + 0.5
                readonly property real scrollGutter: scrollable ? Theme.dp(10) : 0

                ScrollBar.vertical: ThinScrollBar {
                    policy: optionList.scrollable ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                    // No se ve hasta que el panel termina de abrirse del
                    // todo (ver dropdownClip.settled): antes se dibujaba con
                    // el tamaño/posición a medio calcular sobre una altura
                    // que todavía se estaba animando.
                    opacity: dropdownClip.settled ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                    // Retranqueo vertical = lo que le falta al tirador para
                    // librar el redondeo de las esquinas del panel (la lista
                    // ya está metida 'space4'): en los extremos del recorrido
                    // se metía en la curva y parecía asomar fuera del menú.
                    // Calculado, no estimado, para que siga valiendo con
                    // cualquier ajuste de redondeo de esquinas.
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

                    // Entrada escalonada: cada opción aparece un poco después
                    // que la anterior. Solo al abrir; una vez abierto vale 1 y
                    // no interviene en nada.
                    //
                    // Se desliza en el EJE en el que se abre el panel, no de
                    // lado: iba desde la derecha, y un movimiento horizontal
                    // dentro de una lista que crece hacia abajo son dos gestos
                    // distintos a la vez. Ahora las opciones salen del selector
                    // — caen si el panel baja, suben si sube.
                    readonly property real appear: root.appearAt(index)
                    opacity: appear
                    transform: Translate {
                        y: (1 - optionRow.appear) * Theme.dp(root.flipUp ? 9 : -9)
                    }
                    radius: Theme.pillRadius - Theme.space2
                    // El color base solo va de acento-tinte a "transparent"; el hover
                    // es una capa aparte que anima su opacidad (si no, se interpola
                    // hacia el negro de "transparent").
                    color: sel ? Theme.withAlpha(Theme.accent, 0.18)
                               : focused ? Theme.focusBg : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

                    border.width: focused ? Theme.focusWidth : 0
                    border.color: Theme.focusRing

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: root.hoverColor
                        opacity: rowMa.containsMouse && !optionRow.sel && !optionRow.focused ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutQuad } }
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
