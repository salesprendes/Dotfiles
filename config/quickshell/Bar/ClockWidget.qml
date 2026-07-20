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
    active: Globals.dashboardOpen
    onClicked: Globals.toggleDashboard()


    Text {
        text: "󰅐"
        color: Globals.dashboardOpen ? Theme.accent2 : Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
    Text {
        text: Qt.formatDateTime(Time.now, Time.clockFormat)
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
