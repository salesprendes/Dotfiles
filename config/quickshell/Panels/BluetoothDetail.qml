import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Detalle Bluetooth unificado en una caja: cabecera con estado + interruptor,
// y lista de dispositivos con el conectado resaltado por color y borde.
// Click conecta/desconecta. Debajo del nombre: % de batería si
// está disponible; si no, "conectado".
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

    // Fila de dispositivo (mismo estilo que DeviceRow del audio / NetRow).
    component BtRow: Rectangle {
        id: br
        required property var modelData
        width: ListView.view ? ListView.view.width : implicitWidth

        readonly property bool conn: modelData?.connected ?? false
        readonly property bool paired: modelData?.paired ?? false
        readonly property bool batAvail: modelData?.batteryAvailable ?? false
        readonly property int bat: Math.round((modelData?.battery ?? 0) * 100)

        implicitHeight: Theme.rowL
        radius: Theme.pillRadius
        color: conn ? Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, 0.16)
                    : brMa.containsMouse ? Theme.surfaceHi : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.36)
        border.width: conn ? Math.max(1, Theme.dp(2)) : Theme.hairline
        border.color: conn ? Theme.accent2 : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.28)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space10
            anchors.rightMargin: Theme.space10
            spacing: Theme.space8

            Text {
                text: br.conn ? "󰂱" : "󰂯"
                color: br.conn ? Theme.accent2 : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                // Nombre del dispositivo (limitado si es muy largo).
                Text {
                    Layout.fillWidth: true
                    text: br.modelData?.name ?? br.modelData?.deviceName ?? I18n.tr("Device")
                    color: br.conn ? Theme.fg : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: br.conn
                    elide: Text.ElideRight
                }
                // Debajo: % de batería; si no está disponible → "conectado"
                // (o "emparejado" para los no conectados pero recordados).
                Text {
                    Layout.fillWidth: true
                    visible: br.batAvail || br.conn || br.paired
                    text: br.batAvail ? (br.bat + "%")
                        : br.conn ? I18n.tr("connected")
                        : I18n.tr("paired")
                    color: br.batAvail ? Theme.green
                        : br.conn ? Theme.green
                        : Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 4
                    elide: Text.ElideRight
                }
            }
            // Glifo de batería a la derecha cuando hay nivel disponible.
            Text {
                visible: br.batAvail
                text: br.bat >= 80 ? "󰁹" : br.bat >= 60 ? "󰂀" : br.bat >= 40 ? "󰁾" : br.bat >= 20 ? "󰁻" : "󰁺"
                color: br.bat <= 20 ? Theme.red : Theme.green
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
        }

        MouseArea {
            id: brMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (br.conn) br.modelData.disconnect()
                else br.modelData.connect()
            }
        }
    }
}
