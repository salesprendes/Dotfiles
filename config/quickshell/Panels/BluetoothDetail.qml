import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Bluetooth: cabecera con estado + interruptor y lista de dispositivos, el
// conectado resaltado. Click conecta/desconecta. Debajo del nombre va la
// batería si hay dato, si no "conectado".
ColumnLayout {
    id: root
    width: parent ? parent.width : implicitWidth
    spacing: Theme.space10

    // Conectados primero, luego emparejados, luego el resto.
    readonly property var devList: {
        const arr = (BT.devices?.values ?? BT.devices ?? []).slice()
        arr.sort((a, b) =>
            ((b.connected ? 1 : 0) - (a.connected ? 1 : 0))
            || ((b.paired ? 1 : 0) - (a.paired ? 1 : 0)))
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

            // Cabecera: icono + estado + spinner de búsqueda + interruptor.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                Text {
                    text: BT.icon
                    color: Theme.accent2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 1
                }
                Text {
                    Layout.fillWidth: true
                    text: !BT.available ? I18n.tr("No adapter")
                        : !BT.enabled ? I18n.tr("Bluetooth disabled")
                        : BT.discovering ? I18n.tr("Searching...")
                        : I18n.tr("Bluetooth enabled")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    visible: BT.enabled && BT.discovering
                    text: "󰑮"
                    color: Theme.accent2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    RotationAnimation on rotation {
                        from: 0; to: 360; duration: 1200
                        loops: Animation.Infinite; running: parent.visible
                    }
                }
                Switch {
                    checked: BT.enabled
                    onColor: Theme.accent2
                    onToggled: BT.toggle()
                }
            }

            // Estado vacío.
            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space2
                Layout.bottomMargin: Theme.space2
                visible: BT.enabled && root.devList.length === 0
                horizontalAlignment: Text.AlignHCenter
                text: BT.discovering ? I18n.tr("Searching...") : I18n.tr("No devices found")
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            // Lista de dispositivos (capada + scroll), conectado resaltado.
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(Theme.dp(248), contentHeight)
                visible: BT.enabled && root.devList.length > 0
                clip: true
                spacing: Theme.space6
                model: root.devList
                delegate: BtRow {}
            }
        }
    }

    // Fila de dispositivo sobre la DeviceRow compartida; aquí solo queda lo
    // propio del Bluetooth: batería en el subtítulo y glifo a la derecha.
    component BtRow: DeviceRow {
        id: br
        required property var modelData
        width: ListView.view ? ListView.view.width : implicitWidth

        readonly property bool conn: modelData?.connected ?? false
        readonly property bool paired: modelData?.paired ?? false
        readonly property bool batAvail: modelData?.batteryAvailable ?? false
        readonly property int bat: Math.round((modelData?.battery ?? 0) * 100)

        active: conn
        accent: Theme.accent2
        icon: conn ? "󰂱" : "󰂯"
        // Nombre del dispositivo (limitado si es muy largo).
        title: modelData?.name ?? modelData?.deviceName ?? I18n.tr("Device")
        // Batería si hay dato; si no "conectado", o "emparejado" para los
        // recordados que no están conectados.
        subtitle: batAvail ? (bat + "%")
            : conn ? I18n.tr("connected")
            : paired ? I18n.tr("paired")
            : ""
        subtitleColor: (batAvail || conn) ? Theme.green : Theme.fgMuted

        // Glifo de batería a la derecha cuando hay nivel disponible.
        Text {
            visible: br.batAvail
            text: br.bat >= 80 ? "󰁹" : br.bat >= 60 ? "󰂀" : br.bat >= 40 ? "󰁾" : br.bat >= 20 ? "󰁻" : "󰁺"
            color: br.bat <= 20 ? Theme.red : Theme.green
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
        }

        onClicked: {
            if (conn) modelData.disconnect()
            else modelData.connect()
        }
    }
}
