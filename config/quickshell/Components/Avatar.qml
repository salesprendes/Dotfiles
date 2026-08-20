import QtQuick
import Quickshell.Widgets

// Avatar de usuario: imagen recortada en círculo si hay una válida, y si no
// (ruta vacía, fichero borrado o que no carga) la inicial en un círculo tonal.
// La inicial va SIEMPRE debajo, así nunca queda un hueco: la imagen solo se
// pinta encima cuando de verdad ha cargado. El recorte circular lo hace
// ClippingRectangle (de Quickshell), sin depender de módulos de efectos.
//
// SIN dependencias de ningún Theme a propósito: los colores y la tipografía
// entran por propiedades. El greeter corre antes de la sesión con su propio
// Theme (Modules/Greeter/Theme.qml), y sin esto tendría que duplicar el
// componente —como hacía— en vez de desplegarlo vía GREETD_SHARED_QML.
Item {
    id: root

    property real diameter: 40
    property string source: ""          // ruta absoluta o ""
    property string initial: "?"
    property color tint: "#7aa2f7"
    property real initialPixelSize: 18
    property string fontFamily: ""      // "" = tipografía por defecto de Qt
    property bool isDark: true

    // Aspecto del círculo de respaldo. Los valores por defecto salen de
    // 'isDark'; se exponen porque el greeter los quiere más tenues y con
    // contorno, y así el componente sirve a los dos sin bifurcarse.
    property real bgAlpha: isDark ? 0.28 : 0.32
    property color initialColor: isDark ? Qt.lighter(tint, 1.25) : Qt.darker(tint, 1.3)
    property real borderWidth: 0
    property color borderColor: "transparent"

    implicitWidth: diameter
    implicitHeight: diameter

    readonly property bool hasImage: source !== "" && img.status === Image.Ready

    // Fondo: círculo tonal con la inicial. Visible salvo cuando hay imagen.
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.bgAlpha)
        border.width: root.borderWidth
        border.color: root.borderColor
        visible: !root.hasImage
        Text {
            anchors.centerIn: parent
            text: root.initial
            color: root.initialColor
            font.family: root.fontFamily
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
