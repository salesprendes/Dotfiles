// LA TRANSCRIPCIÓN, LA BANDERA Y EL DESBORDAMIENTO: las tres piezas que hacen
// que resumir sea barato y que un contexto lleno deje de ser el final del turno.
//
// Antes, la compactación le mandaba al archivero el MISMO array de mensajes que
// viaja en un turno normal: protocolo de herramientas reconstruido y resultados
// íntegros. Costaba lo mismo que el turno más caro de la conversación y —lo
// grave— si el contexto acababa de desbordar, la petición de resumen desbordaba
// también, o sea que justo cuando hacía falta no se podía hacer.
const fs = require("fs")
const vm = require("vm")

const IA = require("path").resolve(__dirname, "..") + "/"

function carga(rel, expuestos) {
    const src = fs.readFileSync(IA + rel, "utf8")
                  .replace(/^\.pragma library$/m, "")
    const caja = {}
    vm.createContext(caja)
    vm.runInContext(src + ";__x={" + expuestos.map(n => n + ":" + n).join(",") + "};", caja)
    return caja.__x
}

const TR = carga("core/Transcript.js",
                 ["serializar", "linea", "argumentos", "TOPE_RESULTADO"])
const LT = carga("tools/LocalTools.js", ["inutil", "VACIOS"])

const CHAT = fs.readFileSync(IA + "core/ChatClient.qml", "utf8")
const RUNNER = fs.readFileSync(IA + "tools/ToolRunner.qml", "utf8")
const SVC = fs.readFileSync(IA + "core/AiService.qml", "utf8")
const PANEL = fs.readFileSync(IA + "ui/AiPanel.qml", "utf8")

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) { ok++; return }
    mal++
    console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : ""))
}

function extrae(src, nombre) {
    const ini = src.indexOf("    function " + nombre + "(")
    if (ini === -1) throw new Error("no encuentro " + nombre)
    const fin = src.indexOf("\n    }", ini)
    if (fin === -1) throw new Error(nombre + " no cierra")
    return src.slice(ini, fin + 6).trim()
}

function tarjeta(nombre, args, res, extra) {
    const m = { role: "tool", content: "", reasoning: "", toolName: nombre,
                toolArgs: JSON.stringify(args), toolId: "c1", toolResult: res,
                toolStatus: "done", compactOf: 0, at: 0, toolUseless: false }
    for (const k in (extra || {}))
        m[k] = extra[k]
    return m
}
function texto(role, c, extra) {
    const m = { role: role, content: c, reasoning: "", toolName: "", toolArgs: "",
                toolId: "", toolResult: "", toolStatus: "", compactOf: 0, at: 0,
                toolUseless: false }
    for (const k in (extra || {}))
        m[k] = extra[k]
    return m
}
const limpio = n => new Array(n + 1).join("a")

// ── 1. Una fila cada vez ─────────────────────────────────────────────────────
comprueba("el usuario se identifica",
          TR.linea(texto("user", "hola")) === "[Usuario]: hola")
comprueba("el asistente también",
          TR.linea(texto("assistant", "qué tal")) === "[Asistente]: qué tal")
// El RAZONAMIENTO no entra nunca: es efímero, pesa más que la respuesta, y hay
// clasificadores que rechazan una entrada que reproduce el pensamiento del
// propio modelo como texto.
comprueba("el razonamiento no viaja",
          TR.linea(texto("assistant", "hola", { reasoning: "pensando mucho" }))
              .indexOf("pensando") === -1)
// Las notas del harness y los errores de transporte no son conversación: son
// ruido de la máquina, y en un resumen solo despistan.
comprueba("las notas del harness no viajan", TR.linea(texto("info", "compactado")) === "")
comprueba("los errores de transporte tampoco", TR.linea(texto("error", "curl 7")) === "")
comprueba("una tarjeta sin resolver no viaja",
          TR.linea(tarjeta("read_file", { path: "~/x" }, "", { toolStatus: "pending" })) === "")

