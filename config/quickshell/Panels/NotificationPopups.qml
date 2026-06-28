import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

// ─────────────────────────────────────────────────────────────
//  Popups transitorios. Escuchan NotifService.posted y muestran
//  la notificación arriba a la derecha; se autodescarta a los 5s
//  (se pausa al pasar el ratón por encima).
// ─────────────────────────────────────────────────────────────
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
    implicitHeight: activePopupCount > 0
        ? Math.max(reservedStackHeight, list.contentHeight, exitContentHeight())
        : 1

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-popups"

    // Posición configurable: tr | tl | br | bl.
    readonly property string pos: Settings.notifPosition

    // Animación de popup: desplazamiento lateral, fundido corto y reacomodo
    // estable. La altura reservada evita que la primera notificación de una
    // nueva tanda nazca recortada por el primer cálculo de layout.
    readonly property int  reservedStackHeight: Theme.dp(190)
    readonly property int  enterDuration: Theme.animNormal <= 0 ? 0 : 260
    readonly property int  exitDuration:  Theme.animNormal <= 0 ? 0 : 260
    readonly property int  reflowDuration: Theme.animNormal <= 0 ? 0 : Math.min(230, Math.max(150, Math.round(Theme.animNormal * 0.68)))
    readonly property real enterOffset: (pos.charAt(1) === "l" ? -1 : 1) * Theme.dp(58)
    readonly property real exitOffset:  (pos.charAt(1) === "l" ? -1 : 1) * Theme.dp(48)
    readonly property var  enterCurve:  [0.19, 1.0, 0.22, 1.0, 1.0, 1.0]
    readonly property var  exitCurve:   [0.22, 0.0, 0.18, 1.0, 1.0, 1.0]
    readonly property var  reflowCurve: [0.22, 1.0, 0.36, 1.0, 1.0, 1.0]
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

    function exitContentHeight() {
        let h = 0
        for (let i = 0; i < exitModel.count; i++) {
            const e = exitModel.get(i)
            h = Math.max(h, Math.round((e.startY || 0) + (e.startHeight || 0)))
        }
        return h
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
        exitModel.clear()
        notificationsByKey = ({})
    }

    function removeKey(key) {
        for (let i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).key === key) {
                const item = list.itemAtIndex(i)
                exitModel.append({
                    "key": key,
                    "startY": item ? item.y : 0,
                    "startHeight": item ? item.height : Theme.dp(120)
                })
                popupModel.remove(i)
                return
            }
        }
    }

    function finishExit(key) {
        for (let i = 0; i < exitModel.count; i++) {
            if (exitModel.get(i).key === key) {
                exitModel.remove(i)
                break
            }
        }
        const map = Object.assign({}, notificationsByKey)
        delete map[key]
        notificationsByKey = map
        activePopupCount = Math.max(0, activePopupCount - 1)
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

    ListModel {
        id: exitModel
    }

    // Pila en ListView. Al cerrar, el item se saca de esta lista y se anima en
    // una capa flotante; así la salida no puede deformar ni dejar bandas.
    ListView {
        id: list
        width: parent.width
        height: popups.activePopupCount > 0
            ? Math.max(contentHeight, popups.reservedStackHeight, popups.exitContentHeight())
            : 1
        y: popups.pos.charAt(0) === "b" ? Math.max(0, parent.height - height) : 0
        interactive: false
        clip: false
        spacing: Theme.space8
        model: popupModel
        // Según la posición: arriba → la nueva encima; abajo → la nueva debajo.
        verticalLayoutDirection: popups.pos.charAt(0) === "b" ? ListView.BottomToTop
                                                              : ListView.TopToBottom

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
            implicitHeight: card.implicitHeight
            height: implicitHeight
            clip: false

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
                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: popups.enterDuration
                        easing.type: Easing.OutCubic }
                    NumberAnimation { target: card; property: "x"; to: 0; duration: popups.enterDuration
                        easing.type: Easing.BezierSpline; easing.bezierCurve: popups.enterCurve }
                    NumberAnimation { target: card; property: "scale"; to: 1; duration: popups.enterDuration
                        easing.type: Easing.BezierSpline; easing.bezierCurve: popups.enterCurve }
                }
            }

            MouseArea {
                id: hov
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }

            Timer {
                id: autoDismiss
                interval: Math.max(1000, Settings.notifTimeout * 1000)
                repeat: false
                running: !hov.containsMouse
                onTriggered: popups.removeKey(row.key)
            }
        }
    }

    Repeater {
        model: exitModel
        delegate: Item {
            id: exitRow
            required property int key
            required property real startY
            required property real startHeight
            readonly property var notification: popups.notificationFor(key)

            width: popups.width
            height: startHeight
            y: startY
            z: 100
            clip: false

            NotificationItem {
                id: exitCard
                width: parent.width
                notif: exitRow.notification
                popupMode: true
                opacity: 1
                x: 0
                transformOrigin: popups.pos.charAt(1) === "r" ? Item.Right : Item.Left
                layer.enabled: true
                layer.smooth: true
            }

            Component.onCompleted: Qt.callLater(exitAnim.start)

            ParallelAnimation {
                id: exitAnim
                onFinished: popups.finishExit(exitRow.key)
                NumberAnimation { target: exitCard; property: "opacity"; to: 0; duration: popups.exitDuration
                    easing.type: Easing.BezierSpline; easing.bezierCurve: popups.exitCurve }
                NumberAnimation { target: exitCard; property: "x"; to: popups.exitOffset; duration: popups.exitDuration
                    easing.type: Easing.BezierSpline; easing.bezierCurve: popups.exitCurve }
            }
        }
    }
}
