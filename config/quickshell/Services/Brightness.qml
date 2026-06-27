pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

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

    // ── Detección del método + lectura inicial ───────────────
    Process {
        id: detect
        running: true
        command: ["sh", "-c",
            "bl=$(brightnessctl -m -c backlight 2>/dev/null | grep -m1 ',backlight,'); " +
            "if [ -n \"$bl\" ]; then " +
              "p=$(echo \"$bl\" | cut -d, -f4 | tr -d '%'); " +
              "echo \"backlight ${p:-0} 100 -1\"; " +
            "elif command -v ddcutil >/dev/null 2>&1; then " +
              "bus=$(ddcutil detect --brief 2>/dev/null | awk -F'i2c-' '/I2C bus/{print $2; exit}'); " +
              "if [ -n \"$bus\" ]; then " +
                "v=$(ddcutil --bus \"$bus\" --brief getvcp 10 2>/dev/null); " +
                "c=$(echo \"$v\" | awk '{print $4}'); m=$(echo \"$v\" | awk '{print $5}'); " +
                "if [ -n \"$c\" ] && [ -n \"$m\" ]; then echo \"ddc $c $m $bus\"; " +
                "else echo 'none 0 100 -1'; fi; " +
              "else echo 'none 0 100 -1'; fi; " +
            "else echo 'none 0 100 -1'; fi"]
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
    Timer {
        interval: 5000
        running: bright.available && bright.method === "backlight"
        repeat: true
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
            Quickshell.execDetached(["brightnessctl", "-c", "backlight", "set", p + "%"])
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
                Quickshell.execDetached(["ddcutil", "--bus", String(bright._ddcBus),
                                         "setvcp", "10", String(bright._pending)])
                bright._pending = -1
            }
        }
    }
}
