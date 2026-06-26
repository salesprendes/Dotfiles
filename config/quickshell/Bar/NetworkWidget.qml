import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Icono de red. Click → centro de control.
Pill {
    id: root
    interactive: true
    onClicked: Globals.toggleControlCenter()

    Text {
        text: Net.icon
        color: Net.online ? Theme.accent : Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize
    }
    Text {
        visible: Net.wifiEnabled && Net.ssid !== ""
        text: Net.signal + "%"
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
