// RESULTADOS TIPADOS. Un subagente que devuelve prosa obliga a su jefe a
// interpretarla, y un modelo pequeño interpreta mal: "no encontré nada" y "no
// pude mirar" acaban significando lo mismo tres turnos después. Si el encargo
// dice qué FORMA tiene la respuesta, el jefe recibe datos y no un texto.
//
// Es un subconjunto deliberado de JSON Schema —tipos, propiedades, requeridos,
// enum, items y los topes numéricos—, porque lo que hace falta aquí no es
// validar contratos ajenos sino comprobar que un modelo local rellenó lo que se
// le pidió. Y por eso lo importante de este archivo no es validar: es
// EXPLICAR el fallo con palabras que el propio modelo pueda arreglar en la
// siguiente ronda.
.pragma library

// ── El esqueleto que se le enseña al modelo ──────────────────────────────────
// Un esquema JSON crudo en el prompt es ruido; un ejemplo de la forma esperada,
// con el tipo y la descripción de cada campo, es una instrucción.
function skeleton(s, nivel) {
    const d = nivel || 0
    if (!s || typeof s !== "object")
        return "cualquiera"
    const t = _tipo(s)
    if (s["enum"] && s["enum"].length > 0)
        return "uno de: " + s["enum"].map(x => JSON.stringify(x)).join(" | ")
    if (t === "object") {
        const props = s.properties || ({})
        const req = s.required || []
        const claves = Object.keys(props)
        if (claves.length === 0 || d > 3)
            return "{…}"
        const sangria = _sp(d + 1)
        const filas = claves.map(k => {
            const hijo = props[k]
            const marca = req.indexOf(k) !== -1 ? "" : "   // opcional"
            const desc = hijo && hijo.description
                       ? "   // " + String(hijo.description) : marca
            return sangria + JSON.stringify(k) + ": " + skeleton(hijo, d + 1)
                 + (desc !== "" ? "," + desc : ",")
        })
        return "{\n" + filas.join("\n") + "\n" + _sp(d) + "}"
    }
    if (t === "array")
        return "[ " + skeleton(s.items, d + 1) + ", … ]"
    return "<" + t + ">"
}
function _sp(n) {
    let o = ""
    for (let i = 0; i < n; i++)
        o += "  "
    return o
}
function _tipo(s) {
    const t = s.type
    if (Array.isArray(t))
        return t.length > 0 ? String(t[0]) : "any"
    return t === undefined ? (s.properties ? "object" : "any") : String(t)
}

