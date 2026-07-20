pragma Singleton

import QtQuick
import Quickshell
import qs.Config

// Modelo compartido de las acciones de energía (bloquear, suspender, reiniciar
// y apagar): icono, etiqueta traducida, clave para Globals.runPowerAction y
// color. El centro de control y el lanzador lo presentan cada uno a su manera;
// aquí solo vive el modelo.
Singleton {
    readonly property var model: [
        { "ic": "󰍁", "label": I18n.tr("Lock"),      "action": "lock",     "col": Theme.accent },
        { "ic": "󰤄", "label": I18n.tr("Suspend"),   "action": "suspend",  "col": Theme.accent },
        { "ic": "󰜉", "label": I18n.tr("Restart"),   "action": "reboot",   "col": Theme.accent },
        { "ic": "󰐥", "label": I18n.tr("Shut down"), "action": "poweroff", "col": Theme.red }
    ]
}
