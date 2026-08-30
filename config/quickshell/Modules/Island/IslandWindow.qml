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
    implicitHeight: Theme.barTopMargin + Theme.dp(560)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-island"
    // Sin teclado: la isla se maneja con el ratón y por IPC. Pedir foco
    // exclusivo aquí se lo quitaría a la ventana en la que estás escribiendo,
    // que es exactamente lo que no debe hacer algo que vive siempre en pantalla.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // La isla está en TODAS las pantallas, como la barra: en reposo enseña la
    // hora y con una notificación la enseña mires donde mires. Lo que no se
    // reparte es la HOJA expandida — esa va solo donde la abriste (ver
    // IslandState.sheetBelongsTo).
    //
    // Se esconde entera mientras haya un panel abierto: los popouts son de esta
    // misma capa y cubren la pantalla con su propio captador de clics, así que
    // dejarla encima sería pelearse por el ratón. Misma regla que ya seguían
    // los popups de notificación.
    visible: Settings.islandEnabled && Globals.openPanel === "" && !remapGuard.remapping

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
    }

    Island {
        id: island
        anchors.fill: parent
        atBottom: win.atBottom
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
