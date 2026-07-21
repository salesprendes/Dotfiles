import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Components
import qs.Config

// Bandeja del sistema (StatusNotifierItem).
Pill {
    id: root

    visible: Settings.showTray && SystemTray.items.values.length > 0

    // Script de respaldo para LANZAR la app del icono con gtk-launch cuando
    // no tiene ninguna ventana abierta (la búsqueda de ventana existente se
    // hace en QML vía Hyprland.toplevels, ver openApplication). Constante
    // para no reconstruirla en un binding por cada icono.
    readonly property string launchScript:
        "for raw in \"$@\"; do " +
        "  key=$(printf '%s' \"$raw\" | tr '[:upper:]' '[:lower:]' | sed 's/\\.desktop$//; s/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'); " +
        "  test -n \"$key\" || continue; " +
        "  gtk-launch \"$key\" >/dev/null 2>&1 && exit 0; " +
        "  gtk-launch \"$key.desktop\" >/dev/null 2>&1 && exit 0; " +
        "done; exit 0"

    // Un único Process compartido; el comando se compone al hacer clic.
    Process { id: appLauncher }

    // Empareja un icono de la bandeja con su ventana de Hyprland: claves del
    // item (id/título/tooltip, normalizadas) contra clase/clase inicial/
    // título de cada toplevel, en ambos sentidos (igual que hacía el jq).
    function findToplevel(item) {
        const keys = [item?.id, item?.title, item?.tooltipTitle]
            .map(k => String(k || "").toLowerCase().replace(/\.desktop$/, "").trim())
            .filter(k => k !== "")
        const list = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (let i = 0; i < list.length; i++) {
            const tl = list[i]
            if (!tl) continue
            const ipc = tl.lastIpcObject
            const cls = String(ipc?.class || "").toLowerCase()
            const icls = String(ipc?.initialClass || "").toLowerCase()
            const title = String(tl.title || "").toLowerCase()
            for (let j = 0; j < keys.length; j++) {
                const k = keys[j]
                if ((cls !== "" && (cls.indexOf(k) !== -1 || k.indexOf(cls) !== -1))
                    || (icls !== "" && (icls.indexOf(k) !== -1 || k.indexOf(icls) !== -1))
                    || (title !== "" && title.indexOf(k) !== -1))
                    return tl
            }
        }
        return null
    }

    // Clic en un icono: si su app ya tiene ventana, tráela — si está en otro
    // workspace se mueve al ACTUAL y se enfoca (mismo patrón que la ventana
    // de Ajustes en summonOrClose; este Hyprland va en modo Lua, la sintaxis
    // clásica de dispatchers no vale). Sin ventana, se lanza la app.
    function openApplication(item) {
        const tl = findToplevel(item)
        const ws = Hyprland.focusedWorkspace
        if (tl && ws) {
            let addr = String(tl.address)
            if (addr.indexOf("0x") !== 0) addr = "0x" + addr
            // Solo se TRAE la ventana al workspace actual, sin robarle el
            // foco a la que estabas usando. window.move enfoca a la movida
            // por defecto (y su variante silenciosa no está documentada en
            // la API Lua), así que tras mover se DEVUELVE el foco a la
            // ventana que lo tenía.
            const here = tl.workspace && tl.workspace.id === ws.id
            if (!here) {
                const prev = Hyprland.activeToplevel
                let prevAddr = prev ? String(prev.address) : ""
                if (prevAddr !== "" && prevAddr.indexOf("0x") !== 0)
                    prevAddr = "0x" + prevAddr
                if (Hyprland.usingLua) {
                    Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + ws.id
                        + ', window = "address:' + addr + '" })')
                    if (prevAddr !== "" && prevAddr !== addr)
                        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + prevAddr + '" })')
                } else {
                    Hyprland.dispatch("movetoworkspacesilent " + ws.id + ",address:" + addr)
                }
            }
            return
        }
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
                scale: trayMa.containsMouse ? 1.2 : 1
                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
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
