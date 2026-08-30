import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Una app fijada dentro del editor: icono, nombre y aspa para quitarla.
//
// Se arrastra desde la propia ficha, pero la ficha NO SE MUEVE: se atenúa y se
// queda haciendo de hueco de origen mientras el fantasma sigue al ratón. Ver la
// cabecera de DockPinEditor.qml para el porqué.
Rectangle {
    id: root

    required property var editor
    required property string appId
    required property int indice

    readonly property bool arrastrada: root.editor.arrastrando === root.indice

    implicitWidth: fila.implicitWidth + Theme.space10 * 2
    implicitHeight: Theme.dp(34)
    radius: Theme.shapeSm
    color: zona.containsMouse || root.arrastrada
           ? Theme.withAlpha(Theme.accent, 0.14) : Theme.surfaceContainer
    border.width: 1
    border.color: Theme.outlineVariant
    opacity: root.arrastrada ? 0.4 : 1
    antialiasing: true

    Row {
        id: fila
        anchors.centerIn: parent
        spacing: Theme.space8

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.dp(20)
            height: Theme.dp(20)
            source: Dock.iconoDe(root.appId)
            sourceSize.width: Theme.dp(20)
            sourceSize.height: Theme.dp(20)
            fillMode: Image.PreserveAspectFit
        }

        ThemedText {
            anchors.verticalCenter: parent.verticalCenter
            text: Dock.nombreDe(root.appId)
            color: Theme.fg
            font.pixelSize: Theme.sp(12)
        }

        ThemedText {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅖"
            color: zonaAspa.containsMouse ? Theme.red : Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.sp(12)

            MouseArea {
                id: zonaAspa
                anchors.fill: parent
                anchors.margins: -Theme.space4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Dock.soltar(root.appId)
            }
        }
    }

    MouseArea {
        id: zona
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // El aspa va por encima con su propia zona; esta no debe robarle el
        // clic, así que se declara antes en el árbol y el aspa gana por orden.
        z: -1

        // Umbral de 6 px antes de considerar que es un arrastre: sin él,
        // cualquier clic con un temblor de un píxel empieza a arrastrar y el
        // aspa se vuelve imposible de acertar.
        property real x0: 0
        property real y0: 0
        property bool armado: false

        onPressed: (ev) => { zona.x0 = ev.x; zona.y0 = ev.y; zona.armado = true }

        onPositionChanged: (ev) => {
            if (!zona.armado)
                return
            if (root.editor.arrastrando === -1) {
                if (Math.abs(ev.x - zona.x0) < 6 && Math.abs(ev.y - zona.y0) < 6)
                    return
                root.editor.arrastrando = root.indice
            }
            const p = root.mapToItem(root.editor, ev.x, ev.y)
            root.editor.fantasmaX = p.x - Theme.dp(17)
            root.editor.fantasmaY = p.y - Theme.dp(17)
        }

        onReleased: {
            zona.armado = false
            if (root.editor.arrastrando !== -1)
                root.editor.soltar()
        }
        onCanceled: {
            zona.armado = false
            root.editor.arrastrando = -1
            root.editor.destino = -1
        }
    }
}
