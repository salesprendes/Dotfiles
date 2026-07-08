pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Detección centralizada de dependencias externas: un solo proceso al arrancar
// comprueba todos los binarios que usan los servicios. has(name) es reactivo
// (se re-evalúa al terminar la detección), ready pasa a true al acabar y se
// emite loaded() una vez.
Singleton {
    id: root

    readonly property var _bins: [
        "cliphist", "wl-copy", "wl-paste",
        "hyprshot", "grim", "slurp", "gpu-screen-recorder", "ffmpeg",
        "notify-send", "jq", "hyprctl", "pactl",
        "kitty", "alacritty", "foot",
        "powerprofilesctl", "brightnessctl", "ddcutil", "xdg-user-dir"
    ]
    property var _found: ({})
    property bool ready: false
    signal loaded()

    // Reactivo: depende de _found, así que los bindings que llamen a has()
    // se re-evalúan al terminar la detección.
    function has(name) { return _found[name] === true }

    Process {
        running: true
        command: ["sh", "-c",
            "for b in \"$@\"; do command -v \"$b\" >/dev/null 2>&1 && echo \"$b\"; done",
            "deps"].concat(root._bins)
        stdout: StdioCollector {
            onStreamFinished: {
                const f = {}
                for (const b of (this.text || "").split("\n"))
                    if (b.trim() !== "")
                        f[b.trim()] = true
                root._found = f
                root.ready = true
                root.loaded()
            }
        }
    }
}
