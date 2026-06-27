import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config
import qs.Services

// ─────────────────────────────────────────────────────────────
//  Fondo de pantalla renderizado por Quickshell (sin daemon externo
//  tipo swww/hyprpaper). Una ventana por monitor en la capa Background.
//
//  Transiciones en QML puro, seleccionables (Settings.wallpaperTransition):
//    fade   · fundido cruzado de opacidad
//    zoom   · la nueva entra escalando desde 1.08→1 + fundido
//    slide  · la nueva entra deslizando desde la derecha
//    push   · la nueva empuja a la vieja (ambas se mueven)
//    wipe   · la nueva se revela con un barrido de izquierda a derecha
//
//  Dos "slots" (A y B) que se alternan: el slot ENTRANTE recibe la nueva
//  imagen y se anima de 0→1; el SALIENTE queda en reposo debajo.
// ─────────────────────────────────────────────────────────────
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
            return Qt.size(win.screen ? win.screen.width : 1920,
                           win.screen ? win.screen.height : 1080)
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
        }

        // ── Componente "Holder": aplica la transición elegida ─
        //  El SALIENTE (incoming=false) queda en reposo (lleno, opaco), salvo
        //  en 'push' donde sale desplazándose. El ENTRANTE se anima según t.
        //  La imagen interior mantiene SIEMPRE el tamaño del monitor (no se
        //  deforma); en 'wipe' es el Holder quien recorta y la va revelando.
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
