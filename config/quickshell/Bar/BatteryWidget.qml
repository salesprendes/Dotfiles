import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Batería (estado en Services/Battery.qml). Oculta en equipos sin batería.
Pill {
    id: root

    // Solo en portátiles (con batería) y si está activado en ajustes.
    shown: Battery.present

    readonly property color levelColor:
        Battery.percent <= 15 ? Theme.red
      : Battery.percent <= 35 ? Theme.yellow
      : Theme.green

    BarGlyph {
        text: Battery.charging ? ""
             : Battery.percent <= 15 ? ""
             : Battery.percent <= 35 ? ""
             : Battery.percent <= 60 ? ""
             : Battery.percent <= 85 ? ""
             : ""
        color: Battery.charging ? Theme.cyan : root.levelColor
    }
    // El porcentaje hereda el color de nivel cuando queda poca batería, para
    // que el aviso se lea sin mirar el icono.
    BarLabel {
        text: Battery.percent + "%"
        color: !Battery.charging && Battery.percent <= 35 ? root.levelColor
             : Theme.fgDim
        animateColor: true
    }
}
