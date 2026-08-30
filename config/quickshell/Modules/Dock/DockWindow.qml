import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

// La superficie del dock. Una por monitor.
//
// ── POR QUÉ ES MUCHO MÁS ALTA QUE EL DOCK ───────────────────────────────────
// La vista previa y el menú contextual salen HACIA ARRIBA desde el icono. Con
// una ventana de la altura del dock harían falta dos superficies de layer-shell
// más por monitor, cada una con su agarre de foco, su colocación contra los
// bordes de la pantalla y su coordinación de cierre con las otras dos.
//
// Alta y enmascarada, viven dentro y no hay nada que coordinar. El precio es un
// lienzo transparente grande, y ese precio lo paga 'mask': sin ella, todo ese
// vacío se comería los clics al escritorio.
//
// ── POR QUÉ CAPA Top Y NO Overlay ───────────────────────────────────────────
// Los paneles del shell (y la isla) viven en Overlay y tienen que quedar
// DELANTE del dock, no detrás. Un dock en Overlay taparía la esquina inferior
// de cualquier panel abierto.
PanelWindow {
    id: win

    property var modelData
    screen: modelData

    readonly property string nombre: win.screen ? win.screen.name : ""
    readonly property bool barraAbajo: Settings.barPosition === "bottom"

    anchors { bottom: true; left: true; right: true }
    implicitHeight: Theme.dp(420)
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qs-dock"
    // Sin teclado: el dock se maneja con el ratón. Pedir foco exclusivo se lo
    // quitaría a la ventana en la que estás escribiendo, y esto vive en
    // pantalla toda la sesión.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Se esconde entero con un panel abierto, por la misma razón que la isla:
    // los popouts cubren la pantalla con su propio captador de clics y pelearse
    // por el ratón con ellos no lleva a nada bueno.
    visible: Globals.openPanel === "" && !remapGuard.remapping

    ScreenMoveRemap { id: remapGuard; window: win }

    // ── Reserva de espacio ───────────────────────────────────────────────────
    // Solo con "never". Reservar un hueco para algo que está escondido dejaría
    // una franja vacía permanente en el borde de la pantalla, que es justo lo
    // contrario de lo que se pide al activar el autoocultar.
    readonly property bool reserva: Settings.dockAutoHide === "never"
                                    && Settings.dockReserveSpace
    exclusionMode: win.reserva ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: win.reserva ? (dock.altoDock + win.margenBorde) : 0

    // ── Dónde se apoya ───────────────────────────────────────────────────────
    // Con la barra abajo, el dock se pone JUSTO ENCIMA de ella. La barra ya
    // reserva su zona exclusiva, así que basta con sumar su alto: no hay nada
    // que negociar con el compositor.
    readonly property int margenBarra: win.barraAbajo
        ? (Theme.barHeight + Theme.barTopMargin) : 0
    readonly property int margenBorde: (dock.esHotseat ? 0 : Theme.dp(10))
                                       + win.margenBarra

    // ── Cuándo se ve ─────────────────────────────────────────────────────────
    // Una sola propiedad con las razones en orden. No hay condición de bloqueo
    // de sesión a propósito: este shell bloquea con WlSessionLock
    // (ext-session-lock), y ese protocolo hace que el compositor esconda TODAS
    // las superficies normales, layer-shell incluida. Añadirla no escondería
    // nada que no esté ya escondido, y a cambio destruiría y reconstruiría una
    // ventana por monitor en cada bloqueo.
    readonly property bool revelado: {
        if (globos.abiertos)
            return true
        if (zonaRaton.containsMouse)
            return true
        if (Settings.dockAutoHide === "never")
            return true
        if (Settings.dockAutoHide === "always")
            return false
        // "smart": visible mientras el escritorio de ESTE monitor esté vacío.
        // Que sea de este monitor importa — con dos pantallas, un navegador a
        // pantalla completa en la principal no debe esconder el dock de la
        // secundaria, que no tiene nada.
        return !Dock.hayVentanasEn(win.nombre)
    }

    // ── La máscara ───────────────────────────────────────────────────────────
    // Lo más delicado de este archivo: mal calculada, deja una franja del ancho
    // de la pantalla donde el clic no llega al escritorio y no hay nada visible
    // que explique por qué.
    //
    // Tres estados, y solo tres:
    //   · menú abierto → la ventana entera, para poder cerrarlo pulsando fuera
    //   · revelado     → el rectángulo del dock, MÁS el de la vista previa
    //   · escondido    → una tira fina en el borde, del ancho del dock
    //
    // La tira NO ocupa todo el ancho ni en pastilla ni en hotseat: es del ancho
    // que tendría el dock, para no quedarse con los clics del borde inferior
    // allí donde el dock ni siquiera aparecería.
    //
    // ── Y POR QUÉ LA VISTA PREVIA NO AGRANDA LA MÁSCARA A TODA LA VENTANA ────
    // Porque entonces posar el ratón en un icono dejaría 2560×420 dp del tercio
    // inferior de la pantalla sin recibir clics: te acercas al dock, subes el
    // ratón, pulsas en tu editor y no pasa nada. Un menú sí se lleva la ventana
    // entera —lo has abierto tú y pulsar fuera es como se cierra—, pero un
    // globo que sale solo al pasar por encima no puede cobrarse eso.
    //
    // Las dos zonas se suman con una Region hija: es exactamente para lo que
    // están, y evita tener que calcular a mano un rectángulo que las cubra a
    // las dos (que además taparía todo el hueco vacío entre ellas).
    mask: Region {
        item: zonaRaton
        radius: globos.menuAbierto ? 0 : Math.round(dock.radio)

        Region {
            item: cargaVista
            radius: Theme.shapeLg
            // Sin la vista previa abierta, el Loader mide 0×0 y la región
            // simplemente no aporta nada.
        }
    }

    // El item que define la máscara Y detecta el ratón. Es el mismo objeto a
    // propósito: si la zona sensible y la zona enmascarada pudieran diferir,
    // habría posiciones donde el dock se revela y no se puede pulsar.
    MouseArea {
        id: zonaRaton
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        readonly property int alturaTira: Theme.dp(6)

        width: globos.menuAbierto ? parent.width : dock.implicitWidth
        height: globos.menuAbierto ? parent.height
              : (win.revelado ? dock.implicitHeight + win.margenBorde
                              : alturaTira + win.margenBarra)
        x: globos.menuAbierto ? 0 : Math.round((parent.width - width) / 2)
        y: parent.height - height
    }

    DockRow {
        id: dock
        onPideMenu: (r, x, y) => globos.abrirMenu(r, x)
        onHoverCambia: (r, b, dentro) => globos.hover(r, b, dentro)
        anchoPantalla: win.screen ? win.screen.width : 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.revelado
           ? (parent.height - height - win.margenBorde)
           // Escondido se va POR DEBAJO del borde de la pantalla, no solo se
           // hace transparente: transparente seguiría pintándose cada cuadro.
           : parent.height

        opacity: win.revelado ? 1 : 0

        Behavior on y {
            enabled: Theme.animNormal > 0
            NumberAnimation {
                duration: Theme.animNormal
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            enabled: Theme.animNormal > 0
            NumberAnimation { duration: Theme.animFast }
        }
    }

    // ── Los globos: vista previa y menú ──────────────────────────────────────
    // La coordinación vive AQUÍ y no en cada botón porque las dos reglas que
    // hacen usable la vista previa necesitan ver los dos botones a la vez:
    //
    //   · Al pasar del icono al globo, el globo NO debe cerrarse. De ahí el
    //     retardo de salida: sin él, el hueco entre el icono y el globo lo mata
    //     en el camino y la función es inservible.
    //   · Al pasar de un icono al vecino, el globo debe RECOLOCARSE, no
    //     cerrarse y volver a abrirse con su medio segundo de espera.
    Item {
        id: globos
        anchors.fill: parent

        property var ranuraVista: null
        property var ranuraPendiente: null
        property var botonVista: null
        property real centroVista: 0
        property var ranuraMenu: null
        property real centroMenu: 0
        property bool ratonEnGlobo: false

        readonly property bool vistaAbierta: globos.ranuraVista !== null
                                             && Settings.dockPreviews
        readonly property bool menuAbierto: globos.ranuraMenu !== null
        readonly property bool abiertos: globos.vistaAbierta || globos.menuAbierto

        function hover(ranura, boton, dentro) {
            if (!Settings.dockPreviews)
                return
            if (dentro) {
                globos.botonVista = boton
                globos.ranuraPendiente = ranura
                salir.stop()
                // Con un globo ya abierto se salta la espera de entrada: ya
                // estás mirando globos, hacerte esperar medio segundo por cada
                // icono del dock sería absurdo.
                if (globos.vistaAbierta)
                    globos.mostrar(ranura, boton)
                else
                    entrar.restart()
                return
            }
            entrar.stop()
            if (globos.botonVista === boton)
                salir.restart()
        }

        function mostrar(ranura, boton) {
            if (!boton)
                return
            const p = boton.mapToItem(globos, boton.width / 2, 0)
            globos.centroVista = p.x
            globos.ranuraVista = ranura
        }

        function cerrarVista() {
            entrar.stop()
            salir.stop()
            globos.ranuraVista = null
            globos.botonVista = null
        }

        function abrirMenu(ranura, xVentana) {
            globos.cerrarVista()
            globos.centroMenu = xVentana
            globos.ranuraMenu = ranura
        }

        function cerrarMenu() { globos.ranuraMenu = null }

        Timer {
            id: entrar
            interval: 500
            onTriggered: globos.mostrar(globos.ranuraPendiente, globos.botonVista)
        }
        Timer {
            id: salir
            interval: 250
            onTriggered: if (!globos.ratonEnGlobo) globos.cerrarVista()
        }

        // Captador de clics de fondo: solo existe con el menú abierto, y solo
        // entonces la máscara cubre la ventana entera. Con la vista previa NO
        // se pone: la vista previa se cierra sola al retirar el ratón, y un
        // captador a pantalla completa por pasar el ratón por encima de un
        // icono se comería el primer clic de cualquier cosa que hicieras.
        MouseArea {
            anchors.fill: parent
            visible: globos.menuAbierto
            enabled: globos.menuAbierto
            onClicked: globos.cerrarMenu()
        }

        Loader {
            id: cargaVista
            active: globos.vistaAbierta
            visible: active
            sourceComponent: DockPreview {
                ranura: globos.ranuraVista
                onPideCerrar: globos.cerrarVista()
            }
            // Centrado sobre el icono y acotado a la pantalla: un globo de la
            // app más a la derecha se saldría por el borde y quedaría cortado.
            x: Math.max(Theme.space8,
                        Math.min(globos.width - width - Theme.space8,
                                 globos.centroVista - width / 2))
            y: dock.y - height - Theme.space8

            // Con el ratón DENTRO del globo, el temporizador de salida no debe
            // cerrarlo: es la otra mitad de la histéresis. HoverHandler y no un
            // MouseArea porque un captador encima se comería los clics de las
            // filas, que son justo para lo que está el globo.
            HoverHandler {
                onHoveredChanged: {
                    globos.ratonEnGlobo = hovered
                    if (hovered) salir.stop()
                    else salir.restart()
                }
            }
        }

        Loader {
            active: globos.menuAbierto
            visible: active
            sourceComponent: DockMenu {
                ranura: globos.ranuraMenu
                onPideCerrar: globos.cerrarMenu()
            }
            x: Math.max(Theme.space8,
                        Math.min(globos.width - width - Theme.space8,
                                 globos.centroMenu - width / 2))
            y: dock.y - height - Theme.space8
        }
    }
}
