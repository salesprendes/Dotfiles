//@ pragma Env QV4_FORCE_INTERPRETER = 1
// Punto de entrada del shell: una barra por monitor.
// Se fuerza el intérprete de QV4 para evitar una caída reproducida del JIT de
// Qt 6.11.1 (QV4::Value::sameValueZero) al reevaluar bindings de larga vida.
// La bandeja usa su propio menú QML, así que no necesita QApplication/Widgets.

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

    // Un único inhibidor global para el modo cafeína. Hypridle respeta los
    // inhibidores systemd de tipo "idle", por lo que pausa todos sus listeners
    // (brillo, bloqueo, DPMS y suspensión). Al poner running a false, Process
    // envía SIGTERM y systemd-inhibit libera el bloqueo inmediatamente.
    Process {
        id: caffeineInhibitor
        running: Settings.caffeine
        command: [
            "systemd-inhibit",
            "--what=idle",
            "--who=Quickshell",
            "--why=Modo cafeína activo",
            "--mode=block",
            "sleep", "infinity"
        ]

        stderr: SplitParser {
            onRead: (line) => console.warn("Cafeína: " + line)
        }

        onExited: (exitCode, exitStatus) => {
            // Si el comando falla mientras debía estar activo, no dejamos la
            // interfaz mostrando un estado que en realidad no está protegido.
            if (Settings.caffeine) {
                console.warn("Cafeína: el inhibidor terminó (código " + exitCode + ")")
                Settings.caffeine = false
            }
        }
    }

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

    // El aviso de batería baja vive en Services/Battery.qml. Referenciarlo
    // aquí crea el singleton al arrancar, aunque ningún widget lo consulte.
    readonly property var _battery: Battery.device

    // Lo mismo con las plantillas de apps (Qt, terminal, starship, btop…).
    // AppTemplates reaplica lo activo en su Component.onCompleted, pero es un
    // singleton y QML no crea un singleton hasta que ALGUIEN lo toca: sus
    // únicas menciones estaban en la página de Ajustes, así que las plantillas
    // no se escribían hasta abrir Ajustes ▸ Tema una vez por sesión. Cambiar
    // de tema y reiniciar el shell dejaba el terminal y compañía con los
    // colores viejos hasta pasar por esa página.
    readonly property int _templatesAlive: AppTemplates.registry.length

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
        function caffeine(): void { Settings.caffeine = !Settings.caffeine }
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

    // Los popups de notificación animan su entrada/salida DESDE QML; sin esta
    // regla Hyprland superpone además su animación de layers (fade al mapear/
    // desmapear y el redimensionado de la capa), lo que producía una entrada
    // doble "forzada" y una franja gris residual al desvanecer la instantánea
    // del último búfer tras cerrar.
    function applyLayerRules() {
        Quickshell.execDetached(["hyprctl", "eval",
            'hl.layer_rule({ name = "qs-noanim-popups", match = '
            + '{ namespace = "qs-popups" }, no_anim = true })'])
    }
    Component.onCompleted: applyLayerRules()

    // Plugin autocontenido: carrusel para elegir fondo (Super+W → IPC
    // "carousel"). No modifica ningún componente; solo se instancia aquí.
    WallpaperCarousel {
        Component.onCompleted: shell.startupCarouselReady = true
    }

    // Ranura de panel con cierre animado: se construye al abrir ('open') y se
    // libera cuando termina la animación de cierre — 'closing' mantiene el
    // loader activo mientras la ventana siga visible (openProgress > 0), así
    // el cierre anima completo antes de destruir. Toda la maquinaria vive
    // aquí; cada uso declara solo su bandera 'open' y el panel que aloja.
    component PanelSlot: LazyLoader {
        property bool open: false
        property bool closing: false
        activeAsync: open || closing
    }

    // Todo lo que existe por monitor vive en este único recorrido de
    // pantallas: fondo, splash de arranque, barra, ranuras de paneles,
    // píldora de grabación, OSD de volumen y popups de notificación.
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: scr
            required property var modelData

            // Solo el monitor donde se abrió el panel construye su ranura: los
            // demás ni instancian (antes se creaban N copias del panel, N-1
            // invisibles, con sus timers y decodificaciones duplicados). Con
            // openedOnMonitor vacío (sin Hyprland) instancian todos, como antes.
            readonly property bool showsPanels: Globals.openedOnMonitor === ""
                                                || scr.modelData.name === Globals.openedOnMonitor

            // Fondo de pantalla en la capa Background, con la transición de
            // imagen gestionada desde QML.
            Backdrop {
                modelData: scr.modelData
                Component.onCompleted: shell.startupBackdropReadyCount++
            }

            // Splash breve al entrar en la sesión; tapa el salto visual entre
            // TTY y escritorio mientras aparecen la barra y el fondo. Tras la
            // animación se libera (active=false) para no dejar una ventana por
            // monitor residente toda la sesión.
            LazyLoader {
                id: splashL
                active: true
                StartupSplash {
                    modelData: scr.modelData
                    loadProgress: shell.startupLoadProgress
                    ready: shell.startupLoadReady
                    onFinished: splashL.active = false
                }
            }

            Bar {
                modelData: scr.modelData
                Component.onCompleted: shell.startupBarReadyCount++
            }

            // Paneles emergentes (Globals controla su visibilidad desde los
            // widgets de la barra); Popout anima al nacer vía Component.onCompleted.
            PanelSlot {
                id: ccS
                open: Globals.controlCenterOpen && scr.showsPanels
                ControlCenter { modelData: scr.modelData; onVisibleChanged: ccS.closing = visible }
            }
            PanelSlot {
                id: ncS
                open: Globals.notifCenterOpen && scr.showsPanels
                NotificationCenter { modelData: scr.modelData; onVisibleChanged: ncS.closing = visible }
            }
            PanelSlot {
                id: smS
                open: Globals.sysMonOpen && scr.showsPanels
                SystemMonitor { modelData: scr.modelData; onVisibleChanged: smS.closing = visible }
            }
            PanelSlot {
                id: alS
                open: Globals.launcherOpen && scr.showsPanels
                AppLauncher { modelData: scr.modelData; onVisibleChanged: alS.closing = visible }
            }
            PanelSlot {
                id: clipS
                open: Globals.clipboardOpen && scr.showsPanels
                ClipboardPanel { modelData: scr.modelData; onVisibleChanged: clipS.closing = visible }
            }
            PanelSlot {
                id: dashS
                open: Globals.dashboardOpen && scr.showsPanels
                Dashboard { modelData: scr.modelData; onVisibleChanged: dashS.closing = visible }
            }

            // La píldora de grabación solo existe mientras se graba.
            LazyLoader {
                active: ScreenCapture.isRecording
                RecordingPill { modelData: scr.modelData }
            }

            VolumeOSD { modelData: scr.modelData }
            NotificationPopups { modelData: scr.modelData }
        }
    }

    // La toolbar de captura es única (no por pantalla): la píldora basta para
    // controlar la grabación y ScreenCapture (singleton) conserva el estado.
    // Si se reabre mientras graba, se reconstruye al momento.
    PanelSlot {
        id: sctS
        open: Globals.screenCaptureOpen
        ScreenCaptureToolbar { onVisibleChanged: sctS.closing = visible }
    }

    // Agente de polkit: el diálogo de "se requiere autenticación". Único para
    // toda la sesión (no por pantalla) y sin coste mientras nadie lo pide.
    PolkitDialog {}

    // Ventana de ajustes: una sola ventana real (toplevel de Hyprland). Carga
    // perezosa: no se construye hasta el primer uso y se libera al cerrarla.
    LazyLoader {
        active: Globals.settingsOpen
        Settings {}
    }

    // Modales de red: casos raros, se construyen solo al abrirse y se liberan
    // al cerrar. UNA sola instancia en el monitor con foco: piden teclado
    // exclusivo, y una copia por monitor eran N ventanas compitiendo por él.
    LazyLoader {
        active: Net.promptNetwork !== null
        WifiPasswordModal { modelData: Globals.focusedScreen() }
    }
    LazyLoader {
        active: Net.ipConfigOpen
        IpSettingsModal { modelData: Globals.focusedScreen() }
    }
}
