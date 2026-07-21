pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Fondos de pantalla: escanea una o varias carpetas y expone la ruta del
// fondo actual. Backdrop.qml renderiza la imagen y sus transiciones; apply()
// solo cambia current y la ventana de fondo hace el fundido.
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
    property double _lastScan: 0 // ms epoch del último escaneo completado

    // Miniaturas persistentes en disco: decodificar 36 fondos a tamaño
    // completo en cada apertura del Dashboard era lo que hacía lenta la
    // pestaña. Tras el escaneo se generan (una sola vez, ffmpeg, 640px de
    // ancho) y la rejilla decodifica estos JPEG diminutos en su lugar. La
    // clave incluye el mtime: si un fondo cambia, su miniatura se regenera.
    property var thumbs: ({})    // ruta original → ruta de miniatura lista

    // Miniatura si existe; si aún no está generada, el original (la rejilla
    // funciona igual en el primer arranque, solo que más lenta esa vez).
    function thumb(path) {
        return thumbs[path] || path
    }

    function refresh() { scanProc.running = true }

    // Re-escanea solo si el último escaneo completado es más viejo que
    // maxAgeMs (o si aún no hay lista). Evita que cada apertura del Dashboard
    // resetee el GridView y re-pida todas las miniaturas.
    function refreshIfStale(maxAgeMs) {
        if (list.length === 0 || _lastScan === 0 || Date.now() - _lastScan > maxAgeMs)
            refresh()
    }

    // Cambia el fondo: basta con fijar 'current'; Backdrop.qml hace el fundido.
    // Persiste la ruta en Settings para conservarla entre reinicios/recargas.
    function apply(path) {
        if (!path) return
        current = path
        Settings.wallpaperCurrent = path
    }

    // Fondo por defecto: solo si no hay fondo guardado (sistema recién
    // instalado) o el guardado ya NO EXISTE en disco. Que no aparezca en el
    // escaneo no basta: las carpetas XDG se resuelven async y el primer
    // escaneo del arranque puede ver solo ~/.config/wallpapers — antes eso
    // pisaba el fondo guardado con simple.png y lo persistía (el clásico
    // "a veces no se guarda"). Ahora se comprueba el archivo en disco y el
    // guardado solo se descarta si de verdad fue borrado.
    function _applyDefaultIfNeeded() {
        if (current === "") { _pickDefault(); return }
        if (list.indexOf(current) !== -1) return
        existsProc.command = ["test", "-f", current]
        existsProc.running = true
    }

    function _pickDefault() {
        // simple.png si existe; si no (carpeta por defecto ausente, como en
        // instalaciones que solo usan la carpeta XDG), el primero que haya.
        const def = list.find(p => p.endsWith("/simple.png")) || list[0]
        if (def) apply(def)
    }

    // test -f del fondo guardado: si ya no existe, entonces sí, al defecto.
    Process {
        id: existsProc
        onExited: (code, status) => {
            if (code !== 0)
                root._pickDefault()
        }
    }

    // Restaura el último fondo guardado al arrancar y vuelve a escanear.
    Component.onCompleted: {
        if (Settings.wallpaperCurrent)
            current = Settings.wallpaperCurrent
        refresh()
    }

    // Rotación automática (Ajustes → Fondos): cada wallpaperAutoMin minutos
    // aplica otro fondo de la lista — al azar (sin repetir el actual) o el
    // siguiente en orden. Parada con 0 minutos o sin al menos dos fondos.
    Timer {
        interval: Math.max(1, Settings.wallpaperAutoMin) * 60 * 1000
        running: Settings.wallpaperAutoMin > 0 && root.list.length > 1
        repeat: true
        onTriggered: {
            const l = root.list
            const cur = l.indexOf(root.current)
            let next
            if (Settings.wallpaperRandom) {
                do { next = Math.floor(Math.random() * l.length) } while (next === cur)
            } else {
                next = (cur + 1) % l.length
            }
            root.apply(l[next])
        }
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
        // find acepta varios directorios de partida en argv plano; los que no
        // existan solo producen un error ignorable en stderr. La ordenación y
        // la deduplicación (antes sort -u) se hacen al recoger la salida.
        command: ["find", "-L"].concat(root.searchDirs).concat([
            "-maxdepth", "2", "-type", "f",
            "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png",
            "-o", "-iname", "*.webp", "-o", "-iname", "*.gif", ")"])
        onRunningChanged: root.scanning = running
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}
                const out = []
                const lines = text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const l = lines[i].trim()
                    if (l !== "" && !seen[l]) { seen[l] = true; out.push(l) }
                }
                out.sort()
                root.list = out
                root._lastScan = Date.now()
                root._applyDefaultIfNeeded()
                if (out.length > 0) {
                    thumbProc.command = ["sh", "-c", thumbProc.script, "thumbs"].concat(out)
                    thumbProc.running = true
                }
            }
        }
    }

    // Genera las miniaturas que falten y poda las huérfanas. Emite una línea
    // "original<TAB>miniatura" por fondo; al terminar se vuelca al mapa.
    Process {
        id: thumbProc
        readonly property string script: '
T="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/wallthumbs"
mkdir -p "$T" || exit 1
keep=""
for f in "$@"; do
  [ -f "$f" ] || continue
  key=$(printf "%s:%s" "$f" "$(stat -c %Y "$f")" | md5sum | cut -d" " -f1)
  out="$T/$key.jpg"
  if [ ! -s "$out" ]; then
    ffmpeg -loglevel error -y -i "$f" -frames:v 1 -vf "scale=640:-2" -q:v 4 "$out" </dev/null || continue
  fi
  keep="$keep $key.jpg"
  printf "%s\\t%s\\n" "$f" "$out"
done
for t in "$T"/*.jpg; do
  [ -e "$t" ] || continue
  case " $keep " in *" ${t##*/} "*) ;; *) rm -f "$t" ;; esac
done'
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {}
                const lines = text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const p = lines[i].split("\t")
                    if (p.length === 2 && p[0] !== "" && p[1] !== "")
                        map[p[0]] = p[1]
                }
                root.thumbs = map
            }
        }
    }
}
