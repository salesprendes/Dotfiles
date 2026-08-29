import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Toggle de luz nocturna (hyprsunset). Ámbar cuando el filtro está puesto,
// atenuado cuando no. La rueda sube y baja la temperatura en pasos de 250 K
// sin tener que abrir ningún panel.
IconPill {
    id: root

    shown: NightLight.available
    interactive: true
    icon: NightLight.enabled ? "󰖔" : "󰖙"
    iconColor: NightLight.enabled ? Theme.orange : Theme.fgMuted
    animateColor: true

    onClicked: NightLight.toggle()

    // Ajuste fino: solo tiene sentido con el filtro puesto — con la luz
    // nocturna apagada la pantalla ya está en su temperatura neutra y
    // "subirla" no significa nada.
    onScrolled: (dy) => {
        if (!NightLight.enabled)
            return
        const step = dy > 0 ? 250 : -250
        // Tope superior en 6499 K y no en 6500: 6500 ES "apagado", así que
        // llegar ahí rodando apagaría el filtro por sorpresa en vez de dejarlo
        // en su punto más suave.
        const next = Math.max(2500, Math.min(6499, (NightLight.temperature || 4000) + step))
        NightLight.nightTemperature = next
        NightLight.apply(next)
    }
}
