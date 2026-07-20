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
        "powerprofilesctl", "brightnessctl", "ddcutil", "xdg-user-dir",
        // Apps de las plantillas (Config/AppTemplates.qml): detectarlas aquí
        // evita el Instantiator que lanzaba un 'which' por app al arrancar.
        "qt6ct", "plasmashell", "ghostty", "wezterm", "starship", "hx",
        "emacs", "labwc", "niri", "mango", "scroll", "sway", "cava", "btop"
    ]
    property var _found: ({})
    property bool ready: false
    signal loaded()

    // Reactivo: depende de _found, así que los bindings que llamen a has()
    // se re-evalúan al terminar la detección.
    function has(name) { return _found[name] === true }

    Process {
        running: true
        // 'which' imprime por stdout la ruta de cada binario encontrado (los
        // ausentes solo van a stderr): el nombre base de cada ruta identifica
        // el binario, sin necesidad de shell.
        command: ["which"].concat(root._bins)
        stdout: StdioCollector {
            onStreamFinished: {
                const f = {}
                for (const b of (this.text || "").split("\n")) {
                    const path = b.trim()
                    if (path !== "")
                        f[path.substring(path.lastIndexOf("/") + 1)] = true
                }
                root._found = f
                root.ready = true
                root.loaded()
            }
        }
    }
}
