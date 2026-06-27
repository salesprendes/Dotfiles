//@ pragma UseQApplication
//  ╔══════════════════════════════════════════════════════════╗
//  ║   Quickshell · Tema "Storm"  (Tokyo Night × Omarchy)       ║
//  ║   Punto de entrada — una barra por cada monitor.           ║
//  ╚══════════════════════════════════════════════════════════╝
//  UseQApplication: necesario para los menús nativos del tray
//  (SystemTray → modelData.display()).

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Background
import qs.Bar
import qs.Config
import qs.Panels

ShellRoot {
    // Control por IPC / atajos de teclado:
    //   qs ipc call panel controlcenter | notifications | clipboard | dnd | close
    IpcHandler {
        target: "panel"
        function controlcenter(): void { Globals.toggleControlCenter() }
        function notifications(): void { Globals.toggleNotifCenter() }
        function sysmon(): void { Globals.toggleSysMon() }
        function launcher(): void { Globals.toggleLauncher() }
        function clipboard(): void { Globals.toggleClipboard() }
        function dashboard(): void { Globals.toggleDashboard() }
        function settings(): void { Globals.toggleSettings() }
        function dnd(): void { Globals.dnd = !Globals.dnd }
        function caffeine(): void { Globals.caffeine = !Globals.caffeine }
        function close(): void { Globals.closeAll() }
    }

    // ── Cierre automático al bloquear la sesión ──────────────────
    //  Escucha la señal 'Lock' de logind (la emite `loginctl lock-session`,
    //  que es lo que usa hypridle al inactivarse/suspender). Así Quickshell
    //  cierra sus paneles por sí mismo, sin depender de que el lock_cmd
    //  ejecute `qs ipc` — pase como pase el bloqueo, los popouts se cierran.
    //  Usa `gdbus monitor` (suscripción normal de cliente, permitida sin
    //  privilegios) — NO `dbus-monitor --system`, que requiere ser root.
    //  Cada señal sale como: ".../session/_X: org.freedesktop.login1.Session.Lock ()"
    Process {
        id: lockMonitor
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("Session.Lock") !== -1)
                    Globals.closeAll()
            }
        }
    }
    // Vigilante: si dbus-monitor muriera, lo relanza.
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: if (!lockMonitor.running) lockMonitor.running = true
    }

    // Fondo de pantalla (uno por monitor, capa Background). Lo dibuja
    // Quickshell mismo con cross-fade; no usa swww ni hyprpaper.
    Variants {
        model: Quickshell.screens
        delegate: Backdrop {}
    }

    // Una instancia de Bar por pantalla conectada.
    Variants {
        model: Quickshell.screens
        delegate: Bar {}
    }

    // Paneles emergentes (uno por pantalla; su visibilidad la controla
    // el singleton Globals desde los widgets de la barra).
    //
    // Carga perezosa con "latch": no se construyen al arrancar, solo la
    // primera vez que se abren, y luego permanecen cargados para conservar
    // las animaciones de apertura (si se destruyeran al cerrar, cada
    // apertura nacería con shown=true y no animaría).
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: ccL
            required property var modelData
            property bool loaded: false
            active: Globals.controlCenterOpen || loaded
            onActiveChanged: if (active) loaded = true
            ControlCenter { modelData: ccL.modelData }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: ncL
            required property var modelData
            property bool loaded: false
            active: Globals.notifCenterOpen || loaded
            onActiveChanged: if (active) loaded = true
            NotificationCenter { modelData: ncL.modelData }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: smL
            required property var modelData
            property bool loaded: false
            activeAsync: Globals.sysMonOpen || loaded
            onActiveChanged: if (active) loaded = true
            SystemMonitor { modelData: smL.modelData }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: alL
            required property var modelData
            property bool loaded: false
            activeAsync: Globals.launcherOpen || loaded
            onActiveChanged: if (active) loaded = true
            AppLauncher { modelData: alL.modelData }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: clipL
            required property var modelData
            property bool loaded: false
            active: Globals.clipboardOpen || loaded
            onActiveChanged: if (active) loaded = true
            ClipboardPanel { modelData: clipL.modelData }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: dashL
            required property var modelData
            property bool loaded: false
            active: Globals.dashboardOpen || loaded
            onActiveChanged: if (active) loaded = true
            Dashboard { modelData: dashL.modelData }
        }
    }
    // Ventana de ajustes: una sola ventana real (toplevel de Hyprland).
    // Carga perezosa: no se construye (937 líneas) hasta el primer
    // uso, y se libera al cerrarla.
    LazyLoader {
        active: Globals.settingsOpen
        Settings {}
    }
    Variants {
        model: Quickshell.screens
        delegate: WifiPasswordModal {}
    }
    Variants {
        model: Quickshell.screens
        delegate: VolumeOSD {}
    }
    Variants {
        model: Quickshell.screens
        delegate: NotificationPopups {}
    }
}
