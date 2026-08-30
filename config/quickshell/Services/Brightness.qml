pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Brillo híbrido: brightnessctl para el backlight interno o ddcutil por DDC/CI
// para un monitor externo. Se detecta cuál al arrancar, y sin ninguno de los dos
// 'available' queda en false y el slider se oculta.
//
// DDC/CI necesita el paquete ddcutil, el módulo i2c-dev y permisos de lectura y
// escritura sobre /dev/i2c-*. brightnessctl sin clase coge por error los LED del
// teclado, así que se filtra siempre por backlight.
Singleton {
    id: bright

    property bool   available: false
    property int    percent: 0
    property string method: "none"     // "backlight" | "ddc" | "none"

    property int _ddcBus: -1
    property int _ddcMax: 100
    property string _backlightPath: ""
    property int _pending: -1           // valor DDC pendiente (debounce)
    property int _pendingPct: -1        // % backlight pendiente (throttle)

    // Detección del método y lectura inicial. El bus i2c del monitor se cachea en
    // disco: el primer arranque hace `ddcutil detect` y guarda el bus, y luego va
    // directo a él. Si el bus cacheado falla porque cambió el monitor, reintenta
    // y re-cachea.
    //
    // Arranca cuando Deps termina, porque la mitad DDC del script solo se incluye
    // si hay ddcutil; hasta entonces 'available' sigue en false.
    Component.onCompleted: if (Deps.ready) detect.running = true
    Connections {
        target: Deps
        function onLoaded() { detect.running = true }
    }
    Process {
        id: detect
        command: ["sh", "-c",
            "dev=''; for p in /sys/class/backlight/*; do [ -r \"$p/brightness\" ] && dev=$p && break; done; " +
            "if [ -n \"$dev\" ]; then c=$(cat \"$dev/brightness\"); m=$(cat \"$dev/max_brightness\"); " +
            "echo \"backlight ${c:-0} ${m:-100} $dev/brightness\"; exit 0; fi; " +
            (!Deps.has("ddcutil") ? "echo 'none 0 100 -1'" :
            "cache=\"${XDG_CACHE_HOME:-$HOME/.cache}/qs-brightness-bus\"; " +
            "bus=$(cat \"$cache\" 2>/dev/null); " +
            "if [ -n \"$bus\" ]; then v=$(ddcutil --bus \"$bus\" --brief getvcp 10 2>/dev/null); else v=''; fi; " +
            "if [ -z \"$v\" ]; then " +
              "bus=$(ddcutil detect --brief 2>/dev/null | awk -F'i2c-' '/I2C bus/{print $2; exit}'); " +
              "if [ -n \"$bus\" ]; then v=$(ddcutil --bus \"$bus\" --brief getvcp 10 2>/dev/null); " +
              "[ -n \"$v\" ] && mkdir -p \"$(dirname \"$cache\")\" && printf '%s' \"$bus\" > \"$cache\"; fi; " +
            "fi; " +
            "c=$(echo \"$v\" | awk '{print $4}'); m=$(echo \"$v\" | awk '{print $5}'); " +
            "if [ -n \"$c\" ] && [ -n \"$m\" ]; then echo \"ddc $c $m $bus\"; else echo 'none 0 100 -1'; fi")]
        stdout: StdioCollector {
            onStreamFinished: bright._applyDetect((this.text || "").trim())
        }
    }

    // Tras el resume un monitor DDC/CI puede re-enumerarse, cambiando el bus i2c
    // cacheado, o el backlight puede haber cambiado de valor. Relanzar la
    // detección re-cachea el bus y relee el brillo; solo si ya había método.
    Connections {
        target: Resume
        function onResumed() { if (bright.method !== "none") detect.running = true }
    }

    function _applyDetect(line) {
        const f = line.split(/\s+/)
        if (f.length < 3 || f[0] === "none") {
            bright.available = false
            bright.method = "none"
            bright._backlightPath = ""
            return
        }
        bright.method = f[0]
        // Marca de tiempo de la última lectura DDC válida, para el enfriamiento
        // de la relectura.
        if (f[0] === "ddc") {
            bright._lastDdcRead = Date.now()
            bright._backlightPath = ""
        } else {
            bright._backlightPath = f.length >= 4 ? f[3] : ""
        }
        const cur = parseInt(f[1]) || 0
        const max = parseInt(f[2]) || 100
        bright._ddcMax = max > 0 ? max : 100
        bright._ddcBus = (f[0] === "ddc" && f.length >= 4) ? parseInt(f[3]) : -1
        bright.percent = Math.max(0, Math.min(100, Math.round(cur / bright._ddcMax * 100)))
        bright.available = true
    }

    // Relectura DDC al abrir el Centro de control: los botones físicos del
    // monitor cambian el brillo por fuera y el slider quedaría desfasado. Con
    // enfriamiento, porque ddcutil tarda alrededor de un segundo.
    property double _lastDdcRead: 0
    Connections {
        target: Globals
        function onControlCenterOpenChanged() {
            if (!Globals.controlCenterOpen) return
            if (bright.method !== "ddc" || !Deps.has("ddcutil")) return
            if (detect.running) return
            if (Date.now() - bright._lastDdcRead < 10000) return
            detect.running = true
        }
    }

    // El kernel notifica los cambios del backlight por sysfs, así que un
    // FileView con inotify evita lanzar brightnessctl cada pocos segundos
    // mientras el Centro de control está abierto.
    FileView {
        id: backlightFile
        path: bright.method === "backlight" ? bright._backlightPath : ""
        watchChanges: path !== ""
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const current = parseInt(text())
            if (!isNaN(current) && bright._ddcMax > 0)
                bright.percent = Math.max(0, Math.min(100,
                    Math.round(current / bright._ddcMax * 100)))
        }
    }

    // Aplicar brillo
    function setPercent(p) {
        p = Math.max(1, Math.min(100, Math.round(p)))
        bright.percent = p   // feedback inmediato en la UI
        if (bright.method === "backlight") {
            // Aplica el primero al instante y luego como mucho uno cada 40 ms
            // mientras se arrastra, en vez de lanzar un proceso por píxel.
            bright._applyBacklight(p)
        } else if (bright.method === "ddc") {
            // DDC/CI es lento, así que se rebota para no saturar el bus i2c
            // mientras se arrastra: solo se escribe el último valor.
            bright._pending = Math.round(p / 100 * bright._ddcMax)
            ddcWrite.restart()
        }
    }

    Timer {
        id: ddcWrite
        interval: 220
        repeat: false
        onTriggered: {
            if (bright._pending >= 0 && bright._ddcBus >= 0) {
                // --noverify: no relee tras escribir, así responde antes.
                Quickshell.execDetached(["ddcutil", "--bus", String(bright._ddcBus),
                                         "--noverify", "setvcp", "10", String(bright._pending)])
                bright._pending = -1
            }
        }
    }

    // El primer valor se aplica al instante y, mientras la ventana está abierta,
    // los siguientes solo guardan el último, que se escribe al cerrarse.
    function _applyBacklight(p) {
        if (blWrite.running) {
            bright._pendingPct = p
        } else {
            Quickshell.execDetached(["brightnessctl", "-c", "backlight", "set", p + "%"])
            bright._pendingPct = -1
            blWrite.start()
        }
    }
    Timer {
        id: blWrite
        interval: 40
        repeat: false
        onTriggered: {
            if (bright._pendingPct >= 0) {
                Quickshell.execDetached(["brightnessctl", "-c", "backlight", "set",
                                         bright._pendingPct + "%"])
                bright._pendingPct = -1
                blWrite.start()   // reabre la ventana por si siguen llegando
            }
        }
    }
}
