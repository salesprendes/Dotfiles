import QtQuick
import Quickshell.Widgets
import qs.Config

// Avatar de usuario: imagen recortada en círculo si hay una válida, y si no
// (ruta vacía, fichero borrado o que no carga) la inicial en un círculo tonal
// de acento. La inicial va SIEMPRE debajo, así nunca queda un hueco: la imagen
// solo se pinta encima cuando de verdad ha cargado. El recorte circular lo hace
// ClippingRectangle (de Quickshell), sin depender de módulos de efectos.
Item {
    id: root

    property real diameter: Theme.dp(40)
    property string source: ""          // ruta absoluta o ""
    property string initial: "?"
    property color tint: Theme.accent
    property real initialPixelSize: Theme.sp(18)

    implicitWidth: diameter
    implicitHeight: diameter

    readonly property bool hasImage: source !== "" && img.status === Image.Ready

    // Fondo: círculo tonal con la inicial. Visible salvo cuando hay imagen.
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.withAlpha(root.tint, Theme.isDark ? 0.28 : 0.32)
        visible: !root.hasImage
        Text {
            anchors.centerIn: parent
            text: root.initial
            color: Theme.isDark ? Qt.lighter(root.tint, 1.25) : Qt.darker(root.tint, 1.3)
            font.family: Theme.fontFamily
            font.pixelSize: root.initialPixelSize
            font.bold: true
        }
    }

    // Imagen recortada al círculo. Se mantiene montada aunque no se vea, para
    // que cargue; al estar lista, hasImage la muestra y oculta la inicial.
    ClippingRectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        visible: root.hasImage
        Image {
            id: img
            anchors.fill: parent
            source: root.source !== "" ? "file://" + root.source : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            // Muestrea al doble del tamaño mostrado: nítido en pantallas densas
            // sin cargar la foto entera en memoria.
            sourceSize.width: Math.round(root.diameter * 2)
            sourceSize.height: Math.round(root.diameter * 2)
        }
    }
}
