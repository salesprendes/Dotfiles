//@ pragma UseQApplication
// Punto de entrada del shell: una barra por monitor.
// UseQApplication hace falta para los menús nativos del tray
// (SystemTray → modelData.display()).

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

    // Cierre automático al bloquear la sesión. Escucha la señal 'Lock' de
    // logind (la emite `loginctl lock-session`, que es lo que usa hypridle al
    // inactivarse/suspender), así los paneles se cierran solos sin depender de
    // que el lock_cmd ejecute `qs ipc`. Usa `gdbus monitor` (suscripción de
    // cliente, sin privilegios), no `dbus-monitor --system` que requiere root.
    // Cada señal sale como: ".../session/_X: org.freedesktop.login1.Session.Lock ()"
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
        // Si el monitor muere (reinicio de dbus, etc.) se relanza tras una pausa.
        onExited: lockRestart.restart()
    }
    Timer {
        id: lockRestart
        interval: 3000
        onTriggered: lockMonitor.running = true
    }

    // Tema "Liquid Glass": pide a Hyprland (parser Lua → `hyprctl eval`) que
    // aplique blur a los namespaces del shell mientras el tema esté activo.
    // `ignore_alpha` limita el blur a la parte translúcida (barra/tarjeta); el
    // resto de la ventana es transparente y no se esmerila, si no un popout a
    // pantalla completa frostearía toda la pantalla. Al salir se revierte
    // (blur=false). Se re-aplica al arrancar por si el tema ya venía puesto. Se
    // excluyen a propósito wallpaper/splash/carrusel.
    readonly property var glassLayers: [
        "quickshell", "qs-popout", "qs-launcher", "qs-notifcenter", "qs-clipboard",
        "qs-controlcenter", "qs-sysmon", "qs-dashboard", "qs-popups", "qs-osd-volume",
        "qs-ipconfig", "qs-wifiprompt", "qs-recording-pill", "qs-screen-capture"
    ]
    function applyGlassBlur() {
        const on = Settings.themeName === "liquid-glass"
        // qs-popups lleva además xray: sin él, la caché del blur de Hyprland
        // se realimenta con el fotograma anterior de la propia capa y, al
        // reacomodarse la pila de popups (escena estática tras no_anim), la
        // tarjeta restante se veía con el texto duplicado/emborronado durante
        // segundos. Con xray el blur muestrea solo lo que hay detrás.
        const lua = shell.glassLayers.map(n =>
            'hl.layer_rule({ name = "qs-glass-' + n + '", match = { namespace = "' + n
            + '" }, blur = ' + on + ', ignore_alpha = 0.1'
            + (n === "qs-popups" ? ', xray = true' : '') + ' })'
        ).join("; ")
        // Los popups de notificación animan su entrada/salida DESDE QML;
        // sin esta regla Hyprland superpone además su animación de layers
        // (fade al mapear/desmapear y el redimensionado de la capa), lo que
        // producía una entrada doble "forzada" y una franja gris residual
        // al desvanecer la instantánea del último búfer tras cerrar.
        const noanim = '; hl.layer_rule({ name = "qs-noanim-popups", match = '
            + '{ namespace = "qs-popups" }, no_anim = true })'
        Quickshell.execDetached(["hyprctl", "eval", lua + noanim])
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

    // Splash breve al entrar en la sesión; tapa el salto visual entre TTY y
    // escritorio mientras aparecen la barra y el fondo. Se usa solo al arrancar:
    // tras la animación se libera (active=false) para no dejar una ventana por
    // monitor residente toda la sesión.
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

    // Paneles emergentes (uno por pantalla; Globals controla su visibilidad
    // desde los widgets de la barra). Carga perezosa sin latch: se construyen
    // al abrir (Popout anima al nacer vía Component.onCompleted) y se liberan al
    // terminar la animación de cierre; `closing` mantiene el loader activo
    // mientras la ventana siga visible (openProgress > 0), así el cierre anima
    // completo antes de destruir.
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: ccL
            required property var modelData
            property bool closing: false
            activeAsync: Globals.controlCenterOpen || closing
            ControlCenter {
                modelData: ccL.modelData
                onVisibleChanged: ccL.closing = visible
            }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: ncL
            required property var modelData
            property bool closing: false
            activeAsync: Globals.notifCenterOpen || closing
            NotificationCenter {
                modelData: ncL.modelData
                onVisibleChanged: ncL.closing = visible
            }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: smL
            required property var modelData
            property bool closing: false
            activeAsync: Globals.sysMonOpen || closing
            SystemMonitor {
                modelData: smL.modelData
                onVisibleChanged: smL.closing = visible
            }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: alL
            required property var modelData
            property bool closing: false
            activeAsync: Globals.launcherOpen || closing
            AppLauncher {
                modelData: alL.modelData
                onVisibleChanged: alL.closing = visible
            }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: clipL
            required property var modelData
            property bool closing: false
            activeAsync: Globals.clipboardOpen || closing
            ClipboardPanel {
                modelData: clipL.modelData
                onVisibleChanged: clipL.closing = visible
            }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: dashL
            required property var modelData
            property bool closing: false
            activeAsync: Globals.dashboardOpen || closing
            Dashboard {
                modelData: dashL.modelData
                onVisibleChanged: dashL.closing = visible
            }
        }
    }
    // La toolbar se libera al cerrarse (patrón `closing`, como los paneles): la
    // píldora basta para controlar la grabación y ScreenCapture (singleton)
    // conserva el estado. Si se reabre mientras graba, se reconstruye al momento.
    LazyLoader {
        id: sctL
        property bool closing: false
        activeAsync: Globals.screenCaptureOpen || closing
        ScreenCaptureToolbar {
            onVisibleChanged: sctL.closing = visible
        }
    }
    // La píldora de grabación solo existe mientras se graba.
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: pillL
            required property var modelData
            active: ScreenCapture.isRecording
            RecordingPill { modelData: pillL.modelData }
        }
    }
    // Ventana de ajustes: una sola ventana real (toplevel de Hyprland). Carga
    // perezosa: no se construye hasta el primer uso y se libera al cerrarla.
    LazyLoader {
        active: Globals.settingsOpen
        Settings {}
    }
    // Modales de red: casos raros, se construyen solo al abrirse y se liberan al
    // cerrar.
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: wifiL
            required property var modelData
            active: Net.promptNetwork !== null
            WifiPasswordModal { modelData: wifiL.modelData }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: ipL
            required property var modelData
            active: Net.ipConfigOpen
            IpSettingsModal { modelData: ipL.modelData }
        }
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
