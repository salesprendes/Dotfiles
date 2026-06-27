import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config

// Reloj central: hora + fecha. Click → abre el Dashboard.
Pill {
    id: root
    interactive: true
    onClicked: Globals.toggleDashboard()

    SystemClock {
        id: clock
        precision: Settings.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // Formato según ajustes: 24h/12h y segundos.
    readonly property string timeFormat: (Settings.clock24h ? "HH:mm" : "hh:mm")
        + (Settings.clockShowSeconds ? ":ss" : "")
        + (Settings.clock24h ? "" : " AP")

    Text {
        text: "󰅐"
        color: Globals.dashboardOpen ? Theme.accent2 : Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
    Text {
        text: Qt.formatDateTime(clock.date, root.timeFormat)
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
        // Nombres de día/mes según el idioma de la app (en/es/ca), no el locale C.
        text: clock.date.toLocaleDateString(I18n.locale(), "ddd dd MMM")
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
