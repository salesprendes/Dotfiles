import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs.Config
import qs.Services

// Detalle WiFi unificado en una "caja" (como el de audio): cabecera con
// estado + interruptor, y lista de redes con la conectada RESALTADA estilo
// DMS. Escanea solo mientras está visible. Click conecta/desconecta.
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

    // ── Caja única ───────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + Theme.space16 * 2
        radius: Theme.barRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.62)
        border.width: Theme.hairline
        border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.34)

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
                Rectangle {
                    implicitWidth: Theme.dp(40); implicitHeight: Theme.controlXS; radius: height / 2
                    color: Net.wifiEnabled ? Theme.accent : Theme.surface
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Rectangle {
                        width: Theme.space16; height: Theme.space16; radius: height / 2; color: Theme.fg
                        anchors.verticalCenter: parent.verticalCenter
                        x: Net.wifiEnabled ? parent.width - width - Theme.space2 : Theme.space2
                        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Net.toggleWifi() }
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

            // Lista de redes (capada + scroll), cada una resaltada estilo DMS.
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

    // Fila de red (mismo estilo que DeviceRow del audio).
    component NetRow: Rectangle {
        id: nr
        required property var modelData
        width: ListView.view ? ListView.view.width : implicitWidth

        readonly property bool conn: modelData?.connected ?? false
        readonly property bool known: modelData?.known ?? false
        readonly property int sig: Math.round((modelData?.signalStrength ?? 0) * 100)
        readonly property bool secured: (modelData?.security ?? WifiSecurityType.None) !== WifiSecurityType.None

        implicitHeight: Theme.rowL
        radius: Theme.pillRadius
        color: conn ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                    : nrMa.containsMouse ? Theme.surfaceHi : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.36)
        border.width: conn ? Math.max(1, Theme.dp(2)) : Theme.hairline
        border.color: conn ? Theme.accent : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.28)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space10
            anchors.rightMargin: Theme.space10
            spacing: Theme.space8

            Text {
                text: nr.sig >= 75 ? "󰤨" : nr.sig >= 50 ? "󰤥" : nr.sig >= 25 ? "󰤢" : "󰤟"
                color: nr.conn ? Theme.accent : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: nr.modelData?.name ?? ""
                    color: nr.conn ? Theme.fg : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: nr.conn
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: nr.conn || nr.known
                    text: nr.conn ? I18n.tr("connected") : I18n.tr("saved")
                    color: nr.conn ? Theme.green : Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 4
                }
            }
            // % de cobertura de la red.
            Text {
                text: nr.sig + "%"
                color: nr.conn ? Theme.accent : Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                font.bold: nr.conn
            }
            Text {
                visible: nr.secured
                text: "󰌾"
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }

        MouseArea {
            id: nrMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (nr.conn)
                    nr.modelData.disconnect()
                else if (nr.known || !nr.secured)
                    nr.modelData.connect()
                else
                    Net.requestPassword(nr.modelData)
            }
        }
    }
}
