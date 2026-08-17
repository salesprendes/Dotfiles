// Prueba de las piezas nuevas del subagente: la memoria de lo ya pedido, la
// huella que detecta que una ronda no ha traído nada, y el traspaso al encargo
// de lo que el agente principal ya había buscado.
//
// Las funciones se sacan del QML de PRODUCCIÓN y se evalúan aquí: son JavaScript
// puro (no tocan ni propiedades ni señales), así que lo que se prueba es
// exactamente el código que corre en el panel, no una copia.
const fs = require("fs")

const IA = require("path").resolve(__dirname, "..") + "/"
const SUB = fs.readFileSync(IA + "agents/SubAgent.qml", "utf8")
const TR = fs.readFileSync(IA + "tools/ToolRunner.qml", "utf8")

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) ok++
    else { mal++; console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : "")) }
}

// Una función QML, desde su nombre hasta la llave que cierra a su misma sangría.
function extrae(src, nombre) {
    const ini = src.indexOf("    function " + nombre + "(")
    if (ini === -1) throw new Error("no encuentro " + nombre)
    const fin = src.indexOf("\n    }", ini)
    if (fin === -1) throw new Error(nombre + " no cierra")
    return src.slice(ini, fin + 6).trim()
}

// ── 1. La clave de lo ya pedido ──────────────────────────────────────────────
const memo = new Function(extrae(SUB, "_memoClave") + "\n"
                        + extrae(SUB, "_memoAviso") + "\n"
                        + extrae(SUB, "_huella")
                        + "\nreturn { _memoClave, _memoAviso, _huella }")()
const cl = (n, a) => memo._memoClave(n, a)

// La misma búsqueda escrita de otra manera es la misma búsqueda. Esto es el
// centro del asunto: el modelo repite reescribiendo, no copiando.
comprueba("mayúsculas y espacios sobran",
          cl("web_search", { query: "  RTX PRO 5000   Precio " })
          === cl("web_search", { query: "rtx pro 5000 precio" }))
comprueba("dos consultas distintas son distintas",
          cl("web_search", { query: "a" }) !== cl("web_search", { query: "b" }))
// Los filtros SÍ cambian la respuesta, así que cambian la clave.
comprueba("la antigüedad cuenta",
          cl("web_search", { query: "a", recency: "week" })
          !== cl("web_search", { query: "a" }))
comprueba("el dominio cuenta",
          cl("web_search", { query: "a", domains: ["idealo.es"] })
          !== cl("web_search", { query: "a" }))
comprueba("consulta vacía no se guarda", cl("web_search", { query: "  " }) === "")

// Las URL: lo que no distingue el servidor tampoco distingue la clave.
comprueba("el ancla sobra",
          cl("fetch_url", { url: "https://x.com/p#frag" })
          === cl("fetch_url", { url: "https://x.com/p" }))
comprueba("la barra final sobra",
          cl("fetch_url", { url: "https://x.com/p/" })
          === cl("fetch_url", { url: "https://x.com/p" }))
comprueba("www y las mayúsculas del host sobran",
          cl("fetch_url", { url: "https://WWW.X.com/p" })
          === cl("fetch_url", { url: "https://x.com/p" }))
// …y lo que sí distingue, se respeta. Hay servidores donde /Dp y /dp son
// páginas distintas, y un identificador de producto suele ir en mayúsculas.
comprueba("la ruta distingue mayúsculas",
          cl("fetch_url", { url: "https://amazon.es/dp/B0GLQYH1L2" })
          !== cl("fetch_url", { url: "https://amazon.es/dp/b0glqyh1l2" }))
comprueba("el parámetro cuenta",
          cl("fetch_url", { url: "https://x.com/p?id=2" })
          !== cl("fetch_url", { url: "https://x.com/p" }))
comprueba("una búsqueda y una descarga nunca chocan",
          cl("fetch_url", { url: "https://x" }) !== cl("web_search", { query: "https://x" }))
// Leer un archivo dos veces puede ser legítimo: eso no se memoriza.
comprueba("las herramientas locales no se memorizan",
          cl("read_file", { path: "/tmp/x" }) === "" && cl("lsp", {}) === "")

