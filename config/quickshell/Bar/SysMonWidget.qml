import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// CPU y RAM. Click abre el monitor de sistema.
Pill {
    id: root
    interactive: true
    active: Globals.sysMonOpen
    onClicked: Globals.toggleSysMon()

    Text {
        text: "󰻠"   // cpu
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
    }
    // Los porcentajes avisan por color al acercarse al límite (90% ámbar,
    // 97% rojo), sin cambiar de tamaño ni mover la píldora.
    Text {
        text: Math.round(SysMon.cpu) + "%"
        color: SysMon.cpu >= 97 ? Theme.red
             : SysMon.cpu >= 90 ? Theme.yellow
             : Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
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
        color: SysMon.memPercent >= 97 ? Theme.red
             : SysMon.memPercent >= 90 ? Theme.yellow
             : Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
}
