import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

// ─────────────────────────────────────────────────────────────
//  Ajustes IP rápidos desde el engranaje del centro rápido. Comparte
//  la MISMA lógica que Ajustes → Red (servicio NetConfig): al abrirse
//  autoselecciona la interfaz ACTIVA (la conectada; ethernet si hay
//  varias) y edita su IPv4. No muestra selector de interfaz. "Aplicar"
//  delega en NetConfig.apply() (que preserva IPv6/MAC/MTU actuales).
// ─────────────────────────────────────────────────────────────
PanelWindow {
    id: modal

    property var modelData
    screen: modelData
    visible: Net.ipConfigOpen

    readonly property bool manual: NetConfig.ip4method === "manual"

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-ipconfig"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

    onVisibleChanged: {
        if (visible) {
            NetConfig.error = ""
            NetConfig.refreshAll()
            NetConfig.selectActive()
        }
    }

    // Cierra al aplicar con éxito; si falla, NetConfig.error se muestra.
    Connections {
        target: NetConfig
        function onApplyDone(ok) { if (ok && modal.visible) Net.closeIpConfig() }
    }

    // ── Fondo oscuro: click cancela ──────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: modal.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        MouseArea { anchors.fill: parent; onClicked: Net.closeIpConfig() }
    }

    // ── Tarjeta ──────────────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width: Theme.panelWidth(screen, 380, 320, 0.88)
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

            // Cabecera: muestra la interfaz activa (sin selector).
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space10
                Text {
                    text: "󰒓"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 6
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: I18n.tr("Network settings")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: NetConfig.loading ? I18n.tr("Loading...")
                            : NetConfig.selectedIface === "" ? I18n.tr("No active connection found.")
                            : (NetConfig.isWifi ? "󰤨  " : "󰈁  ") + NetConfig.selectedIface
                              + (NetConfig.ifaceConn !== "" ? " · " + NetConfig.ifaceConn : "")
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        elide: Text.ElideRight
                    }
                }
            }

            // Interfaz sin perfil activo (ej. ethernet desconectado).
            Text {
                Layout.fillWidth: true
                visible: NetConfig.selectedIface !== "" && !NetConfig.hasConn
                text: I18n.tr("Interface not connected. Connect it to edit its settings.")
                color: Theme.fgMuted; wrapMode: Text.WordWrap
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
            }

            // Selector de método: Automático / Manual.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space2
                visible: NetConfig.hasConn
                spacing: Theme.space8
                MethodBtn { label: I18n.tr("Automatic (DHCP)"); on: !modal.manual; onPicked: NetConfig.ip4method = "auto" }
                MethodBtn { label: I18n.tr("Manual (static)");  on: modal.manual;  onPicked: NetConfig.ip4method = "manual" }
            }

            // Campos manuales (modo estático): altura + opacidad animadas.
            Item {
                Layout.fillWidth: true
                clip: true
                enabled: modal.manual
                implicitHeight: modal.manual ? manualCol.implicitHeight : 0
                opacity: modal.manual ? 1 : 0
                Behavior on implicitHeight { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    id: manualCol
                    width: parent.width
                    spacing: Theme.space8

                    TextField {
                        Layout.fillWidth: true
                        label: I18n.tr("IP address"); placeholder: "192.168.1.50"
                        value: NetConfig.ip4addr
                        invalid: NetConfig.ip4addr !== "" && !NetConfig.validIp(NetConfig.ip4addr)
                        onEdited: (t) => NetConfig.ip4addr = t
                        onCanceled: Net.closeIpConfig()
                    }
                    TextField {
                        Layout.fillWidth: true
                        label: I18n.tr("Subnet mask"); placeholder: "255.255.255.0"
                        value: NetConfig.ip4mask
                        invalid: NetConfig.ip4mask !== "" && NetConfig.maskToPrefix(NetConfig.ip4mask) < 0
                        onEdited: (t) => NetConfig.ip4mask = t
                        onCanceled: Net.closeIpConfig()
                    }
                    TextField {
                        Layout.fillWidth: true
                        label: I18n.tr("Gateway"); placeholder: "192.168.1.1"
                        value: NetConfig.ip4gw
                        invalid: NetConfig.ip4gw !== "" && !NetConfig.validIp(NetConfig.ip4gw)
                        onEdited: (t) => NetConfig.ip4gw = t
                        onCanceled: Net.closeIpConfig()
                    }
                    TextField {
                        Layout.fillWidth: true
                        label: I18n.tr("DNS"); placeholder: "1.1.1.1, 8.8.8.8"
                        value: NetConfig.ip4dns; invalid: false
                        onEdited: (t) => NetConfig.ip4dns = t
                        onCanceled: Net.closeIpConfig()
                    }
                }
            }

            // Error.
            Text {
                Layout.fillWidth: true
                visible: NetConfig.error !== ""
                text: NetConfig.error
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
                    onClicked: Net.closeIpConfig()
                }

                TextButton {
                    text: NetConfig.applying ? I18n.tr("Applying...") : I18n.tr("Apply")
                    primary: true
                    enabled: NetConfig.hasConn && NetConfig.ready && !NetConfig.loading && !NetConfig.applying
                    onClicked: NetConfig.apply()
                }
            }
        }
    }

    // ── Componente: botón de método (Auto/Manual) ────────────
    component MethodBtn: Rectangle {
        property string label: ""
        property bool on: false
        signal picked()
        Layout.fillWidth: true
        implicitHeight: Theme.dp(32)
        radius: Theme.pillRadius
        color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                  : mbMa.containsMouse ? Theme.surfaceHi : Theme.surface
        border.width: on ? Math.max(1, Theme.dp(2)) : Theme.hairline
        border.color: on ? Theme.accent : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.34)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Text {
            anchors.centerIn: parent
            text: parent.label
            color: parent.on ? Theme.accent : Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            font.bold: parent.on
        }
        MouseArea { id: mbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.picked() }
    }
}
