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

    // Script para abrir la app del icono: enfoca su ventana si ya existe
    // (hyprctl+jq) o la lanza con gtk-launch. Constante para no reconstruirla
    // en un binding por cada icono.
    readonly property string launchScript:
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
        "done; exit 0"

    // Un único Process compartido; el comando se compone al hacer clic.
    Process { id: appLauncher }

    function openApplication(item) {
        appLauncher.running = false
        appLauncher.command = ["sh", "-c", root.launchScript, "tray-open",
            item?.id ?? "", item?.title ?? "", item?.tooltipTitle ?? ""]
        appLauncher.running = true
    }

    // Un único menú contextual compartido por todos los iconos, creado al
    // primer uso y liberado al cerrarse. Así evitamos un TrayMenu residente
    // por icono y monitor (cada uno con su suscripción dbusmenu y sus filas
    // construidas aunque nunca se abriera).
    Loader {
        id: menuLoader
        active: false
        property Item menuAnchor: null
        property var menuHandle: null
        sourceComponent: TrayMenu {
            anchorItem: menuLoader.menuAnchor
            menuHandle: menuLoader.menuHandle
            // Al cerrarse suelta el handle (cae la suscripción dbusmenu) y
            // destruye el popup. callLater para no destruir el emisor dentro
            // de su propio handler.
            onVisibleChanged: if (!visible)
                Qt.callLater(() => { menuLoader.menuHandle = null; menuLoader.active = false })
        }
    }

    function openMenuFor(item) {
        menuLoader.menuAnchor = item
        menuLoader.menuHandle = item.modelData.menu
        menuLoader.active = true
        menuLoader.item.open()
    }

    Repeater {
        model: SystemTray.items

        delegate: Item {
            id: trayItem
            required property var modelData
            implicitWidth: Theme.barIconSize + 4
            implicitHeight: Theme.barIconSize + 4

            // Si el icono desaparece con su menú abierto, ciérralo para no
            // dejar el popup anclado a un item destruido.
            Component.onDestruction: {
                if (menuLoader.menuAnchor === trayItem) {
                    menuLoader.menuAnchor = null
                    menuLoader.menuHandle = null
                    menuLoader.active = false
                }
            }

            function activatePrimary(force) {
                if (trayItem.modelData.onlyMenu && !force)
                    root.openApplication(trayItem.modelData)
                else
                    trayItem.modelData.activate()
            }

            Image {
                anchors.centerIn: parent
                width: Theme.barIconSize
                height: Theme.barIconSize
                source: trayItem.modelData?.icon ?? ""
                sourceSize.width: Theme.barIconSize
                sourceSize.height: Theme.barIconSize
                smooth: true
            }

            MouseArea {
                id: trayMa
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        root.openApplication(trayItem.modelData)
                    } else if (mouse.button === Qt.MiddleButton) {
                        trayItem.modelData.secondaryActivate()
                    } else if (trayItem.modelData.hasMenu) {
                        root.openMenuFor(trayItem)
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
