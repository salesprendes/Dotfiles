import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config
import qs.Services

// Fondo de pantalla en QML: una ventana por monitor en la capa Background,
// sincronizada con el servicio Wallpaper. Dos slots (A/B) que se alternan: el
// entrante recibe la imagen nueva y se anima de 0→1, el saliente queda debajo
// en reposo. Transiciones (Settings.wallpaperTransition): fade, zoom, slide,
// push, wipe.
PanelWindow {
    id: win

    property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "qs-wallpaper"
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.bg   // respaldo mientras no hay imagen cargada

    readonly property int    fadeMs:     Math.max(0, Math.round(Settings.wallpaperTransitionDuration * 1000))
    readonly property string transition: Settings.wallpaperTransition

    Item {
        id: stage
        anchors.fill: parent

        property string src: Wallpaper.current
        property bool   showB: false   // true → el slot entrante es B
        property real   t: 1           // progreso de la transición (0→1)

        function texSize() {
            // Píxeles FÍSICOS del monitor: screen.width/height son lógicos y
            // en escalas >1 la textura quedaba pequeña (fondo borroso).
            const dpr = (win.screen && win.screen.devicePixelRatio) ? win.screen.devicePixelRatio : 1
            return Qt.size(Math.round((win.screen ? win.screen.width : 1920) * dpr),
                           Math.round((win.screen ? win.screen.height : 1080) * dpr))
        }

        // Arranca la animación solo cuando la imagen entrante está lista,
        // para no mostrar un fotograma en negro a medio cargar.
        function kick(holder) {
            if (holder.incoming && holder.status === Image.Ready)
                anim.restart()
        }

        onSrcChanged: {
            if (!src)
                return
            anim.stop()
            stage.t = 0                       // entrante oculto de salida
            stage.showB = !stage.showB        // alterna el slot entrante
            const inc = stage.showB ? holderB : holderA
            inc.source = src
            stage.kick(inc)                   // si ya está en caché, arranca ya
        }

        NumberAnimation {
            id: anim
            target: stage; property: "t"
            from: 0; to: 1
            duration: win.fadeMs
            easing.type: Easing.OutCubic
            // Al terminar, libera la imagen del slot saliente: quedaba
            // decodificada bajo el entrante (~8 MB por monitor) sin volver
            // a usarse. Solo en el final natural (stop() no emite finished),
            // así una transición interrumpida nunca vacía el slot que entra.
            onFinished: {
                const out = stage.showB ? holderA : holderB
                out.source = ""
            }
        }

        // Holder: aplica la transición elegida. El saliente (incoming=false)
        // queda en reposo, lleno y opaco, salvo en 'push' donde sale
        // desplazándose. El entrante se anima según t. La imagen interior
        // mantiene siempre el tamaño del monitor; en 'wipe' el Holder recorta y
        // la va revelando.
        component Holder: Item {
            id: holder
            property bool incoming: false
            property alias source: img.source
            property alias status: img.status

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
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize: stage.texSize()
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
