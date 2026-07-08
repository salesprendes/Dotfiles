import QtQuick
import QtQuick.Layouts
import qs.Config

// Texto de ayuda bajo un control: apagado, a lo ancho, con ajuste de línea.
Text {
    Layout.fillWidth: true
    color: Theme.fgMuted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize - 3
    wrapMode: Text.WordWrap
}
