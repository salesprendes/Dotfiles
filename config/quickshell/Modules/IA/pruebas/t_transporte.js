// Prueba del transporte (Payload.js): cómo sale una petición de esta máquina.
// Lo que se comprueba es lo que motivó el cambio — que la clave no esté en el
// argv y que un cuerpo grande LLEGUE, porque con la conversación entera en un
// argumento fallaba con E2BIG por encima de 128 kB.
const fs = require("fs")
const { execFileSync, spawn, spawnSync } = require("child_process")

const DIR = __dirname
const IA = "/home/salesprendes/.config/quickshell/Modules/IA/"
const PL = {}
new Function("exports", fs.readFileSync(IA + "Payload.js", "utf8")
    .replace(/^\.pragma library$/m, "") + `
exports.transport=transport; exports.probeTransport=probeTransport;
exports.transportError=transportError;`)(PL)

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) ok++
    else { mal++; console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : "")) }
}

const PUERTO = 8093
const DIARIO = DIR + "/recibido.json"
try { fs.unlinkSync(DIARIO) } catch (e) {}
const srv = spawn("python3", [DIR + "/falso_llm.py", String(PUERTO), DIARIO],
                  { stdio: ["ignore", "pipe", "inherit"] })
for (let i = 0; i < 100; i++) {
    try {
        execFileSync("sh", ["-c", "curl -s --max-time 1 -o /dev/null http://127.0.0.1:"
                                  + PUERTO + "/ping"], { stdio: "ignore" })
        break
    } catch (e) { execFileSync("sleep", ["0.05"]) }
}

// Ejecuta el transporte igual que QML: arranca el proceso, escribe el cuerpo en
// su entrada estándar y la CIERRA.
function envia(req, opts, sinCerrar) {
    const t = PL.transport(req, Object.assign(
        { url: "http://127.0.0.1:" + PUERTO + "/v1/chat/completions", maxTime: 20 }, opts))
    const r = spawnSync(t.cmd[0], t.cmd.slice(1), {
        input: sinCerrar ? undefined : t.body,
        env: Object.assign({}, process.env, t.env),
        encoding: "utf8", timeout: 40000,
        stdio: sinCerrar ? ["pipe", "pipe", "pipe"] : undefined })
    let recibido = null
    try { recibido = JSON.parse(fs.readFileSync(DIARIO, "utf8")) } catch (e) {}
    return { code: r.status, out: r.stdout || "", err: r.stderr || "",
             argv: t.cmd.join(" "), env: t.env, recibido: recibido }
}

