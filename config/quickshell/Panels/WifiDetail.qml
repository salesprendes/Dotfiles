import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs.Components
import qs.Config
import qs.Services

// WiFi: cabecera con estado + interruptor y lista de redes, la conectada
// resaltada. Escanea solo mientras está visible. Click conecta/desconecta.
ColumnLayout {
    id: root
    width: parent ? parent.width : implicitWidth
    spacing: Theme.space10

    Component.onCompleted: Net.setScanning(true)
    Component.onDestruction: Net.setScanning(false)

    // Conectada primero, luego por intensidad.
    readonly property var netList: {
        const arr = (Net.networks?.values ?? []).slice()
        arr.sort((a, b) =>
            ((b.connected ? 1 : 0) - (a.connected ? 1 : 0))
            || ((b.signalStrength ?? 0) - (a.signalStrength ?? 0)))
        return arr
    }

    // Caja única.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + Theme.space16 * 2
        radius: Theme.barRadius
        color: Theme.withAlpha(Theme.surface, 0.62)
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.34)

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: Theme.space14
            spacing: Theme.space10

            // Cabecera: icono + estado + spinner de escaneo + interruptor.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                Text {
                    text: Net.icon
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 1
                }
                Text {
                    Layout.fillWidth: true
                    text: !Net.wifiEnabled ? I18n.tr("WiFi disabled")
                        : Net.ssid !== "" ? I18n.tr("Connected to %1").arg(Net.ssid)
                        : Net.scanning ? I18n.tr("Searching networks...")
                        : I18n.tr("WiFi enabled")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    visible: Net.wifiEnabled && Net.scanning
                    text: "󰑮"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    RotationAnimation on rotation {
                        from: 0; to: 360; duration: 1200
                        loops: Animation.Infinite; running: parent.visible
                    }
                }
                // Engranaje: ajustes IP de la conexión activa (wifi/ethernet).
                Text {
                    visible: Net.online
                    text: "󰒓"
                    color: gearMa.containsMouse ? Theme.accent : Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    MouseArea {
                        id: gearMa
                        anchors.fill: parent
                        anchors.margins: -Theme.space4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Net.openIpConfig()
                    }
                }
                Switch {
                    checked: Net.wifiEnabled
                    onToggled: Net.toggleWifi()
                }
            }

            // Estado vacío.
            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space2
                Layout.bottomMargin: Theme.space2
                visible: Net.wifiEnabled && root.netList.length === 0
                horizontalAlignment: Text.AlignHCenter
                text: Net.scanning ? I18n.tr("Searching networks...") : I18n.tr("No networks found")
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            // Lista de redes con altura acotada y scroll; la activa queda resaltada.
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(Theme.dp(248), contentHeight)
                visible: Net.wifiEnabled && root.netList.length > 0
                clip: true
                spacing: Theme.space6
                model: root.netList
                delegate: NetRow {}
            }
        }
    }

    // Fila de red sobre la DeviceRow compartida; aquí solo queda lo propio
    // del WiFi: glifo por cobertura, % y candado, y la lógica de conexión.
    component NetRow: DeviceRow {
        id: nr
        required property var modelData
        width: ListView.view ? ListView.view.width : implicitWidth

        readonly property bool conn: modelData?.connected ?? false
        readonly property bool known: modelData?.known ?? false
        readonly property int sig: Math.round((modelData?.signalStrength ?? 0) * 100)
        readonly property bool secured: (modelData?.security ?? WifiSecurityType.None) !== WifiSecurityType.None

        active: conn
        icon: sig >= 75 ? "󰤨" : sig >= 50 ? "󰤥" : sig >= 25 ? "󰤢" : "󰤟"
        title: modelData?.name ?? ""
        subtitle: conn ? I18n.tr("connected") : known ? I18n.tr("saved") : ""
        subtitleColor: conn ? Theme.green : Theme.fgMuted

        // % de cobertura de la red.
        Text {
            text: nr.sig + "%"
            color: nr.conn ? Theme.accent : Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
            font.bold: nr.conn
        }
        // Candado para redes protegidas.
        Text {
            visible: nr.secured
            text: "󰌾"
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }

        onClicked: {
            if (conn)
                modelData.disconnect()
            else if (known || !secured)
                modelData.connect()
            else
                Net.requestPassword(modelData)
        }
    }
}
