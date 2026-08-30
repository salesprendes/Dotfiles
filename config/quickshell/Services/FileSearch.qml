pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Búsqueda de archivos por nombre para el prefijo "/" de Spotlight.
//
// POR QUÉ ES UN SERVICIO Y NO UNA FUNCIÓN MÁS EN Sources.qml: las otras fuentes
// son síncronas —el catálogo de apps ya está en memoria, los emojis se leen de
// un JSON— y esta no puede serlo. Recorrer un $HOME tarda cientos de
// milisegundos, y hacerlo dentro del binding de resultados congelaría el
// teclado en cada letra. Aquí se lanza fuera, se acumula lo que va llegando y
// se publica cuando termina; Spotlight solo mira 'results'.
Singleton {
    id: root

    // Tope de resultados. No es por memoria sino por sentido: nadie repasa una
    // lista de mil archivos en un buscador que se maneja con las flechas, y
    // parar pronto es lo que permite matar el proceso antes de que acabe de
    // recorrer el disco.
    readonly property int cap: 100

    // Por debajo de tres letras no se busca. Con una o dos, la mitad del $HOME
    // coincide: se paga el recorrido entero del disco para devolver ruido.
    readonly property int minChars: 3

    property var results: []
    property bool running: false
    property string query: ""

    // ── Herramienta ──────────────────────────────────────────────────────────
    // 'fd' es varias veces más rápido (recorre en paralelo y respeta
    // .gitignore), pero no está en una instalación básica. 'find' sí está
    // SIEMPRE, así que es el suelo: sin él no habría prefijo "/" en la mitad de
    // las máquinas, y un prefijo que funciona en unas y en otras no es peor que
    // no tenerlo.
    property string tool: ""
    Process {
        id: probe
        running: true
        command: ["sh", "-c", "command -v fd || command -v fdfind || command -v find"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const linea = String(this.text || "").trim().split("\n")[0] || ""
                root.tool = linea
            }
        }
    }

    // El sondeo no arranca hasta que alguien toca el singleton por primera vez
    // (así son los Singleton de Quickshell), o sea justo cuando se teclea el
    // primer "/". Si la detección tarda más que el rebote, _launch() se
    // encuentra sin herramienta y se rinde EN SILENCIO: la primera búsqueda de
    // cada arranque no devolvía nada y no había forma de saber por qué. Al
    // llegar la herramienta se relanza lo que estuviera pendiente.
    onToolChanged: if (root.tool !== "" && root.query.length >= root.minChars)
        root._launch()

    readonly property string home: Quickshell.env("HOME") || "/home"

    // Argumentos por herramienta. Van como LISTA, nunca por 'sh -c': lo que se
    // busca lo escribe el usuario, y meterlo en una cadena de shell es abrirle
    // la puerta a que un nombre con comillas o un ';' ejecute algo. Como lista,
    // el texto llega al programa como un argumento y nada más.
    function _argv(q) {
        const t = root.tool
        if (t === "")
            return null
        // ¿Es un trozo de RUTA o solo un nombre? "documentos/informe" quiere
        // decir «informe, pero dentro de documentos», y eso no lo puede
        // resolver una comparación contra el nombre del archivo a secas.
        const porRuta = q.indexOf("/") !== -1
        if (t.endsWith("/fd") || t.endsWith("/fdfind")) {
            const argv = [t, "--type", "f", "--max-results", String(root.cap),
                          "--exclude", ".git"]
            if (porRuta)
                argv.push("--full-path")
            return argv.concat([q, root.home])
        }
        // find: se poda lo oculto en vez de filtrarlo después, para no bajar a
        // ~/.cache ni a ~/.local/share, que son el grueso de los archivos de un
        // $HOME y nunca son lo que se busca. La profundidad acotada es por lo
        // mismo: a partir de seis niveles ya es todo árboles de dependencias.
        return [t, root.home, "-maxdepth", "6",
                "-name", ".*", "-prune", "-o",
                "-type", "f", porRuta ? "-ipath" : "-iname", "*" + q + "*",
                "-print"]
    }

    // ── Proceso ──────────────────────────────────────────────────────────────
    property var _acc: []

    // Matar el proceso también dispara onRunningChanged, y ahí no hay forma de
    // distinguir «ha terminado» de «lo he matado yo». Sin esta marca, abortar
    // una búsqueda para lanzar la siguiente publicaba lo que llevara acumulado
    // de la consulta ANTERIOR: al teclear rápido, la lista enseñaba a medias
    // los resultados de un texto que ya no estaba escrito.
    property bool _abortando: false

    function _matar() {
        root._abortando = true
        hunt.running = false
        root._abortando = false
    }

    Process {
        id: hunt
        stdout: SplitParser {
            onRead: function (line) {
                if (root._acc.length >= root.cap) {
                    // Ya hay de sobra: parar aquí ahorra el resto del recorrido.
                    // 'find' no tiene tope propio, así que este es el único.
                    // Y aquí NO se aborta: lo acumulado es justo lo que se pide.
                    hunt.running = false
                    return
                }
                if (line !== "")
                    root._acc.push(line)
            }
        }
        onRunningChanged: {
            if (running || root._abortando)
                return
            root.results = root._acc
            root.running = false
        }
    }

    // Rebote. Escribir "documento" son nueve pulsaciones, y sin esto son nueve
    // recorridos del disco de los que solo importa el último.
    Timer {
        id: rebote
        interval: 180
        onTriggered: root._launch()
    }

    function _launch() {
        root._matar()
        const q = root.query
        if (q.length < root.minChars) {
            root._acc = []
            root.results = []
            root.running = false
            return
        }
        const argv = root._argv(q)
        if (!argv) {
            root.running = false
            return
        }
        root._acc = []
        root.running = true
        hunt.command = argv
        hunt.running = true
    }

    // La consulta llega con la barra del prefijo puesta: Search.parseQuery la
    // conserva a propósito, porque "/etc/hosts" es una ruta absoluta y no el
    // archivo "etc/hosts". Para buscar por nombre sobra, así que se quita UNA
    // —y solo una— barra del principio: "//" en medio de una ruta no es lo
    // mismo que el prefijo.
    function _limpia(q) {
        const t = (q || "").trim()
        return t.charAt(0) === "/" ? t.substring(1) : t
    }

    function search(q) {
        const limpio = root._limpia(q)
        if (limpio === root.query)
            return
        root.query = limpio
        if (limpio.length < root.minChars) {
            // Se limpia YA, sin esperar al rebote: al borrar hasta dejar dos
            // letras, seguir enseñando los resultados de la consulta anterior
            // es enseñar algo que ya no se ha pedido.
            rebote.stop()
            root._matar()
            root.results = []
            root.running = false
            return
        }
        rebote.restart()
    }

    // Al cerrar el buscador: soltar el proceso y la lista. Un 'find' sobre el
    // $HOME que sigue corriendo después de cerrar es disco gastado para nadie.
    function clear() {
        rebote.stop()
        root._matar()
        root.query = ""
        root._acc = []
        root.results = []
        root.running = false
    }
}
