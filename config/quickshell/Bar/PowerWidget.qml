import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Perfil de energía (power-profiles-daemon). Click o rueda ciclan al
// siguiente perfil; click derecho abre el Centro de control.
Pill {
    interactive: true

    // Oculto si falta power-profiles-daemon o se desactiva en Ajustes.
    visible: Power.available && Settings.showPowerProfile

    onClicked: Power.cycle()
    onRightClicked: Globals.toggleControlCenter()
    onScrolled: (dy) => Power.cycle()

    BarGlyph { text: Power.icon; color: Power.color }
}
