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
    // Vaciado programático (el alta de un servidor MCP limpia sus campos):
    // el texto vive en el TextInput interno, no en 'value'.
    function clear() { input.text = "" }
    signal accepted()
    signal canceled()

    function forceFocus() { input.forceActiveFocus() }

    spacing: Theme.space2

    ThemedText {
        visible: field.label !== ""
        text: field.label
        // Etiqueta del campo: en M3 es un 'label', no un texto de lectura, y
        // se tiñe de acento cuando el campo tiene el foco — así el ojo sabe
        // qué está editando sin buscar el cursor.
        color: field.invalid ? Theme.red
             : input.activeFocus ? Theme.accent : Theme.fgMuted
        font.pixelSize: Theme.typeLabelMedium
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    Rectangle {
        id: box
        Layout.fillWidth: true
        implicitHeight: Theme.rowM
        radius: Theme.pillRadius
        color: Theme.surface
        // El borde ENGORDA al enfocar (1 → 2 px), no solo cambia de color.
        // Es la diferencia entre "este campo está resaltado" y "este campo
        // está recibiendo lo que escribes": con solo el color, en un tema de
        // acento apagado el foco casi no se distinguía del reposo.
        border.width: (input.activeFocus || field.invalid)
            ? Math.max(2, Theme.dp(2)) : Theme.hairline
        border.color: field.invalid ? Theme.red
                     : input.activeFocus ? Theme.accent
                     : Theme.withAlpha(Theme.overlay, 0.4)
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
        Behavior on border.width { NumberAnimation { duration: Theme.animFast } }

        // Capa de estado al pasar el ratón (ver Theme.stateHover).
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.fg
            opacity: boxMa.containsMouse && !input.activeFocus ? Theme.stateHover : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        }
        MouseArea {
            id: boxMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            onPressed: input.forceActiveFocus()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space12
            anchors.rightMargin: Theme.space10
            spacing: Theme.space8

            ThemedText {
                visible: field.leftIcon !== ""
                text: field.leftIcon
                color: Theme.fgMuted
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
            ThemedText {
                id: eye
                property bool shown: false
                visible: field.password
                text: shown ? "󰈉" : "󰈈"
                color: Theme.fgMuted
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
