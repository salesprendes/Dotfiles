//  Fila de acciones de energía: reiniciar · suspender · apagar.
import QtQuick
import Quickshell
import qs.Modules.Greeter

Row {
    id: powerRow
    spacing: Theme.dp(14)

    // Entrada: aparece subiendo suavemente.
    opacity: 0
    property real enterY: Theme.dp(16)
    transform: Translate { y: powerRow.enterY }
    Component.onCompleted: powerIn.start()
    ParallelAnimation {
        id: powerIn
        NumberAnimation { target: powerRow; property: "opacity"; from: 0; to: 0.9; duration: 500; easing.type: Easing.OutCubic }
        NumberAnimation { target: powerRow; property: "enterY"; from: Theme.dp(16); to: 0; duration: 560; easing.type: Easing.OutCubic }
    }

    PowerButton { glyph: "󰜉"; label: "Reiniciar"; cmd: ["systemctl", "reboot"];   spin: true }
    PowerButton { glyph: "󰤄"; label: "Suspender"; cmd: ["systemctl", "suspend"] }
    PowerButton { glyph: "󰐥"; label: "Apagar";    cmd: ["systemctl", "poweroff"] }
}
