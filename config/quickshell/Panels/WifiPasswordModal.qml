import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
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

    onVisibleChanged: {
        if (visible) {
            pw = ""; err = ""; connecting = false
            pwInput.text = ""
            focusTimer.restart()
        }
    }
    Timer { id: focusTimer; interval: 60; onTriggered: pwInput.forceActiveFocus() }

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
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.rowM
                radius: Theme.pillRadius
                color: Theme.surface
                border.width: Theme.hairline
                border.color: modal.err !== "" ? Theme.red
                             : pwInput.activeFocus ? Theme.accent
                             : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space12
                    anchors.rightMargin: Theme.space10
                    spacing: Theme.space8

                    Text { text: "󰌾"; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize }

                    TextInput {
                        id: pwInput
                        Layout.fillWidth: true
                        clip: true
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        selectionColor: Theme.accent
                        echoMode: showPw.on ? TextInput.Normal : TextInput.Password
                        verticalAlignment: TextInput.AlignVCenter
                        focus: true
                        onTextChanged: { modal.pw = text; modal.err = "" }
                        Keys.onReturnPressed: modal.tryConnect()
                        Keys.onEnterPressed: modal.tryConnect()
                        Keys.onEscapePressed: Net.clearPrompt()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pwInput.text === ""
                            text: I18n.tr("Password")
                            color: Theme.fgMuted
                            font: pwInput.font
                        }
                    }

                    // Mostrar/ocultar contraseña.
                    Text {
                        id: showPw
                        property bool on: false
                        text: on ? "󰈉" : "󰈈"
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Theme.space4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: showPw.on = !showPw.on
                        }
                    }
                }
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

                Rectangle {
                    implicitWidth: cancelTxt.implicitWidth + Theme.controlS
                    implicitHeight: Theme.dp(32)
                    radius: Theme.pillRadius
                    color: cancelMa.containsMouse ? Theme.surfaceHi : Theme.surface
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text { id: cancelTxt; anchors.centerIn: parent; text: I18n.tr("Cancel"); color: Theme.fgDim; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                    MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Net.clearPrompt() }
                }

                Rectangle {
                    implicitWidth: connTxt.implicitWidth + Theme.controlS
                    implicitHeight: Theme.dp(32)
                    radius: Theme.pillRadius
                    enabled: modal.pw !== ""
                    opacity: modal.pw !== "" ? 1 : 0.5
                    color: connMa.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        id: connTxt
                        anchors.centerIn: parent
                        text: modal.connecting ? I18n.tr("Connecting...") : I18n.tr("Connect")
                        color: Theme.bg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                    MouseArea {
                        id: connMa
                        anchors.fill: parent
                        enabled: modal.pw !== ""
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: modal.tryConnect()
                    }
                }
            }
        }
    }
}
