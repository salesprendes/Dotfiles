import QtQuick
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

    property var ranura: null
    readonly property var ventanas: root.ranura ? (root.ranura.ventanas || []) : []

    signal pideCerrar()

    implicitWidth: Theme.dp(320)
    implicitHeight: col.implicitHeight + Theme.space12 * 2

    radius: Theme.shapeLg
    color: Theme.surfaceContainer
    border.width: 1
    border.color: Theme.outlineVariant
    antialiasing: true

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
        }

        Repeater {
            model: root.ventanas
            delegate: Rectangle {
                id: filaV
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Theme.dp(26)
                radius: Theme.shapeSm
                color: zona.containsMouse ? Theme.withAlpha(Theme.accent, 0.16)
                                          : "transparent"

                ThemedText {
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
