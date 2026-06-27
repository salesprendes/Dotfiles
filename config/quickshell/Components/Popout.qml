import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Ventana base para popouts anclados bajo la barra.
//  exclusionMode=Ignore evita que la zona exclusiva de la barra
//  la empuje hacia abajo → la tarjeta queda justo bajo la barra.
//  El contenido se añade a un ColumnLayout (Popout { ...filas... }).
// ─────────────────────────────────────────────────────────────
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
    property bool keyboardExclusive: false // captura teclado (lanzador)
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

    visible: shown || openProgress > 0
    color: "transparent"
    // Ignore (no 'exclusiveZone: 0', que forzaría Normal y empujaría
    // la ventana bajo la barra). Así cubre desde y=0 y la tarjeta
    // queda anclada justo bajo la barra.
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: ns
    WlrLayershell.keyboardFocus: shown
        ? (keyboardExclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
        : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

    onShownChanged: {
        if (shown)
            openAnim.restart()
        else
            closeAnim.restart()
    }

    Component.onCompleted: {
        if (shown)
            openAnim.restart()
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
        border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.5)
        clip: true
        antialiasing: true
        opacity: win.directionalMotion ? 1 : win.openProgress
        scale: win.panelScale
        transformOrigin: Item.Top

        // Renderiza la tarjeta a una textura (FBO) durante toda su vida
        // visible y escala ESA textura, en vez de re-rasterizar el borde
        // fino (hairline) y las esquinas redondeadas en cada frame del
        // escalado → elimina el parpadeo de las líneas del contorno. Se
        // mantiene activa toda la vida visible (no se conmuta a mitad de la
        // animación) para que los paneles altos/pesados no tengan ningún
        // frame de transición al asignar el FBO. En reposo scale=1 y la
        // geometría es entera, así que la textura se muestrea 1:1 → nítido.
        layer.enabled: win.visible
        layer.smooth: true

        transform: Translate { y: win.panelOffsetY }

        // Absorbe clicks para que no cierre.
        MouseArea {
            anchors.fill: parent
            enabled: win.openProgress > 0.92
        }

        // Contenedor desplazable. Cuando 'scrollable' está activo y el
        // contenido supera la altura de la tarjeta (topada en cardMaxHeight),
        // se desplaza en vez de recortarse → lo de abajo nunca desaparece.
        // Para los paneles que no lo activan se comporta igual que antes
        // (no interactivo): su scroll interno propio sigue funcionando.
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
