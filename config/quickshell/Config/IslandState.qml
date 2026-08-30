pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Config

// Máquina de estados de la isla. Solo estado: sin ventanas ni geometría, que
// las calcula Modules/Island/IslandGeometry.qml y las pinta Island.qml.
//
// La isla enseña UNA actividad, que sale de tres capas apiladas por prioridad:
//
//   transitorio  lo que acaba de pasar y se va solo (volumen, una notificación)
//   destino      donde ha entrado el usuario a propósito (calendario, medios…)
//   base         lo que hay cuando no pasa nada: reproductor si suena algo, y
//                si no, el reloj
//
// Gana la capa ocupada más alta, y un transitorio TAPA un destino sin cerrarlo:
// al caducar reaparece el destino donde estaba.
//
// Qué capas mueve cada función —la tabla contesta el "¿aquí closeDestination o
// collapse?" que aparece cada vez que algo tiene que cerrarse:
//
//   función                 transitorio      destino          cola
//   showLevel               pone "level"     ·                ·
//   pushNotification        pone "notif"     ·                encola
//   dismissNotification     quita si era él  ·                saca la primera
//   clearNotifications      quita si era él  ·                vacía
//   clearTransient          QUITA            ·                ·
//   openDestination         LIMPIA           pone             ·
//   peekMedia               exige vacío      pone ("auto")    ·
//   pinDestination          ·                fija el asomado  ·
//   toggleDestination       limpia o nada    pone o quita     ·
//   closeDestination        ·                QUITA            ·
//   collapse                QUITA            QUITA            ·
//
// De ahí salen las tres reglas del diseño:
//
//   · collapse() es el único que se lleva un transitorio no pedido, así que lo
//     llaman los gestos que significan "quita lo que hay" —ESC, clic fuera,
//     botón derecho— y no Globals al abrir un panel, que usa closeDestination.
//   · openDestination() sí limpia el transitorio: la entrada es deliberada y
//     dejar el volumen tapando el destino recién abierto no tendría sentido.
//   · peekMedia() no limpia nada; se niega a asomarse si hay algo puesto.
//
// La cola de notificaciones existe porque la isla es una sola superficie: las
// que llegan mientras hay otra puesta esperan turno en vez de perderse.
Singleton {
    id: root

    // "" en cualquiera de las dos = capa libre.
    property string transientId: ""      // "level" | "notification"
    property string destination: ""    // "calendar" | "control" | "notifs" | "media"
    // Monitor donde se abrió la hoja; vacío = en todos (sin Hyprland). Los
    // estados compactos van en todas las pantallas, pero una hoja expandida es
    // una acción deliberada sobre una pantalla concreta y no se replica.
    property string destinationMonitor: ""

    // La base se deduce, nunca se asigna, así que no puede quedarse pegada en
    // un estado viejo. Grabando va por encima de todo: es lo único de esta capa
    // que sigue costando disco mientras no se mire.
    readonly property string base: root.recordingActive ? "recording"
                                 : root.mediaActive ? "media"
                                                    : "home"

    readonly property string activity: root.transientId !== "" ? root.transientId
                                     : root.destination !== "" ? root.destination
                                                               : root.base

    // Lo que enseñan las islas que no pueden expandirse: igual pero saltándose
    // la capa de destinos, de modo que una hoja abierta en un monitor no cambia
    // lo que muestran los demás.
    readonly property string compactActivity: root.transientId !== "" ? root.transientId
                                                                      : root.base

    // Ocupa una hoja en vez de una píldora: los destinos siempre, los
    // transitorios nunca.
    readonly property bool expanded: root.destination !== "" && root.transientId === ""

    // La isla enseña algo distinto del reposo; la barra lo usa para apartarse.
    readonly property bool busy: root.activity !== "home"

    // Entradas del mundo, escritas por Modules/Island/sources/*. Aquí no se
    // consulta ningún servicio, para que esta máquina de estados pueda correr
    // sin PipeWire, MPRIS ni grabadora.
    property bool mediaActive: false
    property bool recordingActive: false

    // El puntero encima congela las cuentas atrás de esta máquina.
    property bool pointerInside: false

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

    property var notifQueue: []
    readonly property var notifCurrent: root.notifQueue.length > 0 ? root.notifQueue[0] : null
    readonly property int notifPending: Math.max(0, root.notifQueue.length - 1)

    // Encola un aviso y lo pone a la vista. La cola se recorta a
    // notifMaxVisible quedándose con los más recientes: ante una avalancha, ir
    // enseñando de uno en uno los cincuenta primeros no le sirve a nadie.
    function pushNotification(n) {
        if (!n || Settings.dnd || !Settings.notifPopupsEnabled)
            return
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

    // Segundos a la vista según la urgencia declarada por la app (0 baja ·
    // 1 normal · 2 crítica). Cero significa NUNCA, como manda freedesktop para
    // lo crítico.
    function notifLifetime(n) {
        const u = n && n.urgency !== undefined ? n.urgency : 1
        return u === 2 ? Settings.notifTimeoutCritical
             : u === 0 ? Settings.notifTimeoutLow
                       : Settings.notifTimeout
    }

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

    // Con el puntero dentro el disparo se reprograma entero en vez de
    // continuar: quien se para a leer recibe el tiempo completo al apartarse.
    readonly property Timer _transientTimer: Timer {
        id: transientTimer
        interval: root.transientMs > 0 ? root.transientMs : 1
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

    // Esta lista y el catálogo de hojas de IslandWindow tienen que cuadrar: un
    // destino sin hoja no da error, abre la isla expandida con la ranura vacía
    // y deja una píldora en blanco que parece rota.
    readonly property var destinations: ["calendar", "notifs", "media", "recording"]

    function isDestination(id) {
        return root.destinations.indexOf(id) !== -1
    }

    // Quién abrió la hoja, que decide cómo termina:
    //
    //   ""       acción deliberada (clic, atajo, IPC) — se queda hasta cerrarla
    //   "hover"  la asomó el puntero — se va al apartarlo
    //   "auto"   se asomó sola al cambiar la canción — caduca sola
    property string destinationSource: ""

    // Modal = captura teclado y clic fuera. Mira el ORIGEN y no solo si está
    // expandida: una hoja asomada sola ("auto") no puede volverse modal nunca,
    // porque se quedaría con el siguiente clic de la pantalla solo por haber
    // cambiado de canción. Fijarla con pinDestination la vuelve modal.
    readonly property bool modal: root.expanded && root.destinationSource === ""

    // Duración de un vistazo asomado solo: lo justo para leer título y artista.
    readonly property int peekMs: 4500

    // Abre una hoja y cancela el transitorio que hubiera. 'source' y 'monitor'
    // son opcionales; el monitor explícito lo usa el asomado por puntero, que
    // debe abrirse en la pantalla tocada y no en la que tiene el foco.
    //
    // Consulta Hyprland directamente en vez de Globals: esta máquina de estados
    // no depende del singleton de paneles, y así no hay ciclo entre los dos.
    function openDestination(id, source, monitor) {
        if (!root.isDestination(id))
            return false
        root.clearTransient()
        root.destinationMonitor = monitor ? monitor
                                          : (Hyprland.focusedMonitor?.name ?? "")
        root.destinationSource = source ? source : ""
        root.destination = id
        if (root.destinationSource === "auto")
            peekTimer.restart()
        else
            peekTimer.stop()
        return true
    }

    // Fija un vistazo asomado para que deje de caducar: pulsar sobre algo que
    // ya se estaba yendo significa quererlo, no cerrarlo.
    function pinDestination() {
        if (root.destination === "" || root.destinationSource === "")
            return false
        root.destinationSource = ""
        peekTimer.stop()
        return true
    }

    // Asoma el reproductor al cambiar de canción. Es una función y no un
    // openDestination suelto por las guardas: openDestination limpia el
    // transitorio, así que sin ellas este vistazo automático se llevaría por
    // delante una notificación, una hoja abierta a mano o el aviso de grabación.
    function peekMedia() {
        if (root.base !== "media")
            return false
        if (root.transientId !== "" || root.destination !== "")
            return false
        return root.openDestination("media", "auto")
    }

    // Mismo trato que el reloj de los transitorios: el puntero congela la cuenta.
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

    // ¿Le toca a esta pantalla enseñar la hoja? Sin monitor asignado no hay
    // forma de distinguirlas, y entonces se enseña en todas.
    function sheetBelongsTo(screenName) {
        return root.destinationMonitor === "" || !screenName
               || root.destinationMonitor === screenName
    }

    // Cierra las dos capas y vuelve al reposo. Lo llaman los tres gestos que
    // significan "quita lo que hay": ESC y el clic fuera desde Island.qml
    // mientras la hoja es modal, y el botón derecho sobre la isla. Es el único
    // que se lleva un transitorio, por eso no lo usa Globals al abrir un panel.
    function collapse() {
        root.clearTransient()
        root.closeDestination()
    }

    // Con "no molestar" encendido no se guardan pendientes: al apagarlo no debe
    // descargarse la cola acumulada.
    readonly property var _dndWatch: Connections {
        target: Settings
        function onDndChanged() {
            if (Settings.dnd)
                root.clearNotifications()
        }
    }

    // El destino "media" no tiene sentido sin reproductor: se cierra solo en
    // vez de dejar una hoja vacía.
    onMediaActiveChanged: {
        if (!root.mediaActive && root.destination === "media")
            root.closeDestination()
    }

    // Igual con la grabación: al parar quedaría una hoja con un cronómetro
    // congelado y botones inertes.
    onRecordingActiveChanged: {
        if (!root.recordingActive && root.destination === "recording")
            root.closeDestination()
    }
}
