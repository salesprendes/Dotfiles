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

    // Carpetas donde buscar fondos (configurable desde ajustes).
    property var searchDirs: Settings.wallpaperDirs

    // Re-escanea si cambian las carpetas.
    onSearchDirsChanged: refresh()

    property var    list: []     // rutas absolutas de imágenes encontradas
    property string current: ""  // fondo aplicado actualmente
    property bool   scanning: false
    property double _lastScan: 0 // ms epoch del último escaneo completado

    // Miniaturas persistentes en disco, generadas con ffmpeg tras el escaneo:
    // sin ellas la rejilla del Dashboard decodifica cada fondo a tamaño
    // completo en cada apertura. La clave lleva el mtime, así que un fondo
    // modificado regenera la suya, más un sufijo de versión para invalidarlas
    // todas de golpe cuando cambia el tamaño con el que se generan.
    //
    // El lado CORTO mide 540, no el ancho: las tarjetas del carrusel piden 483
    // px de alto, y dimensionar por el ancho deja los apaisados en 360.
    property var thumbs: ({})    // ruta original → ruta de miniatura lista

    // Miniatura si existe; si no, el original. El primer arranque funciona
    // igual, solo que decodificando a tamaño completo esa vez.
    function thumb(path) {
        return thumbs[path] || path
    }

    // Copias de los fondos al tamaño de la pantalla.
    //
    // No es por la textura en reposo, que el 'sourceSize' de Backdrop.qml ya
    // limita, sino por el PICO de descodificación, que sourceSize no toca: Qt
    // descomprime la imagen entera y solo después la encoge, así que el pico lo
    // manda el fichero. Un PNG de 5120x2880 cuesta unos 82 MB transitorios
    // frente a los 14 de la copia, y se paga en cada carga de fondo.
    //
    // Las copias son PNG sin pérdida. El JPEG descodifica unas tres veces más
    // rápido, pero 'asynchronous: true' ya saca eso del hilo principal, y en
    // cambio marca los degradados planos —SSIM 0,77-0,82 frente al reducido sin
    // pérdida— en una imagen que ocupa la pantalla entera todo el rato.
    property var fulls: ({})     // ruta original → copia al tamaño de pantalla

    // Copia si existe; si no, el original.
    function full(path) {
        return fulls[path] || path
    }

    // "original<TAB>copia" por línea → mapa. Lo comparten el índice de disco y
    // la salida del generador.
    function _mapaDeCopias(texto) {
        const map = {}
        const lines = (texto || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const p = lines[i].split("\t")
            if (p.length === 2 && p[0] !== "" && p[1] !== "")
                map[p[0]] = p[1]
        }
        return map
    }

    // Índice en disco, leído con blockLoading para que el mapa esté puesto
    // antes de que Backdrop pida el fondo. El generador tarda unos 100 ms
    // incluso con todo en caché, y sin el índice la carga del arranque —la más
    // frecuente— sería la única que usara el original. Si el índice miente,
    // Backdrop cae al original por su cuenta y el generador lo reescribe.
    readonly property string _dirCache: (Quickshell.env("XDG_CACHE_HOME")
                                         || (Settings.home + "/.cache")) + "/quickshell/wallcache"

    FileView {
        id: indiceCopias
        path: root._dirCache + "/indice.tsv"
        blockLoading: true
        printErrors: false
    }

    // Píxeles físicos del monitor más grande: Backdrop pone la misma imagen en
    // todos, así que la copia debe cubrir al mayor.
    readonly property var _pantalla: {
        let w = 0, h = 0
        for (const s of Quickshell.screens) {
            const d = s.devicePixelRatio > 0 ? s.devicePixelRatio : 1
            w = Math.max(w, Math.round(s.width * d))
            h = Math.max(h, Math.round(s.height * d))
        }
        return { w: w > 0 ? w : 1920, h: h > 0 ? h : 1080 }
    }

    function refresh() { scanProc.running = true }

    // Reescanea solo si el último escaneo es más viejo que maxAgeMs, para que
    // abrir el Dashboard no resetee el GridView ni repida las miniaturas.
    function refreshIfStale(maxAgeMs) {
        if (list.length === 0 || _lastScan === 0 || Date.now() - _lastScan > maxAgeMs)
            refresh()
    }

    // Cambia el fondo y lo persiste; Backdrop.qml hace la transición al ver
    // cambiar 'current'.
    function apply(path) {
        if (!path) return
        current = path
        Settings.wallpaperCurrent = path
    }

    // Aplica el fondo por defecto solo si no hay ninguno guardado o el guardado
    // ya no existe en disco. No basta con que falte del escaneo: las carpetas
    // XDG se resuelven de forma asíncrona y el primer escaneo puede ver solo
    // una de ellas, lo que pisaría el fondo guardado y lo persistiría.
    function _applyDefaultIfNeeded() {
        if (current === "") { _pickDefault(); return }
        if (list.indexOf(current) !== -1) return
        existsProc.command = ["test", "-f", current]
        existsProc.running = true
    }

    // simple.png si existe; si no, el primero de la lista.
    function _pickDefault() {
        const def = list.find(p => p.endsWith("/simple.png")) || list[0]
        if (def) apply(def)
    }

    // Comprueba en disco el fondo guardado antes de descartarlo.
    Process {
        id: existsProc
        onExited: (code, status) => {
            if (code !== 0)
                root._pickDefault()
        }
    }

    // Restaura el último fondo guardado y reescanea. El mapa de copias se pone
    // lo primero: quien lea 'current' pedirá su copia inmediatamente después.
    Component.onCompleted: {
        fulls = _mapaDeCopias(indiceCopias.text())
        if (Settings.wallpaperCurrent)
            current = Settings.wallpaperCurrent
        refresh()
    }

    // Rotación automática: cada wallpaperAutoMin minutos aplica otro fondo, al
    // azar sin repetir el actual o el siguiente en orden. Parada con 0 minutos
    // o con menos de dos fondos.
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

    // Refleja en 'current' un cambio del ajuste, venga de que Settings cargue
    // después que este singleton o de otro proceso.
    Connections {
        target: Settings
        function onWallpaperCurrentChanged() {
            if (Settings.wallpaperCurrent && Settings.wallpaperCurrent !== root.current)
                root.current = Settings.wallpaperCurrent
        }
    }

    // Escaneo de imágenes con `find` sobre todas las carpetas configuradas.
    Process {
        id: scanProc
        // find acepta varios directorios de partida en argv plano; los que no
        // existan solo producen un error ignorable en stderr. Ordenación y
        // deduplicación se hacen al recoger la salida.
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
                    fullProc.command = ["sh", "-c", fullProc.script, "fulls",
                                        String(root._pantalla.w), String(root._pantalla.h)].concat(out)
                    fullProc.running = true
                }
            }
        }
    }

    // Genera las miniaturas que falten, poda las huérfanas y emite una línea
    // "original<TAB>miniatura" por fondo.
    Process {
        id: thumbProc
        readonly property string script: '
T="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/wallthumbs"
mkdir -p "$T" || exit 1
keep=""
for f in "$@"; do
  [ -f "$f" ] || continue
  key=$(printf "%s:%s:v2" "$f" "$(stat -c %Y "$f")" | md5sum | cut -d" " -f1)
  out="$T/$key.jpg"
  if [ ! -s "$out" ]; then
    nice -n 19 ionice -c3 ffmpeg -loglevel error -y -i "$f" -frames:v 1 -vf "scale=\'if(gt(a,1),-2,540)\':\'if(gt(a,1),540,-2)\'" -q:v 4 "$out" </dev/null || continue
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

    // Genera las copias que falten, poda las huérfanas y emite
    // "original<TAB>copia" por cada fondo que tenga copia.
    //
    // Todo va con 'nice' e 'ionice': en régimen normal esto no lanza ni un
    // ffmpeg —el bucle comprueba antes si la copia ya está—, pero al añadir
    // fondos son varios segundos de CPU y disco que no tienen ninguna prisa y
    // no deben competir con el compositor.
    //
    // El orden del bucle es deliberado: comprueba si la copia ya está antes de
    // sondear dimensiones, porque sondear la carpeta entera cuesta más de un
    // segundo y el Dashboard reescanea cada vez que se abre. El marcador
    // '.igual' cumple lo mismo para los fondos que ya caben en la pantalla.
    //
    // La clave incluye el tamaño de pantalla, así que cambiar de monitor
    // regenera las copias y el bucle final se lleva las del tamaño viejo.
    Process {
        id: fullProc
        readonly property string script: '
T="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/wallcache"
mkdir -p "$T" || exit 1
MW=$1; MH=$2; shift 2
keep=" indice.tsv "
tmp="$T/.indice.$$"
: > "$tmp"
for f in "$@"; do
  [ -f "$f" ] || continue
  key=$(printf "%s:%s:%sx%s:v1" "$f" "$(stat -c %Y "$f")" "$MW" "$MH" | md5sum | cut -d" " -f1)
  out="$T/$key.png"
  if [ -s "$out" ]; then
    keep="$keep $key.png"
    printf "%s\\t%s\\n" "$f" "$out" >> "$tmp"
    continue
  fi
  if [ -e "$T/$key.igual" ]; then
    keep="$keep $key.igual"
    continue
  fi
  d=$(nice -n 19 ionice -c3 ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$f" </dev/null 2>/dev/null) || continue
  w=${d%%,*}; r=${d#*,}; h=${r%%,*}
  case "$w$h" in ""|*[!0-9]*) continue ;; esac
  if [ "$w" -le "$MW" ] && [ "$h" -le "$MH" ]; then
    : > "$T/$key.igual"
    keep="$keep $key.igual"
    continue
  fi
  nice -n 19 ionice -c3 ffmpeg -loglevel error -y -i "$f" -frames:v 1 \\
    -vf "format=rgb24,scale=$MW:$MH:force_original_aspect_ratio=decrease" \\
    "$out" </dev/null || continue
  keep="$keep $key.png"
  printf "%s\\t%s\\n" "$f" "$out" >> "$tmp"
done
for c in "$T"/*; do
  [ -e "$c" ] || continue
  case " $keep " in *" ${c##*/} "*) ;; *) rm -f "$c" ;; esac
done
mv -f "$tmp" "$T/indice.tsv"
cat "$T/indice.tsv"'
        // Manda sobre el índice: sabe qué se ha borrado o añadido.
        stdout: StdioCollector {
            onStreamFinished: root.fulls = root._mapaDeCopias(text)
        }
    }
}
