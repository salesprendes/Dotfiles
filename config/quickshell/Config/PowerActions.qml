pragma Singleton

import QtQuick
import Quickshell
import qs.Config

// Las acciones de energía: bloquear, suspender, reiniciar y apagar. El MODELO
// (icono, etiqueta traducida, color) y el EJECUTOR viven aquí juntos.
//
// ── POR QUÉ JUNTOS ──────────────────────────────────────────────────────────
// Estuvieron partidos: el modelo aquí y run() en Globals, con tres comentarios
// repartidos por el árbol cuyo único trabajo era mandar al lector de un fichero
// al otro. Y los tres sitios que presentan el menú de energía —el lanzador, el
// centro de control y el buscador— usaban las dos mitades a la vez, con dos
// líneas de por medio:
//
//     model: PowerActions.model
//     ...
//     onClicked: Globals.runPowerAction(modelData.action)
//
// Un concepto en dos ficheros que nadie importa por separado no son dos
// ficheros: es uno partido. Y sacarlo de Globals le quita a ese singleton una
// razón entera para cambiar, que no tenía nada que ver con los paneles.
Singleton {
    id: root

    readonly property var model: [
        { "ic": "󰍁", "label": I18n.tr("Lock"),      "action": "lock",     "col": Theme.accent },
        { "ic": "󰤄", "label": I18n.tr("Suspend"),   "action": "suspend",  "col": Theme.accent },
        { "ic": "󰜉", "label": I18n.tr("Restart"),   "action": "reboot",   "col": Theme.accent },
        { "ic": "󰐥", "label": I18n.tr("Shut down"), "action": "poweroff", "col": Theme.red }
    ]

    // El bloqueo ya no sale a hyprlock: lo sirve el propio shell con
    // WlSessionLock (ver Services/Lock.qml), así que comparte tema, paleta e
    // idioma con todo lo demás. Y desaparece la pausa de 0,25 s que hacía
    // falta antes para que el popout soltara el teclado exclusivo a tiempo:
    // ahora el bloqueo es una capa del mismo proceso y Wayland le da el foco
    // en exclusiva por protocolo.
    //
    // Se pide por SEÑAL y no llamando a Services.Lock: Config es la capa de
    // abajo y no debe importar qs.Services (Services ya importa qs.Config; el
    // par cruzado es una dependencia circular entre directorios del módulo).
    // El servicio se suscribe; shell.qml lo mantiene vivo.
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
