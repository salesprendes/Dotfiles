import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Distribución de teclado activa. Solo aparece si hay MÁS DE UNA configurada:
// con una sola, la etiqueta sería un adorno que nunca cambia y que solo
// consume sitio en la barra.
//
// Click rota a la siguiente; la rueda hace lo mismo (es el gesto que ya usan
// los workspaces en esta barra).
Pill {
    id: root

    shown: Keyboard.available && Keyboard.multiple
    interactive: true
    onClicked: Keyboard.cycle()
    onScrolled: Keyboard.cycle()

    BarGlyph { text: "󰌌"; color: Theme.fgMuted }
    BarLabel {
        text: Keyboard.short
        color: Theme.fgDim
        font.bold: true
    }
}
