import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

// Popups transitorios: escuchan NotifService.posted, muestran la notificación
// en una esquina y se autodescartan a los 5s (pausa al pasar el ratón).
//
// La pila NO es un ListView: cada tarjeta es un delegate de Repeater dueño de
// su propia animación (entrada, salida y cuenta atrás). Con las transiciones
// nativas del ListView el estado de animación era compartido y dos avisos
// seguidos se pisaban: la tarjeta que aún entraba pasaba a ser "desplazada" y
// su transición se cancelaba a medio camino, y al descartar una, el ListView
// recolocaba el resto contra posiciones que ya tenía cacheadas (de ahí los
// saltos y los huecos de más).
//
// Aquí hay un único origen del movimiento: la altura de ranura (slotHeight) de
// cada tarjeta. La posición de una tarjeta es la suma de las ranuras de las
// anteriores, así que desplegar una y empujar a las de abajo son literalmente
// el MISMO valor animado — no dos animaciones que haya que mantener en sincronía.
PanelWindow {
    id: popups

    property var modelData
    screen: modelData

    property int nextKey: 1
    property var notificationsByKey: ({})
    // Tarjetas vivas: las que no están saliendo. Manda en los límites (número
    // máximo y altura de pantalla); las salientes ya no cuentan.
    property int liveCount: 0
    // Altura ocupada por la pila en este instante (suma de ranuras animadas).
    property real contentHeight: 0

    // Se ocultan mientras haya cualquier panel abierto (centro rápido,
    // notificaciones, lanzador, etc.); las notificaciones siguen llegando
    // al centro de notificaciones.
    // Lo mismo que la isla, y por el mismo motivo: estos avisos solo existen
    // con la isla APAGADA (ver shell.qml), o sea que son su sustituto exacto y
    // están en la misma capa Overlay. Arreglar solo uno de los dos dejaría el
    // fallo intacto para quien tiene la isla quitada.
    visible: popupModel.count > 0 && Settings.notifPopupsEnabled && Globals.openPanel === ""
             && !Globals.hiddenByFullscreen(popups.modelData)
             && !remapGuard.remapping
    // Superficie de vida larga: se remapea si el monitor cambia de sitio en el
    // layout. Ver Components/ScreenMoveRemap.qml.
    ScreenMoveRemap { id: remapGuard; window: popups }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // 360 px de ancho de tarjeta.
    implicitWidth: Theme.panelWidth(screen, 360, 300, 0.94)
    // Altura con marca de agua: mientras haya popups vivos la superficie solo
    // crece; se recompacta al vaciarse. Encogerla en caliente dejaba una
    // banda gris en el hueco de la tarjeta saliente: Hyprland no recalcula la
    // región de blur (ignore_alpha) de una capa redimensionada hasta que
    // llega daño nuevo, y con la escena estática el frost obsoleto se quedaba
    // pegado segundos. La zona sobrante es transparente y sin input (mask).
    property int stackHeight: reservedStackHeight
    onContentHeightChanged: if (contentHeight > stackHeight)
        stackHeight = Math.min(maxStackHeight, Math.ceil(contentHeight))
    implicitHeight: popupModel.count > 0 ? stackHeight : 1

    // Solo las tarjetas reciben input: sin máscara, toda la superficie
    // (incluida la zona vacía bajo la pila) bloqueaba los clics al escritorio.
    mask: Region { item: maskArea }
    Item {
        id: maskArea
        width: popups.width
        height: Math.min(popups.contentHeight, popups.stackHeight)
        y: popups.fromBottom ? popups.stackHeight - height : 0
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-popups"

    // Posición configurable: tr | tl | br | bl.
    readonly property string pos: Settings.notifPosition

    // La tarjeta no se desliza ni se escala: se DESPLIEGA desde el borde al que
    // está anclada la pila (su ranura crece de 0 a su altura) mientras el
    // contenido funde con retardo y entra 12 px desde el lateral. La altura
    // reservada evita que la primera notificación de una nueva tanda nazca
    // recortada por el primer cálculo de layout.
    readonly property int  reservedStackHeight: Theme.dp(190)
    readonly property int  enterDuration:  Theme.animNormal
    readonly property int  exitDuration:   Theme.animNormal
    readonly property int  reflowDuration: Theme.animNormal
    // Hacia qué lado entra el contenido y a qué borde se ancla la pila.
    readonly property bool fromRight:  pos.charAt(1) === "r"
    readonly property bool fromBottom: pos.charAt(0) === "b"
    readonly property int  contentSlide: Theme.dp(12)   // kContentSlideOffset
    readonly property int  gap: Theme.dp(8)             // kGap
    anchors {
        top: pos.charAt(0) === "t"
        bottom: pos.charAt(0) === "b"
        left: pos.charAt(1) === "l"
        right: pos.charAt(1) === "r"
    }
    margins {
        top: Theme.barHeight + Theme.barMargin * 2
        bottom: Theme.barMargin
        left: Theme.barMargin
        right: Theme.barMargin
    }

    Connections {
        target: NotifService
        function onPosted(n) {
            // No mostrar popups si hay un panel abierto; quedan en el centro.
            if (Settings.notifPopupsEnabled && Globals.openPanel === "") popups.add(n)
        }
        function onClearedAll() {
            popups.clear()
        }
    }

    // Al abrir cualquier panel, descarta todos los popups visibles.
    Connections {
        target: Globals
        function onOpenPanelChanged() {
            if (Globals.openPanel !== "") popups.clear()
        }
    }

    function notificationFor(key) {
        return notificationsByKey[key] || null
    }

    function add(n) {
        const key = nextKey++
        const map = Object.assign({}, notificationsByKey)
        map[key] = n
        notificationsByKey = map

        liveCount++
        popupModel.insert(0, { "key": key })   // el Repeater crea el delegate aquí
        trimVisible()
        enforceStackHeight()
    }

    function clear() {
        popupModel.clear()
        notificationsByKey = ({})
        liveCount = 0
        contentHeight = 0
        stackHeight = reservedStackHeight
    }

    // Marca la tarjeta como saliente y lanza SU animación de salida. Sigue en
    // el modelo (y por tanto la ventana sigue visible) hasta que la animación
    // termina y _drop() la retira de verdad: quitarla del modelo al instante
    // hacía que la última notificación se esfumara sin animación, porque la
    // ventana se ocultaba en el mismo frame.
    function dismiss(key) {
        const row = rowFor(key)
        if (!row || row.dying)
            return
        row.dying = true
        liveCount = Math.max(0, liveCount - 1)
        row.startExit()
    }

    function rowFor(key) {
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i)
            if (it && it.key === key)
                return it
        }
        return null
    }

    // La más antigua de las vivas (índice 0 = la más nueva).
    function oldestLive() {
        for (let i = rep.count - 1; i >= 0; i--) {
            const it = rep.itemAt(i)
            if (it && !it.dying)
                return it
        }
        return null
    }

    function _drop(key) {
        for (let i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).key === key) {
                popupModel.remove(i)
                break
            }
        }
        const map = Object.assign({}, notificationsByKey)
        delete map[key]
        notificationsByKey = map
        relayout()
        if (popupModel.count === 0)
            stackHeight = reservedStackHeight
    }

    // Coloca cada tarjeta a la distancia acumulada del borde anclado. Se llama
    // cada vez que una ranura cambia de altura (al desplegarse, al cerrarse o
    // al crecer una imagen que carga tarde), así el empuje de las de abajo va
    // exactamente al ritmo de la que lo provoca.
    function relayout() {
        let off = 0
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i)
            if (!it)
                continue
            it.offset = off
            off += it.slotHeight
        }
        contentHeight = off
    }

    // Alto útil de pantalla para la pila (descontando los márgenes de barra).
    readonly property int maxStackHeight: (screen ? screen.height : 1080)
                                          - margins.top - margins.bottom

    // Altura que ocuparán las vivas cuando terminen de desplegarse. Se mide con
    // la altura natural (no con la ranura animada) para que los límites de
    // abajo no dependan del fotograma en que se consulten.
    function liveHeight() {
        let h = 0
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i)
            if (it && !it.dying)
                h += it.naturalHeight
        }
        return h
    }

    // Límite en píxeles, complementario al límite en número (notifMaxVisible):
    // si la pila no cabe en pantalla (muchas tarjetas altas), se descartan las
    // más antiguas —con su animación de salida— hasta que la de abajo nunca
    // quede recortada por el borde. Siempre se conserva al menos la más nueva.
    function enforceStackHeight() {
        while (liveCount > 1 && liveHeight() > maxStackHeight) {
            const oldest = oldestLive()
            if (!oldest)
                break
            dismiss(oldest.key)
        }
    }

    function trimVisible() {
        while (liveCount > Settings.notifMaxVisible) {
            const oldest = oldestLive()
            if (!oldest)
                break
            dismiss(oldest.key)
        }
    }

    ListModel {
        id: popupModel
    }

    Item {
        id: stack
        width: popups.width
        height: popups.stackHeight

        Repeater {
            id: rep
            model: popupModel

            delegate: Item {
                id: row
                required property int key
                readonly property var notification: popups.notificationFor(key)

                // Distancia al borde anclado; la asigna relayout().
                property real offset: 0

                // Apertura de la ranura, 0 (plegada) → 1 (desplegada). Es EL
                // escalar que animan la entrada y la salida.
                property real openProgress: 0
                readonly property real naturalHeight: card.implicitHeight + popups.gap
                // Altura a la que se abre: sigue a la natural con animación
                // propia, para que una imagen que carga tarde no dé un salto.
                property real targetHeight: 0
                property bool ready: false
                onNaturalHeightChanged: {
                    targetHeight = naturalHeight
                    popups.enforceStackHeight()
                }
                Behavior on targetHeight {
                    enabled: row.ready
                    NumberAnimation {
                        duration: popups.reflowDuration
                        easing.type: Theme.reflowEasing
                    }
                }

                // Altura que esta tarjeta ocupa en la pila (tarjeta + hueco), y
                // de la que sale la posición de todas las de debajo. Es un
                // BINDING, no un valor con destino congelado: animar la altura
                // "hasta N" fijaba N al arrancar, cuando la tarjeta aún no se
                // había medido (implicitHeight 0), y la ranura se quedaba en
                // unos pocos píxeles —tarjeta invisible— hasta que la animación
                // terminaba. Como producto de apertura × altura, recoge la
                // medida real en cuanto llega, esté la animación donde esté.
                readonly property real slotHeight: openProgress * targetHeight
                // 0 → 1: opacidad y desplazamiento lateral del contenido.
                property real reveal: 0
                // Cuenta atrás del timeout, 1 → 0. Alimenta la barra de la tarjeta.
                property real progress: 1
                // Saliendo: ya no cuenta para los límites y no se la vuelve a tocar.
                property bool dying: false

                width: stack.width
                height: slotHeight
                clip: true
                y: popups.fromBottom ? popups.stackHeight - offset - height : offset

                onSlotHeightChanged: popups.relayout()

                NotificationItem {
                    id: card
                    width: row.width
                    // Anclada al borde de la pila: al crecer la ranura la
                    // tarjeta se descubre desde ese borde, no se desliza.
                    y: popups.fromBottom ? row.height - implicitHeight : 0
                    notif: row.notification
                    popupMode: true
                    // Sin cuenta atrás no hay barra que enseñar: con lifetime 0
                    // el aviso no se va solo, así que una barra congelada al
                    // 100% mentiría sobre lo que va a pasar.
                    showProgress: Settings.notifShowProgress && row.lifetime > 0
                    compact: Settings.notifCompact
                    progress: row.progress
                    // Al salir se funde la tarjeta entera; al entrar se descubre
                    // opaca con el propio despliegue (fundirla también en la
                    // entrada la hacía "aparecer dos veces").
                    opacity: row.dying ? Theme.revealOpacity(row.reveal) : 1
                    // El fondo se descubre opaco; sólo el contenido funde (con
                    // retardo) y entra desde el lateral anclado.
                    contentOpacity: Theme.revealOpacity(row.reveal)
                    contentOffsetX: popups.contentSlide * (1 - row.reveal)
                                    * (popups.fromRight ? 1 : -1)
                    onCloseRequested: popups.dismiss(row.key)
                }

                // Entrada: la ranura se despliega desde el borde —empujando a
                // las de abajo en el mismo gesto— mientras el contenido funde.
                ParallelAnimation {
                    id: enterAnim
                    NumberAnimation {
                        target: row; property: "openProgress"
                        from: 0; to: 1
                        duration: popups.enterDuration; easing.type: Theme.enterEasing
                    }
                    NumberAnimation {
                        target: row; property: "reveal"
                        from: 0; to: 1
                        duration: popups.enterDuration; easing.type: Theme.enterEasing
                    }
                }

                // Salida: primero se va la tarjeta, y el hueco se cierra justo
                // detrás; las de abajo suben al ritmo exacto de ese cierre.
                SequentialAnimation {
                    id: exitAnim
                    ParallelAnimation {
                        NumberAnimation {
                            target: row; property: "reveal"; to: 0
                            duration: Math.round(popups.exitDuration * 0.75)
                            easing.type: Theme.exitEasing
                        }
                        SequentialAnimation {
                            PauseAnimation { duration: Math.round(popups.exitDuration * 0.35) }
                            NumberAnimation {
                                target: row; property: "openProgress"; to: 0
                                duration: popups.exitDuration
                                easing.type: Theme.reflowEasing
                            }
                        }
                    }
                    ScriptAction { script: popups._drop(row.key) }
                }

                function startExit() {
                    enterAnim.stop()
                    countdown.stop()
                    exitAnim.start()
                }

                Component.onCompleted: {
                    // Altura inicial sin animar (la anima 'openProgress'); a
                    // partir de aquí, los cambios tardíos sí se suavizan.
                    targetHeight = naturalHeight
                    ready = true
                    popups.relayout()
                    enterAnim.start()
                    // Cuenta atrás lineal y en TIEMPO REAL: se excluye a
                    // propósito del multiplicador de velocidad de animaciones,
                    // porque mide segundos de verdad, no es decoración. Arranca
                    // ya, sin esperar al despliegue.
                    //
                    // Con lifetime 0 (urgencia crítica configurada a "nunca")
                    // no se arranca siquiera: la animación tiene un suelo de
                    // 1000 ms, así que dejarla correr descartaría el aviso al
                    // segundo — justo lo contrario de lo que se ha pedido.
                    if (row.lifetime > 0)
                        countdown.start()
                }

                // Duración según la urgencia que declaró la app (0 baja,
                // 1 normal, 2 crítica). Con 0 segundos el aviso NO expira: se
                // queda hasta que lo descartes, que es lo que manda la
                // especificación de freedesktop para lo crítico.
                readonly property int lifetime: {
                    const u = row.notification && row.notification.urgency !== undefined
                        ? row.notification.urgency : 1
                    return u === 2 ? Settings.notifTimeoutCritical
                         : u === 0 ? Settings.notifTimeoutLow
                                   : Settings.notifTimeout
                }

                NumberAnimation {
                    id: countdown
                    target: row; property: "progress"; from: 1; to: 0
                    duration: Math.max(1000, row.lifetime * 1000)
                    easing.type: Easing.Linear
                    onFinished: popups.dismiss(row.key)
                }

                // El ratón encima pausa la cuenta atrás (y con ella la barra, que se
                // queda congelada donde iba). HoverHandler en vez de un MouseArea
                // por debajo: los handlers no se roban el hover entre sí, así que
                // sigue contando como "encima" aunque el puntero esté sobre la X o
                // sobre un botón de acción, que tienen su propio MouseArea.
                HoverHandler { id: hov }
                readonly property bool hovered: hov.hovered
                onHoveredChanged: {
                    if (row.dying)
                        return
                    if (row.hovered) countdown.pause()
                    else             countdown.resume()
                }
            }
        }
    }
}
