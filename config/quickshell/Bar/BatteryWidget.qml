import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.Components
import qs.Config

// Batería (UPower). Oculta en equipos sin batería.
Pill {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev?.isLaptopBattery ?? false
    readonly property int percent: Math.round(dev?.percentage ?? 0)
    readonly property bool charging: (dev?.state ?? 0) === UPowerDeviceState.Charging
                                     || (dev?.state ?? 0) === UPowerDeviceState.PendingCharge

    // Solo en portátiles (con batería) y si está activado en ajustes.
    visible: present && Settings.showBattery

    readonly property color levelColor:
        percent <= 15 ? Theme.red
      : percent <= 35 ? Theme.yellow
      : Theme.green

    Text {
        text: root.charging ? ""
             : root.percent <= 15 ? ""
             : root.percent <= 35 ? ""
             : root.percent <= 60 ? ""
             : root.percent <= 85 ? ""
             : ""
        color: root.charging ? Theme.cyan : root.levelColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
    }
    Text {
        text: root.percent + "%"
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
