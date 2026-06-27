import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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

            Process {
                id: appLauncher
                running: false
                command: ["sh", "-c",
                    "keys=''; " +
                    "for raw in \"$@\"; do " +
                    "  key=$(printf '%s' \"$raw\" | tr '[:upper:]' '[:lower:]' | sed 's/\\.desktop$//; s/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'); " +
                    "  test -n \"$key\" && keys=\"$keys $key\"; " +
                    "done; " +
                    "if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then " +
                    "  for key in $keys; do " +
                    "    addr=$(hyprctl clients -j 2>/dev/null | jq -r --arg k \"$key\" 'map(select((.class//\"\"|ascii_downcase|contains($k)) or (.initialClass//\"\"|ascii_downcase|contains($k)) or (.title//\"\"|ascii_downcase|contains($k)) or ($k|contains(.class//\"\"|ascii_downcase)) or ($k|contains(.initialClass//\"\"|ascii_downcase)))) | .[0].address // empty'); " +
                    "    test -n \"$addr\" && hyprctl dispatch focuswindow \"address:$addr\" >/dev/null 2>&1 && exit 0; " +
                    "  done; " +
                    "fi; " +
                    "for key in $keys; do " +
                    "  gtk-launch \"$key\" >/dev/null 2>&1 && exit 0; " +
                    "  gtk-launch \"$key.desktop\" >/dev/null 2>&1 && exit 0; " +
                    "done; exit 0",
                    "tray-open",
                    trayItem.modelData?.id ?? "",
                    trayItem.modelData?.title ?? "",
                    trayItem.modelData?.tooltipTitle ?? ""]
            }

            function openApplication() {
                appLauncher.running = false
                appLauncher.running = true
            }
            function activatePrimary(force) {
                if (trayItem.modelData.onlyMenu && !force)
                    trayItem.openApplication()
                else
                    trayItem.modelData.activate()
            }

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
                id: trayMa
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        trayItem.openApplication()
                    } else if (mouse.button === Qt.MiddleButton) {
                        trayItem.modelData.secondaryActivate()
                    } else if (trayItem.modelData.hasMenu) {
                        menuAnchor.open()
                    }
                }
                onDoubleClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton)
                        trayItem.activatePrimary(true)
                }
            }
        }
    }
}
