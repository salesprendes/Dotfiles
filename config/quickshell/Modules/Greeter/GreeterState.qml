pragma Singleton
// Estado central + puente con greetd (PAM): usuarios, sesiones, auth y memoria.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

Singleton {
    id: root

    // Datos del sistema
    property var users: []                 // [{ name, full, shell }]
    property var sessions: []              // [{ id, name, exec }] (índice 0 = por defecto)

    // Selección actual
    property string selectedUser: ""
    property string selectedUserShell: ""
    property int    sessionIndex: 0
    readonly property var currentSession:
        (sessionIndex >= 0 && sessionIndex < sessions.length) ? sessions[sessionIndex] : null

    // Estado de autenticación
    property string prompt: I18n.tr("Contraseña", "Password")
    property string error:  ""
    property bool   secret: true
    property bool   busy:   false
    property bool   revealSecret: false
    readonly property bool masked: secret && !revealSecret
    readonly property bool available: Greetd.available
    signal failed()

    // Máquina de estados de auth. El reintento se conduce por
    // Greetd.onStateChanged: al fallar NO se recrea la sesión, se cancela y se
    // espera a que el estado caiga a Inactive; la nueva se abre SOLO con greetd
    // libre (createSession jamás cae sobre una sesión viva). Evita las carreras
    // del "unable to send message: Connection refused" y el descuadre de estado
    // tras un fallo.
    property bool   canRespond: false     // hay una pregunta de PAM esperando respuesta
    property string _pwBuffer: ""         // clave aceptada, pendiente de enviar
    property bool   _submitPending: false // el usuario pidió enviar; se hará al llegar el prompt
    property bool   _leaving: false       // login correcto en curso (arrancando sesión)
    property string _lastPamError: ""     // último PAM_ERROR_MSG (motivo real del fallo)

    // Todo guiado por eventos (sin timers): cada vez que se pone busy=true es
    // por una acción que greetd SIEMPRE contesta (authMessage, authFailure,
    // readyToLaunch o error), y cada señal vuelve a bajar busy.
    //
    // 'available' es la red de seguridad: si greetd cae (socket cerrado),
    // Quickshell pone available=false y aquí se recupera el control. Un cuelgue
    // de PAM que NO cierra el socket no tiene evento, pero no pasa en un greeter
    // solo-contraseña (PAM responde al momento).
    onAvailableChanged: {
        if (available) {
            // (Re)disponible: si hay usuario elegido y greetd libre, abre sesión.
            if (selectedUser !== "" && Greetd.state === GreetdState.Inactive)
                Greetd.createSession(selectedUser)
        } else if (!_leaving) {
            // greetd desapareció y no estábamos entrando: no dejes "Cargando".
            _resetAuth()
            error = I18n.tr("greetd no disponible", "greetd unavailable")
        }
    }

    // Memoria (último login)
    property string lastUser: ""
    property string _wantSession: ""
    // Índice preferido para resaltar en el selector (último usuario).
    readonly property int preferredIndex: {
        if (lastUser === "") return 0
        for (let i = 0; i < users.length; i++) if (users[i].name === lastUser) return i
        return 0
    }

    // Lectura de usuarios (/etc/passwd, sin subproceso)
    FileView {
        id: passwdFile
        path: "/etc/passwd"
        blockLoading: true
        printErrors: false
        onLoaded: root._loadUsers()
    }
    function _loadUsers() {
        const out = _parsePasswd(passwdFile.text())
        root.users = out
        // Con un único usuario no hay nada que elegir: directo a la clave.
        if (out.length === 1 && root.selectedUser === "")
            root.pickUser(out[0].name)
    }

    // Lectura de sesiones (/usr/share/wayland-sessions)
    Process {
        id: sessionScan
        running: false
        // Se descartan sesiones cuyo binario no está instalado (p.ej.
        // hyprland-uwsm.desktop sin uwsm): elegirlas produce un login
        // que muere al instante y devuelve al greeter.
        command: ["sh", "-c",
            "for f in /usr/share/wayland-sessions/*.desktop /usr/share/xsessions/*.desktop; do " +
            "[ -e \"$f\" ] || continue; " +
            "exe=$(sed -n 's/^Exec=\\([^ ]*\\).*/\\1/p' \"$f\" | head -n 1); " +
            "[ -n \"$exe\" ] && command -v \"$exe\" >/dev/null 2>&1 || continue; " +
            "echo \"@@SESSION@@$f\"; cat \"$f\"; done"]
        stdout: StdioCollector { onStreamFinished: root._loadSessions(this.text) }
    }
    function _loadSessions(dump) {
        const found = _parseSessions(dump || "")
        const list = []
        let watchdogIdx = -1
        for (let i = 0; i < found.length; i++) {
            const first = found[i].exec.split(/\s+/)[0].replace(/.*\//, "")
            if (first === "start-hyprland" && watchdogIdx < 0) watchdogIdx = list.length
            list.push(found[i])
        }
        // Garantiza una sesión que use el watchdog 'start-hyprland' y ponla la
        // primera (= por defecto): así no salta el aviso "iniciaste sin
        // start-hyprland". Si el sistema ya trae una (p.ej. hyprland.desktop),
        // se reutiliza en vez de duplicarla; si no, se crea una sintética.
        if (watchdogIdx < 0)
            list.unshift({ id: "hyprland-watchdog",
                           name: Config.defaultSessionName,
                           exec: Config.defaultSession })
        else if (watchdogIdx > 0)
            list.unshift(list.splice(watchdogIdx, 1)[0])
        root.sessions = list
        root._applyWantedSession()
    }
    function _applyWantedSession() {
        if (root._wantSession === "") return
        for (let i = 0; i < root.sessions.length; i++)
            if (root.sessions[i].id === root._wantSession) { root.sessionIndex = i; return }
    }
    function cycleSession(delta) {
        if (sessions.length < 2) return
        sessionIndex = (sessionIndex + delta + sessions.length) % sessions.length
    }

    // Memoria: leer al arrancar / escribir al entrar
    FileView {
        id: stateFile
        path: Config.statePath
        blockLoading: true
        printErrors: false
        onLoaded: root._loadState()
    }
    function _loadState() {
        if (!Config.rememberLastUser) return
        try {
            const j = JSON.parse(stateFile.text() || "{}")
            root.lastUser = j.user || ""
            root._wantSession = j.session || ""
            root._applyWantedSession()
        } catch (e) { /* fichero ausente o corrupto: se ignora */ }
    }
    function _saveState() {
        if (!Config.rememberLastUser) return
        const obj = { user: root.selectedUser,
                      session: root.currentSession ? root.currentSession.id : "" }
        // Escritura detached vía argv (sin problemas de comillas). Si el
        // path no es escribible, se ignora sin romper el login.
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$(dirname \"$1\")\" 2>/dev/null; printf '%s' \"$2\" > \"$1\" 2>/dev/null",
            "greetd-state", Config.statePath, JSON.stringify(obj)])
    }

    // Puente con greetd (PAM) · máquina de estados
    Connections {
        target: Greetd

        // Pregunta / mensaje de PAM.
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            // Mensaje de ERROR de PAM (PAM_ERROR_MSG): no es un prompt, es el
            // motivo del fallo (p.ej. "Authentication failure", "Permission
            // denied") y no pide respuesta. Se guarda para clasificar el aviso
            // en _failAttempt y NO se pinta como etiqueta del campo.
            if (error && !responseRequired) {
                root._lastPamError = (message || "").trim()
                return
            }
            root.secret = !echoResponse
            root.prompt = _localizedPrompt(message, echoResponse)
            root.canRespond = responseRequired
            // Mensaje informativo (no pide respuesta): Quickshell responde solo
            // con cadena vacía y la conversación PAM avanza. No se toca nada más.
            if (!responseRequired) return
            // Pregunta real: si el usuario ya pidió enviar, se manda ahora la
            // clave guardada; si no, se espera a que escriba.
            if (root._submitPending) {
                root._sendResponse()
            } else {
                root.busy = false
            }
        }

        // Única señal que dispara la reapertura: cuando greetd termina de
        // desmontar (estado Inactive) y hay un envío pendiente, se abre una
        // sesión nueva EN EL SIGUIENTE ciclo (no encadenada al cancel).
        function onStateChanged() {
            if (Greetd.state !== GreetdState.Inactive) return
            root.canRespond = false
            if (root._submitPending && root.selectedUser !== "" && Greetd.available) {
                Qt.callLater(root._startSession)
            } else if (!root._submitPending) {
                root.busy = false
            }
        }

        function onReadyToLaunch() {
            root.canRespond = false
            root._submitPending = false
            root._pwBuffer = ""
            root._leaving = true      // login correcto: silencia la red de 'available'
            root.busy = true
            root._saveState()
            const exec = root.currentSession ? root.currentSession.exec : Config.defaultSession
            Greetd.launch(_launchArgv(root.selectedUserShell, exec), [], true)
        }

        // Fallo de autenticación "limpio" (greetd manda auth_error).
        function onAuthFailure(message) {
            root._failAttempt(message, false)
        }

        // greetd nunca enseña su jerga interna. El fallo de contraseña llega
        // como auth_error o, por la carrera del worker de PAM ya muerto, como
        // error de transporte; los dos son "contraseña incorrecta" de cara al
        // usuario. El resto de errores muestran un aviso genérico.
        function onError(err) {
            const transient = /unable to send message|connection refused|broken pipe/i.test(err || "")
            // Eco del cancel de un fallo ya mostrado: se ignora (no re-agita ni
            // repinta). Si el fallo llega directamente como error de transporte,
            // 'busy' aún está activo y sí se procesa.
            if (transient && !root.busy && !root.canRespond
                    && Greetd.state === GreetdState.Inactive && root.error !== "")
                return
            root._failAttempt("", !transient)
        }
    }

    // Acciones
    function pickUser(name) {
        if (busy || !name) return
        _resetAuth()
        error = ""
        revealSecret = false
        selectedUser = name
        selectedUserShell = ""
        for (let i = 0; i < users.length; i++)
            if (users[i].name === name) { selectedUserShell = users[i].shell || ""; break }
        _startSession()
    }

    function backToUsers() {
        if (busy) return
        _resetAuth()
        error = ""
        revealSecret = false
        selectedUser = ""     // impide que onStateChanged reabra una sesión
        if (Greetd.available && Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession()
    }

    // Acepta la contraseña. Devuelve true si se toma (el campo puede limpiarse):
    // se envía ya si hay una pregunta esperando, o se guarda y se manda en
    // cuanto la sesión (re)abierta presente el prompt. Se guía por 'canRespond',
    // no por Greetd.state (que puede quedar descuadrado tras un fallo).
    function submit(text) {
        if (busy || selectedUser === "" || !Greetd.available) return false
        error = ""
        _pwBuffer = text
        _submitPending = true
        busy = true
        if (canRespond)
            _sendResponse()                              // hay prompt: envía ya
        else if (Greetd.state === GreetdState.Inactive)
            _startSession()                              // abre sesión: el prompt disparará el envío
        // Si greetd sigue desmontando, onStateChanged(Inactive) abrirá la sesión
        // y el prompt enviará la clave. Nada más que hacer aquí.
        return true
    }

    // Internos de la máquina de estados

    // Crea la sesión PAM SOLO si greetd está libre. Si aún no lo está, no fuerza
    // nada: onStateChanged/onAvailableChanged la abrirán al liberarse.
    function _startSession() {
        if (!Greetd.available || selectedUser === "") return
        if (Greetd.state !== GreetdState.Inactive) return
        Greetd.createSession(selectedUser)
    }

    // Envía la clave guardada como respuesta a la pregunta de PAM en curso.
    function _sendResponse() {
        if (!canRespond) return
        busy = true
        canRespond = false
        _submitPending = false
        _lastPamError = ""            // motivo fresco por intento
        const pw = _pwBuffer
        _pwBuffer = ""
        Greetd.respond(pw)
    }

    // Punto único de "intento fallido". Muestra un aviso claro, limpia lo
    // sensible y CANCELA la sesión (no la recrea aquí): al caer a Inactive, el
    // siguiente envío del usuario abrirá una nueva. 'isError' = error genérico
    // en vez de contraseña incorrecta.
    function _failAttempt(message, isError) {
        // OJO: 'message' (de authFailure) es jerga interna de greetd/PAM
        // —"pam_authenticate: AUTH_ERR"—, NO texto para el usuario, así que no
        // se muestra. El único motivo legible es un PAM_ERROR_MSG previo
        // (_lastPamError, p.ej. "Account locked", "Password expired").
        const pamReason = _lastPamError.trim()
        _lastPamError = ""
        _resetAuth()
        revealSecret = false
        if (isError) {
            error = I18n.tr("Error de autenticación, inténtalo de nuevo",
                            "Authentication error, please try again")
        } else {
            const wrong = I18n.tr("Contraseña incorrecta", "Incorrect password")
            // Motivo concreto conocido (bloqueada/caducada…): traducido y con
            // PRIORIDAD, porque su texto de PAM suele traer "failed" (p.ej.
            // "locked due to N failed logins") y si no lo confundiría el filtro
            // genérico con un fallo normal.
            const special = _localizedReason(pamReason)
            // Fórmula genérica de "fallo de autenticación" → contraseña mal.
            const generic = pamReason === "" ||
                /authentication\s+(failure|error)|auth(entication)?\s+failed|incorrect|permission\s+denied|login\s+(incorrect|failed)|try\s+again/i.test(pamReason)
            error = special !== "" ? special
                  : (secret && generic) ? wrong
                  : (pamReason !== "" ? pamReason : wrong)
        }
        failed()
        if (Greetd.available && Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession()
    }

    // Traduce los motivos de PAM más habituales al idioma activo. Devuelve ""
    // si no reconoce el mensaje (entonces se muestra el texto original de PAM).
    // PAM emite en inglés (locale C del usuario 'greeter'), de ahí las claves.
    function _localizedReason(raw) {
        const s = (raw || "").toLowerCase()
        if (s.indexOf("locked") !== -1)
            return I18n.tr("Cuenta bloqueada", "Account locked")
        if (/password (has )?expired|expired.*password|change your password|new password required|password.*change/.test(s))
            return I18n.tr("Contraseña caducada, debes cambiarla",
                           "Password expired, you must change it")
        if (/account (has )?expired|expired.*account/.test(s))
            return I18n.tr("Cuenta caducada", "Account expired")
        if (s.indexOf("disabled") !== -1)
            return I18n.tr("Cuenta deshabilitada", "Account disabled")
        return ""
    }

    // Localiza el prompt del campo. PAM manda su etiqueta en inglés ("Password:",
    // "login:"); los prompts estándar se traducen al idioma activo y los no
    // estándar (PIN, código 2FA…) se muestran tal cual los envía PAM.
    function _localizedPrompt(message, echoResponse) {
        const raw = (message || "").replace(/:\s*$/, "").trim()
        const s = raw.toLowerCase()
        if (raw === "")
            return echoResponse ? I18n.tr("Usuario", "Username")
                                : I18n.tr("Contraseña", "Password")
        if (s.indexOf("password") !== -1)
            return I18n.tr("Contraseña", "Password")
        if (s === "login" || s.indexOf("username") !== -1 || s === "user name")
            return I18n.tr("Usuario", "Username")
        return raw
    }

    // Limpia el estado transitorio de autenticación (no toca selectedUser).
    function _resetAuth() {
        busy = false
        canRespond = false
        _submitPending = false
        _pwBuffer = ""
        _leaving = false
    }

    // Helpers puros

    // /etc/passwd → [{ name, full, shell }]  (solo cuentas humanas)
    function _parsePasswd(txt) {
        const out = []
        if (!txt) return out
        const lines = txt.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const f = lines[i].split(":")
            if (f.length < 7) continue
            const uid = parseInt(f[2], 10)
            const sh = f[6] || ""
            if (uid >= 1000 && uid < 65000
                    && sh.indexOf("nologin") === -1 && sh.indexOf("false") === -1) {
                const gecos = (f[4] || "").split(",")[0].trim()
                out.push({ name: f[0], full: gecos !== "" ? gecos : f[0], shell: sh })
            }
        }
        return out
    }

    // Volcado concatenado de los .desktop de sesión (con separador
    // "@@SESSION@@<ruta>\n<contenido>") → [{ id, name, exec }]
    function _parseSessions(dump) {
        const out = []
        if (!dump) return out
        const blocks = dump.split("@@SESSION@@")
        for (let b = 0; b < blocks.length; b++) {
            const blk = blocks[b]
            if (!blk.trim()) continue
            const nl = blk.indexOf("\n")
            if (nl < 0) continue
            const path = blk.substring(0, nl).trim()
            const body = blk.substring(nl + 1)
            let name = "", exec = "", hidden = false, inEntry = false
            const lines = body.split("\n")
            for (let i = 0; i < lines.length; i++) {
                const ln = lines[i].trim()
                if (ln.startsWith("[")) { inEntry = (ln === "[Desktop Entry]"); continue }
                if (!inEntry) continue
                if (ln.startsWith("Name=") && !name)          name = ln.substring(5).trim()
                else if (ln.startsWith("Exec=") && !exec)     exec = ln.substring(5).trim()
                else if (ln.startsWith("Hidden=true") || ln.startsWith("NoDisplay=true")) hidden = true
            }
            if (exec && !hidden) {
                const id = path.substring(path.lastIndexOf("/") + 1).replace(/\.desktop$/, "")
                out.push({ id: id, name: name || id, exec: exec })
            }
        }
        return out
    }

    // argv para Greetd.launch(): ejecuta la sesión a través del shell de
    // LOGIN del usuario (para heredar PATH/perfil completos) y 'exec' para
    // no dejar un shell colgando de padre. Igual que entrar desde una TTY.
    function _launchArgv(loginShell, sessionExec) {
        const sh = (loginShell && loginShell !== "") ? loginShell : "/bin/sh"
        // greetd une este argv con espacios y lo vuelve a interpretar con el
        // shell del usuario, así que el comando de -c debe ir entre comillas
        // simples para sobrevivir; sin ellas "-c exec" quedaba como no-op y
        // la sesión moría al instante sin error.
        // La salida de la sesión iría a la consola VT (se ve el logo y los
        // logs de start-hyprland al arrancar): se guarda en un log en su
        // lugar, que además sirve para depurar sesiones que no arrancan.
        const inner = "mkdir -p \"$HOME/.local/state\"; " +
                      "exec " + sessionExec +
                      " >\"$HOME/.local/state/greetd-session.log\" 2>&1"
        return [sh, "-l", "-c",
                "'" + inner.replace(/'/g, "'\\''") + "'"]
    }

    Component.onCompleted: {
        // Base con la sesión por defecto; el escaneo la amplía si procede.
        sessions = [{ id: "hyprland-watchdog",
                      name: Config.defaultSessionName,
                      exec: Config.defaultSession }]
        if (Config.showSessionPicker) sessionScan.running = true
        if (!Greetd.available)
            error = I18n.tr("greetd no disponible (ejecuta bajo greetd)",
                            "greetd unavailable (run under greetd)")
    }
}
