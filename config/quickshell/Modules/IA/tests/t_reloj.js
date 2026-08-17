// Prueba del vigilante: la tabla de plazos (ToolPolicy.js de producción) y el
// corte de verdad, ejecutando el MISMO envoltorio que arma exec().
const fs = require("fs")
const { execFileSync, spawnSync } = require("child_process")

const IA = require("path").resolve(__dirname, "..") + "/"
const src = fs.readFileSync(IA + "tools/ToolPolicy.js", "utf8").replace(/^\.pragma library$/m, "")
const TP = new Function(src + `
return { deadlineMs, deadlineText, riskClass, PLAZO_S, PLAZO_CLASE }`)()

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) ok++
    else { mal++; console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : "")) }
}

// ── 1. Toda herramienta tiene plazo, y ninguno es absurdo ────────────────────
// El catálogo real, sacado de ToolDefs: si mañana se añade una herramienta y
// nadie le pone plazo, tiene que caer en la red de su clase, no en undefined.
const TODAS = (fs.readFileSync(IA + "tools/ToolDefs.js", "utf8")
    .match(/name: "([a-z_0-9]+)"/g) || []).map(s => s.slice(7, -1))
comprueba("hay catálogo que probar", TODAS.length > 40, TODAS.length)
for (const t of TODAS) {
    const ms = TP.deadlineMs(t)
    comprueba(t + ": tiene plazo", typeof ms === "number" && ms > 0, ms)
    comprueba(t + ": el plazo es razonable", ms >= 10000 && ms <= 660000, ms)
}
// Una herramienta que no existe no puede dejar el reloj sin poner.
comprueba("una desconocida cae en la red", TP.deadlineMs("herramienta_inventada") === 30000,
          TP.deadlineMs("herramienta_inventada"))
comprueba("un nombre vacío también", TP.deadlineMs("") > 0)
comprueba("una del MCP tiene su propio plazo",
          TP.deadlineMs("mcp__loquesea__get_thing") === 60000,
          TP.deadlineMs("mcp__loquesea__get_thing"))

// ── 2. El plazo dice lo que TARDA, no lo que ARRIESGA ────────────────────────
// Es el motivo de que la tabla vaya por nombre: read_file y disk_query son las
// dos "lectura" y no se parecen en nada.
comprueba("read_file y disk_query son la misma clase",
          TP.riskClass("read_file") === TP.riskClass("disk_query"))
comprueba("…y NO el mismo plazo",
          TP.deadlineMs("read_file") < TP.deadlineMs("disk_query"),
          TP.deadlineMs("read_file") + " vs " + TP.deadlineMs("disk_query"))
// Las que salen a otra máquina esperan más que las locales.
comprueba("lo remoto espera más que lo local",
          TP.deadlineMs("ssh_exec") > TP.deadlineMs("read_file"))
comprueba("una celda de Python puede ser un cálculo de verdad",
          TP.deadlineMs("python_exec") >= 120000, TP.deadlineMs("python_exec"))
// El subagente trae su propio reloj (600 s como mucho): el nuestro va por
// debajo, no por delante, o lo mataría a mitad de un encargo legítimo.
comprueba("el subagente sobrevive a su propio presupuesto",
          TP.deadlineMs("subagent") > 600000, TP.deadlineMs("subagent"))
// La búsqueda web tiene que caber: su peor caso es la rama de SearXNG, que es
// secuencial sobre las bases configuradas.
const BASES = 4, MAXT = 8
comprueba("el plazo de web_search cubre su peor caso",
          TP.deadlineMs("web_search") > BASES * MAXT * 1000,
          TP.deadlineMs("web_search") + " vs " + BASES * MAXT * 1000)

// ── 3. El texto que ve el modelo ─────────────────────────────────────────────
// Un corte mal explicado es peor que el corte: el modelo repite igual.
const txt = TP.deadlineText("glob_files", 45000)
comprueba("dice qué herramienta fue", /glob_files/.test(txt))
comprueba("dice cuánto esperó", /45 segundos/.test(txt), txt)
comprueba("dice que NO es culpa de los argumentos", /NO es un error de tus argumentos/.test(txt))
comprueba("dice qué hacer distinto", /ACOTA/.test(txt))
comprueba("desaconseja repetir igual", /mismo corte/.test(txt))

// ── 4. El corte, de verdad ───────────────────────────────────────────────────
// Se arma el MISMO comando que arma exec() y se ejecuta. Lo que se comprueba no
// es la tabla: es que coreutils mata, que el código de salida es el que el
// ejecutor busca, y que la salida a medias no se cuela.
// El envoltorio ya no lo arma ToolRunner a mano: vive en LocalTools.acotado,
// porque lo comparten el ejecutor de herramientas y el de hooks. Se carga de
// ahí para que esta batería pruebe lo que de verdad se ejecuta.
const LT = new Function(
    fs.readFileSync(IA + "tools/LocalTools.js", "utf8").replace(/^\.pragma library$/m, "")
    + "\nreturn { acotado: acotado }")()

