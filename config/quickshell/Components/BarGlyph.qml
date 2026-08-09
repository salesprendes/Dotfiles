import QtQuick
import qs.Config

// Glifo de icono de la barra: fuente y tamaño unificados para todos los
// widgets. 'sizeDelta' permite ajustes puntuales (p. ej. el lanzador).
Text {
    property int sizeDelta: 0
    property bool animateColor: false

    color: Theme.fgDim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.barIconSize + sizeDelta

    Behavior on color {
        enabled: animateColor
        ColorAnimation { duration: Theme.animFast }
    }
}
