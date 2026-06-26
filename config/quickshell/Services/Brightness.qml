pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ─────────────────────────────────────────────────────────────
//  Servicio de brillo (vía brightnessctl). 'available' es false
//  en equipos sin backlight → el panel oculta el slider.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: bright

    property bool available: false
    property int  percent: 0

    Process {
        id: reader
        command: ["sh", "-c", "command -v brightnessctl >/dev/null && brightnessctl -m || true"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const line = (this.text || "").trim().split("\n")[0]
                if (!line) { bright.available = false; return }
                const parts = line.split(",")
                if (parts.length < 4) { bright.available = false; return }
                bright.percent = parseInt(parts[3]) || 0
                bright.available = true
            }
        }
    }

    // Tras la primera lectura (reader corre solo al arrancar), si no hay
    // backlight `available` queda en false y el sondeo se detiene: así no
    // lanzamos brightnessctl cada 5 s en equipos de sobremesa sin brillo.
    Timer {
        interval: 5000
        running: bright.available
        repeat: true
        onTriggered: reader.running = true
    }

    function setPercent(p) {
        p = Math.max(1, Math.min(100, Math.round(p)))
        Quickshell.execDetached(["brightnessctl", "set", p + "%"])
        bright.percent = p
    }
}
