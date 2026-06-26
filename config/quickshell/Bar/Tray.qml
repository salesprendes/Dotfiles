import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs.Components
import qs.Config

// Bandeja del sistema (StatusNotifierItem).
Pill {
    id: root
    visible: Settings.showTray && SystemTray.items.values.length > 0

    Repeater {
        model: SystemTray.items

        delegate: Item {
            required property var modelData
            implicitWidth: Theme.iconSize + 4
            implicitHeight: Theme.iconSize + 4

            Image {
                anchors.centerIn: parent
                width: Theme.iconSize
                height: Theme.iconSize
                source: modelData?.icon ?? ""
                sourceSize.width: Theme.iconSize
                sourceSize.height: Theme.iconSize
                smooth: true
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton)
                        modelData.activate()
                    else if (modelData.hasMenu)
                        modelData.display(root, mouse.x, mouse.y)
                }
            }
        }
    }
}
