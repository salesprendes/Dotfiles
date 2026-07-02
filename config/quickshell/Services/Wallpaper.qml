pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Servicio de fondos de pantalla.
//  Escanea una o varias carpetas en busca de imágenes y expone la
//  ruta del fondo actual. Background/Backdrop.qml renderiza la imagen y sus
//  transiciones; 'apply()' solo cambia 'current';
//  la ventana de fondo se encarga de la transición.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") ?? "/home"

    // Carpetas donde buscar fondos (configurable desde ajustes).
    property var searchDirs: Settings.wallpaperDirs

    // Re-escanea si cambian las carpetas.
    onSearchDirsChanged: refresh()

    property var    list: []     // rutas absolutas de imágenes encontradas
    property string current: ""  // fondo aplicado actualmente
    property bool   scanning: false

    function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function refresh() { scanProc.running = true }

    // Cambia el fondo: basta con fijar 'current'; Backdrop.qml hace el fundido.
    // Persiste la ruta en Settings para conservarla entre reinicios/recargas.
    function apply(path) {
        if (!path) return
        current = path
        Settings.wallpaperCurrent = path
    }

    // Fondo por defecto: si no hay fondo guardado (sistema recién instalado)
    // o el guardado ya no está entre las imágenes encontradas, usa simple.png.
    function _applyDefaultIfNeeded() {
        if (current !== "" && list.indexOf(current) !== -1) return
        const def = list.find(p => p.endsWith("/simple.png"))
        if (def) apply(def)
    }

    // Restaura el último fondo guardado al arrancar y vuelve a escanear.
    Component.onCompleted: {
        if (Settings.wallpaperCurrent)
            current = Settings.wallpaperCurrent
        refresh()
    }

    // Si Settings carga después (orden de inicialización de singletons) o si
    // otro proceso cambia el fondo guardado, refléjalo en 'current'.
    Connections {
        target: Settings
        function onWallpaperCurrentChanged() {
            if (Settings.wallpaperCurrent && Settings.wallpaperCurrent !== root.current)
                root.current = Settings.wallpaperCurrent
        }
    }

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
                root._applyDefaultIfNeeded()
            }
        }
    }
}
