import QtQuick
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Components
import qs.Config
import qs.Services

// Bandeja del sistema (StatusNotifierItem).
Pill {
    id: root

    shown: SystemTray.items.values.length > 0

    // Script de respaldo para LANZAR la app del icono con gtk-launch cuando
    // no tiene ninguna ventana abierta (la búsqueda de ventana existente se
    // hace en QML vía WindowManager, ver openApplication). Constante
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

    // Lo único que la bandeja sabe de una app son las tres cadenas del icono;
    // emparejarlas con una ventana es cosa de quien tiene la lista de ventanas.
    function findToplevel(item) {
        return WindowManager.porPistas([item?.id, item?.title, item?.tooltipTitle])
    }

    // Clic en un icono: si su app ya tiene ventana, se TRAE al escritorio
    // actual sin robarle el foco a lo que estuvieras usando — pulsar en la
    // bandeja pone algo a la vista, no interrumpe lo que estás escribiendo.
    // Sin ventana (o sin compositor que pueda moverla), se lanza la app.
    function openApplication(item) {
        if (WindowManager.traerSinFoco(findToplevel(item)))
            return
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
                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
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
