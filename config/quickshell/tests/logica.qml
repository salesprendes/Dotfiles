import QtQuick
import Quickshell
import qs.Config
import qs.Panels
import qs.Services

// Batería de lógica del shell. La lanza tests/logica.py, que monta un espejo
// del árbol y pone este archivo como shell.qml, con HOME falso y sin Hyprland
// (ver la cabecera de ese guion). Aquí NO se abre ninguna ventana: solo se
// llaman funciones y se comprueban resultados.
ShellRoot {
    id: suite

    property int total: 0
    property int malas: 0

    function ok(nombre, condicion) {
        suite.total++
        if (!condicion) {
            suite.malas++
            console.log("PRUEBA MAL   " + nombre)
        }
    }

    function igual(nombre, obtenido, esperado) {
        const a = JSON.stringify(obtenido)
        const b = JSON.stringify(esperado)
        suite.total++
        if (a !== b) {
            suite.malas++
            console.log("PRUEBA MAL   " + nombre + "\n     esperado: " + b + "\n     obtenido: " + a)
        }
    }

    // Layout corto y legible para las comprobaciones de abajo.
    function mk(izq, cen, der) {
        return {
            left: izq.map(id => ({ id: id })),
            center: cen.map(id => ({ id: id })),
            right: der.map(id => ({ id: id }))
        }
    }
    function ids(layout, section) {
        return BarCatalog.entriesOf(layout, section).map(e => e.id)
    }

    // ── Catálogo ─────────────────────────────────────────────────────────────
    function pruebaCatalogo() {
        const def = BarCatalog.defaultLayout()
        for (const sec of BarCatalog.sections)
            for (const e of BarCatalog.entriesOf(def, sec))
                ok("el layout de fábrica solo usa ids conocidos: " + e.id,
                   BarCatalog.knows(e.id))

        // Un layout de fábrica con un id repetido sería un widget fantasma:
        // sanitize() se comería el segundo y el usuario vería menos de lo que
        // el archivo dice.
        const vistos = {}
        let repes = 0
        for (const sec of BarCatalog.sections)
            for (const e of BarCatalog.entriesOf(def, sec)) {
                if (vistos[e.id]) repes++
                vistos[e.id] = true
            }
        ok("el layout de fábrica no repite ningún widget", repes === 0)

        ok("has() encuentra lo puesto", BarCatalog.has(def, "clock"))
        ok("has() no inventa lo que no está", !BarCatalog.has(def, "caffeine"))
        igual("locate() da sección e índice",
              BarCatalog.locate(mk(["launcher", "workspaces"], [], []), "workspaces"),
              { section: "left", index: 1 })
        ok("locate() devuelve null si no está",
           BarCatalog.locate(mk([], [], []), "clock") === null)
    }

    // ── Saneado ──────────────────────────────────────────────────────────────
    function pruebaSanitize() {
        const sucio = {
            left: [{ id: "launcher" }, { id: "noExisteEsto" }, { id: "launcher" }],
            center: [{ id: "clock" }, "esto no es un objeto", null],
            // 'right' falta a propósito: sanitize tiene que crearla igualmente.
            basura: [{ id: "clock" }]
        }
        const limpio = BarCatalog.sanitize(sucio)
        igual("sanitize descarta ids desconocidos y duplicados",
              ids(limpio, "left"), ["launcher"])
        igual("sanitize descarta entradas que no son objetos",
              ids(limpio, "center"), ["clock"])
        igual("sanitize garantiza las tres secciones", ids(limpio, "right"), [])
        ok("sanitize no arrastra claves de más", limpio.basura === undefined)

        // El separador SÍ puede repetirse: es el único con multiple.
        const separadores = BarCatalog.sanitize(
            mk([], [], ["spacer", "clock", "spacer"]))
        igual("sanitize conserva varios separadores",
              ids(separadores, "right"), ["spacer", "clock", "spacer"])
    }

    // ── Mover ────────────────────────────────────────────────────────────────
    // Es la aritmética que más fácil se equivoca: el índice de destino se
    // interpreta sobre la lista YA sin la entrada movida.
    function pruebaMove() {
        const base = mk(["a1", "a2", "a3"], [], [])
        // Se usan ids reales para que sanitize no haga falta aquí.
        const uno = mk(["launcher", "workspaces", "activeWindow"], [], [])

        igual("mover a la derecha dentro del mismo carril",
              ids(BarCatalog.move(uno, "left", 0, "left", 2), "left"),
              ["workspaces", "activeWindow", "launcher"])
        igual("mover a la izquierda dentro del mismo carril",
              ids(BarCatalog.move(uno, "left", 2, "left", 0), "left"),
              ["activeWindow", "launcher", "workspaces"])

        const cruzado = BarCatalog.move(uno, "left", 1, "right", 0)
        igual("mover a otro carril: sale del origen",
              ids(cruzado, "left"), ["launcher", "activeWindow"])
        igual("mover a otro carril: entra en el destino",
              ids(cruzado, "right"), ["workspaces"])

        // Un índice fuera de rango no debe corromper nada.
        igual("un índice imposible deja el layout como estaba",
              ids(BarCatalog.move(uno, "left", 99, "right", 0), "left"),
              ["launcher", "workspaces", "activeWindow"])

        // move() devuelve un layout NUEVO: si mutara el recibido, la 'property
        // var' de Settings no emitiría el cambio y la barra no se enteraría.
        BarCatalog.move(uno, "left", 0, "right", 0)
        igual("move no muta el layout de entrada",
              ids(uno, "left"), ["launcher", "workspaces", "activeWindow"])
        ok("base sin tocar", base.left.length === 3)
    }

    // ── Añadir y quitar ──────────────────────────────────────────────────────
    function pruebaAddRemove() {
        const vacio = mk([], [], [])
        igual("add coloca en la sección de fábrica del widget",
              ids(BarCatalog.add(vacio, "clock", ""), "center"), ["clock"])
        igual("add respeta la sección pedida",
              ids(BarCatalog.add(vacio, "clock", "right"), "right"), ["clock"])

        const conReloj = BarCatalog.add(vacio, "clock", "center")
        igual("add no duplica un widget de instancia única",
              ids(BarCatalog.add(conReloj, "clock", "left"), "left"), [])

        const dos = BarCatalog.add(BarCatalog.add(vacio, "spacer", "right"),
                                   "spacer", "right")
        igual("add sí duplica el separador", ids(dos, "right"), ["spacer", "spacer"])

        igual("add ignora un id desconocido",
              ids(BarCatalog.add(vacio, "noExisteEsto", "left"), "left"), [])

        const tres = mk([], [], ["tray", "battery", "clipboard"])
        igual("removeAt quita el del índice",
              ids(BarCatalog.removeAt(tres, "right", 1), "right"),
              ["tray", "clipboard"])
        igual("removeAt con índice imposible no toca nada",
              ids(BarCatalog.removeAt(tres, "right", 9), "right"),
              ["tray", "battery", "clipboard"])
    }

    // ── Migración de settings.json ───────────────────────────────────────────
    function pruebaMigracion() {
        // Una configuración v1 con todo por defecto tiene que dar exactamente
        // el layout de fábrica: quien no tocó nada no debe notar el cambio.
        const virgen = { themeName: "dynamic" }
        Settings.migrate(virgen)
        igual("v1 sin tocar → layout de fábrica",
              virgen.barLayout, BarCatalog.defaultLayout())

        // Lo que el usuario tenía apagado sigue apagado.
        const apagados = {
            showTray: false, showSysmon: false, showAi: false,
            showBattery: true, showClipboard: true,
            showNotifications: true, showPowerProfile: true
        }
        Settings.migrate(apagados)
        ok("showTray:false quita la bandeja",
           !BarCatalog.has(apagados.barLayout, "tray"))
        ok("showSysmon:false quita el monitor",
           !BarCatalog.has(apagados.barLayout, "sysmon"))
        ok("showAi:false quita el asistente",
           !BarCatalog.has(apagados.barLayout, "ai"))
        ok("lo que estaba encendido sigue puesto",
           BarCatalog.has(apagados.barLayout, "battery")
           && BarCatalog.has(apagados.barLayout, "clipboard")
           && BarCatalog.has(apagados.barLayout, "notifications"))

        // Los dos que venían apagados de fábrica solo entran si se encendieron.
        const extras = { showCaffeine: true, weatherShowInBar: true }
        Settings.migrate(extras)
        ok("showCaffeine:true añade la cafeína",
           BarCatalog.has(extras.barLayout, "caffeine"))
        igual("weatherShowInBar:true pone el clima entre reproductor y reloj",
              ids(extras.barLayout, "center"), ["media", "weather", "clock"])

        const sinExtras = {}
        Settings.migrate(sinExtras)
        ok("sin encenderlos, la cafeína no aparece",
           !BarCatalog.has(sinExtras.barLayout, "caffeine"))
        // Es el caso que se coló: el clima SÍ estaba escrito en la barra vieja,
        // pero colgado de 'weatherShowInBar', que venía apagado. Meterlo en el
        // layout de fábrica le habría estrenado una píldora de clima a quien
        // nunca la pidió.
        ok("sin encenderlo, el clima tampoco",
           !BarCatalog.has(sinExtras.barLayout, "weather"))
        ok("y el layout de fábrica no lo trae",
           !BarCatalog.has(BarCatalog.defaultLayout(), "weather"))

        // Idempotencia: volver a migrar algo ya migrado no lo toca.
        const yaHecho = { _version: Settings.schemaVersion,
                          barLayout: mk(["clock"], [], []) }
        Settings.migrate(yaHecho)
        igual("una config ya en la versión actual no se toca",
              ids(yaHecho.barLayout, "left"), ["clock"])

        // Un barLayout escrito a mano en un archivo sin versión manda sobre la
        // conversión: quien ya lo puso a mano no quiere que se lo pisen.
        const aMano = { showTray: false, barLayout: mk([], [], ["tray"]) }
        Settings.migrate(aMano)
        igual("un barLayout ya presente gana a los booleanos viejos",
              ids(aMano.barLayout, "right"), ["tray"])

        // v3 llegó a borrar 'osdPosition' y 'notifPosition', dando por hecho
        // que la isla se quedaba el OSD y los popups para siempre. Era un
        // error —la isla es un interruptor, no un reemplazo— y se revirtió.
        // Esta prueba defiende la reversión: una migración que borra ajustes
        // que luego resulta que sí hacían falta no se puede deshacer para quien
        // ya la corrió.
        const conPosiciones = { osdPosition: "top", notifPosition: "bl",
                                notifTimeout: 9, notifMaxVisible: 2 }
        Settings.migrate(conPosiciones)
        igual("v3 conserva osdPosition", conPosiciones.osdPosition, "top")
        igual("v3 conserva notifPosition", conPosiciones.notifPosition, "bl")
        igual("y NO toca la duración", conPosiciones.notifTimeout, 9)
        igual("ni cuántas caben", conPosiciones.notifMaxVisible, 2)

        ok("la versión de esquema es la esperada", Settings.schemaVersion === 3)
    }

    // ── Saneado de settings ──────────────────────────────────────────────────
    function pruebaSanitizeSettings() {
        ok("sanitize('barLayout') rechaza lo que no es objeto",
           Settings.sanitize("barLayout", "una cadena") === undefined)
        ok("sanitize('barLayout') rechaza un array",
           Settings.sanitize("barLayout", [1, 2]) === undefined)
        const limpio = Settings.sanitize("barLayout", mk(["noExisteEsto", "clock"], [], []))
        igual("sanitize('barLayout') limpia el contenido",
              ids(limpio, "left"), ["clock"])
    }

    // ── Selector de emojis ───────────────────────────────────────────────────
    function pruebaEmoji() {
        Emoji.load()
        ok("el catálogo de emojis carga", Emoji.loaded)
        ok("y trae bastantes entradas", Emoji.all.length > 1000)

        // Estructura: sin esto, un catálogo regenerado con otro formato pasaría
        // desapercibido hasta abrir el panel y verlo vacío.
        let malformadas = 0
        for (const e of Emoji.all)
            if (!e || typeof e.c !== "string" || e.c === ""
                || typeof e.n !== "string" || typeof e.g !== "string")
                malformadas++
        ok("todas las entradas tienen carácter, nombre y grupo", malformadas === 0)

        // Los nombres van en minúsculas porque la búsqueda compara en
        // minúsculas sin normalizar: una mayúscula en el catálogo sería una
        // entrada imposible de encontrar.
        let conMayusculas = 0
        for (const e of Emoji.all)
            if (e.n !== e.n.toLowerCase())
                conMayusculas++
        ok("los nombres están en minúsculas", conMayusculas === 0)

        ok("hay más de un grupo para el filtro", Emoji.groups.length > 1)

        const antes = Emoji.query
        Emoji.query = "grinning face"
        ok("buscar por nombre encuentra algo", Emoji.filtered.length > 0)
        Emoji.query = "estonoexistenidedelejos"
        igual("una búsqueda sin resultados da lista vacía", Emoji.filtered.length, 0)
        Emoji.query = antes
    }

    // ── Reproductor activo ───────────────────────────────────────────────────
    // Los estados son los MEDIDOS en el bus, no inventados: el fantasma es
    // literalmente lo que publica Brave con el navegador abierto y nada
    // sonando (playbackState=0, sin título ni artista).
    function pruebaMedia() {
        const parado = 0, sonando = 1, pausado = 2

        const fantasma = { playbackState: parado, isPlaying: false,
                           trackTitle: "", trackArtist: "" }
        ok("un reproductor parado y sin metadatos no cuenta",
           !Media.isLive(fantasma))

        // El caso que más duele: parado pero con los metadatos de lo último
        // que sonó. Antes bastaba con tener título para que la píldora se
        // quedara puesta para siempre.
        ok("parado CON metadatos tampoco cuenta",
           !Media.isLive({ playbackState: parado, isPlaying: false,
                           trackTitle: "Lo último que sonó", trackArtist: "" }))

        ok("sonando cuenta aunque no traiga metadatos",
           Media.isLive({ playbackState: sonando, isPlaying: true,
                          trackTitle: "", trackArtist: "" }))

        ok("en pausa con título cuenta (quieres reanudar)",
           Media.isLive({ playbackState: pausado, isPlaying: false,
                          trackTitle: "Una canción", trackArtist: "" }))
        ok("en pausa con solo artista también",
           Media.isLive({ playbackState: pausado, isPlaying: false,
                          trackTitle: "", trackArtist: "Alguien" }))
        ok("en pausa y vacío no cuenta",
           !Media.isLive({ playbackState: pausado, isPlaying: false,
                           trackTitle: "", trackArtist: "" }))

        ok("null no cuenta", !Media.isLive(null))
        ok("undefined tampoco", !Media.isLive(undefined))

        // Y el estado de la máquina AHORA: con el navegador abierto y nada
        // sonando, la píldora tiene que estar escondida.
        for (const p of Media.players)
            ok("todo lo que sale como activo está vivo: " + p.identity,
               Media.isLive(p))
        ok("los activos son un subconjunto de lo que hay en el bus",
           Media.players.length <= Media.all.length)
        ok("si no hay activos, no hay 'active'",
           Media.players.length > 0 || Media.active === null)
        ok("hasMedia va con active",
           Media.hasMedia === (Media.active !== null))
    }

    // ── Pantalla de bloqueo ──────────────────────────────────────────────────
    // Se MONTA de verdad, con todos sus hijos, y se comprueba que el árbol
    // existe. Es la única prueba que se puede hacer sin bloquear la sesión, y
    // es justo la que hace falta: si LockContent no carga, la pantalla de
    // bloqueo aparece vacía o directamente no aparece, y para descubrirlo
    // tendrías que bloquearte fuera de tu propia sesión.
    //
    // 'active' se deja en false: no queremos el temporizador de foco corriendo
    // en una prueba, solo saber que todo el árbol se construye.
    // Se monta con 'active' en false: no queremos el temporizador de foco
    // corriendo en una prueba, solo saber que todo el árbol se construye. Sin
    // pantalla asignada, 'primary' es false y la tarjeta de contraseña no se
    // muestra — pero sus hijos SÍ se crean, que es lo que se está comprobando.
    readonly property LockContent lockProbe: LockContent {
        width: 1920
        height: 1080
        active: false
    }

    function pruebaBloqueo() {
        const c = suite.lockProbe
        ok("LockContent se instancia entero", c !== null)
        if (!c)
            return
        ok("conoce si es la pantalla principal", typeof c.primary === "boolean")
        ok("arranca inactiva en la prueba", c.active === false)
        // La regla del reparto: sin pantalla asignada no puede ser la
        // principal, así que no monta una segunda tarjeta de contraseña.
        ok("sin pantalla no se considera principal", c.primary === false)
        // El árbol de verdad: si alguno de estos no se hubiera construido,
        // 'children' vendría corto y la pantalla de bloqueo saldría a medias.
        ok("tiene hijos montados", c.children.length > 4)
    }

    // ── Etiqueta de distribución de teclado ──────────────────────────────────
    function pruebaTeclado() {
        const antes = Keyboard.layout
        const casos = [
            ["Spanish", "ES"],            // el que fallaba: daba "SP"
            ["English (US)", "EN"],       // se resuelve por la parte sin paréntesis
            ["Catalan", "CA"],
            ["German", "DE"],
            ["Portuguese (Brazil)", "BR"],
            ["", ""],                     // sin distribución, sin etiqueta
            ["Idioma Inventado", "ID"]    // desconocido: recorte de dos letras
        ]
        for (const [nombre, esperado] of casos) {
            Keyboard.layout = nombre
            igual("etiqueta de «" + nombre + "»", Keyboard.short, esperado)
        }
        Keyboard.layout = antes
    }

    // ── La isla ──────────────────────────────────────────────────────────────
    // La máquina de estados entera, sin abrir una ventana. Es donde vive la
    // parte que de verdad puede salir mal: las prioridades entre capas y las
    // caducidades.
    function pruebaIsla() {
        IslandState.collapse()
        IslandState.clearNotifications()
        IslandState.mediaActive = false
        IslandState.pointerInside = false

        igual("en reposo, la isla enseña el reloj", IslandState.activity, "home")
        ok("y no está expandida", !IslandState.expanded)

        // La base se DEDUCE, no se asigna: si suena algo, manda el reproductor.
        IslandState.mediaActive = true
        igual("con música, la base es el reproductor", IslandState.activity, "media")
        IslandState.mediaActive = false
        igual("sin música, vuelve el reloj", IslandState.activity, "home")

        // Un destino se abre y se expande.
        ok("abrir el calendario funciona", IslandState.openDestination("calendar"))
        igual("y es lo que se enseña", IslandState.activity, "calendar")
        ok("expandida", IslandState.expanded)
        ok("un destino inventado se rechaza", !IslandState.openDestination("noExiste"))

        // ── El interruptor de la isla no puede dejar nada colgando ───────────
        // Los dos son estados que NO dan ningún error: simplemente el shell se
        // queda mal y hay que reiniciarlo para entender por qué.
        {
            // Se guarda TODO lo que este bloque toca: más abajo hay pruebas
            // que siguen contando con el destino que quedó abierto antes.
            const antes = Settings.islandEnabled
            const destAntes = IslandState.destination

            // Encender la isla con el centro clásico abierto: si 'openPanel' se
            // quedara en "notif", la isla se escondería para siempre —se oculta
            // mientras haya un panel abierto— hasta abrir y cerrar otra cosa.
            Settings.islandEnabled = false
            Globals.openPanel = "notif"
            Settings.islandEnabled = true
            igual("encender la isla suelta el centro clásico", Globals.openPanel, "")

            // Apagarla con la hoja abierta: el destino se quedaría puesto en una
            // isla que ya no existe, y volvería expandida al reencenderla.
            IslandState.openDestination("notifs")
            Settings.islandEnabled = false
            igual("apagarla cierra la hoja", IslandState.destination, "")
            ok("y ya no está expandida", !IslandState.expanded)

            // Y la campana lleva a un sitio distinto según el interruptor.
            Settings.islandEnabled = false
            Globals.openPanel = ""
            Globals.toggleNotifCenter()
            igual("con la isla apagada abre el centro clásico", Globals.openPanel, "notif")
            Globals.openPanel = ""
            Settings.islandEnabled = true
            Globals.toggleNotifCenter()
            igual("con la isla encendida abre su hoja", IslandState.destination, "notifs")
            igual("y no abre ningún panel", Globals.openPanel, "")

            // Y POR LA PUERTA DE ATRÁS. `qs ipc call panel open notif` y los
            // atajos de teclado no pasan por la campana: entran por open() y
            // toggle() a secas. Esto dejaba openPanel = "notif" con la isla
            // encendida — la isla se esconde con cualquier panel abierto y el
            // centro clásico no se construye, así que no salía nada y la isla
            // se quedaba invisible.
            IslandState.closeDestination()
            Globals.openPanel = ""
            Globals.open("notif")
            igual("abrir 'notif' por IPC no toca openPanel", Globals.openPanel, "")
            igual("y lleva a la hoja de la isla", IslandState.destination, "notifs")
            Globals.toggle("notif")
            igual("y el toggle la cierra", IslandState.destination, "")
            igual("sin dejar ningún panel puesto", Globals.openPanel, "")

            // Los demás paneles siguen entrando por donde entraban.
            Globals.open("clipboard")
            igual("los otros paneles no se enteran de nada", Globals.openPanel, "clipboard")
            Globals.openPanel = ""

            Settings.islandEnabled = antes
            if (destAntes !== "")
                IslandState.openDestination(destAntes)
            else
                IslandState.closeDestination()
        }

        // Cada destino que se puede abrir TIENE que tener una hoja registrada en
        // Modules/Island/IslandWindow.qml. Cuando no la tiene, nada falla: la
        // isla se expande a una caja vacía y parece rota. Esta lista es la copia
        // de la de allí, y si alguien añade un destino sin hoja, esto lo dice.
        {
            const conHoja = ["calendar", "notifs", "media", "recording"]
            igual("no hay destinos sin hoja que enseñar",
                  IslandState.destinations.filter(d => conHoja.indexOf(d) === -1).length, 0)
            igual("ni hojas sin destino que las abra",
                  conHoja.filter(d => !IslandState.isDestination(d)).length, 0)
        }

        // LO IMPORTANTE: un transitorio TAPA el destino sin cerrarlo, y al
        // caducar vuelve donde estabas. Es la mitad de la gracia de una isla.
        IslandState.showLevel("volume", 0.5, false)
        igual("el volumen tapa el calendario", IslandState.activity, "level")
        ok("y mientras tapa, no está expandida", !IslandState.expanded)
        IslandState.clearTransient()
        igual("al caducar vuelve el calendario", IslandState.activity, "calendar")
        ok("y expandido como estaba", IslandState.expanded)

        // Entrar a un destino a propósito sí cancela lo transitorio.
        IslandState.showLevel("volume", 0.5, false)
        IslandState.openDestination("notifs")
        igual("abrir un destino cancela el transitorio", IslandState.activity, "notifs")

        IslandState.collapse()
        igual("collapse lo cierra todo", IslandState.activity, "home")

        // El destino "media" no puede sobrevivir a que se acabe la música.
        IslandState.mediaActive = true
        IslandState.openDestination("media")
        IslandState.mediaActive = false
        igual("si se acaba la música, su hoja se cierra sola",
              IslandState.destination, "")
    }

    // ── Grabación y vistazos ─────────────────────────────────────────────────
    // Lo de "se asoma solo y se va solo" es donde es más fácil dejar la isla
    // colgada: una hoja que se abrió sola y no se cierra es una hoja que tapa
    // la pantalla para siempre sin que nadie la haya pedido.
    function pruebaIslaVistazos() {
        IslandState.collapse()
        IslandState.clearNotifications()
        IslandState.mediaActive = false
        IslandState.recordingActive = false
        IslandState.pointerInside = false

        // La grabación manda sobre la música: es lo único de la capa base que
        // sigue costando algo mientras no lo mires.
        IslandState.mediaActive = true
        igual("con música, la base es el reproductor", IslandState.base, "media")
        IslandState.recordingActive = true
        igual("grabando, manda la grabación", IslandState.base, "recording")
        IslandState.recordingActive = false
        igual("al parar, vuelve el reproductor", IslandState.base, "media")

        // Su hoja no puede sobrevivir a que se pare la grabación: quedaría un
        // cronómetro congelado con tres botones que ya no hacen nada.
        IslandState.recordingActive = true
        ok("la grabación tiene hoja", IslandState.openDestination("recording"))
        IslandState.recordingActive = false
        igual("si para la grabación, su hoja se cierra sola",
              IslandState.destination, "")

        // ── De dónde salió la hoja ──────────────────────────────────────────
        IslandState.openDestination("calendar")
        igual("abrir a mano no deja marca", IslandState.destinationSource, "")
        ok("y no se puede fijar lo que ya es tuyo", !IslandState.pinDestination())

        IslandState.closeDestination()
        IslandState.openDestination("media", "hover", "DP-1")
        igual("asomado por el ratón queda marcado", IslandState.destinationSource, "hover")
        igual("y en la pantalla que se tocó, no en la del foco",
              IslandState.destinationMonitor, "DP-1")
        ok("un vistazo sí se fija", IslandState.pinDestination())
        igual("y al fijarlo deja de ser un vistazo", IslandState.destinationSource, "")
        igual("sin cerrarse", IslandState.destination, "media")

        IslandState.closeDestination()
        igual("cerrar limpia la marca", IslandState.destinationSource, "")

        // ── El asomado solo, al cambiar de canción ──────────────────────────
        IslandState.mediaActive = true
        ok("con música y en reposo, el reproductor se asoma", IslandState.peekMedia())
        igual("y queda marcado como automático", IslandState.destinationSource, "auto")
        IslandState.closeDestination()

        // Las tres guardas. Ninguna sobra: cada una es una forma de pisar algo
        // que el usuario está mirando.
        IslandState.pushNotification({ urgency: 1, summary: "leyendo" })
        ok("no se asoma encima de una notificación", !IslandState.peekMedia())
        igual("que sigue donde estaba", IslandState.activity, "notification")
        IslandState.clearNotifications()

        IslandState.openDestination("calendar")
        ok("ni encima de una hoja que abriste tú", !IslandState.peekMedia())
        igual("que sigue abierta", IslandState.destination, "calendar")
        IslandState.closeDestination()

        IslandState.recordingActive = true
        ok("ni encima del aviso de que se está grabando", !IslandState.peekMedia())
        IslandState.recordingActive = false

        IslandState.mediaActive = false
        ok("y sin música no hay nada que asomar", !IslandState.peekMedia())

        IslandState.collapse()
        IslandState.mediaActive = false
        IslandState.recordingActive = false
    }

    function pruebaIslaNotificaciones() {
        IslandState.collapse()
        IslandState.clearNotifications()
        Globals.dnd = false

        IslandState.pushNotification({ urgency: 1, summary: "una" })
        igual("una notificación se enseña", IslandState.activity, "notification")
        igual("y es la actual", IslandState.notifCurrent.summary, "una")
        igual("sin nada esperando", IslandState.notifPending, 0)

        IslandState.pushNotification({ urgency: 1, summary: "dos" })
        igual("la segunda espera turno", IslandState.notifPending, 1)
        igual("y la primera sigue puesta", IslandState.notifCurrent.summary, "una")

        IslandState.dismissNotification()
        igual("al descartar pasa a la siguiente",
              IslandState.notifCurrent.summary, "dos")
        IslandState.dismissNotification()
        igual("y al acabarse, vuelve el reloj", IslandState.activity, "home")

        // CERO SEGUNDOS = NO CADUCA. Es lo que manda freedesktop para lo
        // crítico, y perderlo convertiría "se ha caído el servidor" en un
        // parpadeo de dos segundos.
        const antes = Settings.notifTimeoutCritical
        Settings.notifTimeoutCritical = 0
        IslandState.pushNotification({ urgency: 2, summary: "crítica" })
        igual("una crítica con timeout 0 no caduca", IslandState.transientMs, 0)
        IslandState.clearNotifications()
        Settings.notifTimeoutCritical = antes

        // No molestar descarta y no acumula.
        Globals.dnd = true
        IslandState.pushNotification({ urgency: 1, summary: "silenciada" })
        igual("con DND no entra nada", IslandState.notifQueue.length, 0)
        Globals.dnd = false

        // Tope de cola: una tormenta de avisos no debe guardarse entera.
        for (let i = 0; i < 50; i++)
            IslandState.pushNotification({ urgency: 1, summary: "t" + i })
        ok("la cola tiene tope", IslandState.notifQueue.length <= Settings.notifMaxVisible)
        ok("y guarda las MÁS RECIENTES",
           IslandState.notifQueue[IslandState.notifQueue.length - 1].summary === "t49")
        IslandState.clearNotifications()
        IslandState.collapse()
    }

    // ── El interruptor de la isla ────────────────────────────────────────────
    // La isla es una OPCIÓN, no un reemplazo: apagándola tienen que volver el
    // centro de la barra, el OSD clásico y los popups clásicos. Se comprueba
    // que los ajustes que solo significan algo en modo clásico siguen ahí,
    // porque una migración llegó a borrarlos y hubo que revertirla.
    function pruebaIslaInterruptor() {
        const antes = Settings.islandEnabled

        ok("existe el ajuste de posición de los popups clásicos",
           Settings.notifPosition !== undefined && Settings.notifPosition !== "")
        ok("y el del OSD clásico",
           Settings.osdPosition !== undefined && Settings.osdPosition !== "")
        ok("los dos se persisten", Settings._keys.indexOf("notifPosition") !== -1
                                   && Settings._keys.indexOf("osdPosition") !== -1)

        // Y siguen saneándose contra su lista de valores válidos.
        igual("una esquina inventada se rechaza",
              Settings.sanitize("notifPosition", "arriba-del-todo"), undefined)
        igual("una válida se acepta", Settings.sanitize("notifPosition", "bl"), "bl")

        // La migración v3 ya NO los borra: la que sí lo hacía fue un error.
        const config = { osdPosition: "top", notifPosition: "bl", _version: 2 }
        Settings.migrate(config)
        igual("v3 conserva la posición del OSD", config.osdPosition, "top")
        igual("v3 conserva la esquina de los popups", config.notifPosition, "bl")

        // El centro de la barra no se toca al encender la isla: se deja de
        // dibujar, que es otra cosa. Apagarla lo devuelve entero.
        const centro = BarCatalog.entriesOf(Settings.barLayout, "center")
        Settings.islandEnabled = true
        igual("con la isla encendida el layout guardado NO cambia",
              BarCatalog.entriesOf(Settings.barLayout, "center").length, centro.length)
        Settings.islandEnabled = false
        igual("y apagándola sigue igual",
              BarCatalog.entriesOf(Settings.barLayout, "center").length, centro.length)

        Settings.islandEnabled = antes
    }

    // ── Varios monitores ─────────────────────────────────────────────────────
    // Esto NO se puede comprobar mirando la pantalla: con un solo monitor todo
    // parece bien. Es justo el caso donde hace falta una prueba, porque el
    // fallo solo aparece en la máquina de otra persona.
    function pruebaMonitores() {
        IslandState.collapse()

        // Sin destino abierto, la hoja no es de nadie: todas las islas están en
        // su estado compacto.
        igual("sin hoja abierta, cualquier pantalla vale",
              IslandState.sheetBelongsTo("DP-1"), true)

        // Con un destino abierto en un monitor concreto, solo esa pantalla
        // enseña la hoja. Las demás siguen con la hora.
        IslandState.openDestination("calendar")
        IslandState.destinationMonitor = "DP-1"
        ok("la hoja es de la pantalla donde se abrió",
           IslandState.sheetBelongsTo("DP-1"))
        ok("y NO de las otras", !IslandState.sheetBelongsTo("HDMI-A-1"))
        igual("las otras se quedan en compacto",
              IslandState.compactActivity, "home")
        igual("mientras la suya enseña el calendario",
              IslandState.activity, "calendar")

        // Un transitorio se ve en TODAS: una notificación tiene que aparecer
        // mires donde mires.
        IslandState.showLevel("volume", 0.5, false)
        igual("un transitorio tapa también en las otras pantallas",
              IslandState.compactActivity, "level")
        IslandState.clearTransient()

        // Sin Hyprland no hay nombres de pantalla y hay que enseñarla en todas:
        // esconderla en todas sería peor que duplicarla.
        IslandState.destinationMonitor = ""
        ok("sin nombre de monitor, se enseña en todas",
           IslandState.sheetBelongsTo("loQueSea"))
        ok("y con pantalla sin nombre, también",
           IslandState.sheetBelongsTo(""))

        IslandState.collapse()
        igual("cerrar la hoja suelta también su monitor",
              IslandState.destinationMonitor, "")

        // La escala es una sola para todas las pantallas. La prueba no puede
        // inventarse monitores, pero sí comprobar que la detección de mezcla
        // es coherente con lo que hay: con una sola pantalla nunca hay mezcla.
        ok("con una sola pantalla no se avisa de mezcla de resoluciones",
           Quickshell.screens.length > 1 || !Theme.mixedDensity)
    }

    // ── Salto entre paneles ──────────────────────────────────────────────────
    function pruebaSwitchPanel() {
        // El recorrido sale del layout de la barra: solo entran los paneles
        // cuyo widget está puesto, y en el orden en que se ve.
        const orden = Globals.switchOrder
        ok("el recorrido no incluye paneles sin widget",
           orden.indexOf("capture") === -1 && orden.indexOf("emoji") === -1)
        for (const nombre of orden)
            ok("todo lo del recorrido es un panel de verdad: " + nombre,
               Globals.isPanel(nombre))

        ok("isPanel reconoce los que existen", Globals.isPanel("clipboard"))
        ok("isPanel rechaza los que no", !Globals.isPanel("noExisteEsto"))

        // Sin panel abierto no hay de dónde saltar: switchPanel debe decir que
        // no ha hecho nada, para que la tecla siga su camino en vez de
        // consumirse en el vacío.
        Globals.openPanel = ""
        ok("sin panel abierto no se salta", Globals.switchPanel(1) === false)
    }

    Component.onCompleted: {
        pruebaCatalogo()
        pruebaSanitize()
        pruebaMove()
        pruebaAddRemove()
        pruebaMigracion()
        pruebaSanitizeSettings()
        pruebaEmoji()
        pruebaMedia()
        pruebaBloqueo()
        pruebaTeclado()
        pruebaIsla()
        pruebaIslaVistazos()
        pruebaIslaNotificaciones()
        pruebaMonitores()
        pruebaIslaInterruptor()
        pruebaSwitchPanel()
        console.log("PRUEBA TOTAL: " + suite.total + " comprobaciones, "
                    + suite.malas + " mal")
        Qt.exit(suite.malas === 0 ? 0 : 1)
    }
}
