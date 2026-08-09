import QtQuick
import qs.Components
import qs.Config
import qs.Services

// CPU y RAM. Click abre el monitor de sistema.
Pill {
    id: root
    interactive: true
    active: Globals.sysMonOpen
    onClicked: Globals.toggleSysMon()

    // Los porcentajes avisan por color al acercarse al límite (90% ámbar,
    // 97% rojo), sin cambiar de tamaño ni mover la píldora.
    function loadColor(pct) {
        return pct >= 97 ? Theme.red
             : pct >= 90 ? Theme.yellow
             : Theme.fgDim
    }

    BarGlyph { text: "󰻠"; color: Theme.accent }   // cpu
    BarLabel {
        text: Math.round(SysMon.cpu) + "%"
        color: root.loadColor(SysMon.cpu)
        animateColor: true
    }
    PillSeparator {}
    BarGlyph { text: "󰍛"; color: Theme.accent }   // ram
    BarLabel {
        text: Math.round(SysMon.memPercent) + "%"
        color: root.loadColor(SysMon.memPercent)
        animateColor: true
    }
}
