import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

// La superficie del dock. Una por monitor.
//
// La vista previa y el menú contextual salen hacia arriba desde el icono. Con una
// ventana de la altura del dock harían falta dos superficies de layer-shell más
// por monitor, cada una con su agarre de foco, su colocación contra los bordes y
// su coordinación de cierre con las otras dos. Alta y enmascarada, viven dentro y
// no hay nada que coordinar; el precio es un lienzo transparente grande, y lo paga
// 'mask': sin ella, todo ese vacío se comería los clics al escritorio.
//
// Los paneles del shell y la isla viven en Overlay y tienen que quedar delante del
// dock: uno en Overlay taparía la esquina inferior de cualquier panel abierto.
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
    // Sin teclado: el dock se maneja con el ratón, y pedir foco exclusivo se lo
    // quitaría a la ventana en la que se está escribiendo.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Se esconde entero con un panel abierto, por la misma razón que la isla: los
    // popouts cubren la pantalla con su propio captador de clics.
    visible: Globals.openPanel === "" && !remapGuard.remapping

    ScreenMoveRemap { id: remapGuard; window: win }

    // Solo con "never": reservar un hueco para algo escondido dejaría una franja
    // vacía permanente en el borde, que es lo contrario de lo que se pide al
    // activar el autoocultar.
    readonly property bool reserva: Settings.dockAutoHide === "never"
                                    && Settings.dockReserveSpace
    exclusionMode: win.reserva ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: win.reserva ? (dock.altoDock + win.margenBorde) : 0

    // Con la barra abajo, el dock se pone justo encima de ella. La barra ya reserva
    // su zona exclusiva, así que basta con sumar su alto.
    readonly property int margenBarra: win.barraAbajo
        ? (Theme.barHeight + Theme.barTopMargin) : 0
    readonly property int margenBorde: (dock.esHotseat ? 0 : Theme.dp(10))
                                       + win.margenBarra

    // Una sola propiedad con las razones en orden. No hay condición de bloqueo de
    // sesión a propósito: ext-session-lock hace que el compositor esconda todas las
    // superficies normales, layer-shell incluida, así que añadirla no escondería
    // nada y a cambio destruiría y reconstruiría una ventana por monitor en cada
    // bloqueo.
    // Esconderse NO genera un 'salir' del ratón: el puntero no se mueve, se va el
    // dock. Es lo que pasa al pulsar un icono —la ventana se enfoca, tapa el dock
    // y este se retira— y sin esto el globo se queda flotando sobre el escritorio
    // señalando un icono que ya no está. Va aquí y no en el clic porque cubre
    // TODAS las formas de esconderse: pantalla completa, abrir un panel, DND.
    onReveladoChanged: if (!win.revelado) {
        globos.cerrarEtiqueta()
        globos.cerrarVista()
    }

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

    // Lo más delicado de este archivo: mal calculada deja una franja del ancho de
    // la pantalla donde el clic no llega al escritorio, sin nada visible que lo
    // explique.
    //
    // Tres estados y solo tres:
    //   · menú abierto → la ventana entera, para poder cerrarlo pulsando fuera
    //   · revelado     → el rectángulo del dock, más el de la vista previa
    //   · escondido    → una tira fina en el borde, del ancho del dock
    //
    // La tira no ocupa todo el ancho ni en pastilla ni en hotseat: es del ancho que
    // tendría el dock, para no quedarse con los clics del borde allí donde el dock
    // ni siquiera aparecería. Un menú sí se lleva la ventana entera —lo ha abierto
    // el usuario y pulsar fuera es como se cierra—, pero un globo que sale solo al
    // pasar por encima no puede cobrarse eso.
    //
    // Las dos zonas se suman con una Region hija, que es para lo que están, y así
    // no hay que calcular a mano un rectángulo que las cubra —y que taparía el
    // hueco vacío entre ellas—.
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
        onHoverAccion: (b, nombre, dentro) => globos.hoverEtiqueta(b, nombre, b, dentro)
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

        // Estado de la etiqueta del nombre. Va aparte del de la vista previa a
        // propósito: son dos globos con dos tiempos y dos condiciones, y
        // mezclarlos obligaría a que uno heredase los frenos del otro.
        // La clave identifica QUÉ se está señalando —una ranura de app o un
        // botón de acción— y solo sirve para saber si el 'salir' que llega es
        // del mismo sitio. El texto va aparte porque no todo lo que lleva
        // etiqueta tiene una app detrás.
        property var claveEtiqueta: null
        property string textoEtiqueta: ""
        property var botonEtiqueta: null
        property real centroEtiqueta: 0
        property bool etiquetaLista: false

        readonly property bool vistaAbierta: globos.ranuraVista !== null
                                             && Settings.dockPreviews
        readonly property bool menuAbierto: globos.ranuraMenu !== null

        // Cede el sitio a los otros dos: la vista previa ya lleva el nombre en
        // su primera línea, y el menú tapa el icono del que hablaría.
        readonly property bool etiquetaAbierta: globos.etiquetaLista
                                                && globos.claveEtiqueta !== null
                                                && !globos.vistaAbierta
                                                && !globos.menuAbierto
        readonly property bool abiertos: globos.vistaAbierta || globos.menuAbierto

        function hover(ranura, boton, dentro) {
            globos.hoverEtiqueta(ranura, Dock.nombreDe(ranura ? ranura.id : ""),
                                 boton, dentro)
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

        // Espera corta y no medio segundo: saber cómo se llama un icono no
        // puede costar lo mismo que abrir un globo con miniaturas. Pero alguna
        // hay, o cruzar el dock de lado a lado encendería una etiqueta por
        // icono en el camino.
        function hoverEtiqueta(clave, texto, boton, dentro) {
            if (dentro) {
                globos.botonEtiqueta = boton
                globos.claveEtiqueta = clave
                globos.textoEtiqueta = texto
                // Con una etiqueta ya puesta, pasar al vecino es inmediato.
                if (globos.etiquetaLista)
                    globos.colocarEtiqueta()
                else
                    etiquetaEntra.restart()
                return
            }
            etiquetaEntra.stop()
            if (globos.claveEtiqueta === clave)
                globos.cerrarEtiqueta()
        }

        function cerrarEtiqueta() {
            etiquetaEntra.stop()
            globos.claveEtiqueta = null
            globos.etiquetaLista = false
        }

        function colocarEtiqueta() {
            if (!globos.botonEtiqueta)
                return
            const b = globos.botonEtiqueta
            globos.centroEtiqueta = b.mapToItem(globos, b.width / 2, 0).x
            globos.etiquetaLista = true
        }

        function cerrarVista() {
            entrar.stop()
            salir.stop()
            globos.ranuraVista = null
            globos.botonVista = null
        }

        function abrirMenu(ranura, xVentana) {
            globos.cerrarVista()
            globos.cerrarEtiqueta()
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
            id: etiquetaEntra
            interval: 150
            onTriggered: globos.colocarEtiqueta()
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
            active: globos.etiquetaAbierta
            visible: active
            sourceComponent: DockLabel { texto: globos.textoEtiqueta }
            // Mismo estante que la vista previa y misma sujeción a los bordes:
            // la etiqueta de la app más a la derecha se saldría de la pantalla.
            x: Math.max(Theme.space8,
                        Math.min(globos.width - width - Theme.space8,
                                 globos.centroEtiqueta - width / 2))
            y: dock.y - height - Theme.space8
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
