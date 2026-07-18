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
    // Un unico escalar 0→1 mueve todo. La tarjeta se despliega
    // desde el borde anclado (la barra, arriba) recortando su contenido, en vez
    // de escalarse y fundirse. El contenido no se deforma ni se desplaza: se va
    // descubriendo, y funde con retardo (ver Theme.revealOpacity).
    property real openProgress: 0
    readonly property int openAnimDuration: Settings.popoutAnimationMs
    readonly property int closeAnimDuration: Settings.popoutAnimationMs
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
        easing.type: Theme.enterEasing
    }

    NumberAnimation {
        id: closeAnim
        target: win
        property: "openProgress"
        to: 0
        duration: win.closeAnimDuration
        easing.type: Theme.exitEasing
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

        // Altura en reposo. La tarjeta se despliega hasta aquí desde el borde
        // anclado (arriba, bajo la barra): 'height' es el recorte del barrido.
        readonly property int fullHeight: Math.min(win.cardMaxHeight,
                                                   col.implicitHeight + Theme.space16 * 2)
        height: Math.round(fullHeight * win.openProgress)

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

        // Absorbe clicks para que no cierre.
        MouseArea {
            anchors.fill: parent
            enabled: win.openProgress > 0.92
        }

        // Contenido a altura COMPLETA y anclado arriba, aunque la tarjeta aún
        // no haya terminado de desplegarse: así el recorte lo va descubriendo
        // sin comprimirlo ni arrastrarlo (si el contenido siguiera a la altura
        // animada, el layout se recalcularía en cada frame y el texto bailaría).
        Item {
            id: contentHost
            width: card.width
            height: card.fullHeight
            opacity: Theme.revealOpacity(win.openProgress)

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
}