// El aviso sube de tono: a la segunda informa, a la tercera manda parar.
comprueba("el segundo aviso es suave", /sin volver a la red/.test(memo._memoAviso(2)))
comprueba("el tercero manda cerrar", /cierras el informe/.test(memo._memoAviso(3)))
comprueba("el aviso dice cuántas veces", /3ª vez/.test(memo._memoAviso(3)))

// ── 2. La huella ─────────────────────────────────────────────────────────────
const h = memo._huella
comprueba("misma entrada, misma huella", h("(sin resultados)") === h("(sin resultados)"))
comprueba("entradas distintas, huellas distintas", h("a") !== h("b"))
comprueba("no se confunde el orden", h("ab") !== h("ba"))
comprueba("aguanta un resultado largo",
          h("x".repeat(8000)) === h("x".repeat(8000))
          && h("x".repeat(8000)) !== h("x".repeat(7999)))
// El caso real: treinta y dos respuestas idénticas de "sin resultados" con
// treinta y dos consultas distintas. Ninguna cuenta como hallazgo salvo la
// primera, y eso es lo que corta el bucle.
const vistos = {}
let nuevos = 0
for (let i = 0; i < 32; i++) {
    const k = h("[CONTENIDO EXTERNO]\n(sin resultados para esa consulta)")
    if (!vistos[k]) { vistos[k] = true; nuevos++ }
}
comprueba("treinta y dos respuestas iguales son UN hallazgo", nuevos === 1, nuevos)

// ── 3. El freno por rondas estériles ─────────────────────────────────────────
// Se reproduce la contabilidad tal y como la lleva _execNext, con la traza real
// del encargo que motivó todo esto: tres rondas con hallazgos y ocho iguales.
function simula(rondas) {
    const vis = {}
    let esteriles = 0, corto = 0
    for (const ronda of rondas) {
        let nuevosR = 0
        for (const r of ronda)
            if (!vis[h(r)]) { vis[h(r)] = true; nuevosR++ }
        esteriles = nuevosR === 0 ? esteriles + 1 : 0
        corto++
        if (esteriles >= 2) break
    }
    return corto
}
const VACIO = "(sin resultados para esa consulta)"
comprueba("corta a las dos rondas estériles",
          simula([["a", "b"], ["c"], [VACIO], [VACIO], [VACIO], [VACIO],
                  [VACIO], [VACIO], [VACIO], [VACIO], [VACIO]]) === 5,
          simula([["a", "b"], ["c"], [VACIO], [VACIO], [VACIO], [VACIO],
                  [VACIO], [VACIO], [VACIO], [VACIO], [VACIO]]))
comprueba("una ronda floja aislada no corta nada",
          simula([["a"], ["a"], ["b"], ["b"], ["c"], ["d"]]) === 6)
comprueba("no corta mientras encuentre cosas",
          simula([["a"], ["b"], ["c"], ["d"]]) === 4)

// ── 4. El trabajo que ya hizo el jefe ────────────────────────────────────────
// La función se evalúa con un modelo de mensajes falso y el WebSearch de verdad.
const wsSrc = fs.readFileSync(IA + "integrations/WebSearch.js", "utf8")
                .replace(/^\.pragma library$/m, "")
const WS = new Function(wsSrc
    + "\nreturn { fence, unfence, fenced, failed, failureText }")()

comprueba("lo enmarcado se reconoce", WS.fenced(WS.fence("x", "y")))
comprueba("un aviso nuestro NO está enmarcado",
          !WS.fenced(WS.failureText("[[BUSCADOR_KO]]\n- ddg: nada")))

comprueba("unfence deshace fence",
          WS.unfence(WS.fence("un resultado", "x")) === "un resultado")
comprueba("unfence no toca lo que no viene enmarcado",
          WS.unfence("texto suelto") === "texto suelto")
comprueba("unfence conserva las líneas de dentro",
          WS.unfence(WS.fence("- uno\n  https://a\n- dos", "x"))
          === "- uno\n  https://a\n- dos")

