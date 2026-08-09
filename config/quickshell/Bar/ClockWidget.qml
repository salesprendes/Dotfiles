import QtQuick
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


    BarGlyph {
        text: "󰅐"
        color: Globals.dashboardOpen ? Theme.accent2 : Theme.accent
        animateColor: true
    }
    BarLabel {
        text: Qt.formatDateTime(Time.now, Time.clockFormat)
        font.bold: true
    }
    PillSeparator { visible: Settings.clockShowDate }
    BarLabel {
        visible: Settings.clockShowDate
        text: Time.dateString   // precalculada en el singleton, una vez al día
        font.bold: true
    }
}
