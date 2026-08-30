// Punto de entrada del shell: una barra por monitor, más las superficies y
// servicios únicos que se declaran al final.
//
// La bandeja usa su propio menú QML, así que no necesita QApplication ni
// Widgets.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Background
import qs.Bar
import qs.Config
import qs.Modules.Carousel
import qs.Modules.Island
import qs.Modules.Dock
import qs.Modules.Island.sources
import qs.Modules.Spotlight
import qs.Modules.IA.ui
import qs.Panels
import qs.Services

ShellRoot {
    id: shell

    // Inhibidor global del modo cafeína. Hypridle respeta los inhibidores
    // systemd de tipo "idle", así que pausa todos sus listeners: brillo,
    // bloqueo, DPMS y suspensión. Al poner running en false, Process manda
    // SIGTERM y systemd-inhibit libera el bloqueo al momento.
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
            // Si el comando falla mientras debía estar activo, no se deja la
            // interfaz mostrando una protección que no existe.
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

    // Escucha solo lo que la función lee: con las mismas entradas da el mismo
    // resultado, así que cualquier otra señal sería una reevaluación de más.
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

    // Referencias que existen solo para crear el singleton al arrancar: QML no
    // instancia uno hasta que alguien lo toca, y estos tienen trabajo que hacer
    // en su Component.onCompleted aunque ningún widget los consulte. Sin la
    // referencia, el aviso de batería no salta y las plantillas de apps no se
    // escriben hasta abrir Ajustes una vez por sesión.
    readonly property var _battery: Battery.device

    readonly property int _templatesAlive: AppTemplates.registry.length

    // Control por IPC y atajos de teclado, en dos familias:
    //
    //   · Genéricas — `toggle <panel>`, `open <panel>`, `close`, `list`. Un
    //     panel nuevo no obliga a tocar este archivo ni a reescribir atajos:
    //     basta con darlo de alta en Globals.panels.
    //         qs ipc call panel toggle clipboard
    //         qs ipc call panel list     → JSON con los paneles y cuál está abierto
    //
    //   · Con nombre — se mantienen porque los atajos de Hyprland ya existentes
    //     las llaman. Son una línea cada una y delegan en las mismas funciones.
    IpcHandler {
        target: "panel"

        // Genéricas
        function toggle(name: string): void {
            if (Globals.isPanel(name)) Globals.toggle(name)
            else console.warn("IPC: no existe el panel '" + name + "'")
        }
        function open(name: string): void {
            if (Globals.isPanel(name)) Globals.open(name)
            else console.warn("IPC: no existe el panel '" + name + "'")
        }
        // Cierra solo si es ese el panel abierto, para que un atajo de "cierra
        // el portapapeles" no se lleve por delante otro panel que hubiera
        // encima; para cerrar lo que haya está `close` a secas.
        //
        // Va con nombre propio y no como `close(name)` porque un IpcHandler
        // exige tantos argumentos como declara la función, y convertirlo
        // rompería los atajos que ya llaman a `qs ipc call panel close`.
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

        // Con nombre (compatibilidad con los atajos ya escritos)
        function controlcenter(): void { Globals.toggleControlCenter() }
        function notifications(): void { Globals.toggleNotifCenter() }
        function sysmon(): void { Globals.toggleSysMon() }
        function sysmonapp(): void { Globals.toggleSysMonApp() }
        function launcher(): void { Globals.toggleLauncher() }
        function clipboard(): void { Globals.toggleClipboard() }
        function dashboard(): void { Globals.toggleDashboard() }
        function capture(): void { ScreenCapture.openToolbar(false) }
        function record(): void { ScreenCapture.openToolbar(true) }
        function settings(): void { Globals.toggleSettings() }
        function ai(): void { Globals.toggleAi() }
        function emoji(): void { Globals.toggleEmoji() }
        function spotlight(): void { Globals.toggleSpotlight() }
        function dnd(): void { Settings.dnd = !Settings.dnd }
        function caffeine(): void { Settings.caffeine = !Settings.caffeine }
        function lock(): void { PowerActions.run("lock") }
        function nightlight(): void { NightLight.toggle() }
    }

    // Escucha la señal 'Lock' de logind —la que emite `loginctl lock-session`,
    // que es lo que usan hypridle, el menú de energía y systemd antes de
    // suspender— para cerrar los paneles y bloquear, sin depender de que el
    // lock_cmd ejecute `qs ipc`. Usa `gdbus monitor`, una suscripción de cliente
    // sin privilegios, y no `dbus-monitor --system`, que exige root.
    Process {
        id: lockMonitor
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
        stdout: SplitParser {
            onRead: (line) => {
                // Unlock llega por esta misma ruta y se descarta: desbloquear
                // tiene que pasar por PAM, no por una señal del bus.
                if (line.indexOf("Session.Lock") !== -1
                    && line.indexOf("Session.Unlock") === -1) {
                    Globals.closeAll()
                    // Con la pantalla de bloqueo dentro del shell, esta señal
                    // tiene que acabar bloqueando de verdad: si no, suspender el
                    // portátil dejaría la sesión abierta.
                    PowerActions.run("lock")
                }
                // Suspensión y reanudación: logind emite
                // Manager.PrepareForSleep(true) antes de dormir y (false) al
                // despertar. Se reenvía al coordinador Resume, al que se
                // suscriben los servicios que necesitan recuperarse después.
                else if (line.indexOf("PrepareForSleep") !== -1)
                    Resume.notify(line.indexOf("true") !== -1)
            }
        }
        // Si el monitor muere se relanza tras una pausa.
        onExited: lockRestart.restart()
    }
    Timer {
        id: lockRestart
        interval: 3000
        onTriggered: lockMonitor.running = true
    }

    // Las capas que animan su entrada y su salida desde QML tienen que decirle a
    // Hyprland que no las anime él también: si no, el compositor superpone su
    // propio fundido al mapear y desmapear, y se ve una entrada doble y una
    // franja gris residual al desvanecer la instantánea del último búfer.
    //
    // En la isla importa todavía más, porque su ventana está mapeada toda la
    // sesión y lo que se mueve es la forma de dentro: cualquier animación de capa
    // por encima es ruido sobre un muelle que ya está haciendo el trabajo.
    Component.onCompleted: {
        Quickshell.execDetached(["hyprctl", "eval",
            'hl.layer_rule({ name = "qs-noanim-popups", match = '
            + '{ namespace = "qs-popups" }, no_anim = true })'])
        Quickshell.execDetached(["hyprctl", "eval",
            'hl.layer_rule({ name = "qs-noanim-island", match = '
            + '{ namespace = "qs-island" }, no_anim = true })'])
        // El dock, por lo mismo: su entrada y su salida las anima QML
        // deslizando la pastilla por debajo del borde.
        Quickshell.execDetached(["hyprctl", "eval",
            'hl.layer_rule({ name = "qs-noanim-dock", match = '
            + '{ namespace = "qs-dock" }, no_anim = true })'])
    }

    // Bloq Núm sobrevive a las recargas de Hyprland. Un `hyprctl reload` relee
    // la config Lua, que no sabe del ajuste, y resetea la opción; además el
    // propio shell recarga Hyprland al arrancar. En vez de intentar ganar esa
    // carrera se re-aplica cada vez que Hyprland anuncia que ha recargado.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && Settings.numlockOn)
                Settings.applyNumlock()
        }
    }

    // Carrusel para elegir fondo (Super+W → IPC "carousel"). Plugin
    // autocontenido: no modifica ningún componente, solo se instancia aquí.
    WallpaperCarousel {
        Component.onCompleted: shell.startupCarouselReady = true
    }

    // Ranura de panel con cierre animado: se construye al abrir y se libera
    // cuando termina la animación de cierre, así que mientras la ventana siga
    // visible la ranura se mantiene viva aunque 'open' ya sea false.
    //
    // La vigilancia del cierre vive aquí, observando el 'visible' del item que
    // cargó el loader, de modo que cada uso declara solo su bandera 'open'.
    component PanelSlot: LazyLoader {
        id: slot
        property bool open: false
        property bool closing: false
        // Para paneles caros de construir, destruirlos al cerrar convierte cada
        // apertura en reconstruirlo todo y el contenido llega con retraso
        // visible. Con keepAlive la primera apertura construye y las siguientes
        // solo muestran; oculto no pinta, así que el coste es solo memoria.
        property bool keepAlive: false
        property bool _built: false
        activeAsync: open || closing || (keepAlive && _built)

        // El cierre animado se reserva al abrir y no cuando el panel avisa: la
        // primera señal de 'visible' puede dispararse mientras el loader aún no
        // ha publicado 'item', y perderla destruiría el panel a mitad de la
        // animación de cierre.
        onOpenChanged: if (open) { closing = true; _built = true }

        // Con el loader inactivo 'item' es null y Connections no escucha; al
        // cargar, el target se reengancha solo. El guard cubre la emisión durante
        // el desmontaje, con 'item' ya retirado.
        readonly property Connections _closeWatch: Connections {
            target: slot.item
            function onVisibleChanged() {
                if (slot.item)
                    slot.closing = slot.item.visible
            }
        }
    }

    // Todo lo que existe por monitor vive en este único recorrido de pantallas.
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: scr
            required property var modelData

            // Solo el monitor donde se abrió el panel construye su ranura; los
            // demás ni instancian. Con openedOnMonitor vacío, sin Hyprland,
            // instancian todos.
            readonly property bool showsPanels: Globals.openedOnMonitor === ""
                                                || scr.modelData.name === Globals.openedOnMonitor

            // Fondo de pantalla en la capa Background, con la transición de
            // imagen gestionada desde QML.
            Backdrop {
                modelData: scr.modelData
                Component.onCompleted: shell.startupBackdropReadyCount++
            }

            // Splash breve al entrar en la sesión: tapa el salto visual entre
            // TTY y escritorio mientras aparecen la barra y el fondo. Se libera
            // tras la animación para no dejar una ventana por monitor residente
            // toda la sesión.
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
                id: bar
                modelData: scr.modelData
                Component.onCompleted: shell.startupBarReadyCount++
            }

            // Inhibidor de reposo de Wayland: se le pide al compositor en vez de
            // pelearse con el gestor de reposo, así que lo respetan por protocolo
            // sin detectar cuál corre ni tocar su configuración.
            //
            // 'window' no es opcional: sin ella el objeto se construye, 'enabled'
            // se queda en true y no inhibe nada, sin aviso ni error. El
            // compositor la usa para decidir si hace caso, y una ventana de panel
            // es de las que respeta. Por eso va aquí dentro y no suelto en la
            // raíz. Con varios monitores salen varios inhibidores, lo cual da
            // igual: inhibir es un o-lógico.
            //
            // Quién cuenta como "sonando" lo decide Services/Media, con el mismo
            // criterio que enseña la barra: un navegador abierto sin reproducir
            // deja un reproductor MPRIS registrado, y darlo por bueno tendría la
            // pantalla encendida toda la noche por una pestaña.
            IdleInhibitor {
                window: bar
                enabled: Settings.keepAwakeOnMedia && Media.playing
            }

            // La isla, en su propia superficie por encima de la barra: no puede
            // vivir dentro de ella porque la barra mide 36 dp y una hoja
            // expandida necesita quince veces eso.
            //
            // En LazyLoader para que, con la isla apagada, no se construya. Una
            // superficie de layer-shell escondida sigue existiendo —y esta es del
            // ancho de la pantalla por 560 dp, por monitor— con su muelle, sus
            // ranuras de contenido y sus bindings dentro.
            LazyLoader {
                active: Settings.islandEnabled
                IslandWindow { modelData: scr.modelData }
            }

            // El dock, con la misma regla y por el mismo motivo: apagado no se
            // construye. Es una superficie del ancho de la pantalla por 420 dp,
            // por monitor, con su máscara, su fila de iconos y sus bindings a los
            // toplevels de Wayland.
            //
            // El filtro por monitor va aquí y no dentro de la ventana: puesto
            // dentro, un monitor excluido construiría la superficie entera para
            // luego no enseñarla.
            LazyLoader {
                active: Settings.dockEnabled && Dock.enSuMonitor(scr.modelData.name)
                DockWindow { modelData: scr.modelData }
            }

            // Paneles emergentes; Popout anima al nacer vía
            // Component.onCompleted.
            PanelSlot {
                open: Globals.controlCenterOpen && scr.showsPanels
                ControlCenter { modelData: scr.modelData }
            }
            // El centro clásico solo con la isla apagada. Ya no se llega a él
            // desde Globals, pero condicionarlo también aquí es lo que garantiza
            // que no se construya nunca: son seiscientas líneas con su lista, sus
            // grupos y sus animaciones, por monitor.
            PanelSlot {
                open: !Settings.islandEnabled && Globals.notifCenterOpen && scr.showsPanels
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
            // Spotlight no cuelga de la barra sino que va centrado, así que
            // lleva su propia ranura en vez de PanelSlot.
            LazyLoader {
                active: Globals.spotlightOpen && scr.showsPanels
                Spotlight { modelData: scr.modelData }
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

            // La píldora de grabación solo existe mientras se graba y con la
            // isla apagada: encendida, el aviso lo da ella con sus mismos mandos,
            // y dos avisos de lo mismo sobran.
            //
            // Condicionado en el LazyLoader y no dentro de la píldora para que ni
            // siquiera se construya: es una superficie Overlay del tamaño de la
            // pantalla por monitor, con su máscara y su arrastre.
            LazyLoader {
                active: ScreenCapture.isRecording && !Settings.islandEnabled
                RecordingPill { modelData: scr.modelData }
            }

            // El OSD de volumen y los popups de notificación clásicos. Con la
            // isla encendida no se construyen, porque ella hace ese trabajo como
            // actividades suyas.
            //
            // LazyLoader y no un 'visible: false': una ventana escondida sigue
            // siendo una superficie de Wayland con sus temporizadores y sus
            // conexiones, por monitor.
            LazyLoader {
                active: !Settings.islandEnabled
                VolumeOSD { modelData: scr.modelData }
            }
            LazyLoader {
                active: !Settings.islandEnabled
                NotificationPopups { modelData: scr.modelData }
            }
        }
    }

    // La toolbar de captura es única y no por pantalla: la píldora basta para
    // controlar la grabación y ScreenCapture conserva el estado, así que
    // reabrirla mientras graba la reconstruye al momento.
    PanelSlot {
        open: Globals.screenCaptureOpen
        ScreenCaptureToolbar {}
    }

    // El monitor de sistema como aplicación: ventana XDG, una sola. Es un
    // programa, y un programa no se duplica por pantalla.
    SysMonApp {}

    // Fuentes de la isla, en una sola instancia y fuera del recorrido de
    // pantallas: la ventana de la isla sí existe por monitor, y con las fuentes
    // dentro cada notificación entraría en la cola tantas veces como monitores
    // haya. Se apagan solas mirando Settings.islandEnabled por dentro.
    //
    // No van en un LazyLoader: eso construye componentes, y estas son QtObject
    // sin nada visual.
    LevelSource {}
    NotifSource {}
    // El reproductor y la grabación de pantalla. Van en Modules/Island/sources y
    // no dentro de IslandState porque Config no importa qs.Services.
    MediaSource {}
    RecordSource {}

    // Agente de polkit: el diálogo de autenticación. Único para toda la sesión y
    // sin coste mientras nadie lo pide.
    PolkitDialog {}

    // Pantalla de bloqueo (ext-session-lock + PAM). Una sola instancia: es el
    // propio WlSessionLock quien crea una superficie por monitor, incluidos los
    // que se conecten con la sesión ya bloqueada.
    LockScreen {}

    // El servicio de bloqueo tiene que estar vivo antes de que alguien pida
    // bloquear: se suscribe a PowerActions.lockRequested y sondea el servicio PAM
    // al arrancar, y QML no crea un singleton hasta que alguien lo toca.
    readonly property bool _lockAlive: Lock.pamReady

    // Ventana de ajustes: un solo toplevel real, con carga perezosa; no se
    // construye hasta el primer uso y se libera al cerrarla.
    LazyLoader {
        active: Globals.settingsOpen
        Settings {}
    }

    // Modales de red: se construyen solo al abrirse y se liberan al cerrar. Una
    // sola instancia en el monitor con foco, porque piden teclado exclusivo y una
    // copia por monitor serían N ventanas compitiendo por él.
    LazyLoader {
        active: Net.promptNetwork !== null
        WifiPasswordModal { modelData: Globals.focusedScreen() }
    }
    LazyLoader {
        active: Net.ipConfigOpen
        IpSettingsModal { modelData: Globals.focusedScreen() }
    }
}
