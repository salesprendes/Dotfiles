import QtQuick
import qs.Config

// El hueco de suelta entre dos fichas del editor.
//
// ── POR QUÉ NO HAY DropArea AQUÍ ────────────────────────────────────────────
// Lo había, y era código muerto: un DropArea solo reacciona al sistema de
// Drag/Drop de QtQuick, y este arrastre lo lleva a mano un MouseArea con un
// fantasma detrás (ver DockPinChip). Su onEntered no se disparaba jamás, así
// que el resaltado lo hacía por completo el Connections de abajo — con el
// agravante de que el DropArea, ahí puesto, se leía como si fuera EL mecanismo.
//
// Cada hueco mira dónde está el fantasma y se enciende si le cae cerca. Y se
// hace por huecos y no calculando el índice desde la coordenada X, que es lo
// que haría el manual: las fichas llevan el NOMBRE de la app dentro, así que
// sus anchos son muy distintos —"Kitty" mide un tercio que "Visual Studio
// Code"— y un cálculo por posición se equivoca justo donde más se nota.
Item {
    id: root

    required property var editor
    required property int indice
    property real alto: Theme.dp(34)

    readonly property bool activo: root.editor.arrastrando !== -1
    readonly property bool resaltado: root.activo
                                      && root.editor.destino === root.indice

    // Estrecho en reposo para no separar las fichas, ancho mientras se arrastra
    // para que haya dónde apuntar. Sin ese ensanchado, acertar un hueco de 4 px
    // con el ratón es un ejercicio de puntería.
    implicitWidth: root.activo ? Theme.dp(14) : Theme.dp(3)
    implicitHeight: root.alto

    Behavior on implicitWidth {
        enabled: Theme.animNormal > 0
        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Theme.dp(3)
        height: parent.height - Theme.space4
        radius: width / 2
        color: Theme.accent
        opacity: root.resaltado ? 1 : 0
        antialiasing: true

        Behavior on opacity {
            enabled: Theme.animNormal > 0
            NumberAnimation { duration: Theme.animFast }
        }
    }

    Connections {
        target: root.editor
        enabled: root.activo
        function onFantasmaXChanged() {
            const c = root.mapToItem(root.editor, root.width / 2, 0)
            const gx = root.editor.fantasmaX + Theme.dp(17)
            if (Math.abs(gx - c.x) < Theme.dp(24))
                root.editor.destino = root.indice
        }
    }
}
