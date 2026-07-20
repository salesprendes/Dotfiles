import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Red
ColumnLayout {
    spacing: Theme.space12

    // Interfaz/adaptador: WiFi + selección de interfaz cuyos parámetros IP
    // se editan abajo.
    SettingsCard {
        title: I18n.tr("Interface"); glyph: "󰛳"
        SwitchRow {
            skey: "@wifi"
            label: I18n.tr("WiFi")
            checked: Net.wifiEnabled
            onToggled: Net.toggleWifi()
        }
        DropdownRow {
            skey: "@interface"
            label: I18n.tr("Interface")
            options: NetConfig.interfaces.map(i => ({
                text: i.device + " · " + (i.type === "wifi" ? I18n.tr("WiFi") : I18n.tr("Ethernet"))
                      + (i.connection !== "" ? " — " + i.connection : ""),
                value: i.device }))
            current: NetConfig.selectedIface
            onPicked: (v) => NetConfig.selectIface(v)
        }
        Text {
            Layout.fillWidth: true
            visible: NetConfig.selectedIface !== "" && !NetConfig.hasConn
            text: I18n.tr("Interface not connected. Connect it to edit its settings.")
            color: Theme.fgMuted; wrapMode: Text.WordWrap
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
        }
        SwitchRow {
            skey: "@connect-automatically"
            shown: NetConfig.hasConn
            label: I18n.tr("Connect automatically")
            checked: NetConfig.autoconnect
            onToggled: NetConfig.autoconnect = !NetConfig.autoconnect
        }
        SliderRow {
            skey: "@priority"
            shown: NetConfig.hasConn
            label: I18n.tr("Priority"); glyph: "󰓅"
            from: -100; to: 100; value: NetConfig.priority
            valueText: NetConfig.priority
            onMoved: (v) => NetConfig.priority = Math.round(v)
        }
    }

    // IPv4 + DNS.
    SettingsCard {
        shown: NetConfig.hasConn
        title: "IPv4"; glyph: "󰩟"
        SegRow {
            skey: "@method"
            label: I18n.tr("Method")
            options: [ { text: I18n.tr("Automatic (DHCP)"), value: "auto" },
                       { text: I18n.tr("Manual (static)"), value: "manual" } ]
            current: NetConfig.ip4method
            onPicked: (v) => NetConfig.ip4method = v
        }
        TextField {
            skey: "@ip-address"
            shown: NetConfig.ip4method === "manual"; Layout.fillWidth: true
            label: I18n.tr("IP address"); placeholder: "192.168.1.50"
            value: NetConfig.ip4addr
            invalid: NetConfig.ip4addr !== "" && !NetConfig.validIp(NetConfig.ip4addr)
            onEdited: (t) => NetConfig.ip4addr = t
        }
        TextField {
            skey: "@subnet-mask"
            shown: NetConfig.ip4method === "manual"; Layout.fillWidth: true
            label: I18n.tr("Subnet mask"); placeholder: "255.255.255.0"
            value: NetConfig.ip4mask
            invalid: NetConfig.ip4mask !== "" && NetConfig.maskToPrefix(NetConfig.ip4mask) < 0
            onEdited: (t) => NetConfig.ip4mask = t
        }
        TextField {
            skey: "@gateway"
            shown: NetConfig.ip4method === "manual"; Layout.fillWidth: true
            label: I18n.tr("Gateway"); placeholder: "192.168.1.1"
            value: NetConfig.ip4gw
            invalid: NetConfig.ip4gw !== "" && !NetConfig.validIp(NetConfig.ip4gw)
            onEdited: (t) => NetConfig.ip4gw = t
        }
        TextField {
            skey: "@textfield"
            Layout.fillWidth: true
            label: "DNS"; placeholder: "1.1.1.1, 8.8.8.8"
            value: NetConfig.ip4dns
            onEdited: (t) => NetConfig.ip4dns = t
        }
    }

    // IPv6.
    SettingsCard {
        shown: NetConfig.hasConn
        title: "IPv6"; glyph: "󰩟"
        SegRow {
            skey: "@method"
            label: I18n.tr("Method")
            options: [ { text: I18n.tr("Automatic (DHCP)"), value: "auto" },
                       { text: I18n.tr("Disabled"), value: "disabled" },
                       { text: "Link-local", value: "link-local" } ]
            current: NetConfig.ip6method
            onPicked: (v) => NetConfig.ip6method = v
        }
    }

    // Privacidad / avanzado.
    SettingsCard {
        shown: NetConfig.hasConn
        title: I18n.tr("Privacy and advanced"); glyph: "󰒃"
        DropdownRow {
            skey: "@mac-address"
            label: I18n.tr("MAC address")
            options: [ { text: I18n.tr("Default"), value: "default" },
                       { text: I18n.tr("Random"), value: "random" },
                       { text: I18n.tr("Stable"), value: "stable" } ]
            current: NetConfig.mac
            onPicked: (v) => NetConfig.mac = v
        }
        TextField {
            skey: "@textfield"
            Layout.fillWidth: true
            label: "MTU"; placeholder: I18n.tr("Automatic")
            value: NetConfig.mtu
            onEdited: (t) => NetConfig.mtu = t
        }
    }

    // Error.
    Text {
        Layout.fillWidth: true
        visible: NetConfig.error !== ""
        text: NetConfig.error
        color: Theme.red
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
        wrapMode: Text.WordWrap
    }

    // Aplicar cambios de la interfaz seleccionada.
    RowLayout {
        Layout.fillWidth: true
        visible: NetConfig.hasConn
        spacing: Theme.space8
        Item { Layout.fillWidth: true }
        TextButton {
            text: I18n.tr("Apply")
            primary: true
            enabled: NetConfig.ready && !NetConfig.loading
            onClicked: NetConfig.apply()
        }
    }

    Text {
        Layout.fillWidth: true
        visible: NetConfig.interfaces.length === 0
        text: I18n.tr("No network interfaces found.")
        color: Theme.fgMuted
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
    }

    // Gestión de wifis guardadas
    SettingsCard {
        title: I18n.tr("Saved networks"); glyph: "󰤨"

        Repeater {
            model: NetConfig.savedWifis
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.space8

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.space6
                        Text {
                            Layout.fillWidth: true
                            text: modelData.name; color: Theme.fg; elide: Text.ElideRight
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                        }
                        Rectangle {
                            visible: modelData.active
                            radius: Theme.pillRadius
                            color: Theme.withAlpha(Theme.green, 0.18)
                            implicitWidth: badge.implicitWidth + Theme.space10
                            implicitHeight: badge.implicitHeight + Theme.space4
                            Text {
                                id: badge; anchors.centerIn: parent
                                text: I18n.tr("Connected"); color: Theme.green
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 4
                            }
                        }
                    }
                    Text {
                        text: I18n.tr("Priority") + ": " + modelData.priority
                              + (modelData.autoconnect ? "" : "  ·  " + I18n.tr("Auto-connect off"))
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 4
                    }
                }

                // Prioridad −/+
                IconButton {
                    icon: "󰍴"; diameter: Theme.controlS
                    onClicked: NetConfig.setWifiPriority(modelData.name, modelData.priority - 1)
                }
                Text {
                    text: modelData.priority; color: Theme.fgDim
                    horizontalAlignment: Text.AlignHCenter
                    Layout.minimumWidth: Theme.space18 + Theme.space6
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                }
                IconButton {
                    icon: "󰐕"; diameter: Theme.controlS
                    onClicked: NetConfig.setWifiPriority(modelData.name, modelData.priority + 1)
                }
                // Conectar (si no está activa)
                IconButton {
                    icon: "󰐊"; diameter: Theme.controlS
                    visible: !modelData.active
                    onClicked: NetConfig.connectWifi(modelData.name)
                }
                // Olvidar (borrar)
                IconButton {
                    icon: "󰩹"; diameter: Theme.controlS
                    hoverColor: Theme.red
                    onClicked: NetConfig.forgetWifi(modelData.name)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: NetConfig.savedWifis.length === 0
            text: I18n.tr("No saved networks.")
            color: Theme.fgMuted
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
        }
    }
}