const conLlamada = TR.linea(tarjeta("read_file", { path: "~/a.qml", offset: 5 }, "contenido"))
comprueba("la llamada sale con su nombre", conLlamada.indexOf("[Llamada]: read_file(") !== -1)
comprueba("y con sus argumentos",
          /path="~\/a\.qml"/.test(conLlamada) && /offset=5/.test(conLlamada), conLlamada)
comprueba("y el resultado detrás", conLlamada.indexOf("[Resultado]: contenido") !== -1)

// Una tarjeta rechazada SÍ viaja: es una decisión del usuario, y el resumen
// tiene que poder decir que algo se denegó.
const rechazada = TR.linea(tarjeta("run_command", { command: "rm -rf /" },
                                   "Bloqueado por un hook: no.",
                                   { toolStatus: "rejected" }))
comprueba("lo rechazado se cuenta", rechazada.indexOf("[Rechazada]:") !== -1)

// ── 2. Los topes ─────────────────────────────────────────────────────────────
// Dos mil caracteres bastan para resumir lo que hizo una herramienta; los
// treinta mil de un `cat` no aportan nada a un resumen y sí lo empeoran, porque
// entierran la conversación bajo la salida.
const gorda = TR.linea(tarjeta("run_command", { command: "cat x" }, limpio(30000)))
comprueba("el resultado se acota", gorda.length < 3000, gorda.length)
comprueba("y se dice cuánto se dejó fuera",
          /\[… 28000 caracteres más de resultado\]/.test(gorda))
comprueba("el tope es el de oh-my-pi", TR.TOPE_RESULTADO === 2000)
// El contenido de un write_file son diez mil caracteres que ya están en el
// archivo: al resumen le basta con saber que se escribió y dónde.
const escribe = TR.linea(tarjeta("write_file", { path: "~/x", content: limpio(20000) }, "ok"))
comprueba("los argumentos también se acotan", escribe.length < 2000, escribe.length)
comprueba("pero la ruta sobrevive entera", escribe.indexOf('path="~/x"') !== -1)
comprueba("los argumentos rotos no revientan",
          TR.argumentos("{esto no es json").length > 0)

// ── 3. El hilo entero ────────────────────────────────────────────────────────
const hilo = [
    texto("user", "arregla el podador"),
    texto("assistant", "voy a leerlo"),
    tarjeta("read_file", { path: "~/p.js" }, "el fuente"),
    texto("info", "contexto compactado"),
    texto("assistant", "ya está")
]
const g = TR.serializar(hilo, {})
comprueba("sale todo lo que es conversación",
          g.texto.indexOf("arregla el podador") !== -1
          && g.texto.indexOf("el fuente") !== -1
          && g.texto.indexOf("ya está") !== -1)
comprueba("y nada de lo que no lo es", g.texto.indexOf("contexto compactado") === -1)
comprueba("en orden", g.texto.indexOf("arregla el podador") < g.texto.indexOf("ya está"))
comprueba("sin nada omitido", g.omitidos === 0)

// Lo que la herramienta marcó como que no informó de nada se cae ENTERO —la
// llamada y el resultado—: la región se descarta después del resumen de todos
// modos, así que excluirla no cuesta caché y mantiene la basura fuera.
const conInutil = [
    texto("user", "busca zzz"),
    tarjeta("grep_files", { pattern: "zzz", path: "~/p" }, "(sin coincidencias)",
            { toolUseless: true })
]
comprueba("lo que no informó de nada no entra al resumen",
          TR.serializar(conInutil, {}).texto.indexOf("grep_files") === -1)
comprueba("y se puede pedir que sí entre",
          TR.serializar(conInutil, { saltarInutiles: false })
              .texto.indexOf("grep_files") !== -1)

// Cuando no cabe todo se tira de lo MÁS VIEJO: en una compactación incremental
// lo viejo ya está contado en el estado acumulado que viaja aparte, y lo nuevo
// es justo lo que nadie ha resumido todavía.
const largo = []
for (let i = 0; i < 30; i++)
    largo.push(texto("user", "mensaje " + i + " " + limpio(500)))
