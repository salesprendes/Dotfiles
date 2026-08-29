import QtQuick

// Vigilante de reubicación de monitor para superficies de vida larga.
//
// EL PROBLEMA: Hyprland coloca una superficie layer-shell cuando la MAPEA y no
// vuelve a moverla. Si el monitor cambia de sitio en el layout —desconectar el
// portátil de la dock, apagar la pantalla interna, un `hyprctl keyword monitor`
// que reordene— la superficie sigue pintando en el offset global viejo. Las
// ventanas que se crean y destruyen (los popouts) no lo notan porque el
// siguiente mapeo ya usa la posición nueva; las que viven toda la sesión
// (barra, fondo, popups de notificación, OSD) se quedan descolocadas —o
// directamente fuera de pantalla— hasta reiniciar el shell.
//
// LA CURA: desmapear y volver a mapear. Poner 'visible' a false y a true hace
// exactamente eso, y al remapear el compositor recoloca la superficie en el
// origen actual del monitor.
//
// USO: se instancia dentro de la ventana y se dobla en su binding de visible:
//
//     PanelWindow {
//         id: win
//         visible: !remapGuard.remapping
//         ScreenMoveRemap { id: remapGuard; window: win }
//     }
//
// NO se escucha 'onXChanged'/'onYChanged': en Quickshell 0.3.1 las cuatro
// propiedades de geometría de ShellScreen (x, y, width, height) comparten un
// único notify —'geometryChanged'—, así que los manejadores por propiedad no
// existen como señal y un Connections a ellos no se engancharía nunca. Se
// escucha la señal real y se compara el origen a mano.
Item {
    id: root

    required property var window
    readonly property var screen: root.window ? root.window.screen : null

    // Pulso que el dueño dobla en su 'visible'.
    property bool remapping: false

    // Origen conocido del monitor. 'primed' distingue "aún no medido" de
    // "medido y está en 0,0" — sin él, el monitor principal (que suele estar
    // justo en 0,0) provocaría un remapeo espurio en el primer arranque.
    property int lastX: 0
    property int lastY: 0
    property bool primed: false

    visible: false

    function sample() {
        const s = root.screen
        if (!s) {
            root.primed = false
            return
        }
        const x = s.x
        const y = s.y
        if (!root.primed) {
            root.lastX = x
            root.lastY = y
            root.primed = true
            return
        }
        if (x === root.lastX && y === root.lastY)
            return
        root.lastX = x
        root.lastY = y
        settleTimer.restart()
    }

    // Cambiar de pantalla (o perderla) reinicia la medición: el origen de la
    // nueva no tiene nada que ver con el de la anterior y compararlos daría un
    // remapeo que no toca.
    onScreenChanged: {
        root.primed = false
        root.sample()
    }

    Component.onCompleted: root.sample()

    Connections {
        target: root.screen
        ignoreUnknownSignals: true
        function onGeometryChanged() { root.sample() }
    }

    // Una reorganización del layout puede mover el monitor varias veces antes
    // de asentarse (Hyprland recoloca monitor a monitor). Se espera a que pare
    // para hacer UN solo remapeo en vez de uno por paso intermedio.
    Timer {
        id: settleTimer
        interval: 200
        onTriggered: root.remapping = true
    }

    // Se mantiene desmapeada un instante: sin esta pausa el compositor puede
    // fundir el unmap y el remap en el mismo ciclo y quedarse en nada.
    Timer {
        interval: 50
        running: root.remapping
        onTriggered: root.remapping = false
    }
}
