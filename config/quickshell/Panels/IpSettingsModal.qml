import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Ajustes IP rápidos desde el engranaje del centro rápido. Usa NetConfig,
// la misma lógica que Ajustes > Red: al abrir autoselecciona la interfaz
// activa (la conectada; ethernet si hay varias) y edita su IPv4. Sin selector
// de interfaz. Aplicar delega en NetConfig.apply(), que preserva IPv6/MAC/MTU.
ModalWindow {
    id: modal

    visible: Net.ipConfigOpen

    readonly property bool manual: NetConfig.ip4method === "manual"

    ns: "qs-ipconfig"
    cardWidth: 380
    cardMinWidth: 320
    cardMaxRatio: 0.88
    icon: "󰒓"
    heading: I18n.tr("Network settings")
    subheading: NetConfig.loading ? I18n.tr("Loading...")
        : NetConfig.selectedIface === "" ? I18n.tr("No active connection found.")
        : (NetConfig.isWifi ? "󰤨  " : "󰈁  ") + NetConfig.selectedIface
          + (NetConfig.ifaceConn !== "" ? " · " + NetConfig.ifaceConn : "")
    onDismissed: Net.closeIpConfig()

    // Cargado bajo demanda (LazyLoader en shell.qml): puede nacer ya visible
    // y entonces onVisibleChanged no se dispara, de ahí el onCompleted.
    Component.onCompleted: if (visible) _init()
    onVisibleChanged: if (visible) _init()
    function _init() {
        NetConfig.error = ""
        NetConfig.refreshAll()
        NetConfig.selectActive()
    }

    // Cierra al aplicar con éxito; si falla, NetConfig.error se muestra.
    Connections {
        target: NetConfig
        function onApplyDone(ok) { if (ok && modal.visible) Net.closeIpConfig() }
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
        Behavior on implicitHeight { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }

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
    ThemedText {
        Layout.fillWidth: true
        visible: NetConfig.error !== ""
        text: NetConfig.error
        color: Theme.red
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

    // Botón de método (Auto/Manual).
    component MethodBtn: Rectangle {
        property string label: ""
        property bool on: false
        signal picked()
        Layout.fillWidth: true
        implicitHeight: Theme.dp(32)
        radius: Theme.pillRadius
        color: on ? Theme.withAlpha(Theme.accent, 0.18)
                  : mbMa.containsMouse ? Theme.surfaceHi : Theme.surface
        border.width: on ? Math.max(1, Theme.dp(2)) : Theme.hairline
        border.color: on ? Theme.accent : Theme.withAlpha(Theme.overlay, 0.34)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        ThemedText {
            anchors.centerIn: parent
            text: parent.label
            color: parent.on ? Theme.accent : Theme.fgDim
            font.pixelSize: Theme.fontSize - 1
            font.bold: parent.on
        }
        MouseArea { id: mbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.picked() }
    }
}
