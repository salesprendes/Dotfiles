import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Config

// Ventana base para popouts anclados bajo la barra. exclusionMode=Ignore evita que
// la zona exclusiva de la barra la empuje hacia abajo, así la tarjeta queda justo
// bajo la barra. El contenido va a un ColumnLayout.
PanelWindow {
    id: win

    property var modelData
    screen: modelData

    property bool shown: false
    property int cardWidth: 400
    property int cardMinWidth: 300
    property real cardMaxWidthRatio: 0.92
    readonly property int effectiveCardWidth: Theme.panelWidth(screen, cardWidth, cardMinWidth, cardMaxWidthRatio)
    property real cardMaxHeight: (screen ? screen.height : 1080) * 0.82
    property string ns: "qs-popout"
    property bool alignLeft: false        // ancla la tarjeta a la izquierda
    property bool alignCenter: false      // centra la tarjeta horizontalmente
    property bool scrollable: false
    property real openProgress: 0
    readonly property string animationStyle: Settings.panelAnimationStyle
    readonly property bool fluentAnimation: animationStyle === "fluent"
    readonly property bool dynamicAnimation: animationStyle === "dynamic"
    readonly property real enterDurationFactor: fluentAnimation ? 0.95 : dynamicAnimation ? 1.2 : 1.08
    readonly property real exitDurationFactor: fluentAnimation ? 0.72 : dynamicAnimation ? 0.9 : 0.86
    readonly property int openAnimDuration: Math.round(Settings.popoutAnimationMs * enterDurationFactor)
    readonly property int closeAnimDuration: Math.round(Settings.popoutAnimationMs * exitDurationFactor)
    readonly property string motionEffect: Settings.panelMotionEffect
    readonly property bool directionalMotion: motionEffect === "directional"
    readonly property bool depthMotion: motionEffect === "depth"
    readonly property real panelMotionOffset: directionalMotion ? Theme.dp(190)
                                      : depthMotion ? Theme.dp(82)
                                      : Theme.dp(28)
    readonly property real panelClosedScale: directionalMotion ? 1.0
                                      : depthMotion ? 0.82
                                      : 0.94
    readonly property real panelScale: panelClosedScale + (1.0 - panelClosedScale) * openProgress
    readonly property real panelOffsetY: {
        if (directionalMotion || depthMotion)
            return -panelMotionOffset * (1 - openProgress)
        return panelMotionOffset * (1 - openProgress)
    }
    readonly property var materialEnterCurve: [0.34, 1.14, 0.22, 1.0, 1.0, 1.0]
    readonly property var fluentEnterCurve: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
    readonly property var dynamicEnterCurve: [0.28, 1.72, 0.18, 1.0, 1.0, 1.0]
    readonly property var emphasizedExitCurve: [0.05, 0.0, 0.133333, 0.06, 0.166667, 0.40, 0.208333, 0.82, 0.25, 1.0, 1.0, 1.0]
    readonly property var fluentExitCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0]
    readonly property var directionalExitCurve: [0.3, 0.0, 0.8, 0.15, 1.0, 1.0]
    readonly property var panelEnterCurve: dynamicAnimation ? dynamicEnterCurve
                                           : fluentAnimation ? fluentEnterCurve
                                           : directionalMotion ? fluentEnterCurve
                                           : materialEnterCurve
    readonly property var panelExitCurve: directionalMotion && (fluentAnimation || dynamicAnimation) ? directionalExitCurve
                                          : fluentAnimation ? fluentExitCurve
                                          : emphasizedExitCurve
    default property alias content: col.data

    // Solo en el monitor con foco.
    // El popout existe por pantalla (Variants), pero solo se mapea la superficie del
    // monitor que tenía el foco AL ABRIR (fijado en onShownChanged, no en vivo: mover
    // el ratón a otro monitor con el panel abierto no lo teletransporta). Sin Hyprland
    // (focusedMonitor null) cae al fallback: visible en todos.
    property string openedOnMonitor: ""
    readonly property bool showsHere: openedOnMonitor === "" || !screen
                                      || screen.name === openedOnMonitor

    visible: (shown && showsHere) || openProgress > 0
    color: "transparent"
    // Ignore (no 'exclusiveZone: 0', que forzaría Normal y empujaría la ventana bajo
    // la barra). Así cubre desde y=0 y la tarjeta queda anclada justo bajo la barra.
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: ns
    // Exclusive (no OnDemand) incluso en paneles sin buscador: Hyprland solo da teclado
    // a una capa OnDemand si se hace CLIC en ella, así que ESC nunca llegaba. El popout
    // ya es modal de facto (clic fuera cierra); tomar el teclado no quita nada y ESC cierra siempre.
    WlrLayershell.keyboardFocus: (shown && showsHere) ? WlrKeyboardFocus.Exclusive
                                                      : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

    onShownChanged: {
        if (shown) {
            openedOnMonitor = Hyprland.focusedMonitor?.name ?? ""
            if (showsHere)
                openAnim.restart()
        } else {
            closeAnim.restart()   // no-op si nunca se abrió aquí (progress ya es 0)
        }
    }

    Component.onCompleted: {
        if (shown) {
            openedOnMonitor = Hyprland.focusedMonitor?.name ?? ""
            if (showsHere)
                openAnim.restart()
        }
    }

    NumberAnimation {
        id: openAnim
        target: win
        property: "openProgress"
        from: 0
        to: 1
        duration: win.openAnimDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: win.panelEnterCurve
    }

    NumberAnimation {
        id: closeAnim
        target: win
        property: "openProgress"
        to: 0
        duration: win.closeAnimDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: win.panelExitCurve
    }

    // Fondo: click fuera cierra.
    MouseArea {
        anchors.fill: parent
        enabled: win.openProgress > 0.92
        onClicked: Globals.closeAll()
    }

    // Tarjeta flotante.
    Rectangle {
        id: card
        width: win.effectiveCardWidth
        anchors.top: parent.top
        anchors.topMargin: Theme.barHeight + Theme.barMargin * 2
        anchors.horizontalCenter: win.alignCenter ? parent.horizontalCenter : undefined
        anchors.left: (!win.alignCenter && win.alignLeft) ? parent.left : undefined
        anchors.right: (!win.alignCenter && !win.alignLeft) ? parent.right : undefined
        anchors.leftMargin: Theme.barMargin
        anchors.rightMargin: Theme.barMargin
        height: Math.min(win.cardMaxHeight, col.implicitHeight + Theme.space16 * 2)
        radius: Theme.barRadius + 2
        color: Theme.popupBg
        border.width: Theme.hairline
        border.color: Theme.panelBorder
        clip: true
        antialiasing: true
        // ESC cierra el panel. Va en la tarjeta (Item), no en la ventana: Keys solo
        // funciona sobre Items, colgado del PanelWindow nunca recibía la tecla. Con focus
        // la tarjeta captura ESC; si un hijo tiene el foco (buscador), el evento no
        // consumido burbujea hasta aquí.
        focus: true
        Keys.onEscapePressed: Globals.closeAll()
        opacity: win.directionalMotion ? 1 : win.openProgress
        scale: win.panelScale
        transformOrigin: Item.Top

        // Renderiza la tarjeta a una textura (FBO) mientras es visible y escala esa
        // textura, en vez de re-rasterizar el hairline y las esquinas redondeadas en
        // cada frame del escalado (eso hacía parpadear el contorno). Activa toda la vida
        // visible, sin conmutar a mitad de animación. En reposo scale=1 y geometría
        // entera: muestreo 1:1, nítido.
        layer.enabled: win.visible
        layer.smooth: true

        transform: Translate { y: win.panelOffsetY }

        // Absorbe clicks para que no cierre.
        MouseArea {
            anchors.fill: parent
            enabled: win.openProgress > 0.92
        }

        // Contenedor desplazable. Con 'scrollable' activo y contenido más alto que la
        // tarjeta (topada en cardMaxHeight), desplaza en vez de recortar: lo de abajo
        // nunca desaparece. Sin 'scrollable' queda no interactivo y el scroll interno
        // propio del panel sigue funcionando.
        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: Theme.space16
            contentWidth: width
            contentHeight: col.implicitHeight
            clip: true
            interactive: win.scrollable && contentHeight > height + 0.5
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 6000

            ColumnLayout {
                id: col
                width: flick.width
                spacing: Theme.space12
            }
        }
    }
}
