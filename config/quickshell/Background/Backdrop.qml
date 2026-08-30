import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

// Fondo de pantalla: una ventana por monitor en la capa Background, sincronizada
// con el servicio Wallpaper. Dos slots A/B que se alternan; el entrante recibe la
// imagen nueva y se anima de 0 a 1, el saliente queda debajo en reposo.
PanelWindow {
    id: win

    property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "qs-wallpaper"
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.bg   // respaldo mientras no hay imagen cargada

    // Igual que la barra: superficie de vida larga, se remapea si el monitor
    // se mueve en el layout. Ver Components/ScreenMoveRemap.qml.
    visible: !remapGuard.remapping
    ScreenMoveRemap { id: remapGuard; window: win }

    readonly property int    fadeMs:     Math.max(0, Math.round(Settings.wallpaperTransitionDuration * 1000))
    readonly property string transition: Settings.wallpaperTransition

    Item {
        id: stage
        anchors.fill: parent

        property string src: Wallpaper.current
        property bool   showB: false   // true → el slot entrante es B
        property real   t: 1           // progreso de la transición (0→1)

        // Píxeles físicos del monitor: screen.width/height son lógicos, y con
        // escala mayor que 1 la textura saldría pequeña y el fondo borroso.
        function texSize() {
            const dpr = (win.screen && win.screen.devicePixelRatio) ? win.screen.devicePixelRatio : 1
            return Qt.size(Math.round((win.screen ? win.screen.width : 1920) * dpr),
                           Math.round((win.screen ? win.screen.height : 1080) * dpr))
        }

        // Arranca la animación solo con la imagen entrante lista, para no
        // enseñar un fotograma a medio cargar.
        function kick(holder) {
            if (holder.incoming && holder.status === Image.Ready)
                anim.restart()
        }

        // Carga la copia al tamaño de pantalla en el slot entrante y arranca la
        // transición. El original queda guardado como respaldo por si la copia ya
        // no está en disco; ver Services/Wallpaper.full.
        onSrcChanged: {
            if (!src)
                return
            anim.stop()
            stage.t = 0                       // entrante oculto de salida
            stage.showB = !stage.showB        // alterna el slot entrante
            const inc = stage.showB ? holderB : holderA
            inc.original = src
            inc.usandoOriginal = false
            inc.source = Wallpaper.full(src)
            stage.kick(inc)                   // si ya está en caché, arranca ya
        }

        NumberAnimation {
            id: anim
            target: stage; property: "t"
            from: 0; to: 1
            duration: win.fadeMs
            easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel
            // Libera la imagen del slot saliente, que si no queda decodificada
            // bajo el entrante sin volver a usarse. Solo en el final natural:
            // stop() no emite finished, así que una transición interrumpida
            // nunca vacía el slot que está entrando.
            onFinished: {
                const out = stage.showB ? holderA : holderB
                out.source = ""
            }
        }

        // Aplica la transición elegida. El saliente queda en reposo, lleno y
        // opaco, salvo en 'push' donde sale desplazándose; el entrante se anima
        // según t. La imagen interior mantiene el tamaño del monitor, y en
        // 'wipe' es el Holder quien recorta y la va revelando.
        component Holder: Item {
            id: holder
            property bool incoming: false
            property alias source: img.source
            property alias status: img.status

            // Ruta del fondo original, como respaldo; el flag evita reintentar
            // en bucle si el original tampoco carga.
            property string original: ""
            property bool   usandoOriginal: false

            clip: win.transition === "wipe"

            readonly property real fullW: stage.width
            readonly property real fullH: stage.height

            height: fullH
            width: (incoming && win.transition === "wipe") ? fullW * stage.t : fullW

            x: {
                if (incoming) {
                    if (win.transition === "slide" || win.transition === "push")
                        return fullW * (1 - stage.t)
                    return 0
                }
                return (win.transition === "push") ? -fullW * stage.t : 0
            }

            opacity: {
                if (!incoming)
                    return 1
                if (win.transition === "fade" || win.transition === "zoom")
                    return stage.t
                return 1
            }

            scale: (incoming && win.transition === "zoom") ? (1.08 - 0.08 * stage.t) : 1
            transformOrigin: Item.Center

            Image {
                id: img
                // Tamaño fijo del monitor (no se encoge con el Holder en 'wipe').
                width: stage.width
                height: stage.height
                // Encaje elegido en Ajustes. "fit" deja franjas del color de
                // fondo en vez de recortar, que es lo que hace falta con una
                // imagen cuya composición no sobrevive al recorte.
                fillMode: Settings.wallpaperFillMode === "fit" ? Image.PreserveAspectFit
                        : Settings.wallpaperFillMode === "stretch" ? Image.Stretch
                        : Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize: stage.texSize()

                // Si la copia en caché ya no está, vuelve al original en vez de
                // dejar el escritorio en el color de fondo.
                onStatusChanged: {
                    if (status === Image.Error && !holder.usandoOriginal && holder.original !== "") {
                        holder.usandoOriginal = true
                        img.source = holder.original
                    }
                }
            }
        }

        Holder {
            id: holderA
            incoming: !stage.showB
            z: incoming ? 1 : 0
            onStatusChanged: stage.kick(holderA)
        }

        Holder {
            id: holderB
            incoming: stage.showB
            z: incoming ? 1 : 0
            onStatusChanged: stage.kick(holderB)
        }
    }
}
