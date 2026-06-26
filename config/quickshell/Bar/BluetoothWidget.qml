import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Icono de Bluetooth. Oculto si no hay adaptador.
// Click → centro de control · click derecho → on/off.
Pill {
    id: root
    interactive: true
    visible: BT.available
    onClicked: Globals.toggleControlCenter()
    onRightClicked: BT.toggle()

    Text {
        text: BT.icon
        color: BT.enabled ? Theme.accent2 : Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize
    }
    Text {
        visible: BT.connectedCount > 0
        text: BT.connectedCount
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
