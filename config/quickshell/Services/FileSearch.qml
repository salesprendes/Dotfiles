pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// El índice de archivos y carpetas de Spotlight.
//
// ── POR QUÉ ÍNDICE Y NO UNA BÚSQUEDA POR CONSULTA ───────────────────────────
// Esto lanzaba un 'fd' por consulta, con rebote de 180 ms, y solo con el
// prefijo "/". Funcionaba, pero imponía dos cosas: los archivos llegaban TARDE
// —en su propio carril, después de que la lista ya se hubiera dibujado— y por
// eso no podían mezclarse con las apps en una sola lista ordenada.
//
// Medido en esta máquina: 3.438 archivos y carpetas útiles, 364 KB de rutas,
// y un recorrido completo con fd en 12 MILISEGUNDOS. A esa escala, recorrer
// por consulta es tirar un proceso por tecla para nada.
//
// Así que se recorre UNA vez, se guarda la lista cruda en memoria, y buscar
// pasa a ser filtrar cadenas. Los archivos dejan de ser una fuente asíncrona y
// entran en el mismo puntuador que todo lo demás.
//
// ── POR QUÉ NO plocate ──────────────────────────────────────────────────────
// Es el equivalente honesto al índice del kernel que usa macOS, y se descartó
// a propósito: es una base de datos de TODO el sistema con su temporizador de
// systemd, y no le puede ganar a 12 ms sobre tres mil archivos. Sería una
// dependencia nueva a cambio de nada. (DankMaterialShell sí necesita la suya,
// pero porque apunta a máquinas con millones de archivos.)
Singleton {
    id: root

    // Tope de lo que se guarda en el índice. No es por memoria —364 KB— sino
    // por sentido: si un $HOME tiene cien mil archivos, indexarlos todos no
    // mejora ninguna búsqueda y sí empeora cada una.
    readonly property int cap: 40000

    // Por debajo de dos letras no se filtra. Con una, media lista coincide.
    //
    // Baja de tres a dos porque ya no cuesta un recorrido del disco: filtrar
    // cadenas en memoria con una sola letra es barato, y lo único que lo
    // desaconseja es el ruido. Con dos, el ruido ya es manejable.
    readonly property int minChars: 2

    // Carpetas que NO se indexan.
    //
    // '.cache' es la que importa: en esta máquina son 12.316 archivos de los
    // 15.792 que hay — el 78 % del $HOME es basura regenerable que nadie busca
    // jamás. 'node_modules', '__pycache__' y '.venv' son lo mismo en pequeño.
    //
    // Y LA PAPELERA, que son otros 654. Esa no es una cuestión de ruido sino de
    // que estaría mal: un archivo que borraste no puede aparecer en una
    // búsqueda como si siguiera ahí. Y aparecía además DUPLICANDO al vivo, con
    // el mismo nombre y una ruta que no dice a simple vista que está en la
    // basura.
    readonly property var excluidas: [".git", ".cache", "node_modules",
                                      "__pycache__", ".venv",
                                      "Trash", ".Trash-1000"]

    // La lista cruda: rutas absolutas, tal cual las escupe la herramienta.
    // Crudas y no objetos a propósito — ver la nota de las dos etapas en
    // filtrar().
    property var index: []
    property bool building: false
    property double builtAt: 0

    readonly property string home: Quickshell.env("HOME") || "/home"

    // ── Herramienta ──────────────────────────────────────────────────────────
    // 'fd' recorre en paralelo y entiende de exclusiones; 'find' está SIEMPRE.
    // Sin el suelo de 'find' no habría búsqueda de archivos en media máquina, y
    // media función es peor que una función lenta.
    property string tool: ""
    Process {
        id: probe
        running: true
        command: ["sh", "-c", "command -v fd || command -v fdfind || command -v find"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.tool = String(this.text || "").trim().split("\n")[0] || ""
            }
        }
    }

    // El sondeo no arranca hasta que alguien toca el singleton por primera vez
    // (así son los Singleton de Quickshell). Si la detección tarda más que la
    // primera petición de índice, aquélla se quedaría sin herramienta y se
    // rendiría en silencio. Al llegar, se construye lo que estuviera pendiente.
    property bool _pendiente: false
    onToolChanged: if (root.tool !== "" && root._pendiente) root.build()

    // ── Construcción del índice ──────────────────────────────────────────────
    function _argv() {
        const t = root.tool
        if (t === "")
            return null
        if (t.endsWith("/fd") || t.endsWith("/fdfind")) {
            // --hidden porque lo que este usuario busca de verdad vive en
            // ~/.config y ~/.claude; sin él, el índice se queda en 433 archivos
            // y no encuentra su propia configuración.
            const argv = [t, "--type", "f", "--type", "d", "--hidden",
                          "--max-results", String(root.cap)]
            for (const e of root.excluidas)
                argv.push("--exclude", e)
            return argv.concat(["", root.home])
        }
        // find: las exclusiones se PODAN, para no bajar al árbol en vez de
        // filtrarlo después. Podar .cache es lo que convierte 15.792 archivos
        // en 3.438 sin gastar el recorrido.
        const argv = [t, root.home]
        for (let i = 0; i < root.excluidas.length; i++) {
            argv.push(i === 0 ? "(" : "-o", "-name", root.excluidas[i])
            if (i === root.excluidas.length - 1)
                argv.push(")")
        }
        return argv.concat(["-prune", "-o", "(", "-type", "f", "-o",
                            "-type", "d", ")", "-print"])
    }

    property var _acc: []

    Process {
        id: crawl
        stdout: SplitParser {
            onRead: function (line) {
                if (root._acc.length >= root.cap) {
                    crawl.running = false
                    return
                }
                if (line !== "")
                    root._acc.push(line)
            }
        }
        onRunningChanged: {
            if (running)
                return
            root.index = root._acc
            root._acc = []
            root.building = false
            root.builtAt = Date.now()
        }
    }

    // Reconstruye si hace más de 'frescura' que se hizo. Lo llama Spotlight al
    // abrirse: son 12 ms, así que se paga en cada apertura y a cambio un
    // archivo creado hace un minuto ya está. La guarda evita rehacerlo si
    // abres y cierras dos veces seguidas.
    readonly property int frescura: 5000

    function build(forzar) {
        if (root.building)
            return
        if (root.tool === "") {
            root._pendiente = true
            return
        }
        root._pendiente = false
        if (!forzar && root.index.length > 0
            && (Date.now() - root.builtAt) < root.frescura)
            return
        const argv = root._argv()
        if (!argv)
            return
        root._acc = []
        root.building = true
        crawl.command = argv
        crawl.running = true
    }

    // ── Filtrado ─────────────────────────────────────────────────────────────
    // DOS ETAPAS, y es lo que hace que esto sea instantáneo.
    //
    // El puntuador de Spotlight (Search.js) normaliza y parte en palabras cada
    // candidato, y guarda el resultado en el propio objeto. Construir tres mil
    // objetos por pulsación para que el puntuador los descarte casi todos sería
    // el cuello de botella de verdad — el disco no lo era nunca.
    //
    // Así que primero se criba con indexOf sobre la cadena cruda: sin reservar
    // memoria, sin normalizar, sin partir nada. Solo los supervivientes —
    // decenas — llegan a construirse como objetos y a puntuarse.
    //
    // La criba es deliberadamente TONTA y generosa: no decide el orden, solo
    // decide quién no tiene ninguna posibilidad. Ordenar es cosa del puntuador.
    function filtrar(q, tope) {
        const consulta = String(q || "").trim().toLowerCase()
        if (consulta.length < root.minChars)
            return []
        // Una consulta de RUTA ("dotfiles/script") se criba contra la ruta
        // entera; una de nombre, solo contra el último tramo. Sin esta
        // distinción, buscar "sh" traería cualquier archivo que tuviera un
        // "sh" en cualquier carpeta del camino.
        const porRuta = consulta.indexOf("/") !== -1
        const limite = tope && tope > 0 ? tope : root.cap
        const out = []
        const lista = root.index
        for (let i = 0; i < lista.length; i++) {
            const ruta = lista[i]
            const heno = porRuta ? ruta.toLowerCase()
                                 : ruta.slice(ruta.lastIndexOf("/") + 1).toLowerCase()
            if (heno.indexOf(consulta) !== -1) {
                out.push(ruta)
                if (out.length >= limite)
                    break
            }
        }
        return out
    }

    function clear() {
        // El índice NO se tira al cerrar Spotlight: es lo único que hay que
        // conservar para que la siguiente apertura sea instantánea, y son
        // 364 KB. Lo que se suelta es el recorrido si estuviera a medias.
        if (root.building) {
            crawl.running = false
            root._acc = []
            root.building = false
        }
    }
}
