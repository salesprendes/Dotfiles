import QtQuick
import qs.Config

// La isla: una sola forma que se estira, se encoge y cambia de esquinas
// siguiendo un muelle (IslandSpring), con el contenido cruzándose por dentro.
//
// La forma y el contenido van a destiempo a propósito. La forma la mueve el
// muelle, sin duración fija, así que un cambio de objetivo a mitad de camino se
// curva conservando la velocidad. El contenido funde con retraso respecto a la
// forma: entrando a la vez se vería el texto nuevo apretado dentro de la caja
// vieja, y dejando que la caja abra primero aparece en un sitio que ya le cabe.
//
// Hay dos ranuras de contenido (A/B) y no un Loader porque un Loader destruye
// lo viejo en el mismo fotograma en que nace lo nuevo: eso es un corte, no un
// cruce. Con dos ranuras alternas la saliente sigue viva mientras se desvanece.
Item {
    id: island

    // Qué borde de la pantalla ocupa. La isla cuelga del mismo que la barra.
    property bool atBottom: false
    // Altura en reposo: la de la barra, para que la isla se lea como parte de
    // ella y no como algo pegado encima.
    property real compactHeight: Theme.barHeight
    // Separación con el borde de pantalla, la misma que la barra.
    property real edgeMargin: Theme.barTopMargin

    // Techo de la hoja expandida, recibido de fuera y no deducido de 'height':
    // el lienzo crece a la pantalla entera mientras la hoja está abierta, así
    // que una hoja medida sobre el lienzo pasaría a ocupar el monitor de arriba
    // abajo al abrirse. El techo tiene que ser el del lienzo en reposo.
    property real maxSheetHeight: island.height

    // Catálogo de contenidos, rellenado por quien instancia la isla para que
    // este archivo no conozca ni importe ninguna actividad.
    //   { home: Component, level: Component, … }
    property var compactContent: ({})
    property var expandedContent: ({})

    // Solo la pantalla donde se pulsó enseña la hoja; las demás se quedan
    // compactas. Lo decide quien instancia, que sabe en qué pantalla está.
    property bool canExpand: true
    // Pantalla de esta isla. La necesita el asomado por puntero: la hoja se
    // abre donde está el dedo, no donde está el foco.
    property string screenName: ""

    readonly property string activity: island.canExpand ? IslandState.activity
                                                        : IslandState.compactActivity
    readonly property bool expanded: IslandState.expanded && island.canExpand
    // Modal en ESTA pantalla: la regla de cuándo vive en IslandState.modal, y
    // aquí solo se le añade que el clic de fuera que cierra la hoja tiene que
    // ser un clic del monitor donde está la hoja.
    readonly property bool modal: IslandState.modal && island.canExpand

    // ESC cierra, como en cualquier panel. Va en la raíz de la isla y no en la
    // forma porque 'Keys' solo ve lo que sus hijos no han consumido, así que el
    // contenido de la hoja puede quedarse la tecla primero.
    //
    // El foco de teclado lo pide IslandWindow y solo mientras es modal. La
    // guarda repite esa condición a mano en vez de fiarse: si algún día la
    // ventana pidiera teclado por otro motivo, ESC no debe cerrar por su cuenta.
    focus: true
    Keys.onEscapePressed: (ev) => {
        if (!island.modal) {
            ev.accepted = false
            return
        }
        IslandState.collapse()
    }

    readonly property IslandSpring spring: IslandSpring {
        // "Sin animaciones" en Ajustes apaga también el muelle.
        reducedMotion: Theme.animNormal <= 0
    }

    // El ancho en compacto lo pide el contenido: una notificación de una línea
    // no debe ocupar lo mismo que el reproductor. En expandido manda la hoja.
    readonly property real minCompactWidth: Theme.dp(120)
    readonly property real maxCompactWidth: Math.min(Theme.dp(460), island.width - Theme.dp(48))
    readonly property real maxExpandedWidth: Math.min(Theme.dp(420), island.width - Theme.dp(32))

    readonly property real targetWidth: {
        const inner = slotIn.item
        if (!inner)
            return island.minCompactWidth
        if (island.expanded)
            return island.maxExpandedWidth
        const want = inner.implicitWidth + Theme.space16 * 2
        return Math.max(island.minCompactWidth, Math.min(island.maxCompactWidth, want))
    }

    readonly property real targetHeight: {
        const inner = slotIn.item
        if (!island.expanded || !inner)
            return island.compactHeight
        return Math.max(island.compactHeight,
                        Math.min(island.maxSheetHeight - island.edgeMargin - Theme.dp(24),
                                 inner.implicitHeight + Theme.space16 * 2))
    }

    // Píldora en reposo y hoja al expandirse. El radio del lado libre es mayor
    // que el del lado pegado al borde, que es lo que hace que la hoja se lea
    // como algo que cuelga de la barra y no como una caja suelta.
    readonly property real targetRadiusNear: island.expanded ? Theme.shapeLg
                                                             : island.targetHeight / 2
    readonly property real targetRadiusFar: island.expanded ? Theme.shapeXl
                                                            : island.targetHeight / 2

    function syncTarget() {
        island.spring.setTarget(island.targetWidth, island.targetHeight,
                                island.targetRadiusNear, island.targetRadiusFar)
    }

    onTargetWidthChanged: syncTarget()
    onTargetHeightChanged: syncTarget()
    onTargetRadiusNearChanged: syncTarget()
    onTargetRadiusFarChanged: syncTarget()

    // Al nacer se coloca sin movimiento: la isla no debe entrar creciendo desde
    // cero en cada recarga de la configuración.
    Component.onCompleted: {
        spring.targetWidth = targetWidth
        spring.targetHeight = targetHeight
        spring.targetRadiusNear = targetRadiusNear
        spring.targetRadiusFar = targetRadiusFar
        spring.snap()
    }

    // La forma, para que la ventana anfitriona recorte a ella su región de
    // entrada y el resto del lienzo deje pasar los clics al escritorio.
    readonly property alias shapeItem: shape

    Rectangle {
        id: shape

        width: Math.round(island.spring.width)
        height: Math.round(island.spring.height)
        x: Math.round((island.width - width) / 2)
        y: island.atBottom ? Math.round(island.height - island.edgeMargin - height)
                           : Math.round(island.edgeMargin)

        // El radio "cerca" es el del lado pegado al borde de pantalla, así que
        // qué esquinas son cambia con la posición de la barra.
        topLeftRadius:     island.atBottom ? island.spring.radiusFar : island.spring.radiusNear
        topRightRadius:    island.atBottom ? island.spring.radiusFar : island.spring.radiusNear
        bottomLeftRadius:  island.atBottom ? island.spring.radiusNear : island.spring.radiusFar
        bottomRightRadius: island.atBottom ? island.spring.radiusNear : island.spring.radiusFar

        color: Theme.barBg
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.35)
        antialiasing: true
        // Recorta lo que asome mientras la caja es más pequeña que su
        // contenido; sin esto el texto se sale por los lados durante el muelle.
        clip: true

        // Ranuras de contenido, alternas en cada cambio de actividad: la
        // entrante manda en el tamaño y la saliente solo se desvanece.
        property string keyIn: ""
        property string keyOut: ""

        // El ancho del contenido sigue dos reglas distintas, y la asimetría
        // entre ellas es necesaria. En compacto manda el contenido y la píldora
        // se ciñe a él hasta el tope, pasado el cual deja de crecer y es el
        // contenido el que se recorta. En expandido manda la hoja, que mide
        // siempre lo mismo, y el contenido la llena.
        //
        // Expandido usa el ancho FINAL, que es una constante: con 'parent.width'
        // el contenido se recalcularía en cada fotograma de la apertura y, como
        // el alto objetivo sale de ese contenido, el muelle perseguiría un
        // destino que él mismo mueve.
        //
        // Compacto tiene que usar 'parent.width', que es el del muelle, por dos
        // razones. El muelle rompe el ciclo: targetWidth sale del implicitWidth
        // de esta misma ranura, así que usar targetWidth aquí lo cerraría de
        // forma síncrona y QML lo detecta como binding loop, mientras que el
        // muelle avanza por reloj y no por binding. Y el 'min' con implicitWidth
        // deja el contenido en su tamaño natural, que es lo que hace que
        // 'anchors.centerIn' centre de verdad: sin él, los contenidos sin
        // 'Layout.fillWidth' se desplazan unos píxeles.
        Loader {
            id: slotIn
            anchors.centerIn: parent
            width: island.expanded
                   ? island.maxExpandedWidth - Theme.space12 * 2
                   : Math.min(parent.width - Theme.space12 * 2, implicitWidth)
            sourceComponent: island._componentFor(shape.keyIn)
            opacity: island._reveal
        }

        Loader {
            id: slotOut
            anchors.centerIn: parent
            width: slotIn.width
            sourceComponent: island._componentFor(shape.keyOut)
            // Se va deprisa: si se quedara cruzándose con lo entrante se
            // leerían los dos textos superpuestos.
            opacity: 1 - island._crossfade
            visible: opacity > 0.01
        }

        // Va dentro de la forma y no colgado de 'island', que vigilaría el
        // lienzo entero. Con una hoja modal la máscara de la ventana se abre a
        // toda la pantalla, y entonces un handler a nivel de isla daría por
        // "puntero encima" el ratón esté donde esté, congelando las cuentas
        // atrás desde el otro extremo del monitor.
        HoverHandler {
            id: hover
            onHoveredChanged: {
                IslandState.pointerInside = hovered
                if (hovered) {
                    if (island.canPeek)
                        peekIn.restart()
                    return
                }
                peekIn.stop()
                // Al apartar el ratón se va lo que trajo el ratón; lo abierto
                // a mano, y lo asomado solo con su propio reloj, se queda.
                if (IslandState.destinationSource === "hover")
                    IslandState.closeDestination()
            }
        }
    }

    // Un único escalar 0→1 gobierna los dos lados del cruce, para que no haya
    // dos animaciones que puedan desincronizarse.
    property real _crossfade: 1

    // Lo entrante aparece en la segunda mitad del cruce: la caja va por delante
    // y el contenido llega cuando ya hay sitio.
    readonly property real _reveal: Theme.revealOpacity(island._crossfade)

    NumberAnimation {
        id: crossAnim
        target: island
        property: "_crossfade"
        from: 0
        to: 1
        duration: Math.max(1, Theme.animNormal)
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel
        // Al acabar el cruce suelta la ranura saliente: si no, queda
        // instanciada para siempre, invisible pero con todos sus bindings
        // vivos, reevaluándose en cada monitor para algo que ya no se verá.
        onFinished: shape.keyOut = ""
    }

    // La clave incluye si está expandida: pasar de píldora a hoja también es un
    // cambio de contenido, no solo de tamaño.
    readonly property string _contentKey: island.activity + (island.expanded ? ":x" : ":c")

    on_ContentKeyChanged: island._swap()

    function _swap() {
        shape.keyOut = shape.keyIn
        shape.keyIn = island._contentKey
        island._crossfade = 0
        crossAnim.restart()
    }

    function _componentFor(key) {
        if (!key)
            return null
        const cut = key.lastIndexOf(":")
        const id = key.substring(0, cut)
        const map = key.substring(cut + 1) === "x" ? island.expandedContent
                                                   : island.compactContent
        return map[id] ?? null
    }

    Component.onDestruction: island._crossfade = 1

    // La primera actividad no se cruza con nada.
    readonly property Timer _boot: Timer {
        interval: 1
        running: true
        onTriggered: {
            shape.keyIn = island._contentKey
            island._crossfade = 1
        }
    }

    // ¿Se puede asomar el reproductor aquí y ahora? Solo sobre el reposo con
    // música: con algo transitorio o una hoja abierta, el puntero no debe
    // cambiar lo que se está mirando. Y solo media, porque la hoja de grabación
    // lleva un botón de parar y que aparezca sola bajo el cursor es un accidente
    // esperando a ocurrir.
    readonly property bool canPeek: island.canExpand
                                    && IslandState.base === "media"
                                    && IslandState.transientId === ""
                                    && IslandState.destination === ""

    // La espera distingue "quiero verlo" de "iba de paso": sin ella, cruzar la
    // pantalla por arriba abriría la hoja de golpe.
    readonly property Timer _peekIn: Timer {
        id: peekIn
        interval: 400
        repeat: false
        onTriggered: {
            if (!hover.hovered || !island.canPeek)
                return
            IslandState.openDestination("media", "hover", island.screenName)
        }
    }

    // Debajo de todo (z -2, por debajo incluso del captador de la forma): solo
    // recibe lo que no ha querido nadie, que es exactamente el escritorio.
    //
    // Mientras no es modal está apagado y además es inalcanzable, porque la
    // máscara de IslandWindow no deja entrar el ratón fuera de la forma. Los dos
    // candados dicen lo mismo a propósito: si la máscara se abriera por otro
    // motivo, esto no debe empezar a tragarse clics.
    MouseArea {
        z: -2
        anchors.fill: parent
        enabled: island.modal
        onClicked: IslandState.collapse()
    }

    // Debajo del contenido (z negativo), que es lo que hace utilizable la hoja
    // expandida: un clic solo llega aquí si nadie de dentro lo ha querido. Las
    // flechas del calendario, los días y el botón de hoy se lo quedan; el hueco
    // muerto de la hoja cierra, que es como se sale sin buscar una X.
    MouseArea {
        z: -1
        x: shape.x
        y: shape.y
        width: shape.width
        height: shape.height
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onClicked: (m) => {
            if (m.button === Qt.RightButton) {
                // Botón derecho: descarta sin abrir nada.
                if (IslandState.transientId === "notification")
                    IslandState.dismissNotification()
                else
                    IslandState.collapse()
                return
            }
            island.activate()
        }
    }

    // Qué hace un clic depende de qué se esté enseñando: sobre una notificación
    // abre su centro; sobre música o una grabación en marcha, su hoja; sobre el
    // reloj, el calendario; sobre un destino ya abierto, lo cierra.
    function activate() {
        if (IslandState.transientId === "notification") {
            IslandState.clearTransient()
            IslandState.openDestination("notifs")
            return
        }
        if (IslandState.transientId !== "") {
            IslandState.clearTransient()
            return
        }
        if (IslandState.destination !== "") {
            // Sobre un vistazo que se estaba yendo, el clic lo FIJA en vez de
            // cerrarlo; un segundo clic ya sí cierra.
            if (IslandState.pinDestination())
                return
            IslandState.closeDestination()
            return
        }
        IslandState.openDestination(IslandState.isDestination(IslandState.base)
                                    ? IslandState.base : "calendar")
    }
}
