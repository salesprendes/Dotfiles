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
    property real swapUsedGB: 0
    property real swapTotalGB: 0
    property var  processes: []   // [{pid, name, cpu, mem, memKB, memMB}]
    property string loadAvg: ""
    // Tareas totales del sistema —procesos más sus hilos— del cuarto campo de
    // /proc/loadavg. No son procesos: la lista de `ps` cuenta bastantes menos.
    property int  taskCount: 0

    // Procesos de verdad. Solo se saben con la lista de `ps` cargada, y esa solo
    // se pide con un panel a la vista; sin ella se cae a las tareas.
    readonly property int procCount: s.processes.length > 0 ? s.processes.length
                                                            : s.taskCount
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

    // Disco raíz. Cambia despacio: se consulta al arrancar y al abrir el panel
    // Resumen, sin sondeo periódico.
    property real diskPercent: 0
    property real diskUsedGB: 0
    property real diskTotalGB: 0

    // Temperaturas en °C desde hwmon (0 = sensor no encontrado) y tasas de red
    // en KB/s desde /proc/net/dev, calculadas por diferencia entre lecturas.
    property real cpuTemp: 0
    property real gpuTemp: 0
    property real gpuBusy: -1
    property string _gpuBusyPath: ""
    // Sesenta puntos, uno por segundo: un minuto de historia, que es la ventana en
    // la que una subida de CPU todavía significa algo. Solo se muestrea con la
    // aplicación de monitor abierta.
    //
    // Se reasignan arrays nuevos en vez de mutar los existentes, porque QML no
    // notifica los cambios hechos dentro de un array y la gráfica no se enteraría
    // de que hay un punto más.
    readonly property int historyLen: 60
    property var cpuHistory: []
    property var memHistory: []
    property var gpuHistory: []
    property var netDownHistory: []
    property var netUpHistory: []
    property var diskIoHistory: []

    function _push(arr, v) {
        const out = arr.length >= s.historyLen ? arr.slice(arr.length - s.historyLen + 1)
                                               : arr.slice()
        out.push(v)
        return out
    }

    function sampleHistory() {
        s.cpuHistory = s._push(s.cpuHistory, s.cpu)
        s.memHistory = s._push(s.memHistory, s.memPercent)
        // gpuBusy vale -1 cuando no hay sensor: se guarda 0 para no meter un
        // valor negativo en una serie que se dibuja de 0 a 100.
        s.gpuHistory = s._push(s.gpuHistory, Math.max(0, s.gpuBusy))
        s.netDownHistory = s._push(s.netDownHistory, s.netDownKB)
        s.netUpHistory = s._push(s.netUpHistory, s.netUpKB)
        s.diskIoHistory = s._push(s.diskIoHistory, s.diskReadKB + s.diskWriteKB)
    }

    function clearHistory() {
        s.cpuHistory = []
        s.memHistory = []
        s.gpuHistory = []
        s.netDownHistory = []
        s.netUpHistory = []
        s.diskIoHistory = []
    }

    // E/S de disco en KB/s, de /proc/diskstats por diferencia entre lecturas.
    // 'df' diría lo lleno que está el disco, que no dice nada de si algo lo está
    // machacando ahora mismo.
    property real diskReadKB: 0
    property real diskWriteKB: 0
    property real _prevRead: 0
    property real _prevWrite: 0
    property real _prevDiskMs: 0

    property real netDownKB: 0
    property real netUpKB: 0
    property string _cpuTempPath: ""
    property string _gpuTempPath: ""
    property real _prevRx: 0
    property real _prevTx: 0
    property real _prevNetMs: 0

    property bool _pendingProcessRefresh: false
    property real _prevTotal: 0
    property real _prevIdle: 0

    // Recogida periódica: CPU, RAM, carga y uptime se releen de /proc con
    // FileView, sin subprocesos. Solo la lista de procesos necesita `ps`, y solo
    // con el panel abierto. La carga es asíncrona, así que onLoaded salta al
    // terminar cada reload() sin bloquear la interfaz.
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
    FileView {
        id: diskIoFile
        path: "/proc/diskstats"
        printErrors: false
        watchChanges: false
        onLoaded: s._parseDiskIo(diskIoFile.text())
    }
    FileView {
        id: netFile
        path: "/proc/net/dev"
        printErrors: false
        watchChanges: false
        onLoaded: s._parseNet(netFile.text())
    }
    FileView {
        id: cpuTempFile
        path: s._cpuTempPath
        printErrors: false
        watchChanges: false
        onLoaded: s.cpuTemp = (parseInt(cpuTempFile.text()) || 0) / 1000
    }
    FileView {
        id: gpuTempFile
        path: s._gpuTempPath
        printErrors: false
        watchChanges: false
        onLoaded: s.gpuTemp = (parseInt(gpuTempFile.text()) || 0) / 1000
    }
    FileView {
        id: gpuBusyFile
        path: s._gpuBusyPath
        printErrors: false
        watchChanges: false
        onLoaded: s.gpuBusy = parseInt(gpuBusyFile.text())
    }

    // Localiza una vez los sensores hwmon de CPU y GPU y el contador de
    // ocupación: los índices hwmonN y cardN cambian entre arranques, así que
    // 'find' los descubre todos y grep vuelca "ruta:contenido" por línea.
    Process {
        id: hwmonScan
        running: true
        command: ["find", "-L", "/sys/class/hwmon", "/sys/class/drm", "-maxdepth", "3",
            "(", "-path", "*/hwmon*/name", "-o", "-name", "gpu_busy_percent", ")",
            "-exec", "grep", ".", "{}", "+"]
        stdout: StdioCollector {
            onStreamFinished: s._parseHwmon(this.text)
        }
    }

    // Sondeo solo cuando alguien muestra los datos: widget de la barra, panel
    // del monitor, dashboard o centro de control. triggeredOnStart hace que
    // abrir cualquiera refresque al momento.
    Timer {
        interval: 5000
        // El widget de la barra no cuenta si la barra está escondida por una
        // ventana a pantalla completa: sondear para no pintar nada es trabajo
        // invisible. Los paneles sí cuentan siempre, porque si hay uno abierto
        // se está mirando.
        running: (BarCatalog.has(Settings.barLayout, "sysmon")
                  && !Globals.focusedHasFullscreen()) || Globals.sysMonOpen
                 || Globals.sysMonAppOpen
                 || Globals.dashboardOpen || Globals.controlCenterOpen
        repeat: true
        triggeredOnStart: true
        onTriggered: s.refreshStats(false)
    }

    // Tras el resume recalibra la base de CPU —los contadores de /proc/stat dan
    // un salto al cruzar el suspend y saldría un pico falso— y refresca.
    Connections {
        target: Resume
        // Solo el primer pulso: /proc está disponible de inmediato al
        // despertar, no necesita reintentos como la red o el brillo.
        function onResumed() {
            if (Resume.recoveryPulse !== 1) return
            s._prevTotal = 0
            s._prevIdle = 0
            s.refreshStats(Globals.sysMonOpen)
        }
    }

    // Quién quiere la lista de procesos: el popout de la barra, la aplicación o
    // el dashboard. Se decide en un solo sitio porque son tres consumidores del
    // mismo dato. Vive en el servicio y no dentro del Connections, donde sería
    // una función del propio Connections y no se podría llamar desde fuera.
    function _verMonitor() {
        if (Globals.sysMonOpen || Globals.sysMonAppOpen)
            processRefreshTimer.restart()
        else {
            processRefreshTimer.stop()
            // Libera la lista, que son cientos de objetos, si tampoco la está
            // usando el dashboard.
            if (!Globals.dashboardOpen)
                s.processes = []
        }
    }

    Connections {
        target: Globals
        function onSysMonOpenChanged() { s._verMonitor() }
        // Cerrar la aplicación suelta además el minuto de historia: reabrirla
        // debe enseñar lo que pasa ahora, no una gráfica con un agujero.
        function onSysMonAppOpenChanged() {
            s._verMonitor()
            if (Globals.sysMonAppOpen) {
                // Las tasas de red y disco se calculan por diferencia con la
                // lectura anterior, que puede ser de hace horas: la primera
                // muestra sería todo lo transferido desde entonces dividido por
                // un instante. Con la marca de tiempo a cero, la primera lectura
                // solo guarda contadores y no publica tasa.
                s._prevNetMs = 0
                s._prevDiskMs = 0
            } else {
                s.clearHistory()
            }
        }
        function onDashboardOpenChanged() {
            if (Globals.dashboardOpen && !diskProc.running)
                diskProc.running = true
            // Al cerrar el dashboard, misma liberación que hace el monitor.
            if (!Globals.dashboardOpen && !Globals.sysMonOpen && !Globals.sysMonAppOpen)
                s.processes = []
        }
    }

    Process {
        id: diskProc
        running: true
        command: ["df", "-P", "-B1", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                // "df -P": cabecera y una línea por sistema de archivos; se
                // toma la última no vacía.
                const lines = (this.text || "").trim().split("\n")
                const f = (lines[lines.length - 1] || "").trim().split(/\s+/)
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

    // Muestreo de las gráficas a un segundo: el refresco general del shell va a
    // cinco, que en una línea temporal deja escalones en vez de curva.
    //
    // Reactiva 'netFile' aparte porque las tasas de red se calculan por
    // diferencia entre dos lecturas: sin releer, la gráfica sería una recta.
    Timer {
        interval: 1000
        running: Globals.sysMonAppOpen
        repeat: true
        // Se muestrea antes de pedir el refresco: las lecturas de /proc son
        // asíncronas, así que lo que hay ahora en las propiedades es el tick
        // anterior ya completo y no uno a medias.
        onTriggered: {
            s.sampleHistory()
            s.refreshStats(false)
            netFile.reload()
            diskIoFile.reload()
        }
    }

    Timer {
        id: processRefreshTimer
        interval: 320
        onTriggered: s.refreshStats(true)
    }

    // Refresco periódico de la lista de procesos, solo con el panel abierto.
    Timer {
        interval: 20000
        running: Globals.sysMonOpen || Globals.sysMonAppOpen
        repeat: true
        onTriggered: s.refreshStats(true)
    }

    function refreshStats(withProcesses) {
        statFile.reload()
        memFile.reload()
        // loadavg y uptime solo se muestran en paneles: con el widget de la
        // barra a secas no hace falta releerlos ni parsearlos en cada tick.
        if (Globals.sysMonOpen || Globals.sysMonAppOpen || Globals.dashboardOpen
                || Globals.controlCenterOpen || Globals.settingsOpen) {
            loadFile.reload()
            upFile.reload()
        }
        if (!withProcesses)
            return
        netFile.reload()
        if (_cpuTempPath !== "") cpuTempFile.reload()
        if (_gpuTempPath !== "") gpuTempFile.reload()
        if (_gpuBusyPath !== "") gpuBusyFile.reload()
        if (psProc.running) {
            _pendingProcessRefresh = true
            return
        }
        psProc.running = true
    }

    Process {
        id: psProc
        command: ["ps", "-eo", "pid,user:16,comm,pcpu,pmem,rss", "--sort=-pcpu", "--no-headers"]
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

    // Información estática del SO, leída una vez de /etc y /proc con FileView;
    // solo la arquitectura necesita un proceso.
    FileView {
        id: osReleaseFile
        path: "/etc/os-release"
        printErrors: false
        watchChanges: false
        onLoaded: s._parseOsRelease(osReleaseFile.text())
    }
    FileView {
        id: hostnameFile
        path: "/proc/sys/kernel/hostname"
        printErrors: false
        watchChanges: false
        onLoaded: s.hostname = (hostnameFile.text() || "").trim()
    }
    FileView {
        id: kernelFile
        path: "/proc/sys/kernel/osrelease"
        printErrors: false
        watchChanges: false
        onLoaded: s.kernel = (kernelFile.text() || "").trim()
    }
    FileView {
        id: cpuinfoFile
        path: "/proc/cpuinfo"
        printErrors: false
        watchChanges: false
        onLoaded: s._parseCpuinfo(cpuinfoFile.text())
    }
    Process {
        running: true
        command: ["uname", "-m"]
        stdout: StdioCollector {
            onStreamFinished: s.arch = (this.text || "").trim()
        }
    }

    // Extrae ID, PRETTY_NAME y LOGO de os-release.
    function _parseOsRelease(txt) {
        const lines = (txt || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const eq = lines[i].indexOf("=")
            if (eq < 0) continue
            const k = lines[i].substring(0, eq)
            const v = lines[i].substring(eq + 1).trim().replace(/^"|"$/g, "")
            if (k === "ID") s.distroId = v
            else if (k === "PRETTY_NAME") s.distroName = v
            else if (k === "LOGO") s.distroLogo = v
        }
    }

    // Modelo y número de hilos de la CPU.
    function _parseCpuinfo(txt) {
        const lines = (txt || "").split("\n")
        let threads = 0
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("processor") === 0) threads++
            else if (s.cpuModel === "" && lines[i].indexOf("model name") === 0) {
                const c = lines[i].indexOf(":")
                if (c >= 0) s.cpuModel = lines[i].substring(c + 1).trim()
            }
        }
        s.cpuThreads = Math.max(1, threads)
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
        let memTotal = 0, memAvail = 0, swapTotal = 0, swapFree = 0
        const lines = (txt || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const ln = lines[i]
            if (ln.indexOf("MemTotal") === 0) memTotal = parseInt(ln.replace(/\D+/g, ""))
            else if (ln.indexOf("MemAvailable") === 0) memAvail = parseInt(ln.replace(/\D+/g, ""))
            else if (ln.indexOf("SwapTotal") === 0) swapTotal = parseInt(ln.replace(/\D+/g, ""))
            else if (ln.indexOf("SwapFree") === 0) { swapFree = parseInt(ln.replace(/\D+/g, "")); break }
        }
        if (memTotal > 0) {
            s.memTotalGB = memTotal / 1024 / 1024
            s.memUsedGB = (memTotal - memAvail) / 1024 / 1024
            s.memPercent = 100 * (memTotal - memAvail) / memTotal
        }
        s.swapTotalGB = swapTotal / 1024 / 1024
        s.swapUsedGB = Math.max(0, swapTotal - swapFree) / 1024 / 1024
    }

    // Resuelve las rutas de temperatura desde el volcado de nombres hwmon.
    function _parseHwmon(txt) {
        const lines = (txt || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const sep = lines[i].indexOf(":")
            if (sep < 0) continue
            const path = lines[i].substring(0, sep)
            const name = lines[i].substring(sep + 1).trim()
            if (_gpuBusyPath === "" && path.indexOf("gpu_busy_percent") >= 0) {
                _gpuBusyPath = path
                continue
            }
            const dir = path.replace(/\/name$/, "")
            if (_cpuTempPath === "" && ["k10temp", "zenpower", "coretemp"].indexOf(name) >= 0)
                _cpuTempPath = dir + "/temp1_input"
            else if (_gpuTempPath === "" && ["amdgpu", "nouveau", "nvidia"].indexOf(name) >= 0)
                _gpuTempPath = dir + "/temp1_input"
        }
    }

    // Tasas de red por diferencia entre lecturas de /proc/net/dev, sumando todas
    // las interfaces menos loopback.
    // /proc/diskstats: campo 3 = nombre, 6 = sectores leídos, 10 = escritos. Un
    // sector son 512 B siempre en esta interfaz, pase lo que pase con el tamaño
    // real del disco. Se suman solo los discos enteros y no sus particiones, o
    // cada byte se contaría dos veces.
    function _parseDiskIo(txt) {
        const now = Date.now()
        let rd = 0, wr = 0
        const lines = (txt || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const f = lines[i].trim().split(/\s+/)
            if (f.length < 10)
                continue
            const name = f[2]
            // Partición: dígito tras 'p' (nvme0n1p2), o dígito sobre un nombre
            // que no acaba en dígito (sda1). Los discos base se quedan.
            if (/^nvme\d+n\d+p\d+$/.test(name) || /^(sd|vd|hd)[a-z]+\d+$/.test(name)
                    || /^mmcblk\d+p\d+$/.test(name) || /^(loop|ram|zram)/.test(name))
                continue
            rd += parseFloat(f[5]) || 0
            wr += parseFloat(f[9]) || 0
        }
        if (_prevDiskMs > 0 && now > _prevDiskMs) {
            const dt = (now - _prevDiskMs) / 1000
            // sectores × 512 B ÷ 1024 = KB
            diskReadKB = Math.max(0, (rd - _prevRead) * 512 / 1024 / dt)
            diskWriteKB = Math.max(0, (wr - _prevWrite) * 512 / 1024 / dt)
        }
        _prevRead = rd
        _prevWrite = wr
        _prevDiskMs = now
    }

    function _parseNet(txt) {
        const now = Date.now()
        let rx = 0, tx = 0
        const lines = (txt || "").split("\n")
        for (let i = 2; i < lines.length; i++) {
            const parts = lines[i].trim().split(/\s+/)
            if (parts.length < 10 || parts[0].indexOf("lo:") === 0)
                continue
            rx += parseFloat(parts[1]) || 0
            tx += parseFloat(parts[9]) || 0
        }
        if (_prevNetMs > 0 && now > _prevNetMs) {
            const dt = (now - _prevNetMs) / 1000
            netDownKB = Math.max(0, (rx - _prevRx) / 1024 / dt)
            netUpKB = Math.max(0, (tx - _prevTx) / 1024 / dt)
        }
        _prevRx = rx
        _prevTx = tx
        _prevNetMs = now
    }

    function _parseLoad(txt) {
        // loadavg: "0.50 0.42 0.40 1/1234 5678"
        const f = (txt || "").trim().split(/\s+/)
        if (f.length < 3)
            return
        s.loadAvg = f.slice(0, 3).join("  ")
        if (f[3] && f[3].indexOf("/") >= 0) s.taskCount = parseInt(f[3].split("/")[1]) || 0
    }

    function _parseUptime(txt) {
        const secs = parseFloat((txt || "").trim().split(/\s+/)[0]) || 0
        if (secs > 0) s.uptime = s._fmtUptime(secs)
    }

    function _parsePs(txt) {
        // Si al terminar `ps` ya no hay ningún consumidor a la vista, no se
        // retiene la lista: son cientos de objetos para nadie. La lista de
        // consumidores tiene que estar completa, y esta condición vive lejos de
        // las otras compuertas del archivo: dejarse una da una lista vacía sin
        // ningún error que lo explique.
        if (!Globals.sysMonOpen && !Globals.sysMonAppOpen && !Globals.dashboardOpen)
            return
        const procs = []
        const lines = (txt || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            // pid usuario comando %cpu %mem rss. El nombre va con .+? porque
            // puede llevar espacios; el usuario no, así que se ancla antes.
            const m = lines[i].trim().match(/^(\d+)\s+(\S+)\s+(.+?)\s+([\d.]+)\s+([\d.]+)\s+(\d+)$/)
            if (m) {
                const cpuWholeSystem = (parseFloat(m[4]) || 0) / Math.max(1, s.cpuThreads)
                const memKB = parseInt(m[6]) || 0
                procs.push({
                    pid: m[1],
                    user: m[2],
                    name: m[3],
                    cpu: cpuWholeSystem,
                    mem: parseFloat(m[5]),
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
