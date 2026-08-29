//@ pragma Env QV4_FORCE_INTERPRETER = 1
// Punto de entrada del shell: una barra por monitor.
// Se fuerza el intérprete de QV4 para evitar una caída reproducida del JIT de
// Qt 6.11.1 (QV4::Value::sameValueZero) al reevaluar bindings de larga vida.
// La bandeja usa su propio menú QML, así que no necesita QApplication/Widgets.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Background
import qs.Bar
import qs.Config
import qs.Modules.Carousel
import qs.Modules.IA.ui
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

    // Solo escucha lo que la función LEE (scanning y list): también escuchaba
    // onCurrentChanged, pero con las mismas entradas la función da el mismo
    // resultado — era una reevaluación de más por cada cambio de fondo.
    Connections {
        target: Wallpaper
        function onScanningChanged() { shell.updateStartupWallpaperReady() }
        function onListChanged() { shell.updateStartupWallpaperReady() }
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

    // Control por IPC / atajos de teclado.
    //
    // Hay DOS familias a propósito:
    //
    //   · Genéricas — `toggle <panel>`, `open <panel>`, `close <panel>`,
    //     `list`. Añadir un panel nuevo ya no obliga a tocar este archivo ni a
    //     reescribir los atajos: basta con darlo de alta en Globals.panels.
    //         qs ipc call panel toggle clipboard
    //         qs ipc call panel list          → JSON con los paneles y cuál está abierto
    //
    //   · Con nombre — `controlcenter`, `notifications`, … Se mantienen porque
    //     los atajos de Hyprland que ya existen las llaman, y romperlos por
    //     estrenar las genéricas sería cambiarle la configuración al usuario
    //     sin avisar. Son una línea cada una y delegan en las mismas funciones.
    IpcHandler {
        target: "panel"

        // ── Genéricas ────────────────────────────────────────────────────────
        function toggle(name: string): void {
            if (Globals.isPanel(name)) Globals.toggle(name)
            else console.warn("IPC: no existe el panel '" + name + "'")
        }
        function open(name: string): void {
            if (Globals.isPanel(name)) Globals.open(name)
            else console.warn("IPC: no existe el panel '" + name + "'")
        }
        // Cierra solo si es ESE el panel abierto, para que un atajo de "cierra
        // el portapapeles" no se lleve por delante otro panel que hubiera
        // encima. Para cerrar lo que haya, `close` a secas.
        //
        // Va con nombre propio y no como `close(name)` porque un IpcHandler
        // exige que la llamada traiga tantos argumentos como declara la
        // función: convertir `close` en `close(name)` rompería todos los
        // atajos que ya llaman a `qs ipc call panel close`.
        function closePanel(name: string): void {
            if (!name || name === "" || Globals.openPanel === name)
                Globals.closeAll()
        }
        function close(): void { Globals.closeAll() }
        function list(): string {
            const out = []
            for (const p of Globals.panels)
                out.push({ name: p.name, widget: p.widget,
                           open: Globals.openPanel === p.name })
            return JSON.stringify({ panels: out, openPanel: Globals.openPanel,
                                    settingsOpen: Globals.settingsOpen })
        }

        // ── Con nombre (compatibilidad con los atajos ya escritos) ───────────
        function controlcenter(): void { Globals.toggleControlCenter() }
        function notifications(): void { Globals.toggleNotifCenter() }
        function sysmon(): void { Globals.toggleSysMon() }
        function launcher(): void { Globals.toggleLauncher() }
        function clipboard(): void { Globals.toggleClipboard() }
        function dashboard(): void { Globals.toggleDashboard() }
        function capture(): void { ScreenCapture.openToolbar(false) }
        function record(): void { ScreenCapture.openToolbar(true) }
        function settings(): void { Globals.toggleSettings() }
        function ai(): void { Globals.toggleAi() }
        function emoji(): void { Globals.toggleEmoji() }
        function dnd(): void { Globals.dnd = !Globals.dnd }
        function caffeine(): void { Settings.caffeine = !Settings.caffeine }
        function lock(): void { Globals.runPowerAction("lock") }
        function nightlight(): void { NightLight.toggle() }
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
                // Session.Lock también llega como Session.Unlock por esta
                // ruta, así que se descarta explícitamente: desbloquear tiene
                // que pasar por PAM, no por una señal del bus.
                if (line.indexOf("Session.Lock") !== -1
                    && line.indexOf("Session.Unlock") === -1) {
                    Globals.closeAll()
                    // Y AHORA SÍ SE BLOQUEA. Antes esta señal solo servía para
                    // cerrar los paneles y el bloqueo real lo ponía hyprlock por
                    // su cuenta. Con la pantalla de bloqueo dentro del shell,
                    // `loginctl lock-session` —que es lo que ejecutan hypridle
                    // al inactivarse, el menú de energía del escritorio y
                    // systemd antes de suspender— tiene que acabar aquí, o
                    // suspender el portátil dejaría la sesión abierta.
                    Globals.runPowerAction("lock")
                }
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
    Component.onCompleted: Quickshell.execDetached(["hyprctl", "eval",
        'hl.layer_rule({ name = "qs-noanim-popups", match = '
        + '{ namespace = "qs-popups" }, no_anim = true })'])

    // Bloq Núm sobrevive a las recargas de Hyprland. Un `hyprctl reload`
    // relee la config Lua —que no sabe del ajuste— y resetea la opción; y el
    // propio shell recarga Hyprland al arrancar (plantilla de tema), pisando
    // en carrera lo que Settings acababa de aplicar. En vez de intentar ganar
    // esa carrera, se re-aplica cada vez que Hyprland anuncia que recargó —
    // incluidas las recargas que el usuario haga a mano.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && Settings.numlockOn)
                Settings.applyNumlock()
        }
    }

    // Plugin autocontenido: carrusel para elegir fondo (Super+W → IPC
    // "carousel"). No modifica ningún componente; solo se instancia aquí.
    WallpaperCarousel {
        Component.onCompleted: shell.startupCarouselReady = true
    }

    // Ranura de panel con cierre animado: se construye al abrir ('open') y se
    // libera cuando termina la animación de cierre — mientras la ventana siga
    // visible, la ranura se mantiene viva aunque 'open' ya sea false, así el
    // cierre anima completo antes de destruir.
    //
    // La vigilancia del cierre vive AQUÍ, observando 'visible' del item que el
    // loader cargó: antes cada uso tenía que darse un id y cablear su propio
    // «onVisibleChanged: X.closing = visible», siete veces el mismo renglón —
    // el comentario prometía "cada uso declara solo su bandera 'open'" y no
    // era verdad. Ahora sí: PanelSlot { open: …; MiPanel {} }.
    component PanelSlot: LazyLoader {
        id: slot
        property bool open: false
        property bool closing: false
        // Para paneles CAROS de construir (la conversación de la IA: un
        // markdown analizado por mensaje): destruirlos al cerrar convertía
        // cada apertura en volver a construirlo todo, y el contenido llegaba
        // con retraso visible. Con keepAlive la primera apertura construye y
        // las siguientes solo muestran — Popout re-anima vía onShownChanged,
        // así que reabrir funciona igual. Oculto no pinta (visible false);
        // el coste es solo la memoria del panel.
        property bool keepAlive: false
        property bool _built: false
        activeAsync: open || closing || (keepAlive && _built)

        // El cierre animado se RESERVA al abrir, no cuando el panel avisa: la
        // primera señal de 'visible' puede dispararse mientras el loader aún
        // no ha publicado 'item' (carga asíncrona), y de perderla el panel se
        // destruiría a mitad de la animación de cierre.
        onOpenChanged: if (open) { closing = true; _built = true }

        // Con el loader inactivo 'item' es null y Connections simplemente no
        // escucha; al cargar, el target se reengancha solo. El guard cubre la
        // emisión durante el desmontaje, con 'item' ya retirado.
        readonly property Connections _closeWatch: Connections {
            target: slot.item
            function onVisibleChanged() {
                if (slot.item)
                    slot.closing = slot.item.visible
            }
        }
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
                open: Globals.controlCenterOpen && scr.showsPanels
                ControlCenter { modelData: scr.modelData }
            }
            PanelSlot {
                open: Globals.notifCenterOpen && scr.showsPanels
                NotificationCenter { modelData: scr.modelData }
            }
            PanelSlot {
                open: Globals.sysMonOpen && scr.showsPanels
                SystemMonitor { modelData: scr.modelData }
            }
            PanelSlot {
                open: Globals.launcherOpen && scr.showsPanels
                AppLauncher { modelData: scr.modelData }
            }
            PanelSlot {
                open: Globals.clipboardOpen && scr.showsPanels
                ClipboardPanel { modelData: scr.modelData }
            }
            PanelSlot {
                open: Globals.emojiOpen && scr.showsPanels
                EmojiPicker { modelData: scr.modelData }
            }
            PanelSlot {
                open: Globals.dashboardOpen && scr.showsPanels
                Dashboard { modelData: scr.modelData }
            }
            PanelSlot {
                open: Globals.aiOpen && scr.showsPanels
                keepAlive: true
                AiPanel { modelData: scr.modelData }
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
        open: Globals.screenCaptureOpen
        ScreenCaptureToolbar {}
    }

    // Agente de polkit: el diálogo de "se requiere autenticación". Único para
    // toda la sesión (no por pantalla) y sin coste mientras nadie lo pide.
    PolkitDialog {}

    // Pantalla de bloqueo (ext-session-lock + PAM). Una sola instancia: es el
    // propio WlSessionLock quien crea una superficie por monitor, incluidos los
    // que se conecten con la sesión ya bloqueada.
    LockScreen {}

    // El servicio de bloqueo tiene que estar VIVO antes de que alguien pida
    // bloquear: se suscribe a Globals.lockRequested y sondea el servicio PAM al
    // arrancar, y QML no crea un singleton hasta que alguien lo toca. Sin esta
    // línea, la primera petición de bloqueo caería en el vacío. Mismo motivo
    // que _battery y _templatesAlive de arriba.
    readonly property bool _lockAlive: Lock.pamReady

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
