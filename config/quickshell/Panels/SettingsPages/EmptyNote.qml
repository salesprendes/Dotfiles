import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Components

// Estado vacío de una lista ("No hay redes guardadas", "No hay pantallas…").
// Centrado y apagado; el texto lo pone cada sitio. Estaba copiado en tres
// páginas con tres tamaños de letra distintos.
ThemedText {
    Layout.fillWidth: true
    color: Theme.fgMuted
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    font.pixelSize: Theme.typeBodyMedium
}
