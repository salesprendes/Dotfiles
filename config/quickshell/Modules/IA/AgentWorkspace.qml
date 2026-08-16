import QtQuick
import Quickshell
import Quickshell.Io

// EL TALLER de un subagente: las paredes dentro de las que trabaja.
//
// Un subagente con escritura NO escribe encima de los archivos vivos del
// usuario. Nunca. Escribe en un taller propio, y al terminar entrega lo que ha
// hecho para que el agente principal —con la aprobación de siempre— decida qué
// hacer con ello. Esa es la diferencia entre delegar y ceder el mando.
//
// Hay dos clases de taller, y se elige sola:
//
//   · WORKTREE. Si la raíz de trabajo está en un repositorio git, se le da un
//     árbol de trabajo aparte en una rama nueva. El subagente ve el proyecto
//     ENTERO y lo edita a gusto, y lo que hace se lee como un diff: git ya
//     resuelve el aislamiento, el deshacer y el "qué cambió" mucho mejor que
//     cualquier cosa que escribiéramos aquí. Varios subagentes a la vez no se
//     pisan porque cada árbol es un directorio distinto.
//   · CUADERNO. Si no hay repositorio (o el encargo no lo quiere), una carpeta
//     vacía suya. Sirve para lo que en realidad se pide casi siempre: producir
//     un informe, un script, tres archivos de configuración.
//
// Leer es otra cosa: se lee dentro de la RAÍZ (por defecto $HOME, y el jefe
// puede estrecharla). Lo que se lee no se rompe.
QtObject {
    id: ws

    property string agentId: ""
    property string home: ""
    property string agentsDir: ""        // …/data/agents
    property string root: ""             // raíz de LECTURA
    property bool wantWrite: false
    property string isolation: "auto"    // auto | worktree | scratch

    readonly property string dir: agentsDir + "/" + agentId
    readonly property string undoDir: dir + "/undo"
    readonly property string outDir: dir + "/out"
    readonly property string tracePath: dir + "/trace.jsonl"
    readonly property string branch: "agente/" + agentId

    // Lo que quedó montado (lo rellena prepare).
    property string mode: "read"         // read | scratch | worktree
    property string writeRoot: ""        // "" = no escribe
    property string repo: ""             // el repositorio, si es worktree
    property bool ready: false
    // El resumen de lo producido, ya en texto para el informe.
    property string changes: ""
    property bool changed: false

    signal prepared()

    // Cómo se le cuenta al modelo dónde está. Sin esto un subagente con
    // escritura intenta escribir en la ruta original y se lleva un "fuera del
    // área de trabajo" que no sabe interpretar.
    readonly property string note: {
        if (mode === "worktree")
            return "TALLER: trabajas en una copia aparte del repositorio "
                 + repo + ", montada en " + writeRoot + " (rama " + branch
                 + "). Las rutas RELATIVAS cuelgan de ahí: usa "
                 + "\"Carpeta/Archivo.ext\", no la ruta completa. Lo que "
                 + "escribas no toca los archivos vivos del usuario; al "
                 + "terminar se entrega como un diff."
        if (mode === "scratch")
            return "TALLER: tu carpeta de trabajo es " + writeRoot + " y está "
                 + "vacía. Escribe ahí (rutas relativas: \"informe.md\"). No "
                 + "puedes modificar archivos de fuera; para consultarlos, "
                 + "léelos."
        return ""
    }

    // ── Montaje ──────────────────────────────────────────────────────────────
    function prepare() {
        if (agentId === "" || agentsDir === "") {
            ws.ready = true
            ws.prepared()
            return
        }
        proc.onDone = (salida) => {
            const kv = ({})
            for (const l of String(salida).split("\n")) {
                const i = l.indexOf("=")
                if (i > 0)
                    kv[l.slice(0, i).trim()] = l.slice(i + 1).trim()
            }
            ws.mode = kv.MODE || "read"
            ws.writeRoot = kv.WRITE || ""
            ws.repo = kv.REPO || ""
            ws.ready = true
            ws.prepared()
        }
        proc.command = ["sh", "-c",
            // La guarda del principio no es paranoia decorativa: más abajo hay
            // un rm -rf, y una variable vacía lo convertiría en otra cosa.
            '[ -n "$QS_AG" ] && [ -n "$QS_DIR" ] || { echo "MODE=read"; exit 0; }; '
            + 'mkdir -p "$QS_DIR/out" "$QS_DIR/undo"; '
            // Poda de talleres viejos: se van los de más de una semana que no
            // tengan un árbol de git dentro (esos guardan trabajo sin recoger).
            + 'for d in "$QS_AG"/*/; do '
            + '  [ -d "$d" ] || continue; [ -e "$d/tree" ] && continue; '
            + '  [ -n "$(find "$d" -maxdepth 0 -mtime +7 2>/dev/null)" ] && rm -rf -- "$d"; '
            + 'done 2>/dev/null; '
            + '[ "$QS_W" = "1" ] || { echo "MODE=read"; exit 0; }; '
            + 'if [ "$QS_ISO" != "scratch" ]; then '
            + '  TOP=$(git -C "$QS_ROOT" rev-parse --show-toplevel 2>/dev/null); '
            + '  if [ -n "$TOP" ] && git -C "$TOP" worktree add -q -b "$QS_BR" "$QS_DIR/tree" >/dev/null 2>&1; then '
            + '    echo "MODE=worktree"; echo "REPO=$TOP"; echo "WRITE=$QS_DIR/tree"; exit 0; '
            + '  fi; '
            + 'fi; '
            + 'echo "MODE=scratch"; echo "WRITE=$QS_DIR/out"']
        proc.environment = ({
            QS_AG: agentsDir, QS_DIR: dir, QS_ROOT: root || home,
            QS_BR: branch, QS_W: wantWrite ? "1" : "0", QS_ISO: isolation
        })
        proc.running = true
    }

    // ── Recogida y desmontaje, de una vez ────────────────────────────────────
    // Qué produjo, en el formato que mejor lo cuenta: un diff si es un árbol de
    // git, la lista de archivos si es un cuaderno. Y en el mismo paso se quita
    // el árbol si está VACÍO — dejar una rama muerta en el repositorio del
    // usuario por cada subagente que no encontró nada que hacer sería un regalo
    // envenenado. Uno con cambios se queda: es el entregable, y el informe dice
    // dónde está.
    //
    // Las dos cosas van juntas a propósito: al terminar, el subagente se
    // destruye enseguida, y encadenar dos procesos sobre un objeto que se está
    // muriendo es la clase de carrera que solo aparece el día que estorba.
    readonly property string _recoger:
        'if [ "$QS_MODE" = "worktree" ]; then '
        + '  git -C "$QS_W" add -A >/dev/null 2>&1; '
        + '  OUT=$(git -C "$QS_W" diff --cached --stat 2>/dev/null | tail -n 30); '
        + '  if [ -z "$OUT" ]; then '
        + '    git -C "$QS_REPO" worktree remove --force "$QS_W" >/dev/null 2>&1; '
        + '    git -C "$QS_REPO" branch -D "$QS_BR" >/dev/null 2>&1; '
        + '  fi; '
        + '  printf %s "$OUT"; '
        + 'else '
        + '  find "$QS_W" -type f -printf "%P (%s B)\\n" 2>/dev/null | head -n 30; '
        + 'fi'

    function collect(cb) {
        if (mode === "read" || writeRoot === "") {
            cb("")
            return
        }
        proc.onDone = (salida) => {
            const t = String(salida).trim()
            ws.changed = t !== ""
            ws.changes = t
            cb(t)
        }
        proc.command = ["sh", "-c", ws._recoger]
        proc.environment = ({ QS_MODE: mode, QS_W: writeRoot,
                              QS_REPO: repo, QS_BR: branch })
        proc.running = true
    }

    // La misma limpieza cuando al subagente lo cortan: el objeto muere en este
    // mismo turno, así que sale suelta. Los argumentos van por posición —no hay
    // interpolación, igual que con el entorno— porque un proceso desligado no
    // hereda el nuestro.
    function discardDetached() {
        if (mode !== "worktree" || writeRoot === "")
            return
        Quickshell.execDetached(["sh", "-c",
            'MODE=$1; W=$2; REPO=$3; BR=$4; '
            + 'git -C "$W" add -A >/dev/null 2>&1; '
            + 'if [ -z "$(git -C "$W" diff --cached --stat 2>/dev/null)" ]; then '
            + '  git -C "$REPO" worktree remove --force "$W" >/dev/null 2>&1; '
            + '  git -C "$REPO" branch -D "$BR" >/dev/null 2>&1; '
            + 'fi; exit 0',
            "sh", mode, writeRoot, repo, branch])
    }

    // Un solo proceso, y basta: montar, recoger y desmontar ocurren en momentos
    // distintos de la vida del subagente y nunca se solapan.
    readonly property Process _proc: Process {
        id: proc
        property var onDone: null
        stdout: StdioCollector { id: pOut }
        stderr: StdioCollector {}
        onExited: {
            const f = proc.onDone
            proc.onDone = null
            if (f)
                f(pOut.text || "")
        }
    }
}
