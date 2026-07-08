import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Boton de historial de portapapeles.
Pill {
    id: root
    interactive: true
    onClicked: Globals.toggleClipboard()
    onRightClicked: Clipboard.refresh()

    Item {
        implicitWidth: Theme.iconSize + 2
        implicitHeight: Theme.iconSize + 2

        Text {
            anchors.centerIn: parent
            text: "󰅌"
            color: Globals.clipboardOpen ? Theme.accent : (Clipboard.available ? Theme.fgDim : Theme.fgMuted)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
        }

        CountBadge {
            count: Clipboard.count
            badgeColor: Theme.accent
            anchors { right: parent.right; top: parent.top; rightMargin: -Theme.space4; topMargin: -Theme.space4 }
        }
    }
}
