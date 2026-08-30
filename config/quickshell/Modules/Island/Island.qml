import QtQuick
import qs.Config

// La isla: una sola forma que se estira, se encoge y cambia de esquinas
// siguiendo un muelle (IslandSpring), con el contenido cruzándose por dentro.
//
// ── EL TRUCO DE QUE PAREZCA UNA SOLA COSA ───────────────────────────────────
// La forma y el contenido van por caminos distintos y a destiempo, y eso es
// deliberado:
//
//   · La FORMA la mueve el muelle, sin duración fija. Un cambio de objetivo a
//     mitad de camino se curva y sigue, conservando la velocidad.
//   · El CONTENIDO se funde, y entra con RETRASO respecto a la forma. Si
//     entrara a la vez, verías el texto nuevo apretujado dentro de una caja
//     que todavía es del tamaño viejo. Dejando que la caja se abra primero, el
//     contenido aparece en un sitio que ya le viene bien.
//
// Es la misma regla que ya sigue Components/Popout.qml con Theme.revealOpacity,
// aquí aplicada a los dos sentidos de un cruce.
//
// ── POR QUÉ DOS RANURAS (A/B) Y NO UN SOLO Loader ───────────────────────────
// Con un Loader, cambiar de actividad destruye lo viejo en el mismo fotograma
// en que nace lo nuevo: no hay cruce posible, hay un corte. Con dos ranuras
// que se alternan, la saliente sigue viva mientras se desvanece. Es el mismo
// patrón que usan los fondos de pantalla en Background/Backdrop.qml.
Item {
    id: island

    // Qué borde de la pantalla ocupa. La isla cuelga del mismo que la barra.
    property bool atBottom: false
    // Altura en reposo: la de la barra, para que en reposo la isla se lea como
    // parte de ella y no como algo pegado encima.
    property real compactHeight: Theme.barHeight
    // Separación con el borde de pantalla, la misma que la barra.
    property real edgeMargin: Theme.barTopMargin

    // Catálogo de contenidos: lo rellena quien instancia la isla, para que este
    // archivo no tenga que conocer ni importar cada actividad.
    //   { home: Component, level: Component, … }
    property var compactContent: ({})
    property var expandedContent: ({})

    // ¿Puede esta isla expandirse? En un montaje de varios monitores solo la
    // pantalla donde se pulsó enseña la hoja; las demás se quedan en su estado
    // compacto. Lo decide quien instancia (IslandWindow), que es quien sabe en
    // qué pantalla está.
    property bool canExpand: true
    // En qué pantalla vive esta isla. La necesita el asomado por ratón: la hoja
    // tiene que abrirse donde está el dedo, no donde está el foco.
    property string screenName: ""

    readonly property string activity: island.canExpand ? IslandState.activity
                                                        : IslandState.compactActivity
    readonly property bool expanded: IslandState.expanded && island.canExpand

    // ── Motor ────────────────────────────────────────────────────────────────
    readonly property IslandSpring spring: IslandSpring {
        // "Sin animaciones" en Ajustes ▸ Tema apaga también el muelle.
        reducedMotion: Theme.animNormal <= 0
    }

    // ── Objetivo ─────────────────────────────────────────────────────────────
    // El ancho en compacto lo pide el CONTENIDO: una notificación de una línea
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
                        Math.min(island.height - island.edgeMargin - Theme.dp(24),
                                 inner.implicitHeight + Theme.space16 * 2))
    }

    // Píldora en reposo (radio = mitad del alto) y hoja al expandirse. El radio
    // del lado LIBRE es mayor que el del lado pegado al borde: es lo que hace
    // que la hoja se lea como algo que cuelga de la barra y no como una caja
    // suelta que se ha puesto ahí.
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
    // cero cada vez que se recarga la configuración.
    Component.onCompleted: {
        spring.targetWidth = targetWidth
        spring.targetHeight = targetHeight
        spring.targetRadiusNear = targetRadiusNear
        spring.targetRadiusFar = targetRadiusFar
        spring.snap()
    }

    // La forma, para que la ventana anfitriona recorte su región de entrada a
    // ella: el resto del lienzo tiene que dejar pasar los clics al escritorio.
    readonly property alias shapeItem: shape

    // ── La forma ─────────────────────────────────────────────────────────────
    Rectangle {
        id: shape

        width: Math.round(island.spring.width)
        height: Math.round(island.spring.height)
        x: Math.round((island.width - width) / 2)
        y: island.atBottom ? Math.round(island.height - island.edgeMargin - height)
                           : Math.round(island.edgeMargin)

        // El radio "cerca" es el del lado del borde de pantalla, así que qué
        // esquinas son cambia con la posición de la barra.
        topLeftRadius:     island.atBottom ? island.spring.radiusFar : island.spring.radiusNear
        topRightRadius:    island.atBottom ? island.spring.radiusFar : island.spring.radiusNear
        bottomLeftRadius:  island.atBottom ? island.spring.radiusNear : island.spring.radiusFar
        bottomRightRadius: island.atBottom ? island.spring.radiusNear : island.spring.radiusFar

        color: Theme.barBg
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.35)
        antialiasing: true
        // Recorta lo que asome mientras la caja aún es más pequeña que su
        // contenido: sin esto, durante el muelle el texto se sale por los lados.
        clip: true

        // ── Ranuras de contenido ─────────────────────────────────────────────
        // Se alternan en cada cambio de actividad. La entrante manda en el
        // tamaño; la saliente solo se desvanece.
        property string keyIn: ""
        property string keyOut: ""

        Loader {
            id: slotIn
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.space12 * 2, implicitWidth)
            sourceComponent: island._componentFor(shape.keyIn)
            opacity: island._reveal
        }

        Loader {
            id: slotOut
            anchors.centerIn: parent
            width: slotIn.width
            sourceComponent: island._componentFor(shape.keyOut)
            // Se va deprisa: lo que se despide no debe hacerse esperar, y si se
            // quedara cruzándose con lo entrante se leerían los dos textos
            // superpuestos.
            opacity: 1 - island._crossfade
            visible: opacity > 0.01
        }
    }

    // ── El cruce ─────────────────────────────────────────────────────────────
    // Un único escalar 0→1 gobierna los dos lados, como el openProgress de
    // Popout: así no hay dos animaciones que puedan desincronizarse.
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
        // Al acabar el cruce, SOLTAR lo que se ha ido. La ranura saliente se
        // quedaba instanciada para siempre: invisible, sí, pero con todos sus
        // bindings vivos. El reloj de reposo se reevaluaba cada segundo, y en
        // cada monitor, para un componente que ya nadie vería nunca — y basta
        // con que pase una notificación para dejar ahí clavada una actividad
        // que solo se enseñó tres segundos.
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

    // La primera actividad no se cruza con nada: se pone y ya.
    readonly property Timer _boot: Timer {
        interval: 1
        running: true
        onTriggered: {
            shape.keyIn = island._contentKey
            island._crossfade = 1
        }
    }

    // ── Interacción ──────────────────────────────────────────────────────────
    // ¿Se puede asomar el reproductor aquí y ahora? Solo sobre el estado de
    // REPOSO con música: si hay algo transitorio (un volumen, una notificación)
    // o una hoja abierta, el ratón no tiene por qué cambiar lo que estás
    // mirando. Y solo media: la hoja de grabación lleva un botón de PARAR, y
    // que aparezca sola debajo del cursor es pedir un accidente.
    readonly property bool canPeek: island.canExpand
                                    && IslandState.base === "media"
                                    && IslandState.transientId === ""
                                    && IslandState.destination === ""

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
            // Al apartar el ratón se va lo que trajo el ratón. Lo que abriste
            // tú (o lo que se asomó solo, que tiene su propio reloj) se queda.
            if (IslandState.destinationSource === "hover")
                IslandState.closeDestination()
        }
    }

    // La espera es la mitad del asunto. Sin ella, cruzar la pantalla por arriba
    // abre una hoja de 340 dp de golpe; con ella hay que PARARSE encima, que es
    // lo que distingue "quiero verlo" de "iba de paso".
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

    // DEBAJO del contenido, y esto es lo único que hace que la hoja expandida
    // sirva para algo.
    //
    // Este captador es hermano de 'shape' y antes se declaraba después, o sea
    // ENCIMA de todo lo que la isla enseña. Con la píldora daba igual —no hay
    // nada que pulsar dentro—, pero al abrir el calendario se comía los clics
    // de las flechas de mes: nunca llegaban al botón, los recogía esto y, como
    // ya había un destino abierto, activate() lo cerraba. Cambiar de mes
    // cerraba la isla.
    //
    // Con z negativo, un clic solo llega aquí si NADIE de dentro lo ha querido.
    // Las flechas, los días y el botón de hoy se lo quedan; el hueco muerto de
    // la hoja sigue cerrando, que es como se sale sin tener que buscar una X.
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
                // Botón derecho: descarta sin abrir nada. Es el gesto de
                // "quítamelo de delante".
                if (IslandState.transientId === "notification")
                    IslandState.dismissNotification()
                else
                    IslandState.collapse()
                return
            }
            island.activate()
        }
    }

    // Qué hace un clic depende de qué esté enseñando: sobre una notificación,
    // abre el centro de notificaciones; sobre música o sobre una grabación en
    // marcha, su hoja; sobre el reloj, el calendario; sobre un destino ya
    // abierto, lo cierra.
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
            // Sobre un vistazo que se estaba yendo (asomado por el ratón o por
            // un cambio de canción), el clic lo FIJA en vez de cerrarlo. Un
            // segundo clic ya sí lo cierra, como cualquier otra hoja.
            if (IslandState.pinDestination())
                return
            IslandState.closeDestination()
            return
        }
        IslandState.openDestination(IslandState.isDestination(IslandState.base)
                                    ? IslandState.base : "calendar")
    }
}
