import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// El globo que sale sobre un icono con las ventanas abiertas de esa app.
//
// Vive DENTRO de la ventana alta del dock (ver DockWindow), no en una
// superficie propia: así no hay una tercera capa de layer-shell por monitor con
// su agarre de foco y su cierre que coordinar con las otras dos.
//
// La histéresis —tarda en salir, tarda en irse— no es un adorno: sin el retardo
// de salida, mover el ratón del icono al globo lo cierra en el camino y el
// globo es inusable. Los tiempos los pone DockWindow, que es quien ve los dos
// botones a la vez y puede distinguir "se ha ido" de "ha pasado al vecino".
Rectangle {
    id: root

    // La misma sombra que el dock y la etiqueta. Va como hermana anclada a este
    // rectángulo y no como hija, porque una hija se recortaría con sus esquinas.
    RectangularShadow {
        anchors.fill: root
        visible: Settings.dockShadow
        radius: root.radius
        blur: Theme.dp(18)
        spread: Theme.dp(1)
        offset: Qt.vector2d(0, Theme.dp(3))
        color: Theme.withAlpha("#000000", Theme.isDark ? 0.45 : 0.22)
        cached: true
        z: -1
    }

    property var ranura: null
    readonly property var ventanas: root.ranura ? (root.ranura.ventanas || []) : []

    signal pideCerrar()

    // El ancho lo pone el contenido, entre un suelo y un techo. Clavado a 320
    // dp, el globo de una app con un nombre corto y sin ventanas era una losa
    // medio vacía junto a un icono pequeño; y el techo sigue haciendo falta,
    // porque los títulos de ventana de un navegador no tienen final.
    readonly property int anchoMin: Theme.dp(170)
    readonly property int anchoMax: Theme.dp(320)
    implicitWidth: Math.max(root.anchoMin,
                            Math.min(root.anchoMax, col.implicitWidth + Theme.space12 * 2))
    implicitHeight: col.implicitHeight + Theme.space12 * 2

    radius: Theme.shapeLg
    color: Theme.surfaceContainer
    border.width: 1
    border.color: Theme.outlineVariant
    antialiasing: true

    // La misma luz de canto que la pastilla del dock y la etiqueta: las tres
    // superficies que salen del dock tienen que leerse como el mismo material.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Theme.withAlpha("#ffffff", Theme.isDark ? 0.06 : 0.26)
            }
            GradientStop { position: 0.45; color: "transparent" }
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.space12
        spacing: Theme.space4

        ThemedText {
            Layout.fillWidth: true
            text: Dock.nombreDe(root.ranura ? root.ranura.id : "")
            color: Theme.fg
            font.pixelSize: Theme.sp(13)
            font.weight: Font.Medium
            elide: Text.ElideRight
            // Centrado: es el título del globo, no la primera fila de la lista.
            // Las filas de ventanas SÍ van a la izquierda, que es como se lee
            // una lista, y el contraste entre las dos cosas las separa.
            horizontalAlignment: Text.AlignHCenter
        }

        // Una app fijada sin ventanas también enseña globo: decir "no hay nada
        // abierto" es información, y sin él el globo parpadearía al pasar el
        // ratón por la mitad de los iconos del dock.
        ThemedText {
            Layout.fillWidth: true
            visible: root.ventanas.length === 0
            text: I18n.tr("Not running")
            color: Theme.fgMuted
            font.pixelSize: Theme.sp(12)
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        Repeater {
            model: root.ventanas
            delegate: Rectangle {
                id: filaV
                required property var modelData
                Layout.fillWidth: true
                // Sin esto el título no entra en el ancho natural de la columna
                // —el Text va anclado, no en el layout— y el globo se quedaría
                // en el mínimo aunque el título pidiera más.
                implicitWidth: titulo.implicitWidth + Theme.space8 * 2
                implicitHeight: Theme.dp(26)
                radius: Theme.shapeSm
                color: zona.containsMouse ? Theme.withAlpha(Theme.accent, 0.16)
                                          : "transparent"

                ThemedText {
                    id: titulo
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.space8
                    anchors.rightMargin: Theme.space8
                    // El título de la ventana, no el nombre de la app: en un
                    // globo cuyo encabezado YA dice la app, repetirla en cada
                    // fila no distingue una ventana de otra, que es lo único
                    // que aquí hace falta.
                    text: filaV.modelData ? (filaV.modelData.title || I18n.tr("Untitled")) : ""
                    color: Theme.fg
                    font.pixelSize: Theme.sp(12)
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: zona
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Dock.enfocar(filaV.modelData)
                        root.pideCerrar()
                    }
                }
            }
        }
    }
}
