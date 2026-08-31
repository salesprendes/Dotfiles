import QtQuick
import qs.Components
import qs.Config

// Los botones del final del dock: lanzador y Spotlight.
//
// Van con el MISMO círculo y la misma caja que un icono de app, y eso no es
// pereza: si midieran distinto, la fila dejaría de leerse como una fila y
// pasaría a ser dos grupos con un salto en medio. Lo que los separa es el
// filete de DockSeparator, que es suficiente.
//
// Comparten con DockButton la base DockMagnifiable: la ola, la zona sensible y
// la onda. Antes eran dos copias idénticas de lo mismo, y la ola es una sola
// curva repartida por toda la fila — el peor sitio para tener dos copias.
//
// Aquí el glifo se dibuja siempre en color de acento, así que no hace falta el
// MultiEffect de DockButton: un glifo de Nerd Font es texto, y el texto ya se
// pinta del color que le digas.
DockMagnifiable {
    id: root

    property string glifo: ""

    readonly property bool mono: Settings.dockIconStyle === "mono"
    readonly property int iconSize: Theme.dp(Settings.dockIconSize)
    readonly property int caja: root.iconSize + Theme.dp(16)

    implicitWidth: root.caja
    implicitHeight: root.caja

    signal activada()

    // Estos dos botones también dicen cómo se llaman: media fila de iconos muda
    // frente a la otra media que se presenta sería peor que ninguna.
    property string nombre: ""
    signal hoverCambia(var boton, bool dentro)

    onPulsada: {
        root.hoverCambia(root, false)
        root.activada()
    }
    onEntrada: root.hoverCambia(root, true)
    onSalida: root.hoverCambia(root, false)

    Rectangle {
        anchors.centerIn: texto
        width: root.caja - Theme.dp(6)
        height: width
        radius: width / 2
        // En modo COLOR no hay disco de fondo... salvo al señalar o pulsar.
        // Sin esto, en color estos dos botones solo respondían con la
        // escala, que es casi nada: eran los que peor acusaban el clic de
        // todo el dock.
        visible: root.mono || root.senalado || root.pulsando
        antialiasing: true
        color: root.pulsando ? Theme.withAlpha(Theme.accent, 0.52)
             : root.senalado ? Theme.withAlpha(Theme.accent, 0.26)
                             : Theme.withAlpha(Theme.accent, 0.14)
        Behavior on color {
            enabled: Theme.animNormal > 0
            ColorAnimation { duration: root.pulsando ? 0 : Theme.animFast }
        }
    }

    ThemedText {
        id: texto
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -Math.round(Theme.dp(3))
        text: root.glifo
        color: root.senalado ? Theme.accent : Theme.withAlpha(Theme.accent, 0.78)
        font.family: Theme.fontFamily
        font.pixelSize: Math.round(root.iconSize * 0.72)
    }
}
