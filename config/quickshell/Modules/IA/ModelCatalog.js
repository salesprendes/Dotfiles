// Cómo se NOMBRA y se agrupa un modelo. Presentación pura: ni red ni estado,
// solo cadenas. Sale del singleton porque no tenía nada que hacer allí.
.pragma library

// Un id de modelo es una ruta con proveedor, familia y etiquetas
// ("qwen/qwen3-30b-a3b:free"). En un botón de cabecera lo que importa es el
// NOMBRE; el resto sale como insignia aparte o no sale.
function shortName(id) {
    let s = String(id || "")
    const slash = s.lastIndexOf("/")
    if (slash >= 0)
        s = s.slice(slash + 1)
    const colon = s.indexOf(":")
    if (colon > 0)
        s = s.slice(0, colon)
    return s
}

// La etiqueta de la derecha: gratis, local o nada.
function tag(id) {
    const s = String(id || "")
    if (s.indexOf(":free") !== -1)
        return "free"
    return ""
}

// LA VARIANTE: el trozo del id que dice CUÁL de las versiones es — 27b, 32b,
// los activos de una mezcla de expertos (A3B), la cuantización (FP8, Q4_K_M).
//
// Hace falta porque shortName() se queda con el nombre de familia, y sin esto
// tres modelos distintos del mismo servidor se leen IGUAL en la lista: elegir
// entre "qwen3.8", "qwen3.8" y "qwen3.8" es adivinar. Con la variante al lado
// se ve de un vistazo cuál es el de 27B y cuál el cuantizado.
//
// Se reconocen tres cosas y en este orden, que es como se leen:
//   tamaño         27b · 32b · 2.4t · 8x7b
//   expertos       a3b · a95b · e4b (los activos de una MoE, o los embebidos)
//   cuantización   fp8 · bf16 · int4 · awq · gptq · gguf · q4_k_m
const RE_TAMANO = /^\d+(?:\.\d+)?[bt]$|^\d+x\d+(?:\.\d+)?b$/i
const RE_EXPERTOS = /^[ae]\d+(?:\.\d+)?b$/i
const RE_CUANT = /^(fp8|fp16|bf16|int4|int8|awq|gptq|gguf|exl2|mlx|q\d(?:_[a-z0-9]+)*)$/i

// Los trozos reconocibles de una cadena. NO se parte por el punto a propósito:
// "Qwen3.8" y "2.4T" son cada uno una pieza, y partirlos convertía el "8" de
// una versión en el tamaño de otra ("Qwen3.8-27B" salía como 8.27b).
function _reconocida(p) {
    return RE_TAMANO.test(p) || RE_EXPERTOS.test(p) || RE_CUANT.test(p)
}
function _piezas(s) {
    const out = []
    const trozos = String(s).split("-")
    for (let i = 0; i < trozos.length; i++) {
        const p = trozos[i]
        if (p === "")
            continue
        // El guion bajo se prueba DESPUÉS: los nombres de cuantización lo
        // llevan dentro ("q4_K_M" es una pieza, no tres), pero hay ids que lo
        // usan de separador ("Muse_Glimmer_30B").
        if (_reconocida(p)) {
            out.push(p)
            continue
        }
        const sub = p.split("_")
        for (let k = 0; k < sub.length; k++)
            if (sub[k] !== "" && _reconocida(sub[k]))
                out.push(sub[k])
    }
    return out
}

function variant(id) {
    let s = String(id || "")
    // La etiqueta de Ollama ("qwen3.8:27b") ES la variante, y es justo lo que
    // shortName tira. Se mira primero: ahí el usuario ya eligió cuál quiere.
    const colon = s.indexOf(":")
    let etiqueta = ""
    if (colon > 0) {
        etiqueta = s.slice(colon + 1)
        s = s.slice(0, colon)
        const e = etiqueta.toLowerCase()
        if (e === "free" || e === "latest")
            etiqueta = ""
    }
    const slash = s.lastIndexOf("/")
    if (slash >= 0)
        s = s.slice(slash + 1)

    // La etiqueta puede traer varias cosas pegadas
    // ("32b-instruct-q4_K_M"): se le pasa el mismo cedazo. Si no reconoce nada,
    // se enseña entera — en Ollama la etiqueta ES la variante, aunque sea el
    // nombre de un ajuste fino de alguien.
    let partes = _piezas(etiqueta)
    if (partes.length === 0 && etiqueta !== "")
        partes = [etiqueta]
    partes = partes.concat(_piezas(s))

    // Sin repetidos y en minúscula: los ids mezclan mayúsculas sin criterio
    // ("Qwen3.8-27B-FP8" y "qwen3.8-27b-fp8" son el mismo modelo).
    const vistos = ({})
    const out = []
    for (let k = 0; k < partes.length; k++) {
        const v = partes[k].toLowerCase()
        if (!vistos[v]) {
            vistos[v] = true
            out.push(v)
        }
    }
    return out.join(" · ")
}

// Lista de reserva mientras el servidor no ha contestado (solo los proveedores
// de nube con catálogo conocido de antemano). Los de URL propia no aparecen a
// propósito: lo que sirva un servidor ajeno solo lo sabe ese servidor.
const RESERVA = {
    openrouter: ["qwen/qwen3-30b-a3b:free", "qwen/qwen3-14b:free",
                 "deepseek/deepseek-chat-v3-0324:free",
                 "meta-llama/llama-3.3-70b-instruct:free"],
    gemini: ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5-pro",
             "gemini-2.0-flash"]
}

// Catálogo agrupado por proveedor para el selector: el del proveedor activo,
// entero (lo que publica el servidor, o la reserva, más el modelo vigente
// aunque sea un id escrito a mano); de los demás, el modelo que tengan
// elegido — cambiar de cerebro (o de nube a local) sin pasar por la
// configuración.
//
// ctx = { active, model, fetched, labels: {id: etiqueta}, modelFor: fn(id) }
function groups(ctx) {
    const ids = ["gemini", "openrouter", "ollama", "custom"]
    const out = []
    for (let i = 0; i < ids.length; i++) {
        const id = ids[i]
        const activo = id === ctx.active
        let lista
        if (activo) {
            lista = ((ctx.fetched || {})[id] || []).slice()
            // Un array vacío es CIERTO en JavaScript: la reserva se elige con
            // una comprobación explícita, que con "||" nunca entraría.
            if (lista.length === 0)
                lista = (RESERVA[id] || []).slice()
            if (ctx.model !== "" && lista.indexOf(ctx.model) === -1)
                lista.unshift(ctx.model)
        } else {
            const suyo = ctx.modelFor(id)
            lista = suyo !== "" ? [suyo] : []
        }
        if (lista.length === 0)
            continue
        out.push({ provider: id, label: ctx.labels[id],
                   active: activo, models: lista })
    }
    return out
}
