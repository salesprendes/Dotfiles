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
    property var notificationsByKey: ({})
    property var cleanupKeys: []

    // Se ocultan mientras haya cualquier panel abierto (centro rápido,
    // notificaciones, lanzador, etc.); las notificaciones siguen llegando
    // al centro de notificaciones.
    visible: popupModel.count > 0 && Settings.notifPopupsEnabled && Globals.openPanel === ""
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Theme.panelWidth(screen, 410, 320, 0.94)
    implicitHeight: Math.max(1, list.contentHeight)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-popups"

    // Posición configurable: tr | tl | br | bl.
    readonly property string pos: Settings.notifPosition

    // ── Animaciones adaptadas de DankMaterialShell (efecto por defecto) ──
    // La tarjeta entra/sale deslizando + atenuando + escalando; la pila se
    // reordena animando la posición (sin colapso con recorte visible → sin
    // banda gris). Curvas cubic-bezier copiadas de DMS:
    //   · entrada: espacial con leve overshoot (expressiveDefaultSpatial)
    //   · salida:  "emphasized"
    //   · reflujo: decel estándar (standardDecel)
    readonly property real enterOffset: (pos.charAt(1) === "l" ? -1 : 1) * Theme.dp(20)
    readonly property real exitOffset:  (pos.charAt(1) === "l" ? -1 : 1) * Theme.dp(80)
    readonly property var  enterCurve:  [0.38, 1.21, 0.22, 1, 1, 1]
    readonly property var  exitCurve:   [0.05, 0.0, 0.133333, 0.06, 0.166667, 0.40, 0.208333, 0.82, 0.25, 1.0, 1.0, 1.0]
    readonly property var  reflowCurve: [0, 0, 0, 1, 1, 1]
    readonly property real collapsedScale: 0.96
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

        popupModel.insert(0, { "key": key })
        if (popupModel.count > Settings.notifMaxVisible)
            removeKey(popupModel.get(popupModel.count - 1).key)
    }

    function clear() {
        popupModel.clear()
        notificationsByKey = ({})
        cleanupKeys = []
    }

    // Quita la notificación del modelo. El delegate retrasa su destrucción
    // (ListView.delayRemove) para reproducir su animación de salida. La entrada
    // de notificationsByKey se limpia un poco después (cleanupTimer), cuando la
    // animación ya terminó y nadie la lee.
    function removeKey(key) {
        for (let i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).key === key) {
                popupModel.remove(i)
                break
            }
        }
        const pending = cleanupKeys.slice()
        pending.push(key)
        cleanupKeys = pending
        cleanupTimer.restart()
    }

    Timer {
        id: cleanupTimer
        interval: 600
        repeat: false
        onTriggered: {
            const map = Object.assign({}, notificationsByKey)
            for (let i = 0; i < cleanupKeys.length; i++)
                delete map[cleanupKeys[i]]
            cleanupKeys = []
            notificationsByKey = map
        }
    }

    ListModel {
        id: popupModel
    }

    // Pila en ListView (preserva la identidad de cada delegate al insertar/
    // quitar; las que ya están NO se reinician). Reflujo entre tarjetas con la
    // transición 'displaced' (anima la Y, no toca la altura → la ventana NO se
    // reajusta cada frame al entrar). La salida usa el mecanismo canónico
    // ListView.delayRemove para animar de forma determinista (sin banda gris).
    ListView {
        id: list
        width: parent.width
        height: contentHeight
        interactive: false
        clip: false
        spacing: Theme.space8
        model: popupModel
        // Según la posición: arriba → la nueva encima; abajo → la nueva debajo.
        verticalLayoutDirection: popups.pos.charAt(0) === "b" ? ListView.BottomToTop
                                                              : ListView.TopToBottom

        // Reacomodo de las demás cuando entra/sale una (solo mueve la Y, no la
        // altura → la ventana NO se reajusta cada frame). Curva de DMS. Esto es
        // lo que hace que la NUEVA se coloque encima y "arrastre" la otra abajo.
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: Theme.animNormal
                easing.type: Easing.BezierSpline; easing.bezierCurve: popups.reflowCurve }
        }

        delegate: Item {
            id: row
            required property int key
            readonly property var notification: popups.notificationFor(key)

            // 'collapse' 1→0 SOLO al salir; el alto es COMPLETO desde el inicio
            // (no hay "desplegado" lento ni reajuste de ventana cada frame).
            property real collapse: 1

            width: ListView.view.width
            implicitHeight: card.implicitHeight * collapse
            height: implicitHeight
            clip: true

            NotificationItem {
                id: card
                width: parent.width
                notif: row.notification
                popupMode: true
                onCloseRequested: popups.removeKey(row.key)

                // ENTRADA (DMS): deslizamiento + fundido + escala 0.96→1, con la
                // curva espacial. SIN tocar la altura (un único reajuste de
                // ventana → sin el "desplegado" lento ni tirones).
                opacity: 0
                x: popups.enterOffset
                scale: popups.collapsedScale
                transformOrigin: Item.Center
                // Diferido: arranca tras el primer pase de layout (cuando el
                // delegate ya está medido y posicionado), evitando la carrera
                // que hacía que la primera "saltara" abajo y volviera arriba.
                Component.onCompleted: Qt.callLater(enterAnim.start)
                ParallelAnimation {
                    id: enterAnim
                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: Theme.animNormal
                        easing.type: Easing.OutCubic }
                    NumberAnimation { target: card; property: "x"; to: 0; duration: Theme.animNormal
                        easing.type: Easing.BezierSpline; easing.bezierCurve: popups.enterCurve }
                    NumberAnimation { target: card; property: "scale"; to: 1; duration: Theme.animNormal
                        easing.type: Easing.BezierSpline; easing.bezierCurve: popups.enterCurve }
                }
            }

            // SALIDA (DMS): la tarjeta se desliza (80px) + atenúa a 0 + escala a
            // 0.96 con la curva "emphasized"; al quedar invisible, colapsa el alto
            // para cerrar el hueco (sin banda gris, la tarjeta ya no se dibuja).
            // Usa ListView.delayRemove para que sea determinista (sin interrumpir).
            ListView.onRemove: SequentialAnimation {
                PropertyAction { target: row; property: "ListView.delayRemove"; value: true }
                ParallelAnimation {
                    NumberAnimation { target: card; property: "opacity"; to: 0; duration: Theme.animNormal
                        easing.type: Easing.BezierSpline; easing.bezierCurve: popups.exitCurve }
                    NumberAnimation { target: card; property: "x"; to: popups.exitOffset; duration: Theme.animNormal
                        easing.type: Easing.BezierSpline; easing.bezierCurve: popups.exitCurve }
                    NumberAnimation { target: card; property: "scale"; to: popups.collapsedScale; duration: Theme.animNormal
                        easing.type: Easing.BezierSpline; easing.bezierCurve: popups.exitCurve }
                }
                NumberAnimation { target: row; property: "collapse"; to: 0; duration: Theme.animFast
                    easing.type: Easing.BezierSpline; easing.bezierCurve: popups.reflowCurve }
                PropertyAction { target: row; property: "ListView.delayRemove"; value: false }
            }

            MouseArea {
                id: hov
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }

            Timer {
                interval: Math.max(1000, Settings.notifTimeout * 1000)
                repeat: false
                running: !hov.containsMouse
                onTriggered: popups.removeKey(row.key)
            }
        }
    }
}
