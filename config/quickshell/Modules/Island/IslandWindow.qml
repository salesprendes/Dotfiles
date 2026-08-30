import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Modules.Island.activities
import qs.Services

// La ventana que hospeda la isla. Una por monitor.
//
// ── POR QUÉ UNA VENTANA GRANDE Y CASI VACÍA ─────────────────────────────────
// Una superficie de layer-shell no puede cambiar de tamaño con suavidad: cada
// redimensionado es una negociación con el compositor, y animar eso da tirones
// y parpadeos. Así que la ventana es un LIENZO fijo, del tamaño de la hoja más
// grande que la isla pueda llegar a ser, y lo que se anima es un rectángulo
// dentro. El compositor nunca ve la ventana cambiar.
//
// El precio es una superficie grande y transparente por monitor, y ese precio
// se paga con 'mask': sin ella, todo ese vacío se comería los clics al
// escritorio. Con ella, solo la forma de la isla recibe ratón.
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

    // Alto del lienzo: lo que ocupa la hoja más grande, más el margen del borde
    // y un respiro. No reserva espacio (exclusionMode Ignore), así que sobrarle
    // no cuesta nada más que memoria de superficie.
    readonly property int alturaLienzo: Theme.barTopMargin + Theme.dp(560)

    // ── Por qué el lienzo crece al abrir una hoja a mano ─────────────────────
    // Para que un clic FUERA de la isla la cierre, ese clic tiene que llegar a
    // esta ventana; y a una ventana solo le llega lo que cae dentro de ella. Con
    // el lienzo de siempre —una franja de 560 dp pegada a la barra— pulsar en la
    // mitad de abajo de la pantalla no cerraba nada, porque el clic ni siquiera
    // pasaba por aquí. Así que mientras hay hoja abierta, el lienzo es la
    // pantalla entera.
    //
    // Esto NO contradice lo de arriba. Lo que da tirones es redimensionar la
    // superficie EN CADA FOTOGRAMA de una animación; esto son dos cambios de
    // tamaño, uno al abrir y otro al cerrar, y ninguno de los dos mueve la isla
    // de sitio: la forma sigue anclada a su borde, así que el crecimiento pasa
    // entero por el lado contrario y no se ve.
    implicitHeight: (win.modal && win.screen)
                    ? Math.max(win.alturaLienzo, win.screen.height)
                    : win.alturaLienzo
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-island"
    // Teclado SOLO mientras hay una hoja abierta a mano, y por eso mismo:
    // pedirlo en reposo se lo quitaría a la ventana en la que estás escribiendo,
    // que es exactamente lo que no puede hacer algo que vive siempre en
    // pantalla. Con una hoja tuya delante ya no es "algo que vive ahí", es un
    // panel — y entonces ESC tiene que cerrarlo como cierra cualquier otro.
    //
    // Exclusive y no OnDemand por el mismo motivo que Components/Popout: a una
    // capa OnDemand Hyprland solo le da el teclado si haces CLIC en ella, así
    // que ESC no llegaría nunca sin haber pulsado antes.
    //
    // Y atado también a 'visible': con un panel abierto la isla se esconde pero
    // su hoja sigue puesta, así que sin esta condición una ventana invisible
    // estaría peleándole el teclado al panel que sí se ve.
    WlrLayershell.keyboardFocus: (win.modal && win.visible)
                                 ? WlrKeyboardFocus.Exclusive
                                 : WlrKeyboardFocus.None

    // La isla está en TODAS las pantallas, como la barra: en reposo enseña la
    // hora y con una notificación la enseña mires donde mires. Lo que no se
    // reparte es la HOJA expandida — esa va solo donde la abriste (ver
    // IslandState.sheetBelongsTo).
    //
    // Se esconde entera mientras haya un panel abierto: los popouts son de esta
    // misma capa y cubren la pantalla con su propio captador de clics, así que
    // dejarla encima sería pelearse por el ratón. Misma regla que ya seguían
    // los popups de notificación.
    //
    // Y se aparta con una ventana a pantalla completa EN ESTA pantalla. La
    // regla, con su porqué, está en Globals.hiddenByFullscreen.
    //
    // Se le pasa 'modelData' y NO 'screen', que es lo que parece natural y da
    // un bucle: 'screen' de una ventana de layer-shell se resuelve al MAPEARLA,
    // o sea que depende de 'visible' — y aquí estamos calculando 'visible'.
    // Medido: "Binding loop detected for property 'visible'" nada más arrancar.
    // 'modelData' es la pantalla que le pasa shell.qml desde fuera y no depende
    // de si la ventana está puesta o no.
    visible: Settings.islandEnabled && Globals.openPanel === "" && !remapGuard.remapping
             && !Globals.hiddenByFullscreen(win.modelData)

    // Superficie de vida larga: se remapea si el monitor cambia de sitio en el
    // layout. Ver Components/ScreenMoveRemap.qml.
    ScreenMoveRemap { id: remapGuard; window: win }

    // Solo la forma recibe ratón. El resto del lienzo es aire.
    //
    // Y con las ESQUINAS de verdad. Una Region con 'item' recorta al rectángulo
    // que ocupa ese item, así que hasta ahora los cuatro cuadraditos de fuera de
    // las curvas también capturaban el ratón: pinchabas al lado de la isla, en
    // un sitio donde se ve el escritorio, y el clic se lo quedaba ella. Con la
    // isla expandida —radio 20-28 dp— eso son cuatro zonas muertas de buen
    // tamaño sobre lo que estés usando.
    //
    // Quickshell 0.3 añadió radio POR ESQUINA a Region, que es justo lo que
    // hacía falta: la isla ya dibuja sus cuatro esquinas por separado (el lado
    // pegado al borde de pantalla lleva menos radio que el libre), así que una
    // sola 'radius' no habría bastado.
    mask: Region {
        item: island.shapeItem
        topLeftRadius: Math.round(island.shapeItem.topLeftRadius)
        topRightRadius: Math.round(island.shapeItem.topRightRadius)
        bottomLeftRadius: Math.round(island.shapeItem.bottomLeftRadius)
        bottomRightRadius: Math.round(island.shapeItem.bottomRightRadius)

        // …salvo con una hoja abierta a mano, que entonces la ventana entera
        // recibe ratón. Es la otra mitad del clic de fuera: sin abrir la
        // máscara, el clic se lo queda la aplicación de debajo y aquí no llega
        // nunca — y con ella abierta, el fondo de Island.qml lo recoge y cierra.
        //
        // Ancho y alto a cero en vez de quitar la región: una región vacía no
        // une nada, y así el caso normal sigue siendo exactamente la forma.
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

        // El catálogo de contenidos se inyecta desde aquí para que Island.qml
        // no tenga que importar ni conocer cada actividad: añadir una es tocar
        // este mapa y nada más.
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
