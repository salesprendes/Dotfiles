pragma Singleton
//  ╔══════════════════════════════════════════════════════════╗
//  ║   GreeterState — estado central + puente con greetd (PAM)  ║
//  ║   Usuarios, sesiones, estado de autenticación y memoria.   ║
//  ╚══════════════════════════════════════════════════════════╝
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import "GreetdEnv.js" as Env

Singleton {
    id: root

    // ── Datos del sistema ─────────────────────────────────────
    property var users: []                 // [{ name, full, shell }]
    property var sessions: []              // [{ id, name, exec }] (índice 0 = por defecto)

    // ── Selección actual ──────────────────────────────────────
    property string selectedUser: ""
    property string selectedUserShell: ""
    property int    sessionIndex: 0
    readonly property var currentSession:
        (sessionIndex >= 0 && sessionIndex < sessions.length) ? sessions[sessionIndex] : null

    // ── Estado de autenticación ───────────────────────────────
    property string prompt: "Contraseña"
    property string error:  ""
    property bool   secret: true
    property bool   busy:   false
    property bool   revealSecret: false
    readonly property bool masked: secret && !revealSecret
    readonly property bool available: Greetd.available
    signal failed()

    // ── Memoria (último login) ────────────────────────────────
    property string lastUser: ""
    property string _wantSession: ""
    // Índice preferido para resaltar en el selector (último usuario).
    readonly property int preferredIndex: {
        if (lastUser === "") return 0
        for (let i = 0; i < users.length; i++) if (users[i].name === lastUser) return i
        return 0
    }

    // ── Lectura de usuarios (/etc/passwd, sin subproceso) ─────
    FileView {
        id: passwdFile
        path: "/etc/passwd"
        blockLoading: true
        printErrors: false
        onLoaded: root._loadUsers()
    }
    function _loadUsers() {
        const out = Env.parsePasswd(passwdFile.text())
        root.users = out
        // Con un único usuario no hay nada que elegir → salta a la clave.
        if (out.length === 1 && root.selectedUser === "")
            root.pickUser(out[0].name)
    }

    // ── Lectura de sesiones (/usr/share/wayland-sessions) ─────
    Process {
        id: sessionScan
        running: false
        command: ["sh", "-c",
            "for f in /usr/share/wayland-sessions/*.desktop /usr/share/xsessions/*.desktop; do " +
            "[ -e \"$f\" ] || continue; echo \"@@SESSION@@$f\"; cat \"$f\"; done"]
        stdout: StdioCollector { onStreamFinished: root._loadSessions(this.text) }
    }
    function _loadSessions(dump) {
        const found = Env.parseSessions(dump || "")
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

    // ── Memoria: leer al arrancar / escribir al entrar ────────
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
        } catch (e) { /* fichero ausente o corrupto → se ignora */ }
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

    // ── Puente con greetd (PAM) ───────────────────────────────
    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            root.error = ""
            root.secret = !echoResponse
            root.prompt = (message && message.trim() !== "")
                          ? message.replace(/:\s*$/, "")
                          : (echoResponse ? "Usuario" : "Contraseña")
            if (!responseRequired && error) root.error = message
            root.busy = false
        }
        function onAuthFailure(message) {
            root.busy = false
            root.revealSecret = false
            root.error = (message && message.trim() !== "") ? message : "Autenticación fallida"
            root.failed()
            // Reabre la sesión PAM del MISMO usuario para reintentar.
            if (root.selectedUser !== "")
                Greetd.createSession(root.selectedUser)
        }
        function onReadyToLaunch() {
            root.busy = true
            root._saveState()
            const exec = root.currentSession ? root.currentSession.exec : Config.defaultSession
            Greetd.launch(Env.launchArgv(root.selectedUserShell, exec), [], true)
        }
        function onError(err) { root.busy = false; root.error = err }
    }

    // ── Acciones ──────────────────────────────────────────────
    function pickUser(name) {
        if (busy || !name) return
        error = ""
        revealSecret = false
        selectedUser = name
        selectedUserShell = ""
        for (let i = 0; i < users.length; i++)
            if (users[i].name === name) { selectedUserShell = users[i].shell || ""; break }
        if (Greetd.available) Greetd.createSession(name)
    }
    function backToUsers() {
        if (busy) return
        if (Greetd.available) Greetd.cancelSession()
        error = ""
        revealSecret = false
        selectedUser = ""
    }
    function submit(text) {
        if (busy) return
        if (Greetd.state === GreetdState.Authenticating) {
            busy = true
            error = ""
            Greetd.respond(text)
        }
    }

    Component.onCompleted: {
        // Base con la sesión por defecto; el escaneo la amplía si procede.
        sessions = [{ id: "hyprland-watchdog",
                      name: Config.defaultSessionName,
                      exec: Config.defaultSession }]
        if (Config.showSessionPicker) sessionScan.running = true
        if (!Greetd.available)
            error = "greetd no disponible (ejecuta bajo greetd)"
    }
}
