pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Brillo híbrido: brightnessctl (backlight eDP) o ddcutil (DDC/CI en monitor
// externo, VCP 0x10). Se detecta cuál al arrancar; si no hay ninguno,
// available queda false y el slider se oculta.
// DDC/CI necesita el paquete ddcutil, el módulo i2c-dev y RW sobre
// /dev/i2c-* (grupo i2c). brightnessctl sin clase coge por error los LEDs del
// teclado, por eso filtramos siempre por backlight.
Singleton {
    id: bright

    property bool   available: false
    property int    percent: 0
    property string method: "none"     // "backlight" | "ddc" | "none"

    property int _ddcBus: -1
    property int _ddcMax: 100
    property int _pending: -1           // valor DDC pendiente (debounce)
    property int _pendingPct: -1        // % backlight pendiente (throttle)

    // Detección del método + lectura inicial. El bus i2c del monitor se cachea
    // en disco: el primer arranque hace `ddcutil detect` (~0.4 s) y guarda el
    // bus; luego va directo a él (~0.08 s). Si el bus cacheado falla (cambió el
    // monitor), reintenta detect y re-cachea.
    // Arranca cuando Deps termina, porque la mitad DDC del script solo se
    // incluye si hay ddcutil. Hasta entonces available sigue en false.
    Component.onCompleted: if (Deps.ready) detect.running = true
    Connections {
        target: Deps
        function onLoaded() { detect.running = true }
    }
    Process {
        id: detect
        command: ["sh", "-c",
            "bl=$(brightnessctl -m -c backlight 2>/dev/null | grep -m1 ',backlight,'); " +
            "if [ -n \"$bl\" ]; then p=$(echo \"$bl\" | cut -d, -f4 | tr -d '%'); echo \"backlight ${p:-0} 100 -1\"; exit 0; fi; " +
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

    // Tras el resume un monitor DDC/CI puede re-enumerarse (cambia el bus i2c
    // cacheado y el control dejaría de responder) o el backlight puede haber
    // cambiado de valor: re-lanzar la detección re-cachea el bus y re-lee el
    // brillo. Solo si ya había un método disponible.
    Connections {
        target: Resume
        function onResumed() { if (bright.method !== "none") detect.running = true }
    }

    function _applyDetect(line) {
        const f = line.split(/\s+/)
        if (f.length < 3 || f[0] === "none") {
            bright.available = false
            bright.method = "none"
            return
        }
        bright.method = f[0]
        // Marca de tiempo de la última lectura DDC válida (para el enfriamiento
        // de la relectura al abrir el Centro de control).
        if (f[0] === "ddc")
            bright._lastDdcRead = Date.now()
        const cur = parseInt(f[1]) || 0
        const max = parseInt(f[2]) || 100
        bright._ddcMax = max > 0 ? max : 100
        bright._ddcBus = (f.length >= 4) ? parseInt(f[3]) : -1
        bright.percent = Math.max(0, Math.min(100, Math.round(cur / bright._ddcMax * 100)))
        bright.available = true
    }

    // Relectura DDC al abrir el Centro de control: los botones físicos del
    // monitor cambian el brillo por fuera y el slider quedaría desfasado. Al
    // abrir re-lanzamos detect (actualiza percent sin escribir). Enfriamiento
    // de 10 s porque ddcutil tarda ~1 s y no queremos lag al reabrir seguido.
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

    // Relectura periódica (solo backlight; DDC es lento). El único consumidor
    // de percent es el slider del Centro de control, así que solo se sondea
    // mientras está abierto (lectura inmediata al abrir vía triggeredOnStart).
    // Capturar cambios por tecla de hardware solo importa si el slider se ve.
    Timer {
        interval: 5000
        running: bright.available && bright.method === "backlight" && Globals.controlCenterOpen
        repeat: true
        triggeredOnStart: true
        onTriggered: reader.running = true
    }
    Process {
        id: reader
        command: ["sh", "-c", "brightnessctl -m -c backlight 2>/dev/null | grep -m1 ',backlight,'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = (this.text || "").trim()
                if (!l) return
                const parts = l.split(",")
                if (parts.length >= 4)
                    bright.percent = parseInt(parts[3]) || bright.percent
            }
        }
    }

    // Aplicar brillo
    function setPercent(p) {
        p = Math.max(1, Math.min(100, Math.round(p)))
        bright.percent = p   // feedback inmediato en la UI
        if (bright.method === "backlight") {
            // Throttle: aplica el primero al instante y luego como mucho uno
            // cada 40 ms mientras se arrastra, en vez de lanzar un brightnessctl
            // por cada pixel de movimiento (menos fork+exec, menos picos de CPU).
            bright._applyBacklight(p)
        } else if (bright.method === "ddc") {
            // DDC/CI es lento (~100-300 ms): debounce para no saturar el bus
            // i2c mientras se arrastra el slider. Solo se escribe el último valor.
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
                // --noverify: no re-lee tras escribir, así responde más rápido.
                Quickshell.execDetached(["ddcutil", "--bus", String(bright._ddcBus),
                                         "--noverify", "setvcp", "10", String(bright._pending)])
                bright._pending = -1
            }
        }
    }

    // Throttle del backlight: el primer valor se aplica al instante; mientras
    // la ventana de 40 ms está abierta los siguientes solo guardan el último,
    // que se escribe al cerrarse. Máx ~25 escrituras/s sin perder el valor final.
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
