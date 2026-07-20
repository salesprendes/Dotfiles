import QtQuick
import QtQuick.Layouts
import qs.Config

// Caja de búsqueda compartida (lanzador, portapapeles, monitor): borde que se ilumina
// al enfocar, lupa, campo con placeholder y botón de limpiar opcional.
// Los hijos declarados en la instancia van al final de la fila (p.ej. un contador).
// ESC llega al consumidor SIN aceptar; si no lo acepta, burbujea a la tarjeta del Popout.
Rectangle {
    id: root

    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property int textPixelSize: Theme.fontSize + 1
    // La lupa se tiñe de acento al enfocar.
    property bool accentIconOnFocus: false
    // Botón de limpiar de un click.
    property bool showClear: true
    default property alias trailing: row.data

    signal accepted()
    signal upPressed()
    signal downPressed()
    signal escapePressed(var event)

    function clear() { input.text = "" }

    implicitHeight: Theme.rowM
    radius: Theme.pillRadius
    color: Theme.surface
    border.width: Theme.hairline
    border.color: input.activeFocus ? Theme.accent
                 : Theme.withAlpha(Theme.overlay, 0.4)
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    // Toda la píldora enfoca el campo, no solo la franja del texto: el
    // TextInput mide lo que mide su fuente y clicar el relleno de alrededor
    // no hacía nada (en los popouts no se notaba porque enfocan por código
    // al abrirse; en una ventana normal dejaba el buscador "muerto").
    // Declarado ANTES de la fila: el botón de limpiar queda encima y gana.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onPressed: input.forceActiveFocus()
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Theme.space12
        anchors.rightMargin: Theme.space12
        spacing: Theme.space8

        Text {
            text: "󰍉"   // lupa
            color: root.accentIconOnFocus && input.activeFocus ? Theme.accent : Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        TextInput {
            id: input
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: root.textPixelSize
            selectionColor: Theme.accent
            verticalAlignment: TextInput.AlignVCenter
            // ESC no se consume aquí: el consumidor puede aceptarlo; si no, burbujea y la tarjeta cierra.
            Keys.onEscapePressed: (event) => { event.accepted = false; root.escapePressed(event) }
            Keys.onReturnPressed: root.accepted()
            Keys.onEnterPressed: root.accepted()
            Keys.onDownPressed: root.downPressed()
            Keys.onUpPressed: root.upPressed()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === ""
                text: root.placeholder
                color: Theme.fgMuted
                font: input.font
            }
        }

        // Borrar la búsqueda de un click.
        Rectangle {
            visible: root.showClear && input.text !== ""
            implicitWidth: Theme.dp(22); implicitHeight: Theme.dp(22)
            radius: width / 2
            color: Theme.withAlpha(Theme.overlay, clearMa.containsMouse ? 0.5 : 0)
            Text {
                anchors.centerIn: parent
                text: "󰅖"
                color: clearMa.containsMouse ? Theme.fg : Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
            MouseArea {
                id: clearMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: input.text = ""
            }
        }
    }
}
