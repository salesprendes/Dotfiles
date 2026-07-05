pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Capturas y grabacion de pantalla para Hyprland.
// Usa hyprshot como backend principal de capturas y gpu-screen-recorder para video.
Singleton {
    id: cap

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp"
    readonly property string pidFile: runtimeDir + "/qs-screen-recording.pid"
    readonly property bool loaded: _loaded

    property bool hyprshotAvailable: false
    property bool grimAvailable: false
    property bool slurpAvailable: false
    property bool wlCopyAvailable: false
    property bool notifyAvailable: false
    property bool gsrAvailable: false
    property bool jqAvailable: false
    property bool hyprctlAvailable: false
    property bool pactlAvailable: false
    property bool ffmpegAvailable: false

    // Valores por defecto NEUTROS (nombres XDG estándar en inglés). Se
    // sobrescriben al arrancar con `xdg-user-dir PICTURES/VIDEOS`, que devuelve
    // la carpeta LOCALIZADA según el idioma del sistema (Imágenes, Bilder…).
    // Solo se usan durante el instante previo a esa resolución o si
    // `xdg-user-dir` no está disponible.
    property string picturesDir: home + "/Pictures"
    property string videosDir: home + "/Videos"
    property var monitorOptions: [{ text: "Enfocado", value: "focused" }]

    property string captureMode: "region"       // region | monitor | window | all
    property string captureMonitor: "focused"
    property bool freeze: true
    property bool saveToDisk: true
    property bool copyToClipboard: true
    property bool showNotify: true
    property bool showPointer: true
    property string imageFormat: "png"          // png | jpg
    property int imageQuality: 90
    property string screenshotDir: ""
    property string screenshotFilename: ""

    property bool videoMode: false
    property string recordMonitor: "focused"
    property bool recordSystemAudio: true
    property bool recordMic: false
    property string videoFormat: "mkv"
    property int videoFps: 60
    property string videoCodec: "auto"
    property string audioCodec: "aac"
    property string videoQuality: "medium"
    property string videoDir: ""
    property string videoFilename: ""

    property bool isRecording: false
    property bool isPaused: false
    property int recordingElapsed: 0
    property bool showRecordingPill: true
    property bool pillSuppressed: false
    property string recordPillScreenName: ""
    property int recordPillX: -1
    property int recordPillY: 12
    property bool recordPillExpanded: false

    property string status: ""
    property string lastOutputPath: ""
    property bool _loaded: false
    property bool _applying: false
    property bool _persisting: false
    property bool _savingPillPosition: false

    readonly property var modeOptions: [
        { text: "Región",  value: "region",  icon: "󰩭" },
        { text: "Monitor", value: "monitor", icon: "󰍹" },
        { text: "Ventana", value: "window",  icon: "󰖯" },
        { text: "Todo",    value: "all",     icon: "󰍺" }
    ]
    readonly property var imageFormatOptions: [
        { text: "PNG", value: "png" },
        { text: "JPG", value: "jpg" }
    ]
    readonly property var videoFormatOptions: [
        { text: "MKV", value: "mkv" },
        { text: "MP4", value: "mp4" }
    ]
    readonly property var fpsOptions: [
        { text: "30 FPS", value: 30 },
        { text: "60 FPS", value: 60 },
        { text: "120 FPS", value: 120 }
    ]
    readonly property var qualityOptions: [
        { text: "Media", value: "medium" },
        { text: "Alta", value: "high" },
        { text: "Muy alta", value: "very_high" },
        { text: "Ultra", value: "ultra" }
    ]
    readonly property var videoCodecOptions: [
        { text: "Auto", value: "auto" },
        { text: "H.264", value: "h264" },
        { text: "HEVC", value: "hevc" },
        { text: "AV1", value: "av1" },
        { text: "VP9", value: "vp9" }
    ]
    readonly property var audioCodecOptions: [
        { text: "AAC", value: "aac" },
        { text: "Opus", value: "opus" },
        { text: "FLAC", value: "flac" }
    ]

    readonly property var _keys: [
        "captureMode", "captureMonitor", "freeze",
        "saveToDisk", "copyToClipboard", "showNotify", "showPointer",
        "imageFormat", "imageQuality", "screenshotDir", "screenshotFilename",
        "recordMonitor", "recordSystemAudio", "recordMic", "videoFormat",
        "videoFps", "videoCodec", "audioCodec", "videoQuality", "videoDir",
        "videoFilename", "showRecordingPill", "recordPillScreenName",
        "recordPillX", "recordPillY", "recordPillExpanded"
    ]
    readonly property var _enums: ({
        "captureMode": ["region", "monitor", "window", "all"],
        "imageFormat": ["png", "jpg"],
        "videoFormat": ["mkv", "mp4"],
        "videoFps": [30, 60, 120],
        "videoCodec": ["auto", "h264", "hevc", "av1", "vp9"],
        "audioCodec": ["aac", "opus", "flac"],
        "videoQuality": ["medium", "high", "very_high", "ultra"]
    })
    readonly property var _numBounds: ({
        "imageQuality": [10, 100],
        "recordPillX": [-1, 20000],
        "recordPillY": [0, 20000]
    })
    readonly property var _intKeys: ["imageQuality", "videoFps", "recordPillX", "recordPillY"]

    IpcHandler {
        target: "screenCapture"
        function toggle(): string { cap.toggleToolbar(); return Globals.screenCaptureOpen ? "opened" : "closed" }
        function open(): string { cap.openToolbar(false); return "opened" }
        function record(): string { cap.openToolbar(true); return "opened" }
        function close(): string { cap.closeToolbar(); return "closed" }
        function capture(): string { cap.capture(); return "capture" }
        // 'edit' se conserva como alias de captura normal para no romper el
        // atajo Super+Shift+Print de Hyprland; ya no abre ningún editor.
        function edit(): string { cap.capture(); return "capture" }
        function stop(): string { cap.stopRecording(); return "stop" }
        function pause(): string { cap.pauseRecording(); return "pause" }
        function resume(): string { cap.resumeRecording(); return "resume" }
        function cancelRecording(): string { cap.cancelRecording(); return "cancelled" }
        function recordingStarted(): string { cap.recordingStarted(); return "started" }
        function recordingStopped(): string { cap.recordingStopped(); return "stopped" }
    }

    IpcHandler {
        target: "screenCaptureToolbar"
        function toggle(): string { cap.toggleToolbar(); return Globals.screenCaptureOpen ? "opened" : "closed" }
        function open(): string { cap.openToolbar(false); return "opened" }
        function record(): string { cap.openToolbar(true); return "opened" }
        function close(): string { cap.closeToolbar(); return "closed" }
        function cancelRecording(): string { cap.cancelRecording(); return "cancelled" }
        function recordingStarted(): string { cap.recordingStarted(); return "started" }
        function recordingStopped(): string { cap.recordingStopped(); return "stopped" }
    }

    function sanitize(k, val) {
        if (_enums[k] !== undefined)
            return _enums[k].indexOf(val) !== -1 ? val : undefined
        if (_numBounds[k] !== undefined) {
            if (typeof val !== "number" || !isFinite(val)) return undefined
            let v = Math.max(_numBounds[k][0], Math.min(_numBounds[k][1], val))
            if (_intKeys.indexOf(k) !== -1) v = Math.round(v)
            return v
        }
        const def = cap[k]
        if (typeof def === "boolean") return typeof val === "boolean" ? val : undefined
        if (typeof def === "number") return (typeof val === "number" && isFinite(val)) ? val : undefined
        if (typeof def === "string") return typeof val === "string" ? val : undefined
        return val
    }

    // Los ajustes se guardan en settings.json (Settings.screenCapture), unificados
    // con el resto de la configuración. Aquí solo aplicamos ese sub-objeto (con
    // nuestro saneo por rangos/enums) y lo volvemos a escribir al cambiar. Los
    // guardas _applying/_persisting evitan bucles entre aplicar y persistir.
    function applyFromSettings() {
        const o = (Settings.screenCapture && typeof Settings.screenCapture === "object")
                    ? Settings.screenCapture : ({})
        _applying = true
        for (const k of _keys) {
            if (o[k] === undefined || o[k] === null) continue
            const v = sanitize(k, o[k])
            if (v !== undefined) cap[k] = v
        }
        _applying = false
        _loaded = true
        // Primera vez (sin ajustes guardados): vuelca los valores por defecto
        // para que settings.json muestre todas las opciones editables.
        if (Object.keys(o).length === 0)
            persist()
    }

    function persist() {
        if (!_loaded || _applying) return
        const o = {}
        for (const k of _keys) o[k] = cap[k]
        _persisting = true
        Settings.screenCapture = o
        _persisting = false
    }

    function scheduleSave() {
        if (_loaded && !_applying)
            saveTimer.restart()
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
    }

    function parseDateTemplate(template) {
        const now = new Date()
        function pad(value) { return value < 10 ? "0" + value : "" + value }
        return String(template)
            .replace(/%Y/g, now.getFullYear())
            .replace(/%m/g, pad(now.getMonth() + 1))
            .replace(/%d/g, pad(now.getDate()))
            .replace(/%H/g, pad(now.getHours()))
            .replace(/%M/g, pad(now.getMinutes()))
            .replace(/%S/g, pad(now.getSeconds()))
    }

    function timestamp() {
        return parseDateTemplate("%Y-%m-%d_%H-%M-%S")
    }

    function expandHome(path) {
        const p = String(path || "")
        return p.replace(/^~/, home)
    }

    function defaultScreenshotDir() {
        return picturesDir + "/Screenshots"
    }

    function effectiveScreenshotDir() {
        return screenshotDir.trim() !== "" ? expandHome(screenshotDir.trim()) : defaultScreenshotDir()
    }

    function effectiveVideoDir() {
        return videoDir.trim() !== "" ? expandHome(videoDir.trim()) : videosDir
    }

    function filenameFromTemplate(template, prefix, ext) {
        let name = template.trim() !== "" ? parseDateTemplate(template.trim())
                                          : prefix + "_" + timestamp()
        if (name.indexOf(".") === -1)
            name += "." + ext
        return name
    }

    function screenshotFilenameResolved() {
        return filenameFromTemplate(screenshotFilename, "screenshot", imageFormat)
    }

    function videoFilenameResolved() {
        return filenameFromTemplate(videoFilename, "recording", videoFormat)
    }

    function mimeForImageFormat() {
        return imageFormat === "jpg" ? "image/jpeg" : "image/png"
    }

    function ffmpegJpegQuality() {
        return Math.max(2, Math.min(31, Math.round(2 + (100 - imageQuality) * 0.29)))
    }

    function optionText(options, value) {
        for (let i = 0; i < options.length; i++)
            if (options[i].value === value)
                return options[i].text
        return String(value)
    }

    function modeLabel() {
        return optionText(modeOptions, captureMode)
    }

    function monitorLabel(value) {
        for (let i = 0; i < monitorOptions.length; i++)
            if (monitorOptions[i].value === value)
                return monitorOptions[i].text
        return value === "focused" ? "Enfocado" : value
    }

    function notify(summary, body) {
        if (showNotify && notifyAvailable)
            Quickshell.execDetached(["notify-send", summary, body || ""])
    }

    function setStatus(text) {
        status = text
        if (text !== "")
            statusClear.restart()
    }

    function openToolbar(record) {
        videoMode = record === true
        Globals.openPanel = "capture"
    }

    function closeToolbar() {
        if (Globals.screenCaptureOpen)
            Globals.closeAll()
    }

    function toggleToolbar() {
        if (Globals.screenCaptureOpen) closeToolbar()
        else openToolbar(false)
    }

    function primaryAction() {
        if (videoMode) {
            if (isRecording) stopRecording()
            else startRecording()
        } else {
            capture()
        }
    }

    function capture() {
        // "todo" y "región" van con grim (región además con slurp); "ventana" y
        // "monitor" siguen con hyprshot.
        if ((captureMode === "all" || captureMode === "region") && !grimAvailable) {
            notify("Falta grim", "La captura de pantalla requiere grim.")
            setStatus("Falta grim")
            return
        }
        if (captureMode === "region" && !slurpAvailable) {
            notify("Falta slurp", "La captura por región necesita slurp.")
            setStatus("Falta slurp")
            return
        }
        if ((captureMode === "window" || captureMode === "monitor") && !hyprshotAvailable) {
            notify("Falta hyprshot", "La captura de ventana/monitor necesita hyprshot.")
            setStatus("Falta hyprshot")
            return
        }
        if (imageFormat !== "png" && !ffmpegAvailable) {
            notify("Falta ffmpeg", "JPG requiere ffmpeg para convertir la captura.")
            setStatus("Falta ffmpeg")
            return
        }
        if (!saveToDisk && !copyToClipboard) {
            notify("Captura sin salida", "Activa archivo o portapapeles.")
            setStatus("No hay salida activa")
            return
        }

        closeToolbar()
        Qt.callLater(runScreenshot)
    }

    function captureWhileRecording() {
        pillSuppressed = true
        pillRestoreTimer.restart()
        screenshotDuringRecordingTimer.restart()
    }

    function hyprshotRawCommand() {
        let cmd = "hyprshot "
        if (freeze)
            cmd += "-z "
        if (captureMode === "region") {
            cmd += "-m region "
        } else if (captureMode === "window") {
            cmd += "-m window "
        } else if (captureMode === "monitor") {
            cmd += "-m output "
            if (captureMonitor !== "focused")
                cmd += "-m " + shellQuote(captureMonitor) + " "
        }
        // OJO: usar la forma larga --raw. La versión de hyprshot instalada define
        // el getopt corto como "r:" (con argumento), así que "-r" falla ("option
        // requires an argument"), hyprshot ignora el modo raw y guarda su propia
        // copia en vez de volcar la imagen a stdout (que es lo que capturamos).
        cmd += "--raw"
        return cmd
    }

    function grimRawCommand() {
        return "grim " + (showPointer ? "-c " : "") + "-t png -"
    }

    function regionRawCommand() {
        // grim + slurp es la vía canónica y fiable para "región" en wlroots/
        // Hyprland: respeta el puntero (-c) y evita las rarezas del modo raw de
        // hyprshot. slurp -d muestra las dimensiones mientras seleccionas.
        return "grim " + (showPointer ? "-c " : "") + "-g \"$(slurp -d)\" -t png -"
    }

    function runScreenshot() {
        const dir = effectiveScreenshotDir()
        const out = dir + "/" + screenshotFilenameResolved()
        const mime = mimeForImageFormat()
        const raw = captureMode === "all" ? grimRawCommand()
                  : captureMode === "region" ? regionRawCommand()
                  : hyprshotRawCommand()

        let script = "TMP=$(mktemp --suffix=.png); FINAL=\"$TMP\"; trap 'rm -f \"$TMP\" \"$CONVERTED\"' EXIT; CONVERTED=\"\"; "
        // No abortamos por el código de salida de la orden de captura: hyprshot
        // en modo --raw devuelve 1 aunque la captura sea correcta. Nos fiamos de
        // que el archivo temporal no quede vacío (también cubre grim y cancelar
        // la selección de región/ventana, que dejan $TMP vacío).
        script += raw + " > \"$TMP\" 2>/dev/null; [ -s \"$TMP\" ] || exit 1; "

        if (imageFormat === "jpg") {
            script += "CONVERTED=$(mktemp --suffix=.jpg); "
            script += "ffmpeg -v error -y -i \"$TMP\" -q:v " + ffmpegJpegQuality() + " \"$CONVERTED\" || exit 1; FINAL=\"$CONVERTED\"; "
        }
        if (saveToDisk) {
            script += "mkdir -p " + shellQuote(dir) + "; cp \"$FINAL\" " + shellQuote(out) + "; "
        }
        if (copyToClipboard) {
            script += "if command -v wl-copy >/dev/null 2>&1; then wl-copy -t " + shellQuote(mime) + " < \"$FINAL\"; fi; "
        }
        if (showNotify) {
            if (saveToDisk)
                script += "notify-send " + shellQuote("Captura guardada") + " " + shellQuote(out) + " 2>/dev/null || true; "
            else if (copyToClipboard)
                script += "notify-send " + shellQuote("Captura copiada") + " " + shellQuote(modeLabel()) + " 2>/dev/null || true; "
        }

        lastOutputPath = saveToDisk ? out : ""
        setStatus("Captura lanzada")
        Quickshell.execDetached(["sh", "-c", "sleep 0.16; " + script])
    }

    function startRecording() {
        if (!gsrAvailable) {
            notify("Falta gpu-screen-recorder", "Instala gpu-screen-recorder para grabar pantalla.")
            setStatus("Falta gpu-screen-recorder")
            return
        }
        if (captureMode === "region" && !slurpAvailable) {
            notify("Falta slurp", "La grabacion de region necesita slurp.")
            setStatus("Falta slurp")
            return
        }
        if ((captureMode === "window" || captureMode === "monitor") && (!hyprctlAvailable || !jqAvailable)) {
            notify("Faltan herramientas", "La grabacion de ventana/monitor necesita hyprctl y jq.")
            setStatus("Faltan hyprctl/jq")
            return
        }

        closeToolbar()
        setStatus("Preparando grabacion")
        Quickshell.execDetached(["sh", "-c", "sleep 0.18; " + buildRecordingScript()])
    }

    function recordingSuffix(path) {
        let suffix = " -c " + videoFormat
        suffix += " -f " + videoFps
        suffix += " -q " + videoQuality
        suffix += " -ac " + audioCodec

        const audio = []
        if (recordSystemAudio) audio.push("$SYSTEM_AUDIO")
        if (recordMic) audio.push("$MIC_AUDIO")
        if (audio.length > 0)
            suffix += " -a \"" + audio.join("|") + "\""

        suffix += showPointer ? " -cursor yes" : " -cursor no"
        suffix += " -o " + shellQuote(path)
        if (videoCodec !== "auto")
            suffix += " -k " + videoCodec
        return suffix
    }

    function buildRecordingScript() {
        const dir = effectiveVideoDir()
        const path = dir + "/" + videoFilenameResolved()
        lastOutputPath = path

        let script = "set -u; PIDFILE=" + shellQuote(pidFile) + "; OUT=" + shellQuote(path) + "; "
        script += "cancel_rec() { qs ipc --any-display call screenCapture cancelRecording >/dev/null 2>&1 || true; }; "
        script += "start_rec() { qs ipc --any-display call screenCapture recordingStarted >/dev/null 2>&1 || true; }; "
        script += "stop_rec() { qs ipc --any-display call screenCapture recordingStopped >/dev/null 2>&1 || true; }; "
        script += "if ! command -v gpu-screen-recorder >/dev/null 2>&1; then "
        if (showNotify)
            script += "notify-send 'Falta gpu-screen-recorder' 'Instala gpu-screen-recorder para grabar pantalla.' 2>/dev/null || true; "
        script += "cancel_rec; exit 1; fi; "
        script += "mkdir -p " + shellQuote(dir) + "; "
        script += "SYSTEM_AUDIO=\"\"; MIC_AUDIO=\"\"; "
        if (recordSystemAudio)
            script += "SINK=$(pactl get-default-sink 2>/dev/null || true); [ -n \"$SINK\" ] && SYSTEM_AUDIO=\"$SINK.monitor\" || SYSTEM_AUDIO=\"default_output\"; "
        if (recordMic)
            script += "MIC_AUDIO=$(pactl get-default-source 2>/dev/null || true); [ -n \"$MIC_AUDIO\" ] || MIC_AUDIO=\"default_input\"; "
        script += "run_rec() { gpu-screen-recorder \"$@\" & recpid=$!; printf '%s' \"$recpid\" > \"$PIDFILE\"; start_rec; wait \"$recpid\"; code=$?; rm -f \"$PIDFILE\"; stop_rec; "
        if (showNotify)
            script += "if [ -s \"$OUT\" ]; then notify-send 'Grabacion guardada' \"$OUT\" 2>/dev/null || true; fi; "
        script += "exit \"$code\"; }; "

        const suffix = recordingSuffix(path)
        if (captureMode === "region") {
            script += "REGION=$(slurp -f '%wx%h+%x+%y') || { cancel_rec; exit 1; }; [ -n \"$REGION\" ] || { cancel_rec; exit 1; }; "
            script += "run_rec -w region -region \"$REGION\"" + suffix + "; "
        } else if (captureMode === "window") {
            script += "REGION=$(hyprctl activewindow -j 2>/dev/null | jq -r 'select(.address != null) | \"\\(.size[0])x\\(.size[1])+\\(.at[0])+\\(.at[1])\"') || true; "
            script += "[ -n \"$REGION\" ] && [ \"$REGION\" != \"null\" ] || { notify-send 'Sin ventana activa' 'No se pudo resolver la ventana para grabar.' 2>/dev/null || true; cancel_rec; exit 1; }; "
            script += "run_rec -w region -region \"$REGION\"" + suffix + "; "
        } else if (captureMode === "all") {
            script += "run_rec -w portal" + suffix + "; "
        } else {
            if (recordMonitor !== "focused") {
                script += "run_rec -w " + shellQuote(recordMonitor) + suffix + "; "
            } else {
                script += "MONITOR=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' | head -n1); "
                script += "[ -n \"$MONITOR\" ] && [ \"$MONITOR\" != \"null\" ] || MONITOR=portal; "
                script += "run_rec -w \"$MONITOR\"" + suffix + "; "
            }
        }
        return script
    }

    function recordingStarted() {
        isRecording = true
        isPaused = false
        recordingElapsed = 0
        ensurePillScreen()
        setStatus("Grabando")
    }

    function recordingStopped() {
        isRecording = false
        isPaused = false
        recordingElapsed = 0
        pillSuppressed = false
        setStatus("Grabacion detenida")
    }

    function cancelRecording() {
        isRecording = false
        isPaused = false
        recordingElapsed = 0
        pillSuppressed = false
        setStatus("Grabacion cancelada")
    }

    function stopRecording() {
        Quickshell.execDetached(["sh", "-c",
            "pid=$(cat " + shellQuote(pidFile) + " 2>/dev/null || true); " +
            "if [ -n \"$pid\" ]; then kill -INT \"$pid\" 2>/dev/null || true; " +
            "else qs ipc --any-display call screenCapture recordingStopped >/dev/null 2>&1 || true; fi"])
        isRecording = false
        isPaused = false
        recordingElapsed = 0
        setStatus("Deteniendo grabacion")
    }

    function pauseRecording() {
        Quickshell.execDetached(["sh", "-c",
            "pid=$(cat " + shellQuote(pidFile) + " 2>/dev/null || true); " +
            "[ -n \"$pid\" ] && kill -USR2 \"$pid\" 2>/dev/null || true"])
        isPaused = true
        setStatus("Grabacion pausada")
    }

    function resumeRecording() {
        Quickshell.execDetached(["sh", "-c",
            "pid=$(cat " + shellQuote(pidFile) + " 2>/dev/null || true); " +
            "[ -n \"$pid\" ] && kill -USR2 \"$pid\" 2>/dev/null || true"])
        isPaused = false
        setStatus("Grabando")
    }

    function formatElapsed(totalSeconds) {
        const h = Math.floor(totalSeconds / 3600)
        const m = Math.floor((totalSeconds % 3600) / 60)
        const s = totalSeconds % 60
        function pad(v) { return v < 10 ? "0" + v : "" + v }
        if (h > 0) return h + ":" + pad(m) + ":" + pad(s)
        return pad(m) + ":" + pad(s)
    }

    function screenNameAt(index) {
        if (index < 0 || index >= Quickshell.screens.length)
            return ""
        return Quickshell.screens[index].name || ""
    }

    function ensurePillScreen() {
        if (recordPillScreenName !== "") {
            for (let i = 0; i < Quickshell.screens.length; i++)
                if (Quickshell.screens[i].name === recordPillScreenName)
                    return
        }
        recordPillScreenName = screenNameAt(0)
        recordPillX = -1
        recordPillY = 12
    }

    function cyclePillScreen() {
        if (Quickshell.screens.length <= 1)
            return
        let idx = 0
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === recordPillScreenName) {
                idx = i
                break
            }
        }
        idx = (idx + 1) % Quickshell.screens.length
        recordPillScreenName = screenNameAt(idx)
        recordPillX = -1
        recordPillY = 12
    }

    function refreshMonitors() {
        const list = [{ text: "Enfocado", value: "focused" }]
        for (let i = 0; i < Quickshell.screens.length; i++) {
            const s = Quickshell.screens[i]
            if (!s || !s.name) continue
            const desc = s.description || s.model || s.name
            list.push({ text: desc, value: s.name })
        }
        monitorOptions = list
        ensurePillScreen()
    }

    onCaptureModeChanged: scheduleSave()
    onCaptureMonitorChanged: scheduleSave()
    onFreezeChanged: scheduleSave()
    onSaveToDiskChanged: scheduleSave()
    onCopyToClipboardChanged: scheduleSave()
    onShowNotifyChanged: scheduleSave()
    onShowPointerChanged: scheduleSave()
    onImageFormatChanged: scheduleSave()
    onImageQualityChanged: scheduleSave()
    onScreenshotDirChanged: scheduleSave()
    onScreenshotFilenameChanged: scheduleSave()
    onRecordMonitorChanged: scheduleSave()
    onRecordSystemAudioChanged: scheduleSave()
    onRecordMicChanged: scheduleSave()
    onVideoFormatChanged: scheduleSave()
    onVideoFpsChanged: scheduleSave()
    onVideoCodecChanged: scheduleSave()
    onAudioCodecChanged: scheduleSave()
    onVideoQualityChanged: scheduleSave()
    onVideoDirChanged: scheduleSave()
    onVideoFilenameChanged: scheduleSave()
    onShowRecordingPillChanged: scheduleSave()
    onRecordPillScreenNameChanged: scheduleSave()
    onRecordPillXChanged: scheduleSave()
    onRecordPillYChanged: scheduleSave()
    onRecordPillExpandedChanged: scheduleSave()

    Connections {
        target: Quickshell
        function onScreensChanged() { cap.refreshMonitors() }
    }

    Timer {
        id: saveTimer
        interval: 250
        onTriggered: cap.persist()
    }

    Timer {
        id: statusClear
        interval: 4500
        onTriggered: cap.status = ""
    }

    Timer {
        id: screenshotDuringRecordingTimer
        interval: 180
        repeat: false
        onTriggered: cap.runScreenshot()
    }

    Timer {
        id: pillRestoreTimer
        interval: 8000
        repeat: false
        onTriggered: cap.pillSuppressed = false
    }

    Timer {
        id: recordingTimer
        interval: 1000
        repeat: true
        running: cap.isRecording && !cap.isPaused
        onTriggered: cap.recordingElapsed++
    }

    // Reaplica cuando Settings carga (o cuando cambia el sub-objeto por una
    // recarga externa). Ignora los cambios que provienen de nuestro propio
    // persist() para no entrar en bucle.
    Connections {
        target: Settings
        function onScreenCaptureChanged() {
            if (!cap._persisting)
                cap.applyFromSettings()
        }
    }

    Process {
        id: deps
        command: ["sh", "-c",
            "for c in hyprshot grim slurp wl-copy notify-send gpu-screen-recorder jq hyprctl pactl ffmpeg; do " +
            "printf '%s=' \"$c\"; command -v \"$c\" >/dev/null 2>&1 && echo yes || echo no; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").trim().split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const parts = lines[i].split("=")
                    if (parts.length < 2) continue
                    const ok = parts[1] === "yes"
                    if (parts[0] === "hyprshot") cap.hyprshotAvailable = ok
                    else if (parts[0] === "grim") cap.grimAvailable = ok
                    else if (parts[0] === "slurp") cap.slurpAvailable = ok
                    else if (parts[0] === "wl-copy") cap.wlCopyAvailable = ok
                    else if (parts[0] === "notify-send") cap.notifyAvailable = ok
                    else if (parts[0] === "gpu-screen-recorder") cap.gsrAvailable = ok
                    else if (parts[0] === "jq") cap.jqAvailable = ok
                    else if (parts[0] === "hyprctl") cap.hyprctlAvailable = ok
                    else if (parts[0] === "pactl") cap.pactlAvailable = ok
                    else if (parts[0] === "ffmpeg") cap.ffmpegAvailable = ok
                }
            }
        }
    }

    Process {
        id: xdgDirs
        command: ["sh", "-c",
            "printf 'pictures='; xdg-user-dir PICTURES 2>/dev/null || echo \"$HOME/Pictures\"; " +
            "printf 'videos='; xdg-user-dir VIDEOS 2>/dev/null || echo \"$HOME/Videos\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").trim().split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const p = lines[i].indexOf("=")
                    if (p <= 0) continue
                    const k = lines[i].substring(0, p)
                    const v = lines[i].substring(p + 1).trim()
                    if (k === "pictures" && v !== "") cap.picturesDir = v
                    else if (k === "videos" && v !== "") cap.videosDir = v
                }
            }
        }
    }

    Component.onCompleted: {
        applyFromSettings()
        refreshMonitors()
        deps.running = true
        xdgDirs.running = true
    }
}
