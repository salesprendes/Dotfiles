import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Config

// Ventana base para los popouts anclados a la barra. exclusionMode Ignore evita
// que la zona exclusiva de la barra la empuje hacia abajo, así que la tarjeta
// queda justo pegada a ella. El contenido va a un ColumnLayout.
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
    // Un único escalar 0→1 mueve todo: la tarjeta se despliega desde el borde
    // anclado recortando su contenido, en vez de escalarse y fundirse. El
    // contenido no se deforma ni se desplaza, se va descubriendo, y funde con
    // retardo.
    property real openProgress: 0
    // ESC cierra, salvo que el panel tenga algo que interrumpir primero: la
    // primera pulsación corta lo que esté en marcha y la segunda cierra. Quien lo
    // quiera declara 'escapeAction' y devuelve true si ha consumido la tecla.
    property var escapeAction: null
    // ←/→ saltan al panel del widget vecino de la barra, sin cerrar y volver a
    // abrir. Un panel que use las flechas para lo suyo lo apaga.
    //
    // No hace falta excluir los buscadores a mano: 'Keys' en la tarjeta solo ve
    // lo que sus hijos no han consumido, y un campo de texto con el foco se queda
    // las flechas para mover el cursor.
    property bool switchWithArrows: true
    readonly property int openAnimDuration: Settings.popoutAnimationMs
    // El cierre va un punto más ágil que la apertura: lo que entra se disfruta,
    // lo que se despide no debe hacerse esperar.
    readonly property int closeAnimDuration: Math.round(Settings.popoutAnimationMs * 0.7)
    default property alias content: col.data

    // Solo en el monitor con foco al abrir, fijado en ese momento y no en vivo,
    // para que mover el ratón a otro monitor no teletransporte el panel. shell.qml
    // ya construye la ranura solo en ese monitor; esto queda como respaldo para la
    // toolbar única y para el caso sin Hyprland, donde se ve en todos.
    readonly property bool showsHere: Globals.openedOnMonitor === "" || !screen
                                      || screen.name === Globals.openedOnMonitor

    visible: ((shown && showsHere) || openProgress > 0) && !remapGuard.remapping
    // La mayoría de popouts nacen y mueren con su apertura, así que verían la
    // posición nueva solos; los que se mantienen vivos y cualquiera que estuviera
    // abierto durante un cambio de dock sí necesitan el remapeo.
    ScreenMoveRemap { id: remapGuard; window: win }
    color: "transparent"
    // Ignore y no 'exclusiveZone: 0', que forzaría Normal y empujaría la ventana
    // bajo la barra. Así cubre desde y=0 y la tarjeta queda anclada a la barra.
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: ns
    // Exclusive y no OnDemand, incluso en paneles sin buscador: a una capa
    // OnDemand Hyprland solo le da el teclado si se hace clic en ella, y entonces
    // ESC no llegaría nunca. El popout ya es modal de facto.
    WlrLayershell.keyboardFocus: (shown && showsHere) ? WlrKeyboardFocus.Exclusive
                                                      : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

    onShownChanged: {
        if (shown) {
            if (showsHere)
                openAnim.restart()
        } else {
            closeAnim.restart()   // no-op si nunca se abrió aquí (progress ya es 0)
        }
    }

    Component.onCompleted: {
        if (shown && showsHere)
            openAnim.restart()
    }

    NumberAnimation {
        id: openAnim
        target: win
        property: "openProgress"
        from: 0
        to: 1
        duration: win.openAnimDuration
        easing.type: Theme.popoutEnterEasing
    }

    NumberAnimation {
        id: closeAnim
        target: win
        property: "openProgress"
        to: 0
        duration: win.closeAnimDuration
        easing.type: Theme.popoutExitEasing
    }

    // Velo configurable: oscurece el escritorio mientras el panel está abierto,
    // acompasado a su apertura.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: Settings.panelBackdropDim * win.openProgress
        visible: opacity > 0.003
    }

    // Clic fuera cierra.
    MouseArea {
        anchors.fill: parent
        enabled: win.openProgress > 0.92
        onClicked: Globals.closeAll()
    }

    // Tarjeta flotante, anclada al borde donde vive la barra: el barrido de
    // apertura siempre se despliega desde ella.
    readonly property bool fromBottom: Settings.barPosition === "bottom"
    Rectangle {
        id: card
        width: win.effectiveCardWidth
        anchors.top: win.fromBottom ? undefined : parent.top
        anchors.bottom: win.fromBottom ? parent.bottom : undefined
        anchors.topMargin: Theme.barHeight + Theme.barMargin * 2
        anchors.bottomMargin: Theme.barHeight + Theme.barMargin * 2
        anchors.horizontalCenter: win.alignCenter ? parent.horizontalCenter : undefined
        anchors.left: (!win.alignCenter && win.alignLeft) ? parent.left : undefined
        anchors.right: (!win.alignCenter && !win.alignLeft) ? parent.right : undefined
        anchors.leftMargin: Theme.barMargin
        anchors.rightMargin: Theme.barMargin

        // Altura en reposo. La tarjeta se despliega hasta aquí desde el borde
        // anclado, y 'height' es el recorte del barrido.
        readonly property int fullHeight: Math.min(win.cardMaxHeight,
                                                   col.implicitHeight + Theme.space16 * 2)
        height: Math.round(fullHeight * win.openProgress)

        radius: Theme.barRadius + 2
        color: Theme.popupBg
        border.width: Theme.hairline
        border.color: Theme.panelBorder
        clip: true
        antialiasing: true
        // ESC cierra el panel. Va en la tarjeta y no en la ventana: Keys solo
        // funciona sobre Items, y colgado del PanelWindow nunca recibiría la
        // tecla. Si un hijo tiene el foco, el evento no consumido burbujea hasta
        // aquí.
        focus: true
        Keys.onEscapePressed: {
            if (win.escapeAction && win.escapeAction())
                return
            Globals.closeAll()
        }

        // Si no hay a dónde saltar, el evento se deja pasar en vez de tragárselo:
        // quien esté debajo puede querer la flecha.
        Keys.onLeftPressed: (event) => {
            event.accepted = win.switchWithArrows && Globals.switchPanel(-1)
        }
        Keys.onRightPressed: (event) => {
            event.accepted = win.switchWithArrows && Globals.switchPanel(1)
        }

        // Absorbe los clics para que no cierren.
        MouseArea {
            anchors.fill: parent
            enabled: win.openProgress > 0.92
        }

        // Contenido a altura completa y anclado arriba aunque la tarjeta aún no
        // se haya desplegado, así el recorte lo va descubriendo sin comprimirlo:
        // siguiendo la altura animada, el layout se recalcularía en cada fotograma
        // y el texto bailaría.
        Item {
            id: contentHost
            width: card.width
            height: card.fullHeight
            // Fijado al borde de revelado: con la tarjeta creciendo desde abajo,
            // el contenido se alinea al borde inferior para que el recorte lo
            // descubra sin arrastrarlo.
            y: win.fromBottom ? card.height - card.fullHeight : 0
            opacity: Theme.revealOpacity(win.openProgress)
            // Paralaje sutil: el contenido llega con un poco de retraso y se
            // asienta siguiendo el sentido del barrido. Es un transform y no 'y',
            // así que no dispara relayout.
            transform: Translate {
                y: (1 - Theme.revealOpacity(win.openProgress))
                   * (win.fromBottom ? 1 : -1) * Theme.dp(10)
            }

            // Contenedor desplazable: con 'scrollable' activo y contenido más
            // alto que la tarjeta, desplaza en vez de recortar. Sin él queda no
            // interactivo y el scroll propio del panel sigue funcionando.
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
