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
            id: trayItem
            required property var modelData
            implicitWidth: Theme.iconSize + 4
            implicitHeight: Theme.iconSize + 4

            Image {
                anchors.centerIn: parent
                width: Theme.iconSize
                height: Theme.iconSize
                source: trayItem.modelData?.icon ?? ""
                sourceSize.width: Theme.iconSize
                sourceSize.height: Theme.iconSize
                smooth: true
            }

            // Menú contextual del item (dbusmenu) con el estilo del tema.
            TrayMenu {
                id: menuAnchor
                menuHandle: trayItem.modelData?.menu ?? null
                anchorItem: trayItem
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        // Algunos items (p. ej. ciertos estados de Discord/Steam)
                        // no exponen acción de activación, solo menú.
                        if (trayItem.modelData.onlyMenu && trayItem.modelData.hasMenu)
                            menuAnchor.open()
                        else
                            trayItem.modelData.activate()
                    } else if (mouse.button === Qt.MiddleButton) {
                        trayItem.modelData.secondaryActivate()
                    } else if (trayItem.modelData.hasMenu) {
                        menuAnchor.open()
                    }
                }
            }
        }
    }
}
