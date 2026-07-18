import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

// Popups transitorios: escuchan NotifService.posted, muestran la notificación
// en una esquina y se autodescartan a los 5s (pausa al pasar el ratón).
PanelWindow {
    id: popups

    property var modelData
    screen: modelData

    property int nextKey: 1
    property int activePopupCount: 0
    property var notificationsByKey: ({})

    // Se ocultan mientras haya cualquier panel abierto (centro rápido,
    // notificaciones, lanzador, etc.); las notificaciones siguen llegando
    // al centro de notificaciones.
    visible: activePopupCount > 0 && Settings.notifPopupsEnabled && Globals.openPanel === ""
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // 360 px de ancho de tarjeta.
    implicitWidth: Theme.panelWidth(screen, 360, 300, 0.94)
    // Altura con marca de agua: mientras haya popups vivos la superficie solo
    // crece; se recompacta al ocultarse. Encogerla en caliente dejaba una
    // banda gris en el hueco de la tarjeta saliente: Hyprland no recalcula la
    // región de blur (ignore_alpha) de una capa redimensionada hasta que
    // llega daño nuevo, y con la escena estática el frost obsoleto se quedaba
    // pegado segundos. La zona sobrante es transparente y sin input (mask).
    property int stackHeight: reservedStackHeight
    readonly property int liveStackHeight: activePopupCount > 0
        ? Math.max(reservedStackHeight, list.contentHeight)
        : reservedStackHeight
    onLiveStackHeightChanged: if (liveStackHeight > stackHeight)
        stackHeight = Math.min(maxStackHeight, liveStackHeight)
    onActivePopupCountChanged: if (activePopupCount === 0) stackHeight = reservedStackHeight
    implicitHeight: activePopupCount > 0 ? stackHeight : 1

    // Solo las tarjetas reciben input: sin máscara, toda la superficie
    // (incluida la zona vacía bajo la pila) bloqueaba los clics al escritorio.
    mask: Region { item: maskArea }
    Item {
        id: maskArea
        width: popups.width
        height: Math.min(list.contentHeight, popups.height)
        y: popups.pos.charAt(0) === "b" ? popups.height - height : 0
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-popups"

    // Posición configurable: tr | tl | br | bl.
    readonly property string pos: Settings.notifPosition

    // La tarjeta NO se desliza ni se escala; se
    // descubre con un barrido de recorte desde el borde de la pantalla al que
    // está anclada, mientras su contenido funde con retardo y se contra-desplaza
    // 12 px. La altura reservada evita que la primera notificación de una nueva
    // tanda nazca recortada por el primer cálculo de layout.
    readonly property int  reservedStackHeight: Theme.dp(190)
    readonly property int  enterDuration:  Theme.animNormal
    readonly property int  exitDuration:   Theme.animNormal
    readonly property int  reflowDuration: Theme.animNormal
    // Hacia qué lado barre: el del borde al que está anclada la pila.
    readonly property bool fromRight: pos.charAt(1) === "r"
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

        activePopupCount++
        popupModel.insert(0, { "key": key })
        trimVisiblePopups()
    }

    function clear() {
        activePopupCount = 0
        popupModel.clear()
        notificationsByKey = ({})
    }

    // Al descartar se quita del modelo INMEDIATAMENTE: el ListView mantiene vivo
    // el delegate mientras corre su transición 'remove' (la tarjeta se repliega)
    // y a la vez desplaza las de debajo con 'removeDisplaced'. Antes se animaba
    // la ALTURA de la fila hasta 0 para colapsar el hueco: eso rompía el binding
    // height→implicitHeight y descolocaba las posiciones que el ListView tiene
    // cacheadas, dejando un hueco de más entre la primera y la segunda tarjeta.
    // La notificación en sí se olvida (_forgetQueue/forgetTimer) cuando la
    // transición de salida ha terminado: el delegate sigue vivo hasta
    // entonces y necesita seguir leyéndola para pintarse mientras se repliega.
    function removeKey(key) {
        for (let i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).key === key) {
                popupModel.remove(i)
                activePopupCount = Math.max(0, activePopupCount - 1)
                _forgetQueue.push(key)
                forgetTimer.restart()
                return
            }
        }
    }

    property var _forgetQueue: []
    Timer {
        id: forgetTimer
        interval: popups.exitDuration + 120
        onTriggered: {
            const map = Object.assign({}, popups.notificationsByKey)
            for (const k of popups._forgetQueue)
                delete map[k]
            popups.notificationsByKey = map
            popups._forgetQueue = []
        }
    }

    // Alto útil de pantalla para la pila (descontando los márgenes de barra).
    readonly property int maxStackHeight: (screen ? screen.height : 1080)
                                          - margins.top - margins.bottom

    // Límite en píxeles, complementario al límite en número (notifMaxVisible):
    // si la pila no cabe en pantalla (muchas tarjetas altas), se descartan las
    // más antiguas —con su animación de salida— hasta que la de abajo nunca
    // quede recortada por el borde. Siempre se conserva al menos la más nueva.
    function enforceStackHeight() {
        let h = list.contentHeight
        while (popupModel.count > 1 && h > maxStackHeight) {
            const idx = popupModel.count - 1
            const it = list.itemAtIndex(idx)
            h -= it ? it.height : Theme.dp(128)   // la fila ya incluye su hueco
            removeKey(popupModel.get(idx).key)
        }
    }

    function trimVisiblePopups() {
        let visibleCount = popupModel.count
        while (visibleCount > Settings.notifMaxVisible) {
            for (let i = popupModel.count - 1; i >= 0; i--) {
                removeKey(popupModel.get(i).key)
                visibleCount--
                break
            }
        }
    }

    ListModel {
        id: popupModel
    }

    // Pila en ListView. La salida se anima dentro del propio delegate
    // (desvanecer → colapsar hueco), así nunca hay solapes ni bandas.
    ListView {
        id: list
        width: parent.width
        height: popups.activePopupCount > 0
            ? Math.max(contentHeight, popups.reservedStackHeight)
            : 1
        y: popups.pos.charAt(0) === "b" ? Math.max(0, parent.height - height) : 0
        interactive: false
        clip: false
        // El hueco entre tarjetas va dentro de cada delegate (implicitHeight =
        // tarjeta + gap), no en 'spacing'.
        spacing: 0
        model: popupModel
        // Según la posición: arriba → la nueva encima; abajo → la nueva debajo.
        verticalLayoutDirection: popups.pos.charAt(0) === "b" ? ListView.BottomToTop
                                                              : ListView.TopToBottom
        // Cubre tanto la entrada de tarjetas nuevas como los crecimientos
        // tardíos (imágenes/cuerpos que se expanden al medirse).
        onContentHeightChanged: popups.enforceStackHeight()

        // Transiciones NATIVAS del ListView. La altura del delegate no se toca
        // nunca (era la causa del hueco de más): sólo se anima 'reveal' —el
        // barrido— y la 'y' de las que se recolocan. Al entrar una tarjeta, las
        // de debajo bajan; al salir, suben para cerrar el hueco mientras la que
        // se va se repliega encima.
        add: Transition {
            NumberAnimation { property: "reveal"; from: 0; to: 1
                duration: popups.enterDuration; easing.type: Theme.enterEasing }
        }
        addDisplaced: Transition {
            NumberAnimation { properties: "y"; duration: popups.reflowDuration
                easing.type: Theme.reflowEasing }
        }
        remove: Transition {
            NumberAnimation { property: "reveal"; to: 0
                duration: popups.exitDuration; easing.type: Theme.reflowEasing }
        }
        removeDisplaced: Transition {
            NumberAnimation { properties: "y"; duration: popups.reflowDuration
                easing.type: Theme.reflowEasing }
        }
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: popups.reflowDuration
                easing.type: Theme.reflowEasing }
        }

        delegate: Item {
            id: row
            required property int key
            readonly property var notification: popups.notificationFor(key)

            width: ListView.view.width
            implicitHeight: card.implicitHeight + popups.gap
            height: implicitHeight
            clip: false

            // Escalar único del movimiento: de él salen recorte, contra-posición
            // y opacidad del contenido. Lo animan las transiciones del ListView.
            property real reveal: 0
            // Cuenta atrás del timeout, 1 → 0. Alimenta la barra de la tarjeta.
            property real progress: 1

            // Ventana de recorte: crece desde el borde anclado. La tarjeta de
            // dentro se contra-posiciona (x: -viewport.x) para quedarse quieta:
            // no se desliza, se descubre.
            Item {
                id: viewport
                width: Math.round(row.width * row.reveal)
                height: card.implicitHeight
                x: popups.fromRight ? row.width - width : 0
                clip: true

                NotificationItem {
                    id: card
                    width: row.width
                    x: -viewport.x
                    notif: row.notification
                    popupMode: true
                    showProgress: true
                    progress: row.progress
                    // El fondo se descubre opaco; sólo el contenido funde (con
                    // retardo) y se contra-desplaza contra el sentido del barrido.
                    contentOpacity: Theme.revealOpacity(row.reveal)
                    contentOffsetX: popups.contentSlide * (1 - row.reveal)
                                    * (popups.fromRight ? 1 : -1)
                    onCloseRequested: popups.removeKey(row.key)
                }
            }

            // Cuenta atrás lineal y en TIEMPO REAL: se excluye a propósito
            // del multiplicador de velocidad de animaciones, porque mide
            // segundos de verdad, no es decoración. Arranca ya, sin esperar
            // al barrido — se lanza al crear el toast.
            Component.onCompleted: countdown.start()

            NumberAnimation {
                id: countdown
                target: row; property: "progress"; from: 1; to: 0
                duration: Math.max(1000, Settings.notifTimeout * 1000)
                easing.type: Easing.Linear
                onFinished: popups.removeKey(row.key)
            }

            // El ratón encima pausa la cuenta atrás (y con ella la barra, que se
            // queda congelada donde iba). HoverHandler en vez de un MouseArea
            // por debajo: los handlers no se roban el hover entre sí, así que
            // sigue contando como "encima" aunque el puntero esté sobre la X o
            // sobre un botón de acción, que tienen su propio MouseArea.
            HoverHandler { id: hov }
            readonly property bool hovered: hov.hovered
            onHoveredChanged: {
                if (row.hovered) countdown.pause()
                else             countdown.resume()
            }
        }
    }
}
