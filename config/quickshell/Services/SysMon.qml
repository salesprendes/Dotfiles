pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Monitor de sistema: CPU, RAM, procesos, info del SO y logo. Lee /proc con
// FileView (sin subprocesos) y usa `ps` solo para la lista de procesos con el
// panel abierto.
Singleton {
    id: s

    // Dinámico
    property real cpu: 0          // 0..100
    property real memPercent: 0
    property real memUsedGB: 0
    property real memTotalGB: 0
    property var  processes: []   // [{pid, name, cpu, mem, memKB, memMB}]
    property string loadAvg: ""
    property int  procCount: 0
    property string uptime: ""

    // Estático (info del SO)
    property string distroId: ""
    property string distroName: ""
    property string distroLogo: ""   // campo LOGO= de os-release
    property string kernel: ""
    property string arch: ""
    property string hostname: ""
    property string cpuModel: ""
    property int cpuThreads: 1

    // Disco raíz. Cambia despacio: se consulta al arrancar y al abrir
    // el panel Resumen, sin sondeo periódico.
    property real diskPercent: 0
    property real diskUsedGB: 0
    property real diskTotalGB: 0

    property bool _pendingProcessRefresh: false
    property real _prevTotal: 0
    property real _prevIdle: 0

    // Recogida periódica. CPU/RAM/carga/uptime se releen de /proc con FileView
    // (QML puro, sin subprocesos). Solo la lista de procesos necesita `ps`, y
    // solo mientras el panel SystemMonitor está abierto. Carga asíncrona (sin
    // blockLoading): onLoaded salta al terminar cada reload() sin bloquear la GUI.
    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
        watchChanges: false
        onLoaded: s._parseStat(statFile.text())
    }
    FileView {
        id: memFile
        path: "/proc/meminfo"
        printErrors: false
        watchChanges: false
        onLoaded: s._parseMem(memFile.text())
    }
    FileView {
        id: loadFile
        path: "/proc/loadavg"
        printErrors: false
        watchChanges: false
        onLoaded: s._parseLoad(loadFile.text())
    }
    FileView {
        id: upFile
        path: "/proc/uptime"
        printErrors: false
        watchChanges: false
        onLoaded: s._parseUptime(upFile.text())
    }

    // Sondeo solo cuando alguien muestra los datos: widget de la barra
    // (cpu/ram), panel SystemMonitor, Dashboard (anillos) o Control Center
    // (uptime). triggeredOnStart: al abrir cualquiera refresca al momento.
    Timer {
        interval: 5000
        running: Settings.showSysmon || Globals.sysMonOpen
                 || Globals.dashboardOpen || Globals.controlCenterOpen
        repeat: true
        triggeredOnStart: true
        onTriggered: s.refreshStats(false)
    }

    // Tras el resume: recalibra la base de CPU (los contadores de /proc/stat dan
    // un salto raro al cruzar el suspend, evita un pico falso) y refresca ya.
    Connections {
        target: Resume
        // Solo el primer pulso: /proc está disponible de inmediato al despertar,
        // no necesita reintentos como la red o el brillo.
        function onResumed() {
            if (Resume.recoveryPulse !== 1) return
            s._prevTotal = 0
            s._prevIdle = 0
            s.refreshStats(Globals.sysMonOpen)
        }
    }

    Connections {
        target: Globals
        function onSysMonOpenChanged() {
            if (Globals.sysMonOpen)
                processRefreshTimer.restart()
            else {
                processRefreshTimer.stop()
                s.processes = []   // libera la lista (cientos de objetos) al cerrar
            }
        }
        function onDashboardOpenChanged() {
            if (Globals.dashboardOpen && !diskProc.running)
                diskProc.running = true
        }
    }

    Process {
        id: diskProc
        running: true
        command: ["sh", "-c", "df -P -B1 / | tail -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                // "df -P": fs total usado libre capacidad punto-de-montaje
                const f = (this.text || "").trim().split(/\s+/)
                if (f.length < 5)
                    return
                const total = parseFloat(f[1]) || 0
                const used = parseFloat(f[2]) || 0
                if (total > 0) {
                    s.diskTotalGB = total / 1e9
                    s.diskUsedGB = used / 1e9
                    s.diskPercent = 100 * used / total
                }
            }
        }
    }

    Timer {
        id: processRefreshTimer
        interval: 320
        onTriggered: s.refreshStats(true)
    }

    // Refresco periódico de la lista de procesos solo con el panel abierto.
    Timer {
        interval: 20000
        running: Globals.sysMonOpen
        repeat: true
        onTriggered: s.refreshStats(true)
    }

    function refreshStats(withProcesses) {
        statFile.reload()
        memFile.reload()
        loadFile.reload()
        upFile.reload()
        if (!withProcesses)
            return
        if (psProc.running) {
            _pendingProcessRefresh = true
            return
        }
        psProc.running = true
    }

    Process {
        id: psProc
        command: ["ps", "-eo", "pid,comm,pcpu,pmem,rss", "--sort=-pcpu", "--no-headers"]
        onExited: {
            if (s._pendingProcessRefresh) {
                s._pendingProcessRefresh = false
                processRefreshTimer.restart()
            }
        }
        stdout: StdioCollector {
            onStreamFinished: s._parsePs(this.text)
        }
    }

    Process {
        id: killer
        property string pendingPid: ""
        command: ["kill", pendingPid]
        onRunningChanged: {
            if (!running)
                s.refreshStats(true)
        }
    }

    function killProcess(pid) {
        const p = String(pid || "")
        if (!/^[1-9][0-9]*$/.test(p) || killer.running)
            return
        killer.pendingPid = p
        killer.running = true
    }

    // Información estática del SO (una vez)
    Process {
        id: info
        running: true
        command: ["sh", "-c",
            ". /etc/os-release 2>/dev/null; echo \"id=$ID\"; echo \"name=$PRETTY_NAME\"; echo \"logo=$LOGO\"; " +
            "echo \"kernel=$(uname -r)\"; echo \"arch=$(uname -m)\"; " +
            "echo \"host=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)\"; " +
            "echo \"cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')\"; " +
            "echo \"threads=$(getconf _NPROCESSORS_ONLN 2>/dev/null || grep -c '^processor' /proc/cpuinfo || echo 1)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const ln = lines[i]
                    const eq = ln.indexOf("=")
                    if (eq < 0) continue
                    const k = ln.substring(0, eq), v = ln.substring(eq + 1).trim()
                    if (k === "id") s.distroId = v
                    else if (k === "name") s.distroName = v
                    else if (k === "logo") s.distroLogo = v
                    else if (k === "kernel") s.kernel = v
                    else if (k === "arch") s.arch = v
                    else if (k === "host") s.hostname = v
                    else if (k === "cpu") s.cpuModel = v
                    else if (k === "threads") s.cpuThreads = Math.max(1, parseInt(v) || 1)
                }
            }
        }
    }

    function _parseStat(txt) {
        const ln = (txt || "").split("\n")[0] || ""
        if (ln.indexOf("cpu") !== 0)
            return
        const p = ln.trim().split(/\s+/).slice(1).map(Number)
        const idle = (p[3] || 0) + (p[4] || 0)
        const total = p.reduce((a, b) => a + (b || 0), 0)
        const dt = total - s._prevTotal
        const di = idle - s._prevIdle
        if (dt > 0 && s._prevTotal > 0)
            s.cpu = Math.max(0, Math.min(100, 100 * (dt - di) / dt))
        s._prevTotal = total
        s._prevIdle = idle
    }

    function _parseMem(txt) {
        let memTotal = 0, memAvail = 0
        const lines = (txt || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const ln = lines[i]
            if (ln.indexOf("MemTotal") === 0) memTotal = parseInt(ln.replace(/\D+/g, ""))
            else if (ln.indexOf("MemAvailable") === 0) { memAvail = parseInt(ln.replace(/\D+/g, "")); break }
        }
        if (memTotal > 0) {
            s.memTotalGB = memTotal / 1024 / 1024
            s.memUsedGB = (memTotal - memAvail) / 1024 / 1024
            s.memPercent = 100 * (memTotal - memAvail) / memTotal
        }
    }

    function _parseLoad(txt) {
        // loadavg: "0.50 0.42 0.40 1/1234 5678"
        const f = (txt || "").trim().split(/\s+/)
        if (f.length < 3)
            return
        s.loadAvg = f.slice(0, 3).join("  ")
        if (f[3] && f[3].indexOf("/") >= 0) s.procCount = parseInt(f[3].split("/")[1]) || 0
    }

    function _parseUptime(txt) {
        const secs = parseFloat((txt || "").trim().split(/\s+/)[0]) || 0
        if (secs > 0) s.uptime = s._fmtUptime(secs)
    }

    function _parsePs(txt) {
        // Si el panel se cerró mientras corría `ps`, no retengas la lista.
        if (!Globals.sysMonOpen)
            return
        const procs = []
        const lines = (txt || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].trim().match(/^(\d+)\s+(.+?)\s+([\d.]+)\s+([\d.]+)\s+(\d+)$/)
            if (m) {
                const cpuWholeSystem = (parseFloat(m[3]) || 0) / Math.max(1, s.cpuThreads)
                const memKB = parseInt(m[5]) || 0
                procs.push({
                    pid: m[1],
                    name: m[2],
                    cpu: cpuWholeSystem,
                    mem: parseFloat(m[4]),
                    memKB: memKB,
                    memMB: memKB / 1024
                })
            }
        }
        s.processes = procs
    }

    function _fmtUptime(sec) {
        const d = Math.floor(sec / 86400)
        const h = Math.floor((sec % 86400) / 3600)
        const m = Math.floor((sec % 3600) / 60)
        let out = ""
        if (d > 0) out += d + "d "
        if (d > 0 || h > 0) out += h + "h "
        return out + m + "m"
    }

    // Logo de la distribución mediante glifos Nerd Font.
    readonly property var _distroGlyphs: ({
        "arch": "󰣇", "archlinux": "󰣇", "debian": "󰣚", "ubuntu": "󰕈",
        "fedora": "󰣛", "nixos": "󱄅", "gentoo": "󰣨", "manjaro": "󱘊",
        "opensuse": "", "opensuse-tumbleweed": "", "endeavouros": "",
        "artix": "", "void": "", "archcraft": "", "guix": "",
        "linuxmint": "󰣭", "pop": "", "elementary": "", "zorin": ""
    })
    // ¿Hay glifo Nerd Font para esta distro?
    readonly property bool hasGlyph: _distroGlyphs[distroId] !== undefined
    readonly property string distroGlyph: _distroGlyphs[distroId] ?? "󰌽"  // fallback genérico

    readonly property string distroLogoIcon: distroLogo !== ""
        ? Quickshell.iconPath(distroLogo, true) : ""

    function processIcon(command) {
        const cmd = (command || "").toLowerCase()
        if (cmd.includes("firefox") || cmd.includes("chrome") || cmd.includes("browser") || cmd.includes("chromium") || cmd.includes("brave"))
            return "󰖟"   // web
        if (cmd.includes("code") || cmd.includes("editor") || cmd.includes("vim") || cmd.includes("nvim"))
            return "󰨞"   // code
        if (cmd.includes("terminal") || cmd.includes("kitty") || cmd.includes("bash") || cmd.includes("zsh") || cmd.includes("fish"))
            return "󰆍"   // terminal
        if (cmd.includes("music") || cmd.includes("audio") || cmd.includes("spotify") || cmd.includes("pipewire") || cmd.includes("pulse"))
            return "󰝚"   // música
        if (cmd.includes("video") || cmd.includes("vlc") || cmd.includes("mpv"))
            return "󰐊"   // play
        if (cmd.includes("systemd") || cmd.includes("elogind") || cmd.includes("kernel") || cmd.includes("kthread") || cmd.includes("kworker"))
            return "󰒓"   // settings
        return "󰍛"       // memoria (por defecto)
    }
}