// ── Encontrar el JSON dentro de la respuesta ─────────────────────────────────
// Un modelo pequeño casi nunca contesta SOLO el JSON: lo envuelve en un bloque
// ``` o lo precede de "aquí tienes". Se busca primero el bloque marcado y
// después el primer objeto o lista equilibrado, respetando comillas y escapes
// —contar llaves a lo bruto se rompe con la primera '}' dentro de un texto.
// Devuelve la cadena candidata o "" (quien llama la parsea con su reparador).
function extractJsonText(texto) {
    const t = String(texto || "")
    const cerca = /```(?:json|JSON)?\s*([\s\S]*?)```/.exec(t)
    if (cerca) {
        const dentro = _equilibrado(cerca[1])
        if (dentro !== "")
            return dentro
    }
    return _equilibrado(t)
}
function _equilibrado(t) {
    const abre = t.search(/[{[]/)
    if (abre === -1)
        return ""
    const cierra = t[abre] === "{" ? "}" : "]"
    const apertura = t[abre]
    let prof = 0, enTexto = false, escape = false
    for (let i = abre; i < t.length; i++) {
        const c = t[i]
        if (enTexto) {
            if (escape)
                escape = false
            else if (c === "\\")
                escape = true
            else if (c === '"')
                enTexto = false
            continue
        }
        if (c === '"')
            enTexto = true
        else if (c === apertura)
            prof++
        else if (c === cierra) {
            prof--
            if (prof === 0)
                return t.slice(abre, i + 1)
        }
    }
    return ""
}

// ── La comprobación ──────────────────────────────────────────────────────────
// Devuelve una lista de fallos en castellano, cada uno con la ruta del campo.
// Vacía = cumple.
function validate(v, s, ruta) {
    const r = ruta || "raíz"
    const fallos = []
    if (!s || typeof s !== "object")
        return fallos
    const t = _tipo(s)

    if (v === undefined || v === null) {
        if (t !== "any" && t !== "null")
            fallos.push(r + ": falta (se esperaba " + t + ")")
        return fallos
    }
    if (s["enum"] && s["enum"].length > 0 && s["enum"].indexOf(v) === -1) {
        fallos.push(r + ": " + JSON.stringify(v) + " no está entre los valores "
                    + "permitidos (" + s["enum"].join(", ") + ")")
        return fallos
    }

    switch (t) {
    case "object": {
        if (typeof v !== "object" || Array.isArray(v)) {
            fallos.push(r + ": se esperaba un objeto y llegó " + _quees(v))
            return fallos
        }
        const props = s.properties || ({})
        const req = s.required || []
        for (let i = 0; i < req.length; i++)
            if (v[req[i]] === undefined || v[req[i]] === null)
                fallos.push(r + "." + req[i] + ": campo obligatorio que falta")
        for (const k in props)
            if (v[k] !== undefined && v[k] !== null)
                _empujar(fallos, validate(v[k], props[k], r + "." + k))
        if (s.additionalProperties === false)
            for (const k2 in v)
                if (props[k2] === undefined)
                    fallos.push(r + "." + k2 + ": campo que sobra")
        break
    }
    case "array": {
        if (!Array.isArray(v)) {
            fallos.push(r + ": se esperaba una lista y llegó " + _quees(v))
            return fallos
        }
        if (s.minItems !== undefined && v.length < s.minItems)
            fallos.push(r + ": hace falta al menos " + s.minItems
                        + (s.minItems === 1 ? " elemento" : " elementos")
                        + " (hay " + v.length + ")")
        if (s.maxItems !== undefined && v.length > s.maxItems)
            fallos.push(r + ": sobran elementos (máximo " + s.maxItems + ")")
        if (s.items)
            // Se comprueban los primeros veinte: si los veinte están bien, el
            // problema no es el tipo, y una lista de mil fallos no la lee nadie.
            for (let i = 0; i < Math.min(v.length, 20); i++)
                _empujar(fallos, validate(v[i], s.items, r + "[" + i + "]"))
        break
    }
    case "string":
        if (typeof v !== "string")
            fallos.push(r + ": se esperaba texto y llegó " + _quees(v))
        else if (s.minLength !== undefined && v.length < s.minLength)
            fallos.push(r + ": texto demasiado corto (mínimo " + s.minLength + ")")
        break
    case "integer":
    case "number":
        if (typeof v !== "number" || !isFinite(v))
            fallos.push(r + ": se esperaba un número y llegó " + _quees(v))
        else if (t === "integer" && Math.floor(v) !== v)
            fallos.push(r + ": se esperaba un entero y llegó " + v)
        else {
            if (s.minimum !== undefined && v < s.minimum)
                fallos.push(r + ": " + v + " es menor que el mínimo " + s.minimum)
            if (s.maximum !== undefined && v > s.maximum)
                fallos.push(r + ": " + v + " pasa del máximo " + s.maximum)
        }
        break
    case "boolean":
        if (typeof v !== "boolean")
            fallos.push(r + ": se esperaba sí/no (true o false) y llegó " + _quees(v))
        break
    }
    return fallos
}
function _empujar(dst, src) {
    for (let i = 0; i < src.length; i++)
        dst.push(src[i])
}
function _quees(v) {
    if (Array.isArray(v))
        return "una lista"
    if (v === null)
        return "nulo"
    if (typeof v === "object")
        return "un objeto"
    if (typeof v === "string")
        return "texto"
    if (typeof v === "number")
        return "un número"
    if (typeof v === "boolean")
        return "sí/no"
    return typeof v
}

// El recado de vuelta cuando no cumple: los fallos, cortados, y una orden
// concreta. Sin la orden, un modelo pequeño responde disculpándose.
function errorsText(fallos) {
    const l = fallos.slice(0, 12)
    return "Tu respuesta no cumple el formato pedido:\n- " + l.join("\n- ")
         + (fallos.length > l.length
            ? "\n- (y " + (fallos.length - l.length) + " más)" : "")
         + "\nDevuelve AHORA solo el JSON corregido, sin explicaciones ni "
         + "bloques de código alrededor."
}

// ¿Es esto un esquema que sepamos comprobar? Un modelo puede mandar cualquier
// cosa en el parámetro; si no lo es, se ignora y el encargo sigue en prosa —
// mejor eso que rechazar un trabajo por la forma del formulario.
function usable(s) {
    if (!s || typeof s !== "object" || Array.isArray(s))
        return false
    const t = _tipo(s)
    if (t === "object")
        return !!s.properties && Object.keys(s.properties).length > 0
    return t === "array" && !!s.items
}

function pretty(v) {
    try {
        return JSON.stringify(v, null, 2)
    } catch (e) {
        return String(v)
    }
}
