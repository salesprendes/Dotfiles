// EL DESPACHADOR. Doce constructores de comando que hasta ahora vivían dentro
// de un `switch` de 367 líneas en QML, o sea sin ninguna forma de probarlos: la
// única manera de saber si `service_ctl` rechazaba una unidad que empieza por
// guion era levantar el shell y pedírselo a un modelo.
//
// Ahora son JavaScript puro y se comprueban aquí uno a uno. Lo que más importa
// no es que construyan bien, sino que RECHACEN bien: casi todo lo que hay abajo
// es un intento de salir de la jaula, de colar un argumento donde no toca o de
// que un nombre raro se convierta en otra orden.
const fs = require("fs")
const vm = require("vm")
const path = require("path")

const IA = require("path").resolve(__dirname, "..") + "/"

function cargaLib(rel, cache) {
    cache = cache || ({})
    if (cache[rel])
        return cache[rel]
    const ruta = path.resolve(IA, rel)
    let src = fs.readFileSync(ruta, "utf8")
    const importa = []
    src = src.replace(/^\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/mg, (m, f, n) => {
        importa.push({ f: path.relative(IA, path.resolve(path.dirname(ruta), f)), n: n })
        return ""
    })
    src = src.replace(/^\.pragma library$/m, "")
    const nombres = []
    const re = /^(?:function|const|let|var)\s+(\w+)/mg
    let m2
    while ((m2 = re.exec(src)) !== null)
        if (nombres.indexOf(m2[1]) === -1)
            nombres.push(m2[1])
    const caja = ({})
    vm.createContext(caja)
    for (let i = 0; i < importa.length; i++)
        caja[importa[i].n] = cargaLib(importa[i].f, cache)
    vm.runInContext(src + ";__x={" + nombres.map(n => n + ":" + n).join(",") + "};", caja)
    cache[rel] = caja.__x
    return caja.__x
}

const DP = cargaLib("tools/Dispatch.js")
const TD = cargaLib("tools/ToolDefs.js")
const LT = cargaLib("tools/LocalTools.js")
const RT = cargaLib("tools/RemoteTools.js")
const RUNNER = fs.readFileSync(IA + "tools/ToolRunner.qml", "utf8")

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) { ok++; return }
    mal++
    console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : ""))
}

const CASA = "/home/x"
const CTX = {
    home: CASA,
    toolCtx: { home: CASA, hosts: [{ name: "servidor", host: "10.1.1.1", user: "ana" }],
               pass: ({}), haveSshpass: false },
    bak: "/tmp/undo/1.bak", undoDir: "/tmp/undo", iaDir: "/ia",
    searchBroken: false,
    searchCtx: { instancia: "", url: "", backend: "duckduckgo", key: "" }
}
const c = (nombre, args, extra) =>
    DP.construir(nombre, args, Object.assign({}, CTX, extra || ({})))
// Todo lo que se le pasa a un proceso, junto, para buscar dentro.
const todo = (r) => JSON.stringify(r.cmd) + " " + JSON.stringify(r.env)

// ── 1. Quién construye qué ───────────────────────────────────────────────────
// Devolver null es "esta familia no la construyo": quien llama debe probar en
// otro sitio, no dar la llamada por buena.
comprueba("lo que no le toca devuelve null", c("read_file", { path: "~/x" }) === null)
comprueba("y un nombre inventado también", c("herramienta_falsa", {}) === null)
comprueba("un comando sí lo construye", c("run_command", { command: "ls" }) !== null)

// La tabla de asíncronas y el switch que queda no pueden solaparse: una
// herramienta atendida por los dos caminos se ejecutaría dos veces.
// Solo el switch DEL DESPACHADOR: el fuente tiene otros (el que dice qué
// argumento de cada herramienta es una ruta, por ejemplo), y contarlos daría
// por atendida dos veces una herramienta que solo lo está una.
const TRAMO = RUNNER.slice(
    RUNNER.indexOf("── 3. Las que tocan estado del harness"),
    RUNNER.indexOf("        default: {"))
