import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Actualizaciones pendientes. Con paquetes esperando se enciende en acento y
// muestra cuántos; sin nada pendiente queda apagado y discreto.
//
// Click abre el terminal con la actualización en marcha; click derecho vuelve
// a comprobar sin esperar al temporizador de media hora.
IconPill {
    id: root

    shown: Updates.available
    interactive: true
    icon: Updates.checking ? "󰑐" : (Updates.count > 0 ? "󰚰" : "󰂪")
    iconColor: Updates.count > 0 ? Theme.accent : Theme.fgMuted
    animateColor: true
    badgeCount: Updates.count
    badgeColor: Theme.accent

    onClicked: {
        if (Updates.count > 0)
            Updates.runUpdate()
        else
            Updates.refresh()
    }
    onRightClicked: Updates.refresh()
}
