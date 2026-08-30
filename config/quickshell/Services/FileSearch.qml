pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Índice de archivos y carpetas de Spotlight.
//
// El árbol se recorre UNA vez y la lista cruda se guarda en memoria, así que
// buscar es filtrar cadenas. Con unos miles de archivos útiles el recorrido
// completo cuesta unos milisegundos, de modo que lanzar un proceso por consulta
// sería tirar un proceso por tecla para nada.
//
// La consecuencia importante es que los archivos dejan de ser una fuente
// asíncrona que llega tarde y entran en el mismo puntuador que todo lo demás,
// en una sola lista ordenada.
Singleton {
    id: root

    // Tope de lo que se guarda. No es por memoria sino por sentido: si un $HOME
    // tiene cien mil archivos, indexarlos todos no mejora ninguna búsqueda.
    readonly property int cap: 40000

    // Por debajo de dos letras no se filtra: con una, media lista coincide.
    // Filtrar cadenas en memoria con una sola letra es barato, así que lo único
    // que lo desaconseja es el ruido.
    readonly property int minChars: 2

    // Carpetas que no se indexan. Las de caché son la mayor parte del $HOME y
    // son basura regenerable que nadie busca.
    //
    // La papelera no es cuestión de ruido sino de corrección: un archivo borrado
    // no puede aparecer en una búsqueda como si siguiera ahí, y además duplicaba
    // al vivo con el mismo nombre y una ruta que no delata dónde está.
    readonly property var excluidas: [".git", ".cache", "node_modules",
                                      "__pycache__", ".venv",
                                      "Trash", ".Trash-1000"]

    // La lista cruda: rutas absolutas tal cual las escupe la herramienta. Crudas
    // y no objetos a propósito; ver la nota de las dos etapas en filtrar().
    property var index: []
    property bool building: false
    property double builtAt: 0

    readonly property string home: Quickshell.env("HOME") || "/home"

    // 'fd' recorre en paralelo y entiende de exclusiones; 'find' está siempre.
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

    // El sondeo no arranca hasta que alguien toca el singleton. Si la detección
    // tarda más que la primera petición de índice, aquélla se quedaría sin
    // herramienta y se rendiría en silencio, así que al llegar se construye lo
    // que hubiera pendiente.
    property bool _pendiente: false
    onToolChanged: if (root.tool !== "" && root._pendiente) root.build()

    // Construcción del índice
    function _argv() {
        const t = root.tool
        if (t === "")
            return null
        if (t.endsWith("/fd") || t.endsWith("/fdfind")) {
            // --hidden porque buena parte de lo que se busca vive en carpetas
            // ocultas de configuración; sin él, el índice no encuentra ni la
            // configuración del propio shell.
            const argv = [t, "--type", "f", "--type", "d", "--hidden",
                          "--max-results", String(root.cap)]
            for (const e of root.excluidas)
                argv.push("--exclude", e)
            return argv.concat(["", root.home])
        }
        // find: las exclusiones se podan para no bajar al árbol, en vez de
        // filtrarlo después. Podar las cachés es lo que recorta el índice sin
        // gastar el recorrido.
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
    // abrirse: cuesta milisegundos, así que se paga en cada apertura y a cambio
    // un archivo creado hace un minuto ya está. La guarda evita rehacerlo al
    // abrir y cerrar dos veces seguidas.
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

    // Dos etapas, y es lo que hace que esto sea instantáneo.
    //
    // El puntuador de Spotlight normaliza y parte en palabras cada candidato, y
    // guarda el resultado en el propio objeto. Construir miles de objetos por
    // pulsación para descartarlos casi todos sería el cuello de botella real.
    //
    // Así que primero se criba con indexOf sobre la cadena cruda, sin reservar
    // memoria ni normalizar ni partir nada, y solo los supervivientes se
    // construyen como objetos y se puntúan. La criba es deliberadamente tonta y
    // generosa: no decide el orden, solo quién no tiene ninguna posibilidad.
    function filtrar(q, tope) {
        const consulta = String(q || "").trim().toLowerCase()
        if (consulta.length < root.minChars)
            return []
        // Una consulta de ruta se criba contra la ruta entera; una de nombre,
        // solo contra el último tramo. Sin esa distinción, buscar dos letras
        // traería cualquier archivo que las tuviera en cualquier carpeta.
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
        // El índice no se tira al cerrar Spotlight: es lo único que hay que
        // conservar para que la siguiente apertura sea instantánea, y ocupa unos
        // cientos de KB. Lo que se suelta es el recorrido si estuviera a medias.
        if (root.building) {
            crawl.running = false
            root._acc = []
            root.building = false
        }
    }
}
