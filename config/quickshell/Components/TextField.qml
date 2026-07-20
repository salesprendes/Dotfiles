import QtQuick
import QtQuick.Layouts
import qs.Config

// Campo de texto reutilizable.
// label: etiqueta opcional encima (vacío = sin etiqueta). leftIcon: glifo a la izquierda.
// password: modo contraseña + botón ojo para mostrar/ocultar. invalid: borde rojo.
// value: valor desde el estado (el padre es la fuente); 'edited(text)' sube los cambios
// y el campo se re-sincroniza si 'value' cambia (prefill/reset).
ColumnLayout {
    id: field

    property string label: ""
    property string placeholder: ""

    // Filtro de la ventana de Ajustes (ver Config/SettingsFilter.qml). OPT-IN:
    // sin 'skey' la fila no se filtra, así el campo sigue sirviendo fuera.
    property string skey: ""
    property string cardTitle: ""
    property bool shown: true
    readonly property bool matches: SettingsFilter.accepts(
        field.label + " " + field.placeholder + " " + field.cardTitle, field.skey)
    visible: field.shown && field.matches
    property string leftIcon: ""
    property string value: ""
    property bool   password: false
    property bool   invalid: false
    signal edited(string text)
    signal accepted()
    signal canceled()

    function forceFocus() { input.forceActiveFocus() }

    spacing: Theme.space2

    Text {
        visible: field.label !== ""
        text: field.label
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 3
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.rowM
        radius: Theme.pillRadius
        color: Theme.surface
        border.width: Theme.hairline
        border.color: field.invalid ? Theme.red
                     : input.activeFocus ? Theme.accent
                     : Theme.withAlpha(Theme.overlay, 0.4)
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space12
            anchors.rightMargin: Theme.space10
            spacing: Theme.space8

            Text {
                visible: field.leftIcon !== ""
                text: field.leftIcon
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }

            TextInput {
                id: input
                Layout.fillWidth: true
                clip: true
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                selectionColor: Theme.accent
                verticalAlignment: TextInput.AlignVCenter
                inputMethodHints: Qt.ImhNoPredictiveText
                echoMode: (field.password && !eye.shown) ? TextInput.Password : TextInput.Normal
                Component.onCompleted: text = field.value
                onTextChanged: if (text !== field.value) field.edited(text)
                Keys.onReturnPressed: field.accepted()
                Keys.onEnterPressed: field.accepted()
                Keys.onEscapePressed: field.canceled()

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: field.placeholder
                    color: Theme.fgMuted
                    font: input.font
                }
            }

            // Mostrar/ocultar (solo en modo contraseña).
            Text {
                id: eye
                property bool shown: false
                visible: field.password
                text: shown ? "󰈉" : "󰈈"
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Theme.space4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: eye.shown = !eye.shown
                }
            }
        }
    }

    // Re-sincroniza el input cuando 'value' cambia desde fuera (prefill/reset), incluso
    // tras editar (un binding se rompería).
    Connections {
        target: field
        function onValueChanged() {
            if (input.text !== field.value)
                input.text = field.value
        }
    }
}
