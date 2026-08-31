import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Menú contextual de un icono del dock.
//
// Como la vista previa, vive dentro de la ventana alta del dock. Y como ella,
// no pide foco de teclado: se cierra al pulsar fuera o al ejecutar una fila.
// Un menú de layer-shell con foco exclusivo se lo quitaría a la ventana en la
// que estabas escribiendo solo por pulsar con el botón derecho en un icono.
//
// La superficie sale de DockSurface, igual que el dock, la etiqueta y la vista
// previa. Antes era el único de los cuatro sin sombra y sin luz de canto: un
// globo flotante con el filete plano de una tarjeta empotrada, justo al lado de
// otros dos que sí flotaban. No había ninguna razón detrás — es lo que pasa al
// tocar tres archivos en tres días distintos.
DockSurface {
    id: root

    property var ranura: null
    readonly property string appId: root.ranura ? root.ranura.id : ""
    readonly property bool abierta: root.ranura
        ? (root.ranura.ventanas || []).length > 0 : false
    readonly property var acciones: {
        const e = Dock.entradaDe(root.appId)
        return (e && Array.isArray(e.actions)) ? e.actions : []
    }

    signal pideCerrar()

    implicitWidth: Theme.dp(220)
    implicitHeight: col.implicitHeight + Theme.space6 * 2

    radius: Theme.shapeMd
    // Igual que la vista previa: flota por encima del dock, así que su sombra
    // cae un pelín más que la de él para que los dos planos no se confundan.
    sombraBaja: Theme.dp(3)

    // Una fila del menú. Se declara aquí dentro y no como archivo suelto porque
    // no la usa nadie más: sacarla a Components/ sería un archivo más que leer
    // para entender veinte líneas que solo viven aquí.
    component Fila: Rectangle {
        id: fila
        property string etiqueta: ""
        property bool peligrosa: false
        signal activada()

        Layout.fillWidth: true
        implicitHeight: Theme.dp(30)
        radius: Theme.shapeSm
        color: zonaFila.containsMouse
            ? Theme.withAlpha(fila.peligrosa ? Theme.red : Theme.accent, 0.16)
            : "transparent"

        ThemedText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.space10
            anchors.rightMargin: Theme.space10
            text: fila.etiqueta
            color: fila.peligrosa ? Theme.red : Theme.fg
            font.pixelSize: Theme.sp(12)
            elide: Text.ElideRight
        }

        MouseArea {
            id: zonaFila
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fila.activada()
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.space6
        spacing: Theme.space2

        Fila {
            etiqueta: Dock.estaFijada(root.appId) ? I18n.tr("Unpin from dock")
                                                  : I18n.tr("Pin to dock")
            onActivada: {
                if (Dock.estaFijada(root.appId))
                    Dock.soltar(root.appId)
                else
                    Dock.fijar(root.appId)
                root.pideCerrar()
            }
        }

        Fila {
            etiqueta: I18n.tr("New window")
            onActivada: { Dock.lanzarNueva(root.appId); root.pideCerrar() }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.space4
            Layout.bottomMargin: Theme.space4
            implicitHeight: 1
            color: Theme.outlineVariant
            visible: root.acciones.length > 0
        }

        // Las acciones que la propia app declara en su .desktop: "Ventana
        // privada" de Firefox, "Componer correo" de Thunderbird. Salen tal cual
        // las declara la app, sin traducir: son suyas, no del shell.
        Repeater {
            model: root.acciones
            delegate: Fila {
                required property var modelData
                etiqueta: modelData ? (modelData.name || "") : ""
                onActivada: {
                    if (modelData && modelData.execute)
                        modelData.execute()
                    root.pideCerrar()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.space4
            Layout.bottomMargin: Theme.space4
            implicitHeight: 1
            color: Theme.outlineVariant
            visible: root.abierta
        }

        // Va al final y en rojo: es la única fila que no se puede deshacer.
        Fila {
            etiqueta: I18n.tr("Close all")
            peligrosa: true
            visible: root.abierta
            onActivada: { Dock.cerrarTodas(root.ranura); root.pideCerrar() }
        }
    }
}
