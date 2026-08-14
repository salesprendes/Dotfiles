import QtQuick
import QtQuick.Layouts
import qs.Config

// Estado vacío de una lista ("No hay redes guardadas", "No hay pantallas…").
// Centrado y apagado; el texto lo pone cada sitio. Estaba copiado en tres
// páginas con tres tamaños de letra distintos.
Text {
    Layout.fillWidth: true
    color: Theme.fgMuted
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    font.family: Theme.fontFamily
    font.pixelSize: Theme.typeBodyMedium
}