const enSwitch = (TRAMO.match(/^        case "([a-z_]+)":/mg) || [])
    .map(l => l.replace(/^        case "/, "").replace(/":$/, ""))
comprueba("el tramo del despachador se ha encontrado",
          TRAMO.length > 0 && enSwitch.length > 5, enSwitch.length)
for (const n of Object.keys(DP.ASINCRONAS))
    comprueba("la asíncrona " + n + " no está también en el switch",
              enSwitch.indexOf(n) === -1)

// Y toda herramienta declarada al modelo tiene que tener QUIEN la atienda: una
// anunciada que no atiende nadie es una promesa incumplida en cada llamada.
const declaradas = TD.core().concat(TD.sysQuery()).concat(TD.sysAction())
    .concat(TD.sshQuery()).concat(TD.sshAction()).concat(TD.dev())
    .map(d => d["function"].name)
// La familia de solo lectura se atiende ANTES del despacho, con el mismo
// constructor que sirve al subagente. Se calcula igual que en el harness en vez
// de escribirla a mano: una lista copiada se queda vieja y da falsos verdes.
const soloLectura = (n, args) =>
    LT.sysQuery(n, args, CTX.toolCtx) || RT.query(n, args, CTX.toolCtx)
    || LT.files(n, args, CTX.toolCtx)
// Y estas dos no las ejecuta nadie: esperan al usuario (una pregunta con
// opciones, un plan con su botón de empezar).
const ESPERAN = ["ask_user", "propose_plan"]
const ARGS = { path: "~/x", command: "ls", query: "q", action: "start",
               unit: "u", pid: 100, host: "servidor", remote_path: "/r",
               local_path: "~/l", start: 1, end: 2, text: "t", url: "https://x/",
               pattern: "p", name: "n", note: "n", lesson: "l", id: 1,
               code: "1", task: "t", server: "s", uri: "u", title: "t" }
const huerfanas = declaradas.filter(n =>
    DP.ASINCRONAS[n] === undefined && enSwitch.indexOf(n) === -1
    && ESPERAN.indexOf(n) === -1
    && soloLectura(n, ARGS) === null && c(n, ARGS) === null)
comprueba("ninguna herramienta anunciada se queda sin atender",
          huerfanas.length === 0, huerfanas.join(", "))
// Y al revés: nada que se atienda por dos caminos distintos.
const dobles = declaradas.filter(n =>
    (soloLectura(n, ARGS) !== null ? 1 : 0) + (c(n, ARGS) !== null ? 1 : 0)
    + (DP.ASINCRONAS[n] !== undefined ? 1 : 0)
    + (enSwitch.indexOf(n) !== -1 ? 1 : 0) > 1)
comprueba("ni ninguna atendida dos veces", dobles.length === 0, dobles.join(", "))

// ── 2. La jaula ──────────────────────────────────────────────────────────────
// Todo lo que recibe una ruta la pasa por safePath. Sin excepciones, y por eso
// se comprueban todas juntas: la que falte se ve.
const FUERA = ["/etc/passwd", "~/../../etc/shadow", "/home/otro/cosas"]
for (const ruta of FUERA) {
    comprueba("write_file rechaza " + ruta,
              (c("write_file", { path: ruta, content: "x" }) || {}).error !== undefined)
    comprueba("edit_file rechaza " + ruta,
              (c("edit_file", { path: ruta, old_string: "a", new_string: "b" }) || {}).error !== undefined)
    comprueba("edit_patch rechaza " + ruta,
              (c("edit_patch", { path: ruta, hunks: [{ at: "1", text: "x" }] }) || {}).error !== undefined)
    comprueba("edit_lines rechaza " + ruta,
              (c("edit_lines", { path: ruta, start: 1, end: 2, text: "x" }) || {}).error !== undefined)
    comprueba("ast_edit rechaza " + ruta,
              (c("ast_edit", { path: ruta, pattern: "a", rewrite: "b" }) || {}).error !== undefined)
}
// La carpeta de trabajo de un comando libre pasa por la misma jaula: sin esto,
// `cd` a cualquier sitio y el cerco no sirve de nada.
comprueba("run_command rechaza una carpeta de trabajo de fuera",
          c("run_command", { command: "ls", cwd: "/etc" }).error !== undefined)
