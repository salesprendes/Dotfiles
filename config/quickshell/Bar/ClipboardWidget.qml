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

        Rectangle {
            visible: Clipboard.count > 0
            anchors { right: parent.right; top: parent.top; rightMargin: -Theme.dp(5); topMargin: -Theme.dp(5) }
            width: Theme.dp(14); height: Theme.dp(14); radius: height / 2
            color: Theme.accent
            Text {
                anchors.centerIn: parent
                text: Clipboard.count > 9 ? "9+" : Clipboard.count
                color: Theme.bg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(9)
                font.bold: true
            }
        }
    }
}
