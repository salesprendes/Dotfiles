pragma Singleton

import QtQuick
import Quickshell
import qs.Config

// La máquina de estados de la isla. SOLO estado: aquí no hay ni una ventana ni
// un pixel, y por eso se puede probar entera (ver tests/logica.qml). La forma
// la calcula Modules/Island/IslandGeometry.qml y la pinta Island.qml.
//
// ── LAS TRES CAPAS ──────────────────────────────────────────────────────────
// En cualquier momento la isla enseña UNA actividad, que sale de tres capas
// apiladas por prioridad:
//
//   transitorio  lo que acaba de pasar y se va solo (volumen, una notificación)
//   destino      donde has entrado tú a propósito (calendario, control…)
//   base         lo que hay cuando no pasa nada: el reproductor si suena algo,
//                y si no, el reloj
//
// Gana el de más arriba que esté ocupado. Un transitorio TAPA un destino sin
// cerrarlo: subes el volumen con el calendario abierto, ves el volumen, y al
// caducar vuelve el calendario donde estaba. Esa vuelta es la mitad de la
// gracia de una isla, y es lo que se pierde si esto se implementa con un
// simple "activity = X".
//
// ── POR QUÉ UNA COLA DE NOTIFICACIONES ──────────────────────────────────────
// Los popups de antes eran una pila: cabían cuatro a la vez. La isla es UNA,
// así que las que llegan mientras hay otra puesta tienen que esperar turno o
// se pierden. La cola las guarda y el contador dice cuántas quedan.
Singleton {
    id: root

    // ── Capas ────────────────────────────────────────────────────────────────
    // "" = capa libre.
    property string transientId: ""      // "level" | "notification"
    property string destination: ""    // "calendar" | "control" | "notifs" | "media"
    // En qué monitor se abrió la hoja. Vacío = en todos (sin Hyprland).
    //
    // Los estados COMPACTOS sí van en todas las pantallas, como la barra: una
    // notificación tiene que verse mires donde mires. Pero una hoja expandida
    // es algo que has abierto TÚ, con un clic, en un sitio concreto — abrirla
    // por triplicado sería como si pulsar un botón abriera tres ventanas.
    property string destinationMonitor: ""
    // La base no se asigna: se deduce. Así no hay forma de que se quede
    // "pegada" en un estado viejo.
    //
    // El orden importa y es este: GRABANDO por encima de todo lo demás. Una
    // grabación en marcha es lo único de esta capa que sigue costando algo
    // mientras no la mires —espacio en disco, y una pantalla que se está yendo
    // a un archivo— así que no puede quedar tapada porque además suene música.
    readonly property string base: root.recordingActive ? "recording"
                                 : root.mediaActive ? "media"
                                                    : "home"

    readonly property string activity: root.transientId !== "" ? root.transientId
                                     : root.destination !== "" ? root.destination
                                                               : root.base

    // Lo que enseña una isla que no puede expandirse (las de los otros
    // monitores): lo mismo, pero saltándose la capa de destinos. Así, mientras
    // tú tienes el calendario abierto en la pantalla de la derecha, la de la
    // izquierda sigue enseñando la hora — y si llega una notificación, la
    // enseñan las dos.
    readonly property string compactActivity: root.transientId !== "" ? root.transientId
                                                                      : root.base

    // Expandida = ocupa una hoja en vez de una píldora. Los destinos siempre
    // van expandidos (para eso has entrado); los transitorios, nunca.
    readonly property bool expanded: root.destination !== "" && root.transientId === ""

    // ¿Está la isla enseñando algo que no sea su estado de reposo? Lo usa la
    // barra para saber si tiene que apartarse.
    readonly property bool busy: root.activity !== "home"

    // ── Entradas del mundo ───────────────────────────────────────────────────
    property bool mediaActive: false
    // Las pone Modules/Island/sources/*. Aquí no se mira ni un servicio: este
    // archivo tiene que poder ejecutarse en tests/logica.qml sin PipeWire, sin
    // MPRIS y sin grabadora.
    property bool recordingActive: false
    // El puntero encima CONGELA las cuentas atrás: leer una notificación no
    // debería ser una carrera contra el reloj.
    property bool pointerInside: false

    // ── Nivel (volumen y brillo) ─────────────────────────────────────────────
    property string levelKind: ""      // "volume" | "mic" | "brightness"
    property real levelValue: 0
    property bool levelMuted: false

    function showLevel(kind, value, muted) {
        root.levelKind = kind
        root.levelValue = value
        root.levelMuted = muted === true
        root.transientId = "level"
        root._restartTransientTimer()
    }

    // ── Notificaciones ───────────────────────────────────────────────────────
    property var notifQueue: []
    readonly property var notifCurrent: root.notifQueue.length > 0 ? root.notifQueue[0] : null
    readonly property int notifPending: Math.max(0, root.notifQueue.length - 1)

    function pushNotification(n) {
        if (!n || Globals.dnd || !Settings.notifPopupsEnabled)
            return
        // Tope de cola: si llega una tormenta de avisos (una actualización
        // hablando, un script en bucle) no tiene sentido guardar cincuenta
        // para enseñarlos de uno en uno durante dos minutos. Se queda con los
        // más recientes, que es lo que la gente quiere ver.
        const max = Math.max(1, Settings.notifMaxVisible)
        const next = root.notifQueue.concat([n])
        root.notifQueue = next.length > max ? next.slice(next.length - max) : next
        root.transientId = "notification"
        root._restartTransientTimer()
    }

    // Descarta la que está a la vista y pasa a la siguiente, si la hay.
    function dismissNotification() {
        if (root.notifQueue.length === 0)
            return
        root.notifQueue = root.notifQueue.slice(1)
        if (root.notifQueue.length > 0) {
            root._restartTransientTimer()
            return
        }
        if (root.transientId === "notification")
            root.clearTransient()
    }

    function clearNotifications() {
        root.notifQueue = []
        if (root.transientId === "notification")
            root.clearTransient()
    }

    // Segundos que dura la notificación a la vista, según la urgencia que
    // declaró la app (0 baja · 1 normal · 2 crítica). CERO SIGNIFICA NUNCA: lo
    // manda la especificación de freedesktop para lo crítico, y perderlo aquí
    // convertiría "se ha caído el servidor" en un parpadeo de dos segundos.
    function notifLifetime(n) {
        const u = n && n.urgency !== undefined ? n.urgency : 1
        return u === 2 ? Settings.notifTimeoutCritical
             : u === 0 ? Settings.notifTimeoutLow
                       : Settings.notifTimeout
    }

    // ── Transitorios ─────────────────────────────────────────────────────────
    function clearTransient() {
        root.transientId = ""
        root.levelKind = ""
        transientTimer.stop()
    }

    // Duración del transitorio en curso, en milisegundos. 0 = no caduca.
    readonly property int transientMs: {
        if (root.transientId === "level")
            return Math.max(300, Math.round(Settings.osdTimeout * 1000))
        if (root.transientId === "notification")
            return Math.max(0, root.notifLifetime(root.notifCurrent) * 1000)
        return 0
    }

    function _restartTransientTimer() {
        transientTimer.stop()
        if (root.transientMs > 0)
            transientTimer.restart()
    }

    readonly property Timer _transientTimer: Timer {
        id: transientTimer
        interval: root.transientMs > 0 ? root.transientMs : 1
        // El puntero encima para el reloj. Al salir se reanuda entero, no por
        // donde iba: si te has parado a leerlo, lo justo es darte el tiempo
        // completo desde que apartas el ratón.
        running: false
        repeat: false
        onTriggered: {
            if (root.pointerInside) {
                transientTimer.restart()
                return
            }
            if (root.transientId === "notification") {
                root.dismissNotification()
                return
            }
            root.clearTransient()
        }
    }

    // ── Destinos ─────────────────────────────────────────────────────────────
    // ESTA LISTA Y EL CATÁLOGO DE HOJAS DE IslandWindow TIENEN QUE CUADRAR.
    // Un destino que se puede abrir y no tiene hoja no falla: openDestination
    // devuelve true, la isla se da por expandida, la ranura busca su componente,
    // no lo encuentra y se queda vacía — así que la isla se encoge a una
    // píldora en blanco y parece que se ha roto. Ya pasó con "media", que se
    // abría al pulsar sobre música sonando sin tener hoja que enseñar.
    //
    // "control" estaba aquí por lo mismo y nunca llegó a abrirse desde ningún
    // sitio: fuera hasta que exista la hoja que lo respalde.
    readonly property var destinations: ["calendar", "notifs", "media", "recording"]

    function isDestination(id) {
        return root.destinations.indexOf(id) !== -1
    }

    // ── Quién abrió la hoja ──────────────────────────────────────────────────
    // Tres formas de que haya un destino abierto, y se comportan distinto al
    // acabar:
    //
    //   ""       la abriste TÚ (clic, atajo, IPC) — se queda hasta que la cierres
    //   "hover"  la asomó el puntero — se va al apartarlo
    //   "auto"   se asomó sola (cambió la canción) — se va sola
    //
    // Sin esta distinción no se puede tener las dos cosas: o la hoja se queda
    // siempre (y entonces asomarse al pasar el ratón te deja el reproductor
    // abierto para siempre) o se va siempre (y entonces no puedes abrirla).
    property string destinationSource: ""

    // Lo que dura un vistazo que se asomó solo. Cuatro segundos y medio es lo
    // que se tarda en leer título y artista sin prisa; menos convierte el aviso
    // de canción nueva en un parpadeo.
    readonly property int peekMs: 4500

    // 'source' y 'monitor' son opcionales: quien abre a mano no pasa ninguno.
    // El monitor explícito lo necesita el asomado por ratón — se abre en la
    // pantalla que estás TOCANDO, que no tiene por qué ser la que tiene el foco.
    function openDestination(id, source, monitor) {
        if (!root.isDestination(id))
            return false
        // Entrar a un destino cancela lo transitorio: has decidido tú, y dejar
        // el volumen tapando el calendario que acabas de abrir sería absurdo.
        root.clearTransient()
        root.destinationMonitor = monitor ? monitor : Globals.focusedMonitorName()
        root.destinationSource = source ? source : ""
        root.destination = id
        if (root.destinationSource === "auto")
            peekTimer.restart()
        else
            peekTimer.stop()
        return true
    }

    // Un vistazo asomado se QUEDA al pulsarlo. Es lo que quiere quien alarga la
    // mano hacia algo que se iba a ir solo: pulsar para cerrar lo que ya estaba
    // cerrándose no le sirve a nadie.
    function pinDestination() {
        if (root.destination === "" || root.destinationSource === "")
            return false
        root.destinationSource = ""
        peekTimer.stop()
        return true
    }

    // El reproductor asomándose solo al cambiar de canción.
    //
    // Las tres guardas de abajo son el motivo de que esto sea una función y no
    // un `openDestination` suelto en el vigilante: no puede pisar una
    // notificación que estás leyendo (openDestination limpia lo transitorio),
    // ni una hoja que abriste tú, ni el aviso de que se está grabando.
    function peekMedia() {
        if (root.base !== "media")
            return false
        if (root.transientId !== "" || root.destination !== "")
            return false
        return root.openDestination("media", "auto")
    }

    // Mismo trato que el reloj de los transitorios: el puntero encima congela
    // la cuenta. Si te has parado a mirarlo, no se te va de debajo del ratón.
    readonly property Timer _peekTimer: Timer {
        id: peekTimer
        interval: root.peekMs
        repeat: false
        onTriggered: {
            if (root.pointerInside) {
                peekTimer.restart()
                return
            }
            if (root.destinationSource === "auto")
                root.closeDestination()
        }
    }

    function toggleDestination(id) {
        if (root.destination === id) {
            root.closeDestination()
            return false
        }
        return root.openDestination(id)
    }

    function closeDestination() {
        root.destination = ""
        root.destinationMonitor = ""
        root.destinationSource = ""
        peekTimer.stop()
    }

    // ¿Le toca a ESTA pantalla enseñar la hoja? Sin Hyprland (o sin pantalla
    // asignada) no hay forma de saber cuál es cuál, así que se enseña en todas
    // — que es lo que hacía el shell antes de que hubiera islas.
    function sheetBelongsTo(screenName) {
        return root.destinationMonitor === "" || !screenName
               || root.destinationMonitor === screenName
    }

    // Cierra todo y vuelve al reposo. Es lo que hacen ESC y el clic fuera.
    function collapse() {
        root.clearTransient()
        root.closeDestination()
    }

    // ── Coherencia ───────────────────────────────────────────────────────────
    // Con "no molestar" encendido no se guardan avisos pendientes: al apagarlo
    // no debe caerte encima la cola de la última hora.
    readonly property var _dndWatch: Connections {
        target: Globals
        function onDndChanged() {
            if (Globals.dnd)
                root.clearNotifications()
        }
    }

    // El destino "media" no tiene sentido sin reproductor: si la música se
    // acaba con el panel de medios abierto, se cierra solo en vez de dejar una
    // hoja vacía.
    onMediaActiveChanged: {
        if (!root.mediaActive && root.destination === "media")
            root.closeDestination()
    }

    // Y lo mismo con la grabación: al parar, la hoja con el botón de parar no
    // pinta nada. Sin esto se queda una hoja con un cronómetro congelado y tres
    // botones que ya no hacen nada.
    onRecordingActiveChanged: {
        if (!root.recordingActive && root.destination === "recording")
            root.closeDestination()
    }
}
