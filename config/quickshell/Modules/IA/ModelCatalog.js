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