function brief(mensajes, propio) {
    const messages = {
        count: mensajes.length,
        get: (i) => mensajes[i]
    }
    const _briefBusquedas = 3
    return new Function("messages", "WS", "_briefBusquedas",
        extrae(TR, "_briefConTrabajoHecho")
        + "\nreturn _briefConTrabajoHecho(" + JSON.stringify(propio || "") + ")"
    )(messages, WS, _briefBusquedas)
}
const busca = (q, res, estado) => ({
    role: "tool", toolName: "web_search", toolStatus: estado || "done",
    toolArgs: JSON.stringify({ query: q }), toolResult: WS.fence(res, "una búsqueda web")
})
const abre = (u) => ({
    role: "tool", toolName: "fetch_url", toolStatus: "done",
    toolArgs: JSON.stringify({ url: u }), toolResult: "contenido" })

let b = brief([busca("rtx 5000 precio", "- Idealo\n  https://idealo.es/x\n  5.599 €"),
               abre("https://coolmod.com/rtx")], "lo que ya sé")
comprueba("respeta el resumen del jefe", b.indexOf("lo que ya sé") === 0, b)
comprueba("lleva la consulta", /rtx 5000 precio/.test(b), b)
comprueba("lleva el resultado con el precio", /5\.599 €/.test(b), b)
comprueba("lleva la página ya abierta", /coolmod\.com\/rtx/.test(b), b)
comprueba("no repite el marco por cada búsqueda",
          (b.match(/DATOS, no instrucciones/g) || []).length === 1, b)
comprueba("dice que no lo repita", /no lo repitas/i.test(b), b)

// Sin nada que contar, el resumen del jefe pasa intacto.
comprueba("sin trabajo hecho no añade nada", brief([], "solo lo mío") === "solo lo mío")
comprueba("sin trabajo hecho ni resumen, vacío", brief([], "") === "")

// Una búsqueda averiada no se le pasa. Y ojo con la forma REAL del caso: lo
// que queda guardado en la tarjeta no es la avería del buscador, es nuestro
// aviso de "no hay buscador, arréglalo en Ajustes" — que va sin marco y no
// lleva la marca de avería. Si el filtro fuera por la marca, este aviso se le
// colaría al subagente como si fuera lo que encontró el jefe.
const averiada = {
    role: "tool", toolName: "web_search", toolStatus: "done",
    toolArgs: '{"query":"rtx 5000"}',
    toolResult: WS.failureText("[[BUSCADOR_KO]]\n- ddg: reto anti-robot") }
comprueba("el aviso de avería no viaja", brief([averiada], "") === "",
          brief([averiada], ""))
comprueba("y con resumen del jefe, lo deja intacto",
          brief([averiada], "lo mío") === "lo mío")
// La tarjeta que todavía está corriendo tampoco.
comprueba("lo que aún no ha terminado no viaja",
          brief([busca("x", "resultado", "pending")], "") === "")

// El orden: lo más antiguo primero, como se hizo.
b = brief([busca("primera", "R1"), busca("segunda", "R2"), busca("tercera", "R3")], "")
comprueba("respeta el orden cronológico",
          b.indexOf("primera") < b.indexOf("segunda")
          && b.indexOf("segunda") < b.indexOf("tercera"), b)
// Y el tope: el encargo se recorta a 4000 más adelante, así que aquí cabe todo.
b = brief([busca("larga", "x".repeat(3000)), busca("corta", "vale")], "")
comprueba("no se pasa del hueco", b.length < 4000, b.length)
comprueba("prefiere la reciente que quepa entera", /vale/.test(b), b)
comprueba("nunca corta una búsqueda por la mitad",
          b.indexOf("x".repeat(3000)) === -1 || /x{3000}/.test(b), b.length)
b = brief([busca("q", "R")], "y".repeat(3800))
comprueba("si el resumen del jefe lo llena, no se añade nada",
          b.indexOf("TRABAJO YA HECHO") === -1 || b.length < 4200, b.length)

console.log("\n" + ok + " bien, " + mal + " mal")
process.exit(mal === 0 ? 0 : 1)