try {

// ── 1. El cuerpo grande, que es el fallo que había ───────────────────────────
// Medido en esta máquina: un solo argumento aguanta hasta ~131 kB y a 200 kB
// devuelve E2BIG. Una captura en base64 o un hilo de treinta y dos mil
// componentes pasan de ahí sin esfuerzo, así que la petición fallaba antes de
// salir. Aquí van 400 kB.
const gordo = { model: "m", messages: [{ role: "user", content: "x".repeat(400000) }] }
comprueba("el cuerpo grande no cabría en un argumento",
          JSON.stringify(gordo).length > 131072)
let r = envia(gordo)
comprueba("y aun así llega entero", r.code === 0 && r.recibido
          && r.recibido.body.messages[0].content.length === 400000,
          r.code + " · " + (r.recibido ? r.recibido.body.messages[0].content.length : "nada"))
// Y la prueba de que el problema era real: el mismo cuerpo por argv revienta.
const viejo = spawnSync("curl", ["-sS", "-d", JSON.stringify(gordo),
                                 "http://127.0.0.1:" + PUERTO + "/v1/chat/completions"])
comprueba("por argv habría fallado (E2BIG)",
          viejo.error && viejo.error.code === "E2BIG",
          viejo.error ? viejo.error.code : "no falló")

// ── 2. La clave no está en el argv ───────────────────────────────────────────
// /proc/<pid>/cmdline es de lectura pública: una clave ahí la lee cualquier
// proceso de la máquina, y con ella iba la conversación entera.
const CLAVE = "sk-secreta-NO-DEBE-VERSE-123456"
r = envia({ model: "m", messages: [{ role: "user", content: "hola" }] },
          { bearer: CLAVE, extraHeader: 'X-Pasarela: a="b"; c=d', title: true })
comprueba("la clave NO está en el comando", r.argv.indexOf(CLAVE) === -1, r.argv)
comprueba("tampoco el cuerpo", r.argv.indexOf("hola") === -1, r.argv)
comprueba("la clave SÍ llega como cabecera",
          r.recibido && r.recibido.auth === "Bearer " + CLAVE,
          r.recibido && r.recibido.auth)
comprueba("la cabecera extra llega con sus comillas",
          r.recibido && r.recibido.pasarela === 'a="b"; c=d',
          r.recibido && r.recibido.pasarela)
comprueba("el tipo de contenido llega",
          r.recibido && r.recibido.ct === "application/json", r.recibido && r.recibido.ct)
comprueba("X-Title solo si toca", r.recibido && r.recibido.title === "Quickshell")
r = envia({ model: "m", messages: [] }, { bearer: "", title: false })
comprueba("sin clave no manda cabecera vacía",
          r.recibido && r.recibido.auth === null, r.recibido && r.recibido.auth)
comprueba("sin openrouter no manda X-Title", r.recibido && r.recibido.title === null)

// ── 3. Nada queda en el disco ────────────────────────────────────────────────
// El cuerpo pasa por un temporal: si se quedara, ahí estaría la conversación.
const antes = fs.readdirSync("/tmp").length
envia({ model: "m", messages: [{ role: "user", content: "rastro" }] })
const quedan = fs.readdirSync("/tmp").filter(f => {
    try { return fs.readFileSync("/tmp/" + f, "utf8").indexOf("rastro") !== -1 }
    catch (e) { return false }
})
comprueba("el temporal se borra al terminar", quedan.length === 0, quedan.join(","))

// ── 4. Si nadie cierra la entrada, se dice ───────────────────────────────────
// Sin este freno, olvidarse de cerrar la entrada dejaría la conversación muda
// para siempre y sin ninguna pista de por qué.
comprueba("hay un código propio para eso", PL.transportError(98) !== "")
comprueba("y otro para el temporal", PL.transportError(97) !== "")
comprueba("y ninguno para un error de curl", PL.transportError(7) === "")

// ── 5. Las banderas siguen llegando ──────────────────────────────────────────
const t1 = PL.transport({ stream: true }, { url: "u", maxTime: 300, stream: true })
comprueba("el streaming pide sin búfer", /-N --no-buffer/.test(t1.env.QS_FLAGS), t1.env.QS_FLAGS)
comprueba("el tope de tiempo viaja", /--max-time 300/.test(t1.env.QS_FLAGS))
const t2 = PL.transport({}, { url: "u", maxTime: 180, netFlags: ["-k"] })
comprueba("el TLS relajado viaja", /-k/.test(t2.env.QS_FLAGS), t2.env.QS_FLAGS)
comprueba("sin streaming no pide sin búfer", !/--no-buffer/.test(t2.env.QS_FLAGS))

// ── 6. La sonda, por la misma jaula ──────────────────────────────────────────
const p = PL.probeTransport({ url: "http://127.0.0.1:" + PUERTO + "/v1/models",
                              bearer: CLAVE })
comprueba("la sonda tampoco pone la clave en el argv",
          p.cmd.join(" ").indexOf(CLAVE) === -1, p.cmd.join(" "))
const rp = spawnSync(p.cmd[0], p.cmd.slice(1),
                     { env: Object.assign({}, process.env, p.env), encoding: "utf8" })
comprueba("la sonda contesta y trae el estado", /__QS 200/.test(rp.stdout || ""),
          JSON.stringify((rp.stdout || "").slice(-40)))
comprueba("y la sonda manda la clave",
          (rp.stdout || "").indexOf('"models"') !== -1, rp.stdout)

} finally {
    srv.kill()
}

// ── QUIÉN USA EL TRANSPORTE, Y SI LO USA ENTERO ──────────────────────────────
// La prueba que faltaba. chatCommand() devolvía un ARRAY y ahora devuelve un
// {cmd, env, body}: los cuatro llamantes se actualizaron y el supervisor no, así
// que asignaba el objeto entero a Process.command y se quedó mudo semanas. Nadie
// lo notó porque un supervisor que no contesta FALLA ABIERTO, que es justo el
// fallo que no se ve.
//
// Se mira el código fuente, no el comportamiento: un llamante nuevo que se
// olvide del cuerpo no falla en ninguna prueba de las otras — simplemente no
// envía nada. Aquí sí falla.
const D = "/home/salesprendes/.config/quickshell/Modules/IA/";
for (const f of ["ChatClient.qml", "Compactor.qml", "SubAgent.qml",
                 "AgentSupervisor.qml", "ConnectionProbe.qml"]) {
    const src = fs.readFileSync(D + f, "utf8");
    const llamadas = (src.match(/\b(?:chatCommand|probeCommand)\s*\(/g) || []).length;
    comprueba(f + ": llama al transporte", llamadas > 0, String(llamadas));
    // Nunca directo a .command: eso es lo que rompió el supervisor.
    comprueba(f + ": no asigna el objeto a command",
        !/\.command\s*=\s*(?:svc|AiService|ai)\.(?:chatCommand|probeCommand)/.test(src));
    comprueba(f + ": reparte cmd y env", /\.command\s*=\s*\w+\.cmd/.test(src)
                                       && /\.environment\s*=\s*\w+\.env/.test(src));
    // Y el cuerpo: abrir la entrada, escribirla al arrancar y CERRARLA. Sin el
    // cierre el shell espera quince segundos y sale con 98.
    const conCuerpo = /\.body/.test(src);
    comprueba(f + ": guarda el cuerpo", conCuerpo || f === "ConnectionProbe.qml");
    if (conCuerpo) {
        comprueba(f + ": lo escribe en onStarted", /onStarted[\s\S]{0,200}\.write\(/.test(src));
        comprueba(f + ": y cierra la entrada", /stdinEnabled\s*=\s*false/.test(src));
    }
}


console.log("\n" + ok + " bien, " + mal + " mal")
process.exit(mal === 0 ? 0 : 1)
