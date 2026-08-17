// A QUÉ SERVIDOR SE HABLA. Estaba dentro de un singleton de mil trescientas
// líneas, o sea sin ninguna forma de probarlo: la única manera de saber si una
// URL pegada a medias acababa en la base correcta era pegarla en los ajustes y
// mirar si el envío fallaba con un error de red que no explica nada.
//
// Sacarlo a una biblioteca pura no lo hace más bonito: lo hace COMPROBABLE. Y
// resulta que hay bastante que comprobar, porque una URL de servidor propio se
// copia y se pega mal de una docena de maneras distintas y todas tienen que
// acabar en la misma raíz /v1.
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

const EP = cargaLib("core/Endpoint.js")
const SVC = fs.readFileSync(IA + "core/AiService.qml", "utf8")

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) { ok++; return }
    mal++
    console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : ""))
}

// ── 1. El catálogo ───────────────────────────────────────────────────────────
comprueba("están los cuatro proveedores",
          ["gemini", "openrouter", "ollama", "custom"]
              .every(p => EP.PROVEEDORES[p] !== undefined))
// Los dos de nube traen su base escrita; los dos de servidor propio la calculan.
comprueba("los de nube traen base",
          EP.PROVEEDORES.gemini.base !== "" && EP.PROVEEDORES.openrouter.base !== "")
comprueba("y piden clave",
          EP.PROVEEDORES.gemini.needsKey && EP.PROVEEDORES.openrouter.needsKey)
comprueba("los de servidor propio no traen base",
          EP.PROVEEDORES.ollama.base === "" && EP.PROVEEDORES.custom.base === "")
comprueba("y la URL la pone el usuario",
          EP.PROVEEDORES.ollama.userUrl && EP.PROVEEDORES.custom.userUrl)
// Un servidor OpenAI-compatible puede no tener clave: exigirla bloquearía el
// envío contra un vLLM de casa que no la usa.
comprueba("el servidor propio no exige clave", !EP.PROVEEDORES.custom.needsKey)
// Un proveedor desconocido no revienta: cae en el de siempre.
comprueba("un proveedor inventado cae en gemini",
          EP.proveedorDe("inventado").label === "Gemini")
comprueba("y uno vacío también", EP.proveedorDe("").label === "Gemini")

// ── 2. La URL, pegada de todas las formas en que se pega mal ─────────────────
const base = (u) => EP.baseDe("custom", { custom: u })
comprueba("una base correcta se respeta", base("https://x.com/v1") === "https://x.com/v1")
comprueba("sin esquema se le pone", base("x.com/v1").indexOf("://") !== -1)
comprueba("la barra final sobra", base("https://x.com/v1/") === "https://x.com/v1")
comprueba("varias barras finales también", base("https://x.com/v1///") === "https://x.com/v1")
// Lo más común de todo: pegar el endpoint entero copiado de una documentación.
comprueba("pegar el endpoint entero se recorta",
          base("https://x.com/v1/chat/completions") === "https://x.com/v1")
comprueba("pegar el de modelos también",
          base("https://x.com/v1/models") === "https://x.com/v1")
comprueba("y el de completions a secas",
          base("https://x.com/v1/completions") === "https://x.com/v1")
// Sin /v1 se le añade: es la raíz del contrato, no un detalle opcional.
comprueba("sin /v1 se le pone", base("https://x.com") === "https://x.com/v1")
comprueba("con puerto también", base("localhost:8000").indexOf("/v1") !== -1)
comprueba("una URL vacía no inventa nada", base("") === "")
comprueba("ni una de espacios", base("   ") === "")

// Ollama y el servidor propio leen ajustes DISTINTOS: cruzarlos mandaría las
// peticiones al servidor equivocado sin decir nada.
comprueba("ollama lee su propio ajuste",
          EP.baseDe("ollama", { ollama: "http://a/v1", custom: "http://b/v1" })
          === "http://a/v1")
comprueba("y el servidor propio el suyo",
          EP.baseDe("custom", { ollama: "http://a/v1", custom: "http://b/v1" })
          === "http://b/v1")
// Los de nube ignoran lo que haya en los ajustes de URL.
comprueba("un proveedor de nube ignora la URL del usuario",
          EP.baseDe("gemini", { custom: "http://malo/v1" })
          === EP.PROVEEDORES.gemini.base)

// ── 3. Las dos direcciones que salen de la base ──────────────────────────────
comprueba("el endpoint cuelga de la base",
          EP.endpointDe("https://x/v1") === "https://x/v1/chat/completions")
comprueba("sin base no hay endpoint", EP.endpointDe("") === "")
comprueba("sin base tampoco hay catálogo", EP.modelosUrl("", "custom") === "")
comprueba("el catálogo del contrato es /models",
          EP.modelosUrl("https://x/v1", "custom") === "https://x/v1/models")
