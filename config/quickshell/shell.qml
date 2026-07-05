//@ pragma UseQApplication
//  ╔══════════════════════════════════════════════════════════╗
//  ║   Quickshell · Tema "Storm"                                ║
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
import qs.Modules.Carousel
import qs.Panels
import qs.Services

ShellRoot {
    id: shell

    readonly property int startupScreenCount: Math.max(1, Quickshell.screens.length)
    property int startupBackdropReadyCount: 0
    property int startupBarReadyCount: 0
    property bool startupCarouselReady: false
    property bool startupWallpaperScanSeen: Wallpaper.scanning
    property bool startupWallpaperReady: false

    readonly property real startupLoadProgress: Math.min(1,
        0.08
        + (Settings._loaded ? 0.16 : 0)
        + (startupWallpaperReady ? 0.18 : 0)
        + Math.min(1, startupBackdropReadyCount / startupScreenCount) * 0.22
        + (startupCarouselReady ? 0.08 : 0)
        + Math.min(1, startupBarReadyCount / startupScreenCount) * 0.28)
    readonly property bool startupLoadReady: startupLoadProgress >= 0.995

    function updateStartupWallpaperReady() {
        if (Wallpaper.scanning) {
            startupWallpaperScanSeen = true
            startupWallpaperReady = false
            return
        }
        if (startupWallpaperScanSeen || Wallpaper.list.length > 0)
            startupWallpaperReady = true
    }

    Connections {
        target: Wallpaper
        function onScanningChanged() { shell.updateStartupWallpaperReady() }
        function onListChanged() { shell.updateStartupWallpaperReady() }
        function onCurrentChanged() { shell.updateStartupWallpaperReady() }
    }

    Timer {
        interval: 80
        running: true
        repeat: false
        onTriggered: shell.updateStartupWallpaperReady()
    }

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
        function capture(): void { ScreenCapture.openToolbar(false) }
        function record(): void { ScreenCapture.openToolbar(true) }
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
                // Suspensión/reanudación: por este mismo bus logind emite
                // Manager.PrepareForSleep(true) antes de dormir y (false) al
                // despertar. Lo reenviamos al coordinador central Resume, al que
                // se suscriben los servicios que necesitan recuperarse tras el
                // resume (WiFi, clima, brillo, monitor de sistema, pantallas…).
                else if (line.indexOf("PrepareForSleep") !== -1)
                    Resume.notify(line.indexOf("true") !== -1)
            }
        }
        // Si el monitor muere (reinicio de dbus, etc.) se relanza tras una
        // pausa. Por evento: antes un timer sondeaba cada 3 s para siempre.
        onExited: lockRestart.restart()
    }
    Timer {
        id: lockRestart
        interval: 3000
        onTriggered: lockMonitor.running = true
    }

    // ── Tema "Liquid Glass": blur del compositor en las capas del shell ──────
    //  Mientras el tema "liquid-glass" esté activo se pide a Hyprland (parser
    //  Lua → `hyprctl eval`, igual que Displays con los monitores) que aplique
    //  blur a los namespaces del shell. `ignore_alpha` enmascara el blur SOLO a
    //  la parte translúcida (barra/tarjeta); el resto de la ventana, que es
    //  transparente, NO se esmerila (si no, un popout a pantalla completa
    //  frostearía toda la pantalla). Al salir del tema se revierte (blur=false).
    //  Reversible, en vivo y sin editar los .lua de Hyprland; se re-aplica al
    //  arrancar por si el tema ya venía seleccionado. Se excluyen a propósito
    //  wallpaper/splash/carrusel.
    readonly property var glassLayers: [
        "quickshell", "qs-popout", "qs-launcher", "qs-notifcenter", "qs-clipboard",
        "qs-controlcenter", "qs-sysmon", "qs-dashboard", "qs-popups", "qs-osd-volume",
        "qs-ipconfig", "qs-wifiprompt", "qs-recording-pill", "qs-screen-capture"
    ]
    function applyGlassBlur() {
        const on = Settings.themeName === "liquid-glass"
        const lua = shell.glassLayers.map(n =>
            'hl.layer_rule({ name = "qs-glass-' + n + '", match = { namespace = "' + n
            + '" }, blur = ' + on + ', ignore_alpha = 0.1 })'
        ).join("; ")
        Quickshell.execDetached(["hyprctl", "eval", lua])
    }
    Component.onCompleted: applyGlassBlur()
    Connections {
        target: Settings
        function onThemeNameChanged() { shell.applyGlassBlur() }
    }

    // Fondo de pantalla: una ventana por monitor en la capa Background,
    // con la transición de imagen gestionada desde QML.
    Variants {
        model: Quickshell.screens
        delegate: Backdrop {
            Component.onCompleted: shell.startupBackdropReadyCount++
        }
    }

    // Plugin autocontenido: carrusel para elegir fondo (Super+W → IPC
    // "carousel"). No modifica ningún componente; solo se instancia aquí.
    WallpaperCarousel {
        Component.onCompleted: shell.startupCarouselReady = true
    }

    // Splash breve al entrar en la sesión; oculta el salto visual entre TTY
    // y escritorio mientras terminan de aparecer la barra y el fondo.
    //
    // Solo se usa una vez al arrancar: tras la animación se libera (active=false)
    // para no dejar una ventana por monitor residente el resto de la sesión.
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: splashL
            required property var modelData
            active: true
            StartupSplash {
                modelData: splashL.modelData
                loadProgress: shell.startupLoadProgress
                ready: shell.startupLoadReady
                onFinished: splashL.active = false
            }
        }
    }

    // Una instancia de Bar por pantalla conectada.
    Variants {
        model: Quickshell.screens
        delegate: Bar {
            Component.onCompleted: shell.startupBarReadyCount++
        }
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
    LazyLoader {
        active: Globals.screenCaptureOpen || ScreenCapture.isRecording
        ScreenCaptureToolbar {}
    }
    Variants {
        model: Quickshell.screens
        delegate: RecordingPill {}
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
        delegate: IpSettingsModal {}
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
