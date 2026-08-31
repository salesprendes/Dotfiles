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

    // Esconderse NO genera un 'salir' del ratón: el puntero no se mueve, se va el
    // dock. Es lo que pasa al pulsar un icono —la ventana se enfoca, tapa el dock
    // y este se retira— y sin esto el globo se queda flotando sobre el escritorio
    // señalando un icono que ya no está. Va aquí y no en el clic porque cubre
    // TODAS las formas de esconderse: pantalla completa, DND, el escritorio que
    // deja de estar vacío.
    onReveladoChanged: if (!win.revelado) globos.cerrarTodo()

    // Y esto cubre el agujero que dejaba lo de arriba, que no es teórico: con el
    // menú abierto, 'revelado' vale true POR el propio menú (ver 'abiertos' más
    // abajo), así que un atajo que abriera un panel ponía visible=false sin que
    // 'revelado' cambiara nunca — ningún cierre se ejecutaba y el menú volvía
    // luego con la ranura y la posición de antes.
    //
    // El contrato queda claro: si la superficie desaparece, todo el estado que
    // solo tenía sentido encima de ella desaparece con ella.
    onVisibleChanged: if (!win.visible) globos.cerrarTodo()

    // Una sola propiedad con las razones en orden. No hay condición de bloqueo de
    // sesión a propósito: ext-session-lock hace que el compositor esconda todas las
    // superficies normales, layer-shell incluida, así que añadirla no escondería
    // nada y a cambio destruiría y reconstruiría una ventana por monitor en cada
    // bloqueo.
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
        return !WindowManager.hayVentanasEn(win.nombre)
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
    //
    // El rectángulo del dock sale de 'dock.implicitHeight', que desde el arreglo
    // de la lupa incluye el aire por el que asoman los iconos ampliados. Antes no
    // lo incluía y el borde de arriba de la máscara caía EXACTAMENTE en el borde
    // de la pastilla, sin holgura: con la lupa por encima de 1,164 el trozo de
    // icono que sobresalía se veía pero el clic se iba a la ventana de detrás.
    mask: Region {
        item: zonaRaton
        radius: globos.menuAbierto ? 0 : Math.round(dock.radio)

        Region {
            item: globos.itemVista
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
        // Los botones de acción no tienen ranura, así que su clave se compone
        // con el nombre. Prefijada para que no pueda chocar con la de una app
        // que se llamara igual que el botón.
        onHoverAccion: (b, nombre, dentro) =>
            globos.hoverEtiqueta("accion:" + nombre, nombre, b, dentro)
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

    // Quién de los tres globos está abierto, por qué y dónde se pone: todo eso
    // vive en DockPopovers. Este archivo se queda con la única pregunta que le
    // toca —dónde está la superficie y cuándo existe—, que ya era bastante:
    // layer-shell, máscara de entrada, autoocultar, reserva de espacio y
    // animación de aparición.
    DockPopovers {
        id: globos
        anchors.fill: parent
        fila: dock
    }
}
