pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Servicio de fondos de pantalla (swww).
//  Escanea una o varias carpetas en busca de imágenes y aplica el
//  fondo con transición. Carpetas y transición se leen de Settings.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") ?? "/home"

    // Carpetas donde buscar fondos (configurable desde ajustes).
    property var searchDirs: Settings.wallpaperDirs

    // Parámetros de la transición de swww.
    property string transition: Settings.wallpaperTransition
    property int    transitionFps: 60
    property real   transitionDuration: Settings.wallpaperTransitionDuration

    // Re-escanea si cambian las carpetas.
    onSearchDirsChanged: refresh()

    property var    list: []     // rutas absolutas de imágenes encontradas
    property string current: ""  // fondo aplicado actualmente
    property bool   scanning: false

    function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    // Lanza el daemon de swww si no está corriendo.
    function ensureDaemon() {
        Quickshell.execDetached(["sh", "-c",
            "pgrep -x swww-daemon >/dev/null 2>&1 || (swww-daemon >/dev/null 2>&1 &)"])
    }

    function refresh() { scanProc.running = true }

    function apply(path) {
        if (!path) return
        current = path
        Quickshell.execDetached(["sh", "-c",
            "pgrep -x swww-daemon >/dev/null 2>&1 || { swww-daemon >/dev/null 2>&1 & sleep 0.4; }; "
            + "swww img " + shellQuote(path)
            + " --transition-type " + transition
            + " --transition-fps " + transitionFps
            + " --transition-duration " + transitionDuration])
    }

    Component.onCompleted: { ensureDaemon(); refresh(); queryProc.running = true }

    // Escaneo de imágenes con `find` sobre todas las carpetas.
    Process {
        id: scanProc
        command: ["sh", "-c",
            "for d in " + root.searchDirs.map(root.shellQuote).join(" ") + "; do "
            + "[ -d \"$d\" ] && find -L \"$d\" -maxdepth 2 -type f "
            + "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' "
            + "-o -iname '*.webp' -o -iname '*.gif' \\); done | sort -u"]
        onRunningChanged: root.scanning = running
        stdout: StdioCollector {
            onStreamFinished: {
                root.list = text.split("\n").filter(l => l.trim() !== "")
            }
        }
    }

    // Detecta el fondo actual que muestra swww (al arrancar).
    Process {
        id: queryProc
        command: ["sh", "-c",
            "swww query 2>/dev/null | head -1 | sed -n 's/.*image: //p'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t !== "") root.current = t
            }
        }
    }
}
