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
// globo es inusable. Los tiempos los pone DockPopovers, que es quien ve los dos
// botones a la vez y puede distinguir "se ha ido" de "ha pasado al vecino".
DockSurface {
    id: root

    property var ranura: null
    readonly property var ventanas: root.ranura ? (root.ranura.ventanas || []) : []

    // Techo de altura, en píxeles. Lo pone DockPopovers desde el sitio que queda
    // libre por encima del dock, y sin él esto crecía sin freno: la ventana del
    // dock mide 483 px, el globo se coloca en 'y = tope − alto', y a partir de
    // unas diez ventanas el alto pasaba del hueco disponible y la 'y' se iba a
    // negativo. Lo que hay por encima del borde de la ventana simplemente no se
    // pinta, así que la lista se cortaba por arriba —empezando por el nombre de
    // la app— sin ningún aviso de que faltaba algo.
    //
    // Diez ventanas no es un caso rebuscado: son diez terminales o diez ventanas
    // de un navegador.
    property real altoMax: 0

    signal pideCerrar()

    // El ancho lo pone el contenido, entre un suelo y un techo. Clavado a 320
    // dp, el globo de una app con un nombre corto y sin ventanas era una losa
    // medio vacía junto a un icono pequeño; y el techo sigue haciendo falta,
    // porque los títulos de ventana de un navegador no tienen final.
    readonly property int anchoMin: Theme.dp(170)
    readonly property int anchoTope: Theme.dp(320)
    implicitWidth: Math.max(root.anchoMin,
                            Math.min(root.anchoTope, marco.implicitWidth + Theme.space12 * 2))
    implicitHeight: marco.implicitHeight + Theme.space12 * 2

    // Lo que le queda a la lista cuando ya han cobrado el relleno y la cabecera.
    // El suelo de una fila es para que, con el dock en un sitio imposible, se
    // vea al menos una ventana y el globo no quede como una caja vacía.
    readonly property real altoLista: root.altoMax > 0
        ? Math.max(Theme.dp(26), root.altoMax - Theme.space12 * 2
                   - cabecera.implicitHeight - marco.spacing)
        : Number.MAX_VALUE

    radius: Theme.shapeLg
    // Un pelín más caída que la del dock: este globo flota por encima de él, y
    // si las dos sombras fueran iguales los dos planos se leerían como uno.
    sombraBaja: Theme.dp(3)

    ColumnLayout {
        id: marco
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.space12
        spacing: Theme.space4

        ThemedText {
            id: cabecera
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

        // La lista se desplaza en vez de recortarse: una ventana que no cabe
        // sigue siendo una ventana a la que quieres llegar.
        //
        // La cabecera se queda FUERA, fija, y no es un detalle: con quince
        // ventanas, meterla dentro haría que el nombre de la app se fuera
        // arriba al primer gesto de rueda, y ese nombre es lo que dice de qué
        // app son las quince.
        //
        // El ancho natural sigue saliendo de los títulos aunque la lista esté
        // topada de alto: 'filas' es un ColumnLayout, que sí calcula su
        // implicitWidth desde los hijos —un Column normal devuelve el ancho del
        // hijo más ancho YA colocado, que aquí sería el de la propia lista y no
        // diría nada—, y esa medida sube por el implicitWidth del Flickable.
        Flickable {
            id: lista
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(filas.implicitHeight, root.altoLista)
            visible: root.ventanas.length > 0

            implicitWidth: filas.implicitWidth
            contentWidth: width
            contentHeight: filas.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: contentHeight > height + 0.5
            interactive: contentHeight > height + 0.5

            ColumnLayout {
                id: filas
                width: lista.width
                spacing: Theme.space4

                Repeater {
                    model: root.ventanas
                    delegate: Rectangle {
                        id: filaV
                        required property var modelData
                        Layout.fillWidth: true
                        // Sin esto el título no entra en el ancho natural de la
                        // columna —el Text va anclado, no en el layout— y el
                        // globo se quedaría en el mínimo aunque el título
                        // pidiera más.
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
                                WindowManager.enfocar(filaV.modelData)
                                root.pideCerrar()
                            }
                        }
                    }
                }
            }

            // Aviso de que la lista sigue. Mismo argumento que los velos de la
            // fila del dock: cortar en seco contra el borde se lee como un fallo
            // de pintado, no como "hay más".
            Rectangle {
                y: lista.contentY + lista.height - height
                width: lista.width
                height: Theme.dp(16)
                visible: lista.interactive
                         && lista.contentY < lista.contentHeight - lista.height - 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.withAlpha(root.color, 0) }
                    GradientStop { position: 1.0; color: root.color }
                }
            }
        }
    }
}
