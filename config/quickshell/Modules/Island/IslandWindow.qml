import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Modules.Island.activities
import qs.Services

// La ventana que hospeda la isla. Una por monitor.
//
// Es un lienzo fijo del tamaño de la hoja más grande, y lo que se anima es un
// rectángulo dentro: redimensionar una superficie de layer-shell es una
// negociación con el compositor en cada fotograma, y animar eso da tirones.
//
// El precio es una superficie grande y transparente por monitor, y se paga con
// 'mask': sin ella todo ese vacío se comería los clics al escritorio.
PanelWindow {
    id: win

    property var modelData
    screen: modelData

    readonly property bool atBottom: Settings.barPosition === "bottom"

    // ¿Está esta ventana haciendo de panel modal? Lo decide la isla que
    // hospeda; aquí solo se usa para dos cosas físicas que la isla no puede
    // tocar: cuánto ocupa la ventana y por dónde deja entrar el ratón.
    readonly property bool modal: island.modal

    // Se cuelga del mismo borde que la barra y ocupa todo el ancho: centrar la
    // isla es entonces aritmética, no anclajes.
    anchors {
        top: !win.atBottom
        bottom: win.atBottom
        left: true
        right: true
    }

    // Alto del lienzo: la hoja más grande más el margen del borde. No reserva
    // espacio (exclusionMode Ignore), así que pasarse solo cuesta superficie.
    readonly property int alturaLienzo: Theme.barTopMargin + Theme.dp(560)

    // Con una hoja modal abierta el lienzo pasa a ser la pantalla entera: un
    // clic fuera solo puede cerrarla si cae dentro de esta ventana, y la franja
    // de reposo no cubre el resto del escritorio.
    //
    // No contradice lo de arriba: son dos cambios de tamaño, al abrir y al
    // cerrar, no uno por fotograma, y como la forma sigue anclada a su borde el
    // crecimiento ocurre por el lado contrario y no se ve.
    implicitHeight: (win.modal && win.screen)
                    ? Math.max(win.alturaLienzo, win.screen.height)
                    : win.alturaLienzo
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-island"
    // Teclado solo con una hoja modal delante: pedirlo en reposo se lo quitaría
    // a la ventana en la que se está escribiendo. Con la hoja puesta la isla es
    // un panel más y ESC debe cerrarla.
    //
    // Exclusive y no OnDemand porque a una capa OnDemand Hyprland solo le cede
    // el teclado tras un clic, y entonces ESC no llegaría nunca.
    //
    // Atado también a 'visible': con un panel abierto la isla se esconde con su
    // hoja puesta, y sin esa condición una ventana invisible le disputaría el
    // teclado al panel que sí se ve.
    WlrLayershell.keyboardFocus: (win.modal && win.visible)
                                 ? WlrKeyboardFocus.Exclusive
                                 : WlrKeyboardFocus.None

    // La isla existe en todas las pantallas; lo que no se reparte es la hoja
    // expandida (ver IslandState.sheetBelongsTo).
    //
    // Se esconde entera con cualquier panel abierto: los popouts viven en esta
    // misma capa y cubren la pantalla con su captador de clics, así que las dos
    // cosas a la vez se disputarían el ratón. Y se aparta con una ventana a
    // pantalla completa en esta pantalla (ver Globals.hiddenByFullscreen).
    //
    // Se consulta con 'modelData' y no con 'screen' para evitar un bucle de
    // binding: el 'screen' de una superficie de layer-shell se resuelve al
    // mapearla, o sea que depende de 'visible', que es justo lo que se está
    // calculando aquí. 'modelData' lo inyecta shell.qml desde fuera.
    visible: Settings.islandEnabled && Globals.openPanel === "" && !remapGuard.remapping
             && !Globals.hiddenByFullscreen(win.modelData)

    // Superficie de vida larga: se remapea si el monitor cambia de sitio en el
    // layout. Ver Components/ScreenMoveRemap.qml.
    ScreenMoveRemap { id: remapGuard; window: win }

    // Solo la forma recibe ratón; el resto del lienzo es aire.
    //
    // Con radio por esquina y no una 'radius' única: una Region con 'item'
    // recorta al rectángulo del item, así que las cuatro puntas de fuera de las
    // curvas capturarían clics sobre el escritorio, y además la isla dibuja
    // cada esquina con un radio distinto según el borde al que se pega.
    mask: Region {
        item: island.shapeItem
        topLeftRadius: Math.round(island.shapeItem.topLeftRadius)
        topRightRadius: Math.round(island.shapeItem.topRightRadius)
        bottomLeftRadius: Math.round(island.shapeItem.bottomLeftRadius)
        bottomRightRadius: Math.round(island.shapeItem.bottomRightRadius)

        // Con una hoja modal la ventana entera recibe ratón: es la otra mitad
        // del clic de fuera, que si no se lo queda la aplicación de debajo.
        // Ancho y alto a cero en vez de quitar la región, porque una región
        // vacía no une nada y el caso normal sigue siendo exactamente la forma.
        Region {
            width: win.modal ? win.width : 0
            height: win.modal ? win.height : 0
        }
    }

    Island {
        id: island
        anchors.fill: parent
        atBottom: win.atBottom
        // El lienzo en REPOSO, no el de ahora: ver Island.maxSheetHeight.
        maxSheetHeight: win.alturaLienzo
        screenName: win.screen ? win.screen.name : ""
        canExpand: IslandState.sheetBelongsTo(island.screenName)

        // El catálogo se inyecta desde aquí para que Island.qml no conozca
        // ninguna actividad: añadir una es tocar solo estos dos mapas.
        compactContent: ({
            "home": cHome,
            "level": cLevel,
            "notification": cNotif,
            "media": cMedia,
            "recording": cRec
        })
        expandedContent: ({
            "calendar": cCalendar,
            "notifs": cNotifs,
            "media": cMediaX,
            "recording": cRecX
        })
    }

    Component { id: cHome;     HomeCompact {} }
    Component { id: cLevel;    LevelCompact {} }
    Component { id: cNotif;    NotificationCompact {} }
    Component { id: cMedia;    MediaCompact {} }
    Component { id: cRec;      RecordingCompact {} }
    Component { id: cCalendar; CalendarExpanded {} }
    Component { id: cMediaX;   MediaExpanded {} }
    Component { id: cNotifs;   NotifsExpanded {} }
    Component { id: cRecX;     RecordingExpanded {} }
}