function comoExec(cmdArray, seg) {
    const cmd = LT.acotado(seg, cmdArray)
    // maxBuffer generoso: el de node son 1 MiB y MATA al hijo al pasarse, lo
    // que falsearía justo la prueba del tope de 2 MB —parecería que el
    // envoltorio corta mal cuando quien corta es el arnés—.
    const r = spawnSync(cmd[0], cmd.slice(1),
        { encoding: "utf8", timeout: 30000, maxBuffer: 8 * 1024 * 1024 })
    return { code: r.status, out: r.stdout || "" }
}
comprueba("existe timeout", spawnSync("timeout", ["--version"]).status === 0)

let t0 = Date.now()
let r = comoExec(["sh", "-c", "sleep 30"], 1)
let ms = Date.now() - t0
comprueba("corta lo que se cuelga", r.code === 124, r.code)
comprueba("y corta A TIEMPO", ms < 3000, ms + " ms")

// Un proceso que ignora el TERM: para eso está el -k, que manda KILL después.
// Y aquí aparece lo que el ejecutor tiene que saber reconocer — `timeout` mata
// al GRUPO entero (lo que queremos: no deja hijos sueltos) y en ese grupo está
// él mismo, así que no vuelve con código sino MUERTO POR SEÑAL. Un ejecutor que
// solo mirase el 124 daría esto por una salida normal y le pasaría al modelo
// una salida a medias como si fuera el resultado.
t0 = Date.now()
let rs = spawnSync("timeout", ["-k", "2", "1", "sh", "-c", "trap '' TERM; sleep 30"],
                   { encoding: "utf8", timeout: 30000 })
ms = Date.now() - t0
comprueba("al que ignora el TERM se le remata",
          rs.status === 137 || rs.signal === "SIGKILL",
          "status=" + rs.status + " signal=" + rs.signal)
comprueba("y vuelve como caída, no como salida normal",
          rs.status === 137 || rs.status === null,
          "status=" + rs.status)
comprueba("y no tarda más que el margen", ms < 9000, ms + " ms")
// El desempate del ejecutor: murió por señal Y al cumplirse el plazo → fue el
// plazo. Si hubiera muerto mucho antes, sería un programa reventado y se dice
// distinto. Aquí se comprueba la aritmética de esa decisión.
const PLAZO = 1000
comprueba("una muerte al cumplirse el plazo se lee como corte",
          ms >= PLAZO - 500)
comprueba("una muerte inmediata NO se leería como corte", !(120 >= PLAZO - 500))

// Lo que termina a tiempo pasa intacto: el envoltorio no puede cambiar nada de
// lo que ya funcionaba.
r = comoExec(["sh", "-c", "printf 'hola mundo'"], 10)
comprueba("lo que termina a tiempo sale igual", r.code === 0 && r.out === "hola mundo",
          JSON.stringify(r))
// Y el código de error propio del comando NO se confunde con un corte.
r = comoExec(["sh", "-c", "exit 3"], 10)
comprueba("un error del comando no parece un corte", r.code === 3, r.code)
// Salida a medias: el comando escribe y LUEGO se cuelga. El ejecutor descarta
// esa media salida a propósito — leerla como resultado completo es peor que no
// tener nada (fue exactamente el fallo de los 20 000 caracteres de basura).
r = comoExec(["sh", "-c", "printf 'MITAD'; sleep 30"], 1)
comprueba("una salida a medias viene marcada como corte", r.code === 124, r.code)
comprueba("…aunque hubiera escrito algo", /MITAD/.test(r.out), JSON.stringify(r.out))

// ── 5. El envoltorio no rompe lo que ya se ejecutaba ─────────────────────────
// Los comandos reales llevan variables por entorno y comillas dentro. Si el
// envoltorio les cambiara el reparto de argumentos, se rompería todo el harness.
const env = Object.assign({}, process.env, { QS_P: "un valor con espacios y \"comillas\"" })
const cmd = ["timeout", "-k", "5", "10", "sh", "-c", 'printf %s "$QS_P"']
r = spawnSync(cmd[0], cmd.slice(1), { encoding: "utf8", env })
comprueba("el entorno llega intacto a través del envoltorio",
          r.stdout === 'un valor con espacios y "comillas"', JSON.stringify(r.stdout))

// ── El tope de salida, que va en el mismo envoltorio ─────────────────────────
// StdioCollector no tiene límite y se lo guarda todo en memoria: un bucle que
// escupe es un giga por segundo dentro del plazo, y eso no es una herramienta
// que falla, es Quickshell entero muriéndose. `head` corta y cierra la tubería;
// el que siga escribiendo se lleva un SIGPIPE.
const rEnorme = comoExec(["sh", "-c", "yes AAAAAAAA"], 10)
comprueba("corta la salida desbordada", rEnorme.code === 141, rEnorme.code)
comprueba("y justo en el tope de 2 MB", rEnorme.out.length === 2097152,
          rEnorme.out.length)
// Lo que NO puede hacer el tope es estropear lo normal.
const rSalto = comoExec(["printf", "hola"], 5)
comprueba("respeta la salida sin salto final", rSalto.out === "hola",
          JSON.stringify(rSalto.out))
const rCodigo = comoExec(["sh", "-c", "echo o; echo e >&2; exit 3"], 5)
comprueba("conserva el código de la herramienta, no el de head",
          rCodigo.code === 3, rCodigo.code)
comprueba("y no mezcla los dos flujos", rCodigo.out.trim() === "o",
          JSON.stringify(rCodigo.out))


console.log("\n" + ok + " bien, " + mal + " mal")
process.exit(mal === 0 ? 0 : 1)
