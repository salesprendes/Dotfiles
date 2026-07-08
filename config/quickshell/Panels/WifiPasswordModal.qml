import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

// Diálogo de contraseña para conectar a una red WiFi nueva protegida.
// Visible cuando Net.promptNetwork !== null. Centrado, captura teclado.
PanelWindow {
    id: modal

    property var modelData
    screen: modelData

    readonly property var net: Net.promptNetwork
    visible: net !== null

    property string pw: ""
    property string err: ""
    property bool connecting: false

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-wifiprompt"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

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

    // Fondo oscuro: click cancela.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: modal.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        MouseArea { anchors.fill: parent; onClicked: Net.clearPrompt() }
    }

    // Tarjeta centrada.
    Rectangle {
        anchors.centerIn: parent
        width: Theme.panelWidth(screen, 360, 300, 0.86)
        height: content.implicitHeight + Theme.space18 * 2
        radius: Theme.barRadius + Theme.space2
        color: Theme.bgAlt
        border.width: Theme.hairline
        border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.5)

        opacity: modal.visible ? 1 : 0
        scale: modal.visible ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }   // absorbe clicks

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space18 }
            spacing: Theme.space12

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space10
                Text {
                    text: "󰤨"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 6
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: I18n.tr("Connect to WiFi network")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modal.net?.name ?? ""
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        elide: Text.ElideRight
                    }
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
    }
}
