//  Fila de acciones de energía: reiniciar · suspender · apagar.
import QtQuick
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

    PowerButton { glyph: "󰜉"; label: I18n.tr("Reiniciar", "Restart"); cmd: ["systemctl", "reboot"];   spin: true }
    PowerButton { glyph: "󰤄"; label: I18n.tr("Suspender", "Suspend"); cmd: ["systemctl", "suspend"] }
    PowerButton { glyph: "󰐥"; label: I18n.tr("Apagar", "Shut down");   cmd: ["systemctl", "poweroff"] }
}