comprueba("y la acepta dentro",
          c("run_command", { command: "ls", cwd: "~/p" }).error === undefined)
// El destino local de una transferencia también.
comprueba("sftp_get rechaza un destino local de fuera",
          c("sftp_get", { host: "servidor", remote_path: "/r", local_path: "/etc/x" }).error !== undefined)
comprueba("sftp_put rechaza un origen local de fuera",
          c("sftp_put", { host: "servidor", remote_path: "/r", local_path: "/etc/x" }).error !== undefined)

// ── 3. El comando libre ──────────────────────────────────────────────────────
const libre = c("run_command", { command: "echo hola" })
comprueba("el comando no viaja en el argv", JSON.stringify(libre.cmd).indexOf("echo hola") === -1)
comprueba("viaja por el entorno", libre.env.QS_CMD === "echo hola")
comprueba("un comando vacío se rechaza", c("run_command", { command: "" }).error !== undefined)
// El reloj lo pone la puerta, no el comando: un `timeout` metido aquí dentro
// ganaría al plazo de la política y el harness anunciaría una cosa y haría otra.
comprueba("el comando libre no trae su propio reloj",
          JSON.stringify(libre.cmd).indexOf("timeout") === -1)
// Con carpeta de trabajo se levanta el cerco de enlaces sobre ella.
const conCwd = c("run_command", { command: "ls", cwd: "~/p" })
comprueba("la carpeta de trabajo pasa por el cerco de enlaces",
          conCwd.env.QS_PARED === CASA && conCwd.env.QS_P === conCwd.env.QS_CWD)
comprueba("sin carpeta de trabajo no se levanta nada",
          libre.env.QS_CWD === undefined && libre.env.QS_PARED === undefined)

// ── 4. Servicios y procesos ──────────────────────────────────────────────────
comprueba("una acción inventada se rechaza",
          c("service_ctl", { action: "borrar", unit: "x" }).error !== undefined)
comprueba("una unidad vacía también",
          c("service_ctl", { action: "start", unit: "  " }).error !== undefined)
// Una unidad que empieza por guion la leería systemctl como una OPCIÓN.
comprueba("una unidad que parece una opción se rechaza",
          c("service_ctl", { action: "start", unit: "--version" }).error !== undefined)
const svc1 = c("service_ctl", { action: "restart", unit: "nginx.service" })
comprueba("systemctl recibe la unidad como argumento, sin shell",
          svc1.cmd[0] === "systemctl" && svc1.cmd.indexOf("--") !== -1)
comprueba("y el -- va antes de la unidad",
          svc1.cmd.indexOf("--") === svc1.cmd.indexOf("nginx.service") - 1)
comprueba("el modo usuario cambia el comando",
          c("service_ctl", { action: "start", unit: "u", user: true }).cmd.indexOf("--user") !== -1)

comprueba("un PID inválido se rechaza", c("kill_process", { pid: "x" }).error !== undefined)
// PID 1 es init: matarlo apaga la máquina.
comprueba("el PID 1 se rechaza", c("kill_process", { pid: 1 }).error !== undefined)
comprueba("y el 0 y los negativos también",
          c("kill_process", { pid: 0 }).error !== undefined
          && c("kill_process", { pid: -1 }).error !== undefined)
const kill1 = c("kill_process", { pid: 4321, signal: "KILL" })
comprueba("el PID viaja por el entorno", kill1.env.QS_PID === "4321")
comprueba("y no interpolado en el comando",
          JSON.stringify(kill1.cmd).indexOf("4321") === -1)
