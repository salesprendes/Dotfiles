import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// CPU y RAM. Click abre el monitor de sistema.
Pill {
    id: root
    interactive: true
    onClicked: Globals.toggleSysMon()

    Text {
        text: "󰻠"   // cpu
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
    }
    Text {
        text: Math.round(SysMon.cpu) + "%"
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
    Rectangle { implicitWidth: Theme.hairline; implicitHeight: Theme.dp(14); color: Theme.overlay }
    Text {
        text: "󰍛"   // ram
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
    }
    Text {
        text: Math.round(SysMon.memPercent) + "%"
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
