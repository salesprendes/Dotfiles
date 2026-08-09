import QtQuick
import qs.Config

// Etiqueta de texto de la barra: fuente y tamaño unificados.
Text {
    property bool animateColor: false

    color: Theme.fg
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize

    Behavior on color {
        enabled: animateColor
        ColorAnimation { duration: Theme.animFast }
    }
}