const cortado = TR.serializar(largo, { tope: 3000 })
comprueba("respeta el tope", cortado.texto.length < 3600, cortado.texto.length)
comprueba("conserva lo más nuevo", cortado.texto.indexOf("mensaje 29") !== -1)
comprueba("tira lo más viejo", cortado.texto.indexOf("mensaje 0 ") === -1)
comprueba("y dice cuántos dejó fuera",
          cortado.omitidos > 0 && /mensajes anteriores omitidos/.test(cortado.texto))

// ── 4. La bandera la pone la herramienta ─────────────────────────────────────
// Verdad de ORIGEN: la herramienta conoce el texto exacto que suelta cuando no
// encuentra nada. Adivinarlo desde fuera por el tamaño es lo que hacía el
// podador antes, y se equivoca.
comprueba("un grep sin coincidencias no informó de nada",
          LT.inutil("grep_files", "(sin salida; código 0)"))
comprueba("un grep con resultados sí", !LT.inutil("grep_files", "a.qml:12: foo"))
comprueba("un glob sin coincidencias tampoco",
          LT.inutil("glob_files", "(sin coincidencias)\n[0 coincidencias, orden name]"))
comprueba("el LSP sin resultados tampoco", LT.inutil("lsp", "Sin resultados."))
comprueba("ni sin información en esa posición",
          LT.inutil("lsp", "Sin información en esa posición."))
comprueba("una búsqueda web vacía tampoco",
          LT.inutil("web_search", "(sin resultados para esa consulta)"))
comprueba("un trabajo sin salida nueva tampoco",
          LT.inutil("job_view", "(sin salida todavía)"))
// UN FALLO NUNCA ES INÚTIL: es justo lo contrario. Un grep que no encuentra
// nada informa; uno que no puede leer la carpeta es un problema que conservar.
comprueba("un fallo no se marca inútil",
          !LT.inutil("grep_files", "grep: /p: Permission denied"))
comprueba("ni por el código de salida",
          !LT.inutil("grep_files", "(sin salida; código 2)"))
comprueba("ni con stderr por medio",
          !LT.inutil("glob_files", "(sin coincidencias)\n[stderr] algo pasó"))
// Una salida larga que además contenga la palabra no es una salida vacía.
comprueba("un listado largo no es vacío",
          !LT.inutil("glob_files", "(sin coincidencias)" + limpio(400)))
// Y una herramienta que no está en la tabla nunca se marca: leer un archivo
// vacío SÍ informa (el archivo está vacío).
comprueba("read_file no participa", !LT.inutil("read_file", "(sin salida; código 0)"))
comprueba("run_command tampoco", !LT.inutil("run_command", "(sin salida; código 0)"))
comprueba("la tabla cubre las de búsqueda",
          LT.VACIOS.grep_files && LT.VACIOS.glob_files && LT.VACIOS.web_search
          && LT.VACIOS.lsp && LT.VACIOS.ast_search)

// Y la pone el runner en el único sitio por el que pasan todas: al resolver.
comprueba("el runner la escribe al resolver",
          /messages\.setProperty\(index, "toolUseless", seco\)/.test(RUNNER))
// Se decide ANTES de enmarcar: el cerco añade texto alrededor y el
// "(sin coincidencias)" pelado dejaría de reconocerse. El marco lo pone ahora
// la puerta (GT.marcar), pero el orden sigue importando igual.
comprueba("se decide antes del cerco",
          RUNNER.indexOf("const seco = LT.inutil") !== -1
          && RUNNER.indexOf("const seco = LT.inutil")
             < RUNNER.indexOf("result = GT.marcar(permiso, result)"))

// ── 5. El desbordamiento ─────────────────────────────────────────────────────
// Cada servidor lo dice a su manera. El castigo por acertar de más es compactar
// una vez sin necesidad; el de fallar es dejar el turno muerto con un error que
// el usuario no puede arreglar salvo borrando la conversación.
const desb = new Function(extrae(CHAT, "overflow") + "\nreturn overflow")()
const LLENOS = [
    "This model's maximum context length is 8192 tokens, however you requested 10500 tokens",
    "prompt is too long: 205000 tokens > 200000 maximum",
    "context_length_exceeded",
    "The input token count (1050000) exceeds the maximum number of tokens allowed (1048576).",
    "the request exceeds the available context size, try increasing it",
    "Requested tokens (5000) exceed context window of 4096",
    "input length and `max_tokens` exceed context limit",
    "context length exceeded",
    "n_ctx is too small for the prompt"
]
for (let i = 0; i < LLENOS.length; i++)
    comprueba("reconoce el lleno: " + LLENOS[i].slice(0, 34), desb(LLENOS[i]))