// Una señal inventada cae a TERM en vez de colarse en la línea de comando.
comprueba("una señal inventada cae a TERM",
          todo(c("kill_process", { pid: 99, signal: "; rm -rf /" })).indexOf("TERM") !== -1)
comprueba("y no se cuela en el comando",
          todo(c("kill_process", { pid: 99, signal: "; rm -rf /" })).indexOf("rm -rf") === -1)

// ── 5. Servidores remotos ────────────────────────────────────────────────────
comprueba("un ssh sin comando se rechaza",
          c("ssh_exec", { host: "servidor", command: "  " }).error !== undefined)
const ssh1 = c("ssh_exec", { host: "servidor", command: "uptime" })
comprueba("el ssh se construye", ssh1.error === undefined && ssh1.cmd[0] !== undefined)
comprueba("el comando remoto va tras un --", ssh1.cmd.indexOf("--") !== -1)
comprueba("y la salida remota va acotada",
          JSON.stringify(ssh1.cmd).indexOf("tail -c 16000") !== -1)
comprueba("una transferencia sin ruta remota se rechaza",
          c("sftp_get", { host: "servidor", local_path: "~/x", remote_path: " " }).error !== undefined)
// Subir y bajar son el mismo scp con el origen y el destino cambiados: si
// divergieran, una de las dos escribiría donde no debe.
const baja = c("sftp_get", { host: "servidor", remote_path: "/r/a", local_path: "~/a" })
const sube = c("sftp_put", { host: "servidor", remote_path: "/r/a", local_path: "~/a" })
comprueba("bajar pone el remoto primero",
          baja.cmd[baja.cmd.length - 2].indexOf(":/r/a") !== -1)
comprueba("subir pone el local primero",
          sube.cmd[sube.cmd.length - 1].indexOf(":/r/a") !== -1)
comprueba("y usan las mismas opciones",
          JSON.stringify(baja.cmd.slice(0, -2)) === JSON.stringify(sube.cmd.slice(0, -2)))

// ── 6. Edición por líneas, traducida a parche ────────────────────────────────
// edit_lines es la puerta estrecha traducida a un parche de un hunk: así el
// anclaje vive implementado en UN sitio y no puede divergir entre las dos.
comprueba("un rango al revés se rechaza",
          c("edit_lines", { path: "~/a", start: 9, end: 2, text: "x" }).error !== undefined)
comprueba("y empezar en 0 también",
          c("edit_lines", { path: "~/a", start: 0, end: 2, text: "x" }).error !== undefined)
const lin = c("edit_lines", { path: "~/a.txt", start: 3, end: 5,
                              start_hash: "ab", end_hash: "cd", text: "nuevo" })
comprueba("los hashes de los extremos viajan al motor",
          todo(lin).indexOf("3#ab") !== -1 && todo(lin).indexOf("5#cd") !== -1)
comprueba("un texto vacío es un borrado",
          todo(c("edit_lines", { path: "~/a", start: 1, end: 2, text: "" }))
              .indexOf("delete") !== -1)

// ── 7. La copia previa ───────────────────────────────────────────────────────
// Es lo que permite Deshacer, y su ruta forma parte del comando: por eso quien
// llama tiene que apuntarla ANTES de construir.
for (const n of ["write_file", "edit_file", "edit_patch", "edit_lines", "ast_edit"])
    comprueba(n + " deja copia", DP.dejaCopia(n, {}) && DP.ESCRIBEN[n] === "path")
comprueba("una lectura no deja copia", !DP.dejaCopia("read_file", {}))
// Ver el diff no cambia nada: gastar una copia sería mentir sobre lo ocurrido.
comprueba("un edit_patch en seco no deja copia",
          !DP.dejaCopia("edit_patch", { dry_run: true }))
comprueba("la ruta de la copia sale de los argumentos",
          DP.rutaDeEscritura("write_file", { path: "~/a" }) === "~/a")
