pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs.Config

// Bloqueo de sesión servido por el propio shell, con el protocolo
// ext-session-lock de Wayland (WlSessionLock) y autenticación por PAM. Al vivir
// dentro del shell comparte tema e idioma con el resto, y el compositor le da el
// foco a la capa de bloqueo por protocolo, sin carreras con el teclado
// exclusivo de un panel abierto.
//
// SEGURIDAD. Una pantalla de bloqueo que no se puede desbloquear es peor que no
// tener ninguna, así que antes de bloquear se comprueba que el servicio PAM
// elegido existe y es legible; si no, se cae a hyprlock sin llegar a mostrar
// nada propio. No hay ventana de carrera: o se bloquea sabiendo que se puede
// autenticar, o no se bloquea aquí en absoluto.
//
// Si PAM falla después, con el archivo presente, no se desbloquea por las
// buenas: eso convertiría "romper PAM" en un método para saltarse el bloqueo. Se
// muestra el error y se recuerda que siguen existiendo los TTY.
Singleton {
    id: root

    // Preferencia de servicio PAM. El de hyprlock es el que las distribuciones
    // escriben pensando en un bloqueador —contraseña y, si hay, huella, sin el
    // aparato de un inicio de sesión de consola—; 'login' es el respaldo
    // universal.
    readonly property string pamService: Settings.lockPamService !== ""
                                         ? Settings.lockPamService
                                         : (_hasHyprlockPam ? "hyprlock" : "login")
    property bool _hasHyprlockPam: false
    property bool _pamProbed: false
    // ¿Existe el archivo del servicio que se va a usar? Es la comprobación que
    // decide si se puede bloquear.
    property bool pamReady: false

    // Backend efectivo, distinto del ajuste: si el ajuste dice "hyprlock" y
    // hyprlock no está instalado, honrarlo a ciegas mandaría el bloqueo a
    // 'loginctl lock-session', o sea una sesión marcada como bloqueada sin
    // ninguna pantalla que pida la contraseña, y desde Ajustes no habría vuelta
    // porque la opción elegida seguiría siendo válida.
    //
    // Derivándolo aquí, desinstalar hyprlock devuelve el bloqueo propio sin
    // tocar el ajuste, y volver a instalarlo restaura lo elegido.
    readonly property bool hyprlockAvailable: Deps.has("hyprlock")
    readonly property string backend: (Settings.lockBackend === "hyprlock"
                                       && root.hyprlockAvailable) ? "hyprlock" : "shell"

    // "Quiero estar bloqueado". La superficie real vive en Panels/LockScreen.qml
    // y se ata a esto: el servicio no la instancia porque Services está por
    // debajo de Panels en la pila de importaciones, y montar aquí un tipo de
    // Panels cerraría el círculo.
    property bool locked: false
    // Pantalla donde se pidió el bloqueo. Vacío = sin Hyprland, y entonces la
    // tarjeta cae en la primera pantalla.
    property string lockedOnMonitor: ""
    // Autenticando: la interfaz bloquea el campo y enseña el indicador.
    property bool busy: false
    property string message: ""
    property bool messageIsError: false
    property int failures: 0

    signal failed()

    property string _pending: ""

    function lock() {
        if (root.locked)
            return
        if (root.backend === "hyprlock" || !root.pamReady) {
            root._fallback()
            return
        }
        root.message = ""
        root.messageIsError = false
        root.failures = 0
        root.busy = false
        // En qué pantalla se estaba al bloquear. La tarjeta de contraseña va
        // ahí y no en la primera que enumeró el compositor, que con varios
        // monitores la pondría en el equivocado la mayoría de las veces.
        root.lockedOnMonitor = Globals.focusedMonitorName()
        root.locked = true
    }

    // Salida de emergencia, y también opción explícita: el bloqueador externo.
    // Si tampoco está, al menos se pide a logind que bloquee la sesión, que es
    // lo que hará actuar al siguiente bloqueador registrado.
    function _fallback() {
        // El `pidof` es necesario: la señal Lock de logind puede llegar varias
        // veces, y sin el guardia cada una lanzaría otro hyprlock encima.
        Quickshell.execDetached(["sh", "-c",
            "pidof hyprlock >/dev/null && exit 0; "
            + "command -v hyprlock >/dev/null && exec hyprlock || exec loginctl lock-session"])
    }

    function submit(password) {
        if (root.busy || password === "")
            return false
        root._pending = password
        root.busy = true
        root.message = ""
        root.messageIsError = false
        // Un contexto por intento: PAM no permite reutilizar una conversación
        // ya cerrada, y dejar el anterior activo haría fallar start() por una
        // razón que no tiene que ver con la contraseña.
        if (pam.active)
            pam.abort()
        if (!pam.start()) {
            root.busy = false
            root._pending = ""
            root.messageIsError = true
            root.message = I18n.tr("Could not start authentication (%1).").arg(root.pamService)
        }
        return true
    }

    // Contexto PAM
    PamContext {
        id: pam
        config: root.pamService
        user: Quickshell.env("USER") ?? ""

        // PAM pide la contraseña con un mensaje y se contesta con lo que se
        // escribió. Los mensajes que no piden respuesta —avisos del módulo de
        // huella, caducidad— se enseñan.
        onPamMessage: {
            if (pam.responseRequired) {
                pam.respond(root._pending)
                return
            }
            if (pam.message !== "") {
                root.message = pam.message
                root.messageIsError = pam.messageIsError
            }
        }

        onCompleted: (result) => {
            root.busy = false
            root._pending = ""
            if (result === PamResult.Success) {
                root.failures = 0
                root.message = ""
                root.messageIsError = false
                root.locked = false
                return
            }
            root.failures++
            root.messageIsError = true
            root.message = result === PamResult.MaxTries
                         ? I18n.tr("Too many attempts.")
                         : I18n.tr("Wrong password.")
            root.failed()
        }

        onError: (err) => {
            root.busy = false
            root._pending = ""
            root.messageIsError = true
            root.message = I18n.tr("Authentication error (%1).").arg(PamError.toString(err))
            root.failed()
        }
    }

    // Se hace una vez al arrancar y no en cada bloqueo: al bloquear hay que
    // decidir ya, sin esperar a un proceso.
    Process {
        running: true
        command: ["sh", "-c",
            "test -r /etc/pam.d/hyprlock && echo hyprlock; "
            + "test -r /etc/pam.d/login && echo login"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const found = String(this.text || "").split("\n").map(l => l.trim())
                root._hasHyprlockPam = found.indexOf("hyprlock") !== -1
                root._pamProbed = true
                // pamService ya se resuelve con _hasHyprlockPam actualizado.
                root.pamReady = found.indexOf(root.pamService) !== -1
                if (!root.pamReady)
                    console.warn("Lock: no hay /etc/pam.d/" + root.pamService
                                 + "; el bloqueo se delegará en hyprlock")
            }
        }
    }

    // Un servicio PAM escrito a mano hay que volver a comprobarlo: si no existe,
    // más vale saberlo ahora que al bloquear.
    Connections {
        target: Settings
        function onLockPamServiceChanged() {
            if (root._pamProbed)
                customProbe.running = true
        }
    }
    Process {
        id: customProbe
        command: ["test", "-r", "/etc/pam.d/" + root.pamService]
        onExited: (code) => root.pamReady = (code === 0)
    }

    // Petición de bloqueo desde el menú de energía. Llega por señal y no por
    // llamada directa porque Config no puede importar qs.Services.
    Connections {
        target: PowerActions
        function onLockRequested() { root.lock() }
    }
}
