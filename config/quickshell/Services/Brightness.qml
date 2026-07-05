pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Servicio de brillo HÍBRIDO. Detecta el método al arrancar:
//    · Portátil con panel eDP  → brightnessctl (clase backlight).
//    · Monitor externo HDMI/DP → DDC/CI con ddcutil (VCP 0x10).
//  'available' queda en false si no hay ninguno → el slider se oculta.
//
//  Para DDC/CI hace falta: paquete 'ddcutil', módulo i2c-dev y
//  permiso de lectura/escritura sobre /dev/i2c-* (grupo 'i2c').
//  Nota: brightnessctl SIN clase coge por error LEDs del teclado;
//  por eso filtramos siempre por '-c backlight' + ',backlight,'.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: bright

    property bool   available: false
    property int    percent: 0
    property string method: "none"     // "backlight" | "ddc" | "none"

    property int _ddcBus: -1
    property int _ddcMax: 100
    property int _pending: -1           // valor DDC pendiente (debounce)
    property int _pendingPct: -1        // % backlight pendiente (throttle)

    // ── Detección del método + lectura inicial ───────────────
    //  Optimizada: el nº de bus i2c del monitor se CACHEA en disco. En el
    //  primer arranque hace `ddcutil detect` (~0.4 s) y guarda el bus; en
    //  los siguientes va directo a ese bus (~0.08 s, 5× más rápido). Si el
    //  bus cacheado falla (monitor cambiado), reintenta con detect y
    //  re-cachea → auto-reparable.
    Process {
        id: detect
        running: true
        command: ["sh", "-c",
            "bl=$(brightnessctl -m -c backlight 2>/dev/null | grep -m1 ',backlight,'); " +
            "if [ -n \"$bl\" ]; then p=$(echo \"$bl\" | cut -d, -f4 | tr -d '%'); echo \"backlight ${p:-0} 100 -1\"; exit 0; fi; " +
            "command -v ddcutil >/dev/null 2>&1 || { echo 'none 0 100 -1'; exit 0; }; " +
            "cache=\"${XDG_CACHE_HOME:-$HOME/.cache}/qs-brightness-bus\"; " +
            "bus=$(cat \"$cache\" 2>/dev/null); " +
            "if [ -n \"$bus\" ]; then v=$(ddcutil --bus \"$bus\" --brief getvcp 10 2>/dev/null); else v=''; fi; " +
            "if [ -z \"$v\" ]; then " +
              "bus=$(ddcutil detect --brief 2>/dev/null | awk -F'i2c-' '/I2C bus/{print $2; exit}'); " +
              "if [ -n \"$bus\" ]; then v=$(ddcutil --bus \"$bus\" --brief getvcp 10 2>/dev/null); " +
              "[ -n \"$v\" ] && mkdir -p \"$(dirname \"$cache\")\" && printf '%s' \"$bus\" > \"$cache\"; fi; " +
            "fi; " +
            "c=$(echo \"$v\" | awk '{print $4}'); m=$(echo \"$v\" | awk '{print $5}'); " +
            "if [ -n \"$c\" ] && [ -n \"$m\" ]; then echo \"ddc $c $m $bus\"; else echo 'none 0 100 -1'; fi"]
        stdout: StdioCollector {
            onStreamFinished: bright._applyDetect((this.text || "").trim())
        }
    }

    function _applyDetect(line) {
        const f = line.split(/\s+/)
        if (f.length < 3 || f[0] === "none") {
            bright.available = false
            bright.method = "none"
            return
        }
        bright.method = f[0]
        const cur = parseInt(f[1]) || 0
        const max = parseInt(f[2]) || 100
        bright._ddcMax = max > 0 ? max : 100
        bright._ddcBus = (f.length >= 4) ? parseInt(f[3]) : -1
        bright.percent = Math.max(0, Math.min(100, Math.round(cur / bright._ddcMax * 100)))
        bright.available = true
    }

    // ── Relectura periódica (solo backlight; DDC es lento) ────
    //  El único consumidor de 'percent' es el slider del Centro de control,
    //  así que solo se sondea mientras está abierto (con una lectura inmediata
    //  al abrirlo vía triggeredOnStart). En reposo no se lanza ningún
    //  subproceso: capturar los cambios por tecla de hardware solo importa
    //  cuando el slider es visible.
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

    // ── Aplicar brillo ───────────────────────────────────────
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
                // --noverify: no re-lee tras escribir → respuesta más rápida.
                Quickshell.execDetached(["ddcutil", "--bus", String(bright._ddcBus),
                                         "--noverify", "setvcp", "10", String(bright._pending)])
                bright._pending = -1
            }
        }
    }

    // ── Throttle del path backlight (borde inicial + final) ──────
    //  El primer valor se aplica al instante; mientras la ventana de 40 ms
    //  esté abierta, los siguientes solo guardan el último, que se escribe al
    //  cerrarse. Así se pasa de ~1 proceso por pixel a ~25/s como máximo, sin
    //  perder el valor final ni la respuesta inmediata.
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
