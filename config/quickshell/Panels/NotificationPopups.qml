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
    implicitWidth: Theme.panelWidth(screen, 410, 320, 0.94)
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

    // Animación de popup: desplazamiento lateral, fundido corto y reacomodo
    // estable. La altura reservada evita que la primera notificación de una
    // nueva tanda nazca recortada por el primer cálculo de layout.
    readonly property int  reservedStackHeight: Theme.dp(190)
    // Entrada larga con aterrizaje suave. El fundido termina antes que el
    // movimiento para que la tarjeta sea legible mientras aún se desliza.
    readonly property int  enterDuration: Theme.animNormal <= 0 ? 0 : 380
    readonly property int  enterFadeDuration: Theme.animNormal <= 0 ? 0 : 240
    readonly property int  exitDuration:  Theme.animNormal <= 0 ? 0 : 240
    // Reacomodo de la pila con la misma deceleración que la entrada: las
    // tarjetas restantes "flotan" a su sitio en vez de dar un tirón corto.
    readonly property int  reflowDuration: Theme.animNormal <= 0 ? 0 : 300
    readonly property real enterOffset: (pos.charAt(1) === "l" ? -1 : 1) * Theme.dp(44)
    readonly property real exitOffset:  (pos.charAt(1) === "l" ? -1 : 1) * Theme.dp(48)
    readonly property var  enterCurve:  [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
    // Salida acelerada: la tarjeta "se marcha" ganando velocidad, en vez de
    // frenar a mitad de camino.
    readonly property var  exitCurve:   [0.3, 0.0, 0.8, 0.15, 1.0, 1.0]
    readonly property var  reflowCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
    readonly property real collapsedScale: 0.972
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

    // Cierre en dos tiempos dentro del delegate: la tarjeta se desvanece en su
    // sitio y luego su hueco se colapsa, así las de debajo suben siguiéndolo sin
    // cruzarse con una capa fantasma. Solo al final se retira del modelo.
    function removeKey(key) {
        for (let i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).key === key) {
                const item = list.itemAtIndex(i)
                if (item) item.beginExit()
                else finishRemove(key)
                return
            }
        }
    }

    function finishRemove(key) {
        for (let i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).key === key) {
                popupModel.remove(i)
                break
            }
        }
        const map = Object.assign({}, notificationsByKey)
        delete map[key]
        notificationsByKey = map
        activePopupCount = Math.max(0, activePopupCount - 1)
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
        // El hueco entre tarjetas vive DENTRO de cada delegate (no en
        // spacing): al colapsar la altura en el cierre se lleva también su
        // separación y las siguientes aterrizan exactamente en su sitio.
        spacing: 0
        model: popupModel
        // Según la posición: arriba → la nueva encima; abajo → la nueva debajo.
        verticalLayoutDirection: popups.pos.charAt(0) === "b" ? ListView.BottomToTop
                                                              : ListView.TopToBottom
        // Cubre tanto la entrada de tarjetas nuevas como los crecimientos
        // tardíos (imágenes/cuerpos que se expanden al medirse).
        onContentHeightChanged: popups.enforceStackHeight()

        // Reacomodo de los delegates cuando entra o sale un item. Solo cambia
        // la coordenada Y para evitar reajustes de altura en cada frame.
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: popups.reflowDuration
                easing.type: Easing.BezierSpline; easing.bezierCurve: popups.reflowCurve }
        }

        delegate: Item {
            id: row
            required property int key
            readonly property var notification: popups.notificationFor(key)

            width: ListView.view.width
            implicitHeight: card.implicitHeight + Theme.space8
            height: implicitHeight
            clip: false

            property bool exiting: false
            function beginExit() {
                if (exiting)
                    return
                exiting = true
                exitAnim.start()
            }

            SequentialAnimation {
                id: exitAnim
                ParallelAnimation {
                    NumberAnimation { target: card; property: "opacity"; to: 0; duration: popups.exitDuration
                        easing.type: Easing.BezierSpline; easing.bezierCurve: popups.exitCurve }
                    NumberAnimation { target: card; property: "x"; to: popups.exitOffset; duration: popups.exitDuration
                        easing.type: Easing.BezierSpline; easing.bezierCurve: popups.exitCurve }
                }
                // La tarjeta ya es invisible: colapsar ahora su hueco no
                // deforma nada y arrastra suavemente a las de debajo.
                NumberAnimation { target: row; property: "height"; to: 0; duration: popups.reflowDuration
                    easing.type: Easing.BezierSpline; easing.bezierCurve: popups.reflowCurve }
                ScriptAction { script: popups.finishRemove(row.key) }
            }

            NotificationItem {
                id: card
                width: parent.width
                notif: row.notification
                popupMode: true
                onCloseRequested: popups.removeKey(row.key)

                // Entrada del popup: desplazamiento lateral con fundido y escala sutil.
                // No toca la altura para evitar reajustes verticales al nacer.
                opacity: 0
                x: popups.enterOffset
                scale: popups.collapsedScale
                transformOrigin: popups.pos.charAt(1) === "r" ? Item.Right : Item.Left
                layer.enabled: opacity < 0.999 || Math.abs(x) > 0.5 || scale < 0.999
                layer.smooth: true
                // Diferido: arranca tras el primer pase de layout (cuando el
                // delegate ya está medido y posicionado), evitando la carrera
                // que hacía que la primera "saltara" abajo y volviera arriba.
                Component.onCompleted: Qt.callLater(enterAnim.start)
                ParallelAnimation {
                    id: enterAnim
                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: popups.enterFadeDuration
                        easing.type: Easing.OutCubic }
                    NumberAnimation { target: card; property: "x"; to: 0; duration: popups.enterDuration
                        easing.type: Easing.BezierSpline; easing.bezierCurve: popups.enterCurve }
                    NumberAnimation { target: card; property: "scale"; to: 1; duration: popups.enterDuration
                        easing.type: Easing.BezierSpline; easing.bezierCurve: popups.enterCurve }
                }
            }

            // Pausa el auto-cierre mientras el ratón está sobre el popup. Va
            // DEBAJO de la tarjeta (z:-1) para NO robar el hover a los botones
            // internos (la X se pone roja gracias a su propio MouseArea); el
            // cuerpo vacío de la tarjeta le pasa el hover por transparencia.
            MouseArea {
                id: hov
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                z: -1
            }

            Timer {
                id: autoDismiss
                interval: Math.max(1000, Settings.notifTimeout * 1000)
                repeat: false
                // Pausa sobre el cuerpo (hov) y también sobre la propia X, cuyo
                // hover consume su MouseArea y no llegaría a hov.
                running: !row.exiting && !hov.containsMouse && !card.closeHovered
                onTriggered: popups.removeKey(row.key)
            }
        }
    }
}
