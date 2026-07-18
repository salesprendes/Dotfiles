import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Bar
import qs.Config

// Barra superior flotante: bordes redondeados y fondo translúcido.
PanelWindow {
    id: bar

    // modelData lo inyecta Variants: es el QsScreen de este monitor.
    property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: Theme.barTopMargin
        left: Theme.barMargin
        right: Theme.barMargin
    }

    implicitHeight: Theme.barHeight
    color: "transparent"

    // Reserva el espacio justo de la barra + su margen.
    exclusiveZone: Theme.barHeight + Theme.barTopMargin

    // Fondo de la barra
    Rectangle {
        anchors.fill: parent
        radius: Theme.barRadius
        color: Theme.barBg
        border.width: Theme.hairline
        border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.45)

        // Izquierda: workspaces + ventana activa
        RowLayout {
            anchors {
                left: parent.left
                leftMargin: Theme.gap
                verticalCenter: parent.verticalCenter
            }
            spacing: Theme.gap

            LauncherWidget {}
            Workspaces { screen: bar.screen }
            ActiveWindow {}
        }

        // Centro: reproductor (si hay música) + reloj
        RowLayout {
            anchors.centerIn: parent
            spacing: Theme.gap

            MediaWidget {}
            ClockWidget {}
        }

        // Derecha: bandeja + volumen + batería
        RowLayout {
            anchors {
                right: parent.right
                rightMargin: Theme.gap
                verticalCenter: parent.verticalCenter
            }
            spacing: Theme.gap

            Tray {}
            SysMonWidget { visible: Settings.showSysmon }
            ConnectivityAudioWidget {}
            PowerWidget {}
            CaffeineWidget { visible: Settings.showCaffeine }
            BatteryWidget {}
            ClipboardWidget { visible: Settings.showClipboard }
            NotificationsWidget { visible: Settings.showNotifications }
        }
    }
}