const OTROS = [
    "429 rate limit exceeded, retry after 20s",
    "Internal server error (500)",
    "model not found: qwen3:32b",
    "Connection timed out",
    "invalid api key",
    "upstream connect error or disconnect/reset before headers"
]
for (let i = 0; i < OTROS.length; i++)
    comprueba("y no confunde: " + OTROS[i].slice(0, 30), !desb(OTROS[i]))

// Un desbordamiento no es transitorio: reintentarlo igual falla igual. Por eso
// se comprueba ANTES que el reintento genérico.
comprueba("se mira el desbordamiento antes que el reintento",
          CHAT.indexOf("chat.overflow(msg)") < CHAT.indexOf("chat.transient(msg) || vacia"))
comprueba("una sola recuperación por turno",
          /!chat\._desbordado/.test(CHAT) && /chat\._desbordado = true/.test(CHAT))
comprueba("y turno nuevo, derecho nuevo",
          /chat\._desbordado = false/.test(SVC))
comprueba("el servicio compacta y reintenta",
          /function recoverOverflow\(\)/.test(SVC)
          && /comp\.compact\("overflow"\)/.test(SVC))

// ── 6. A mitad de turno ──────────────────────────────────────────────────────
// Un bucle de veinte rondas de herramienta puede llenar la ventana sin que el
// turno haya terminado, y la única comprobación estaba al final: se desbordaba
// antes de llegar a ella.
comprueba("el coordinador comprueba en su frontera segura",
          /svc\.maybeCompactMidTurn\(\)/.test(RUNNER))
// La frontera es justo antes de devolverle la palabra al modelo: ahí el lote
// está resuelto y no hay ningún protocolo a medias.
const frontera = RUNNER.indexOf("svc.maybeCompactMidTurn()")
comprueba("y lo hace antes de hablar con el modelo",
          frontera !== -1 && frontera < RUNNER.indexOf("svc.start()", frontera))
comprueba("si compacta, no arranca dos veces",
          /if \(svc\.maybeCompactMidTurn\(\)\)\s*\n\s*return/.test(RUNNER))
comprueba("el servicio lo expone", /function maybeCompactMidTurn\(\)/.test(SVC))

// ── 7. La pasada de poda por turno ───────────────────────────────────────────
// Barata, determinista y con las bridas de la caché puestas. Es lo que evita
// llegar al umbral, y por eso va ANTES de mirarlo.
comprueba("se poda al acabar el turno", /comp\.prune\(true\)/.test(SVC))
comprueba("y antes de mirar el umbral",
          SVC.indexOf("comp.prune(true)") < SVC.indexOf("contextFill > 0.85"))
comprueba("a mano va sin bridas", /function prune\(\) \{ return comp\.prune\(false\) \}/.test(SVC))

// ── 8. Los comandos ──────────────────────────────────────────────────────────
comprueba("hay /podar", /cmd: "\/podar", alias: "\/prune"/.test(PANEL))
comprueba("hay /sacudir", /cmd: "\/sacudir", alias: "\/shake"/.test(PANEL))
comprueba("hay /traspaso", /cmd: "\/traspaso", alias: "\/handoff"/.test(PANEL))
comprueba("y siguen /compactar y /limpiar",
          /cmd: "\/compactar"/.test(PANEL) && /cmd: "\/limpiar"/.test(PANEL))
comprueba("el servicio expone las tres",
          /function shake\(\)/.test(SVC) && /function handoff\(\)/.test(SVC)
          && /function prune\(\)/.test(SVC))

console.log(ok + " bien, " + mal + " mal")
process.exit(mal === 0 ? 0 : 1)
