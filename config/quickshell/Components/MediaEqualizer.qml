import QtQuick
import qs.Config

// Ecualizador de cuatro barras: rebotan mientras suena algo y se aplanan al
// pausar. Vive aquí porque lo usan la píldora de la barra y la isla, y estaba
// copiado letra por letra en los dos — dos copias de una animación son dos
// animaciones que un día dejan de parecerse.
//
// A ~7 PASOS POR SEGUNDO CON UN TIMER, no a 60 fps con animaciones. Esto vive
// en pantalla toda la sesión: animar de verdad significaría tener la escena
// repintando sin parar por un adorno. A siete pasos se lee igual de vivo y el
// resto del tiempo la GPU no hace nada.
Item {
    id: root

    property bool playing: false
    property color activeColor: Theme.accent
    property color idleColor: Theme.fgMuted
    // Cuántas barras. Cuatro es lo que cabe en una píldora de barra sin que
    // parezca un espectro de audio.
    property int bars: 4

    implicitWidth: Theme.dp(16)
    implicitHeight: Theme.barIconSize

    property int tick: 0
    Timer {
        interval: 140
        // 'visible' además de 'playing': la píldora puede estar escondida con
        // algo sonando —la isla apagada, el widget fuera de la barra— y sin
        // este guardia el tick seguiría reevaluando barras que nadie ve.
        running: root.playing && root.visible
        repeat: true
        onTriggered: root.tick++
    }

    Row {
        anchors.centerIn: parent
        spacing: Theme.dp(2)

        Repeater {
            model: root.bars

            Rectangle {
                id: bar
                required property int index

                width: Theme.dp(2.5)
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.playing ? root.activeColor : root.idleColor

                readonly property real maxH: root.height
                readonly property real minH: Theme.dp(3)
                // Dos senos desfasados por barra: da un movimiento que no se ve
                // periódico sin gastar un Math.random en cada paso (que además
                // haría saltar las barras en vez de ondular).
                readonly property real level: 0.5
                    + 0.3 * Math.sin((root.tick + bar.index * 1.7) * 0.9)
                    + 0.2 * Math.sin((root.tick * 1.31 + bar.index * 2.3))

                height: root.playing
                        ? bar.minH + (bar.maxH - bar.minH) * Math.max(0, Math.min(1, bar.level))
                        : bar.minH

                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                // Solo al PARAR: mientras suena, el tick ya da el movimiento y
                // una transición encima lo emborronaría.
                Behavior on height {
                    enabled: !root.playing
                    NumberAnimation { duration: Theme.animFast }
                }
            }
        }
    }
}
