pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs.Config

// Bloqueo de sesión servido por el propio shell, con el protocolo
// ext-session-lock de Wayland (WlSessionLock) y autenticación por PAM.
//
// POR QUÉ NO SEGUIR DELEGANDO EN HYPRLOCK. Tres razones concretas:
//   · Tema. hyprlock tiene su propia configuración y su propia paleta: al
//     cambiar de tema en Ajustes, la pantalla de bloqueo se quedaba con los
//     colores viejos hasta regenerar su archivo.
//   · Idioma. No hablaba el idioma del shell.
//   · Y una carrera fea: había que dormir 0,25 s antes de lanzarlo para que el
//     popout abierto soltara el teclado exclusivo, porque si no hyprlock
//     aparecía con el panel encima. Al vivir dentro del shell, eso desaparece:
//     el compositor da el foco a la capa de bloqueo por protocolo.
//
// SEGURIDAD. Una pantalla de bloqueo que no se puede desbloquear es peor que
// no tener ninguna. Por eso, ANTES de bloquear se comprueba que el servicio
// PAM elegido existe y es legible; si no, se cae a hyprlock sin llegar a
// mostrar nada nuestro. No hay ventana de carrera: o bloqueamos nosotros
// sabiendo que podemos autenticar, o no bloqueamos nosotros en absoluto.
//
// Si PAM falla DESPUÉS (start() devuelve false con el archivo presente) no se
// desbloquea por las buenas: eso convertiría "romper PAM" en un método para
// saltarse el bloqueo. Se muestra el error y se recuerda que sigue habiendo
// TTYs (Ctrl+Alt+F2).
Singleton {
    id: root

    // ── Servicio PAM ─────────────────────────────────────────────────────────
    // 'hyprlock' es el mejor de los habituales cuando está: es el que las
    // distribuciones ya escriben pensando en un bloqueador (auth por
    // contraseña y, si hay, huella, sin el pam_securetty ni el resto del
    // aparato de un inicio de sesión de consola). 'login' es el respaldo
    // universal.
    readonly property string pamService: Settings.lockPamService !== ""
                                         ? Settings.lockPamService
                                         : (_hasHyprlockPam ? "hyprlock" : "login")
    property bool _hasHyprlockPam: false
    property bool _pamProbed: false
    // ¿Existe el archivo del servicio que vamos a usar? Es la comprobación que
    // decide si nos atrevemos a bloquear.
    property bool pamReady: false

    // "Quiero estar bloqueado". La superficie de verdad (WlSessionLock) vive en
    // Panels/LockScreen.qml y se ata a esto.
    //
    // El servicio NO instancia la ventana: Services está por debajo de Panels
    // en la pila de importaciones (Panels importa qs.Services), y montar aquí
    // un tipo de Panels cerraría el círculo. Así que el servicio guarda el
    // estado y la autenticación, y la capa de arriba pone la superficie.
    property bool locked: false
    // Pantalla donde se pidió el bloqueo. Vacío = sin Hyprland, y entonces la
    // tarjeta cae en la primera pantalla, que es lo único que se puede hacer.
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
        if (Settings.lockBackend === "hyprlock" || !root.pamReady) {
            root._fallback()
            return
        }
        root.message = ""
        root.messageIsError = false
        root.failures = 0
        root.busy = false
        // En qué pantalla estabas al bloquear. La tarjeta de contraseña va ahí
        // y no en Quickshell.screens[0], que es simplemente la primera que
        // enumeró el compositor: con dos monitores, eso ponía la contraseña en
        // el otro la mitad de las veces, y con tres, dos de cada tres.
        root.lockedOnMonitor = Globals.focusedMonitorName()
        root.locked = true
    }

    // Salida de emergencia y opción explícita del usuario: el bloqueador de
    // fuera. Si tampoco está, al menos se pide a logind que bloquee la sesión,
    // que es lo que hará que el siguiente bloqueador registrado actúe.
    function _fallback() {
        // El `pidof` no es adorno: la señal Lock de logind puede llegar varias
        // veces (hypridle al inactivarse y systemd antes de suspender), y sin
        // el guardia cada una lanzaría otro hyprlock encima del anterior.
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
        // ya cerrada, y dejar el anterior 'active' haría que start() fallara
        // por una razón que no tiene nada que ver con la contraseña.
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

    // ── Contexto PAM ─────────────────────────────────────────────────────────
    PamContext {
        id: pam
        config: root.pamService
        user: Quickshell.env("USER") ?? ""

        // PAM pide la contraseña con un mensaje ("Password: "). Se contesta con
        // lo que el usuario escribió. Los mensajes que NO piden respuesta
        // (avisos del módulo de huella, caducidad de contraseña) se enseñan.
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

    // ── Sondeo del servicio PAM ──────────────────────────────────────────────
    // Se hace una vez al arrancar y no en cada bloqueo: en el momento de
    // bloquear hay que decidir YA, sin esperar a un proceso.
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

    // Un servicio PAM escrito a mano en Ajustes hay que volver a comprobarlo:
    // si no existe, más vale saberlo ahora que al bloquear.
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
    // llamada directa porque Config no puede importar qs.Services (ver
    // Config/Globals.qml).
    Connections {
        target: Globals
        function onLockRequested() { root.lock() }
    }
}
