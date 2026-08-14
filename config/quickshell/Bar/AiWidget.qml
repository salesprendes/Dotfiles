import QtQuick
import qs.Components
import qs.Config
import qs.Modules.IA

// Abre el asistente IA (Modules/IA). Con acento mientras el panel está
// abierto o el modelo aún está respondiendo — así la barra dice "hay una
// respuesta en camino" aunque cierres el panel.
IconPill {
    id: root
    interactive: true
    icon: "󱙺"
    iconColor: Globals.aiOpen || AiService.busy ? Theme.accent : Theme.fgMuted
    animateColor: true
    onClicked: Globals.toggleAi()
}
