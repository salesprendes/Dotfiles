import QtQuick
import qs.Config

// Etiqueta de texto de la barra: fuente y tamaño unificados.
ThemedText {
    property bool animateColor: false

    color: Theme.fg

    Behavior on color {
        enabled: animateColor
        ColorAnimation { duration: Theme.animFast }
    }
}
