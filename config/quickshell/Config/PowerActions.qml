pragma Singleton

import QtQuick
import Quickshell
import qs.Config

// Acciones de energía: bloquear, suspender, reiniciar y apagar. El modelo
// (icono, etiqueta traducida, color) y el ejecutor viven juntos porque los tres
// sitios que presentan el menú —lanzador, centro de control y buscador— usan
// siempre las dos mitades a la vez.
Singleton {
    id: root

    readonly property var model: [
        { "ic": "󰍁", "label": I18n.tr("Lock"),      "action": "lock",     "col": Theme.accent },
        { "ic": "󰤄", "label": I18n.tr("Suspend"),   "action": "suspend",  "col": Theme.accent },
        { "ic": "󰜉", "label": I18n.tr("Restart"),   "action": "reboot",   "col": Theme.accent },
        { "ic": "󰐥", "label": I18n.tr("Shut down"), "action": "poweroff", "col": Theme.red }
    ]

    // El bloqueo lo sirve el propio shell con WlSessionLock (Services/Lock.qml),
    // así que comparte tema, paleta e idioma con todo lo demás y Wayland le da
    // el foco en exclusiva por protocolo.
    //
    // Se pide por señal en vez de llamar a Services.Lock: Config es la capa de
    // abajo y no puede importar qs.Services, que ya importa qs.Config. El
    // servicio se suscribe y shell.qml lo mantiene vivo.
    signal lockRequested()

    // Cierra antes lo que haya abierto: una hoja de la isla o un panel debajo
    // de la pantalla de bloqueo no lo ve nadie, pero sigue ahí al volver.
    function run(action) {
        Globals.closeAll()
        if (action === "lock")
            root.lockRequested()
        else if (action === "suspend")
            Quickshell.execDetached(["systemctl", "suspend"])
        else if (action === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"])
        else if (action === "poweroff")
            Quickshell.execDetached(["systemctl", "poweroff"])
    }
}
