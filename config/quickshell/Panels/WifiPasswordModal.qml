import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Diálogo de contraseña para conectar a una red WiFi nueva protegida.
// Visible cuando Net.promptNetwork !== null. Centrado, captura teclado.
ModalWindow {
    id: modal

    readonly property var net: Net.promptNetwork
    visible: net !== null

    property string pw: ""
    property string err: ""
    property bool connecting: false

    ns: "qs-wifiprompt"
    icon: "󰤨"
    heading: I18n.tr("Connect to WiFi network")
    subheading: modal.net?.name ?? ""
    onDismissed: Net.clearPrompt()

    // Cargado bajo demanda (LazyLoader en shell.qml): puede nacer ya visible
    // y entonces onVisibleChanged no se dispara, de ahí el onCompleted.
    Component.onCompleted: if (visible) _init()
    onVisibleChanged: if (visible) _init()
    function _init() {
        pw = ""; err = ""; connecting = false
        focusTimer.restart()
    }
    Timer { id: focusTimer; interval: 60; onTriggered: pwField.forceFocus() }

    function tryConnect() {
        if (pw === "" || !modal.net) return
        modal.connecting = true
        modal.err = ""
        modal.net.connectWithPsk(pw)
    }

    // Reacciona al resultado de la conexión.
    Connections {
        target: Net.promptNetwork
        ignoreUnknownSignals: true
        function onConnectedChanged() {
            if (Net.promptNetwork && Net.promptNetwork.connected) Net.clearPrompt()
        }
        function onConnectionFailed(reason) {
            modal.connecting = false
            modal.err = I18n.tr("Could not connect. Check the password.")
        }
    }

    // Campo de contraseña.
    TextField {
        id: pwField
        Layout.fillWidth: true
        password: true
        leftIcon: "󰌾"
        placeholder: I18n.tr("Password")
        value: modal.pw
        invalid: modal.err !== ""
        onEdited: (t) => { modal.pw = t; modal.err = "" }
        onAccepted: modal.tryConnect()
        onCanceled: Net.clearPrompt()
    }

    // Error.
    Text {
        Layout.fillWidth: true
        visible: modal.err !== ""
        text: modal.err
        color: Theme.red
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
        wrapMode: Text.WordWrap
    }

    // Botones.
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space2
        spacing: Theme.space8

        Item { Layout.fillWidth: true }

        TextButton {
            text: I18n.tr("Cancel")
            onClicked: Net.clearPrompt()
        }

        TextButton {
            text: modal.connecting ? I18n.tr("Connecting...") : I18n.tr("Connect")
            primary: true
            enabled: modal.pw !== ""
            onClicked: modal.tryConnect()
        }
    }
}
