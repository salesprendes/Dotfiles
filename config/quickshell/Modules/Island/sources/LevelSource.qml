import QtQuick
import Quickshell.Services.Pipewire
import qs.Config
import qs.Services

// Vigila volumen, micrófono y brillo, y se lo cuenta a la isla.
//
// Sustituye a Panels/VolumeOSD.qml: en vez de una ventana propia que aparece en
// una esquina, el nivel es una ACTIVIDAD más de la isla. Se gana coherencia (un
// solo sitio donde mira el ojo) y se pierde una superficie por monitor.
//
// EL ARMADO no es un detalle menor y viene de aquel archivo: al arrancar el
// shell, Pipewire publica el volumen actual y eso dispara onVolumeChanged. Sin
// esperar, cada inicio de sesión te enseñaría el OSD de volumen sin que nadie
// haya tocado nada. Se ignora el primer segundo largo.
QtObject {
    id: root

    property bool armed: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinkAudio: root.sink?.audio ?? null
    readonly property var sourceAudio: root.source?.audio ?? null

    // La isla apagada devuelve el trabajo a Panels/VolumeOSD.qml, que escucha
    // a Pipewire por su cuenta. Aquí solo hay que callarse.
    readonly property bool enabled: Settings.islandEnabled

    function show(kind, value, muted) {
        if (!root.enabled || !root.armed || !Settings.osdEnabled)
            return
        // Con un panel abierto no se interrumpe: ya estás mirando otra cosa, y
        // el cambio de volumen lo ves en el propio panel.
        if (Globals.openPanel !== "")
            return
        IslandState.showLevel(kind, value, muted)
    }

    // Mantiene vivos los nodos de Pipewire aunque no haya paneles abiertos: sin
    // esto sus propiedades no se actualizan y no llegaría ningún cambio.
    // Con la isla apagada no se retiene ningún nodo: quien los necesita
    // entonces es el OSD clásico, que trae el suyo.
    readonly property PwObjectTracker _tracker: PwObjectTracker {
        objects: root.enabled ? [root.sink, root.source].filter(n => n !== null) : []
    }

    readonly property Timer _armTimer: Timer {
        interval: 1200
        running: true
        onTriggered: root.armed = true
    }

    readonly property Connections _sinkWatch: Connections {
        target: root.sinkAudio
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            root.show("volume", root.sinkAudio?.volume ?? 0, root.sinkAudio?.muted ?? false)
        }
        function onMutedChanged() {
            root.show("volume", root.sinkAudio?.volume ?? 0, root.sinkAudio?.muted ?? false)
        }
    }

    readonly property Connections _sourceWatch: Connections {
        target: root.sourceAudio
        ignoreUnknownSignals: true
        // Solo el silencio del micro, no su volumen: el volumen de entrada casi
        // nadie lo toca en caliente, y el mute sí es un gesto de todos los días
        // en una llamada.
        function onMutedChanged() {
            root.show("mic", root.sourceAudio?.volume ?? 0, root.sourceAudio?.muted ?? false)
        }
    }

    readonly property Connections _brightnessWatch: Connections {
        target: Brightness
        ignoreUnknownSignals: true
        function onPercentChanged() {
            if (Brightness.available)
                root.show("brightness", Brightness.percent / 100, false)
        }
    }
}
