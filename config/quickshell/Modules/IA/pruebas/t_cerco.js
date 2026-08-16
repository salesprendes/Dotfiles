// LAS DOS FRONTERAS QUE SE REFORZARON: lo que viene de un servidor MCP no se
// auto-aprueba por su nombre, y una ruta que parece de casa pero apunta fuera
// por un enlace simbólico no se toca.
const fs = require("fs")
const vm = require("vm")
const os = require("os")
const path = require("path")
const { execFileSync } = require("child_process")

const D = __dirname + "/../"
function carga(archivo, exporta) {
    const c = {}
    vm.createContext(c)
    vm.runInContext(fs.readFileSync(D + archivo, "utf8")
        .replace(/^\.pragma library$/m, "") + ";__x={" + exporta + "};", c)
    return c.__x
}
const TP = carga("ToolPolicy.js",
    "riskClass,riskLevel,canStandingAllow,naturalPolicy,policy,neverAuto")
const LT = carga("LocalTools.js", "files,writes,acotado")

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) { ok++; return }
    mal++
    console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : ""))
}

// ── 1. MCP no se auto-aprueba por el verbo del nombre ────────────────────────
// El caso que lo explica: un servidor publica get_secrets, suena a lectura, y
// por dentro borra la base de datos. El nombre lo escribe quien queremos
// vigilar, así que no puede ser la autoridad.
const mcpLectura = ["mcp__foo__get_user", "mcp__foo__list_files",
                    "mcp__x__read_doc", "mcp__x__search", "mcp__x__query_db",
                    "mcp__evil__get_secrets"]
const mcpAccion = ["mcp__foo__delete_user", "mcp__x__deploy_now",
                   "mcp__x__send_email", "mcp__x__get_and_delete"]
for (const n of mcpLectura.concat(mcpAccion)) {
    for (const modo of ["careful", "normal", "auto"])
        comprueba(n + " pregunta en modo " + modo,
                  TP.naturalPolicy(n, modo) === "ask", TP.naturalPolicy(n, modo))
    // Ni siquiera se ofrece el "Siempre" de la tarjeta: ese permiso se concede
    // en un segundo mirando el nombre corto, que es justo el dato que no vale.
    comprueba(n + ": sin permiso permanente de tarjeta",
              TP.canStandingAllow(n) === false)
}
// Pero se puede autorizar A MANO, que es la salida honesta: si no, la única
// opción sería una tarjeta por llamada para siempre y se acabaría en modo auto.
comprueba("con excepción explícita sí queda en auto",
          TP.policy("mcp__foo__get_user", "normal",
                    { "mcp__foo__get_user": "auto" }) === "auto")
comprueba("y se puede apagar del todo",
          TP.policy("mcp__foo__get_user", "normal",
                    { "mcp__foo__get_user": "off" }) === "off")
// Lo nuestro no cambia: leer sigue siendo automático en modo normal.
comprueba("read_file sigue automático en normal",
          TP.naturalPolicy("read_file", "normal") === "auto")
comprueba("run_command sigue sin poder ser automático",
          TP.policy("run_command", "auto", { run_command: "auto" }) === "ask")

// La lista de permisos tiene que enseñarlas, o el permiso no se puede conceder.
const svc = fs.readFileSync(D + "AiService.qml", "utf8")
comprueba("AiService publica las MCP para la lista",
          /policyToolDefs[\s\S]{0,160}mcpClient\.toolDefs/.test(svc))
const lista = fs.readFileSync(D + "ToolPolicyList.qml", "utf8")
comprueba("la lista usa esa propiedad", lista.indexOf("AiService.policyToolDefs") !== -1)
comprueba("y les da grupo propio", lista.indexOf('"mcp"') !== -1)

// ── 2. El cerco de rutas mira a dónde apunta el enlace ───────────────────────
// safePath compara TEXTO. Un enlace simbólico se escribe entero dentro de la
// carpeta permitida y apunta fuera — y el modelo pudo crearlo él en una llamada
// anterior.
const jaula = fs.mkdtempSync(path.join(os.tmpdir(), "t_cerco_"))
fs.mkdirSync(jaula + "/dentro")
fs.writeFileSync(jaula + "/dentro/bueno.txt", "contenido legítimo\n")
const fuera = path.join(os.tmpdir(), "t_cerco_fuera_" + process.pid + ".txt")
fs.writeFileSync(fuera, "secreto de fuera\n")
fs.symlinkSync(fuera, jaula + "/dentro/enlace.txt")
fs.symlinkSync("/etc/passwd", jaula + "/dentro/passwd.txt")
fs.symlinkSync(jaula + "/dentro", jaula + "/dentro/circular")
const ctx = { home: jaula }
function corre(b) {
    const cmd = LT.acotado(20, b.cmd)
    try {
        return { rc: 0, out: execFileSync(cmd[0], cmd.slice(1),
            { env: Object.assign({}, process.env, b.env), encoding: "utf8" }) }
    } catch (e) { return { rc: e.status, out: String(e.stdout || "") + String(e.stderr || "") } }
}
const normal = corre(LT.files("read_file", { path: jaula + "/dentro/bueno.txt" }, ctx))
comprueba("un archivo normal se lee igual que siempre",
          normal.rc === 0 && normal.out.indexOf("contenido legítimo") !== -1,
          JSON.stringify(normal.out.slice(0, 60)))
for (const [q, ruta] of [["a /tmp", "/dentro/enlace.txt"],
                         ["a /etc/passwd", "/dentro/passwd.txt"]]) {
    const r = corre(LT.files("read_file", { path: jaula + ruta }, ctx))
    comprueba("no lee por un enlace " + q, r.rc === 96, r.rc)
    comprueba("  y dice a dónde apuntaba", /enlace simbólico que acaba en/.test(r.out),
              JSON.stringify(r.out.slice(0, 70)))
}
const esc = corre(LT.writes("write_file", jaula + "/dentro/enlace.txt",
                            { content: "PISADO" }, jaula + "/bak", jaula + "/bakd", ctx))
comprueba("no ESCRIBE por un enlace fuera", esc.rc === 96, esc.rc)
comprueba("y el archivo de fuera sigue intacto",
          fs.readFileSync(fuera, "utf8").trim() === "secreto de fuera")
// Un enlace que se queda DENTRO no molesta a nadie.
const dentro = corre(LT.files("list_dir", { path: jaula + "/dentro/circular" }, ctx))
comprueba("un enlace que apunta dentro sí vale", dentro.rc === 0, dentro.rc)
// Y sin pared no hay cerco: las consultas del sistema miran /var a propósito.
const sinPared = LT.files("read_file", { path: jaula + "/dentro/bueno.txt" }, ctx)
comprueba("la pared viaja en el entorno", sinPared.env.QS_PARED === jaula, sinPared.env.QS_PARED)
delete sinPared.env.QS_PARED
comprueba("sin pared el envoltorio no estorba", corre(sinPared).rc === 0)
// El taller del subagente es una pared más estrecha que la casa.
const taller = LT.files("read_file", { path: jaula + "/dentro/bueno.txt" },
                        { home: os.homedir(), root: jaula })
comprueba("para el subagente la pared es su taller", taller.env.QS_PARED === jaula,
          taller.env.QS_PARED)
fs.rmSync(jaula, { recursive: true, force: true })
fs.rmSync(fuera, { force: true })

console.log("\n" + ok + " bien, " + mal + " mal")
process.exit(mal === 0 ? 0 : 1)
