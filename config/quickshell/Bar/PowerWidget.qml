import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Perfil de energía (power-profiles-daemon) en la barra. Click izquierdo
// cicla al siguiente perfil; rueda también cicla; click derecho abre el
// Centro de control. Siempre visible.
Pill {
    id: root
    spacing: Theme.space6
    interactive: true
    hoverHighlight: true

    // Oculto si no está instalado power-profiles-daemon o si se desactiva
    // en Ajustes › Widgets.
    visible: Power.available && Settings.showPowerProfile

    onClicked: Power.cycle()
    onRightClicked: Globals.toggleControlCenter()
    onScrolled: (dy) => Power.cycle()

    Text {
        text: Power.icon
        color: Power.color
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize
    }
}