comprueba("y de lo que no escribe, ninguna",
          DP.rutaDeEscritura("run_command", { command: "x" }) === "")

// ── 8. La búsqueda web ───────────────────────────────────────────────────────
comprueba("una consulta vacía se rechaza",
          c("web_search", { query: "  " }).error !== undefined)
// Con el pestillo echado se contesta sin tocar la red: cada intento costaba una
// conexión y, sobre todo, una ronda entera de razonamiento del modelo.
const roto = c("web_search", { query: "algo" }, { searchBroken: true })
comprueba("sin buscador no se sale a la red", roto.error !== undefined)
comprueba("y se dice que ya se sabía", roto.yaSabido === true)
comprueba("un fallo nuevo sí hay que vigilarlo",
          c("web_search", { query: "x" }).yaSabido !== true)

// ── 9. La tabla de asíncronas ────────────────────────────────────────────────
comprueba("cada operación del LSP va a su gestor",
          ["lsp", "lsp_rename", "lsp_fix", "lsp_raw"]
              .every(n => DP.ASINCRONAS[n].gestor === "lsp"))
comprueba("y con la operación que le toca",
          DP.ASINCRONAS.lsp_rename.op === "rename"
          && DP.ASINCRONAS.lsp_fix.op === "fix"
          && DP.ASINCRONAS.lsp_raw.op === "raw"
          && DP.ASINCRONAS.lsp.op === undefined)
comprueba("los trabajos van al suyo",
          ["job_start", "job_view", "job_input", "job_ctl"]
              .every(n => DP.ASINCRONAS[n].gestor === "jobs"))
comprueba("el depurador al suyo",
          ["debug_start", "debug_ctl", "debug_view", "debug_eval"]
              .every(n => DP.ASINCRONAS[n].gestor === "dbg"))
comprueba("la celda al suyo", DP.ASINCRONAS.python_exec.gestor === "repl")
// La `op` se AÑADE, no sustituye a los argumentos.
const aOp = DP.argsAsincrona("lsp_fix", { path: "~/a", line: 4 })
comprueba("la op se añade sin perder los argumentos",
          aOp.op === "fix" && aOp.path === "~/a" && aOp.line === 4)
comprueba("y no se toca el original",
          DP.argsAsincrona("lsp", { path: "~/a" }).op === undefined)
// Los cuatro gestores que nombra la tabla existen en el ejecutor: si alguien
// escribe un gestor mal, la llamada muere en silencio.
for (const g of ["lsp", "jobs", "dbg", "repl"])
    comprueba("el gestor '" + g + "' existe en el ejecutor",
              new RegExp("property var " + g + "\\b").test(RUNNER))
const gestores = {}
Object.keys(DP.ASINCRONAS).forEach(n => gestores[DP.ASINCRONAS[n].gestor] = 1)
comprueba("no hay gestores inventados en la tabla",
          Object.keys(gestores).every(g => ["lsp", "jobs", "dbg", "repl"].indexOf(g) !== -1),
          Object.keys(gestores).join(", "))

// ── 10. Lo que el despachador NO hace ────────────────────────────────────────
// Construir no es ejecutar. Aquí no se pone reloj, ni marco, ni bandera de red
// local: todo eso lo pone la puerta al envolver, y tenerlo repartido era el
// problema que este reparto viene a cerrar.
const FUENTE = fs.readFileSync(IA + "tools/Dispatch.js", "utf8")
comprueba("el despachador no pone reloj", FUENTE.indexOf("deadlineMs") === -1)
comprueba("no enmarca nada", FUENTE.indexOf("fence") === -1)
comprueba("no decide sobre la red de casa", FUENTE.indexOf("QS_LAN") === -1)
comprueba("y no ejecuta", FUENTE.indexOf(".running") === -1)

console.log(ok + " bien, " + mal + " mal")
process.exit(mal === 0 ? 0 : 1)
