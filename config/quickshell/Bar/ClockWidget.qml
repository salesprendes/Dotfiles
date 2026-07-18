import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Services

// Reloj central: hora + fecha. Click abre el Dashboard.
// La hora sale del singleton Time; aquí solo se formatea en cada tick.
Pill {
    id: root
    interactive: true
    onClicked: Globals.toggleDashboard()

    // Formato según ajustes: 24h/12h y segundos.
    readonly property string timeFormat: (Settings.clock24h ? "HH:mm" : "hh:mm")
        + (Settings.clockShowSeconds ? ":ss" : "")
        + (Settings.clock24h ? "" : " AP")

    Text {
        text: "󰅐"
        color: Globals.dashboardOpen ? Theme.accent2 : Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
    Text {
        text: Qt.formatDateTime(Time.now, root.timeFormat)
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
    }
    Rectangle {
        visible: Settings.clockShowDate
        implicitWidth: Theme.hairline
        implicitHeight: Theme.dp(14)
        color: Theme.overlay
    }
    Text {
        visible: Settings.clockShowDate
        text: Time.dateString   // precalculada en el singleton, una vez al día
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
    }
}