// Ollama publica el suyo FUERA de /v1: pedirlo dentro devuelve 404 y el panel
// se queda sin lista de modelos sin decir por qué.
comprueba("ollama publica el suyo fuera de /v1",
          EP.modelosUrl("http://localhost:11434/v1", "ollama")
          === "http://localhost:11434/api/tags")

// ── 4. Un modelo por proveedor ───────────────────────────────────────────────
const AJ = { openrouter: "or/m", ollama: "qwen3", custom: "local", gemini: "flash" }
comprueba("cada proveedor lee su ajuste",
          EP.modeloDe("openrouter", AJ) === "or/m"
          && EP.modeloDe("ollama", AJ) === "qwen3"
          && EP.modeloDe("custom", AJ) === "local"
          && EP.modeloDe("gemini", AJ) === "flash")
comprueba("uno desconocido cae en gemini", EP.modeloDe("raro", AJ) === "flash")
comprueba("sin ajustes no revienta", EP.modeloDe("ollama", null) === "")
comprueba("a dónde se escribe es el mismo reparto",
          EP.ajusteDe("ollama") === "ollama" && EP.ajusteDe("raro") === "gemini")

// ── 5. "proveedor:modelo" ────────────────────────────────────────────────────
// La sintaxis de aisuite: cambiar servidor y modelo en un gesto.
const pm = (t, actual) => EP.parseModelo(t, actual)
comprueba("el prefijo cambia proveedor y modelo",
          pm("ollama:qwen3", "gemini").proveedor === "ollama"
          && pm("ollama:qwen3", "gemini").modelo === "qwen3")
// Y EL CASO QUE LO ROMPÍA TODO: los ":free" de OpenRouter llevan dos puntos y
// NO son un prefijo de proveedor. Por eso se compara contra el catálogo y no
// contra "lo que haya antes del primer dos puntos".
comprueba("un ':free' de OpenRouter no es un proveedor",
          pm("meta/llama-3-8b:free", "openrouter").proveedor === "openrouter")
comprueba("y el modelo llega entero",
          pm("meta/llama-3-8b:free", "openrouter").modelo === "meta/llama-3-8b:free")
comprueba("un modelo con etiqueta de ollama tampoco",
          pm("qwen3:32b", "ollama").proveedor === "ollama"
          && pm("qwen3:32b", "ollama").modelo === "qwen3:32b")
comprueba("sin dos puntos se queda donde está",
          pm("gpt-4", "custom").proveedor === "custom"
          && pm("gpt-4", "custom").modelo === "gpt-4")
comprueba("los espacios de los lados sobran", pm("  ollama:x  ", "gemini").modelo === "x")
// Dos puntos al principio no es un prefijo vacío: es parte del nombre.
comprueba("empezar por dos puntos no cambia de proveedor",
          pm(":raro", "gemini").proveedor === "gemini")

// ── 6. Qué falta para poder hablar ───────────────────────────────────────────
comprueba("de nube sin clave falta la clave",
          EP.faltan("gemini", "https://x", "").clave)
comprueba("y con clave no falta nada",
          !EP.faltan("gemini", "https://x", "abc").alguna)
comprueba("de servidor propio sin URL falta la URL",
          EP.faltan("custom", "", "").url)
// El servidor propio SIN clave está bien configurado: exigirla bloquearía un
// vLLM de casa que no la usa.
comprueba("de servidor propio sin clave no falta nada",
          !EP.faltan("custom", "https://x/v1", "").alguna)
comprueba("ollama igual", !EP.faltan("ollama", "http://l/v1", "").alguna)

// ── 7. Lo que quedó en QML ───────────────────────────────────────────────────
// La etiqueta del servidor propio se rotula con I18n, que una biblioteca pura
// no ve: por eso la calcula el harness y no el catálogo.
comprueba("el catálogo deja la etiqueta del servidor propio vacía",
          EP.PROVEEDORES.custom.label === "")
comprueba("y el harness la rotula",
          /providerLabel[\s\S]{0,120}?I18n\.tr\("Server"\)/.test(SVC))
// Quien la enseña usa la rotulada, no la del catálogo: si no, saldría vacía.
const CHIP = fs.readFileSync(IA + "ui/ModelChip.qml", "utf8")
comprueba("la píldora enseña la rotulada",
          /AiService\.providerLabel/.test(CHIP)
          && CHIP.indexOf("AiService.provider.label") === -1)
// Y el harness ya no lleva su propia copia del catálogo ni del reparto.
comprueba("el harness ya no lleva el catálogo dentro",
          SVC.indexOf("https://openrouter.ai/api/v1") === -1)
comprueba("ni la normalización de URL",
          SVC.indexOf("TU.normalizeBase") === -1)
comprueba("ni el reparto de modelo por proveedor",
          SVC.indexOf("Settings.aiModelOpenrouter\n") === -1
          || /EP\.modeloDe/.test(SVC))

console.log(ok + " bien, " + mal + " mal")
process.exit(mal === 0 ? 0 : 1)
