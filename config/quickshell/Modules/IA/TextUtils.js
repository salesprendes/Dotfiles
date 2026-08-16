// Utilidades PURAS del harness de IA: texto, parseo y normalización, sin nada
// de estado ni de QML. Viven aquí, fuera de AiService.qml, porque no dependen
// de él y así el singleton adelgaza y estas piezas se pueden probar solas.
// `.pragma library`: una sola instancia compartida, sin acceso al árbol QML —
// justo lo que corresponde a funciones sin efectos.
.pragma library

// Normaliza lo que escriba el usuario hasta una raíz /v1 utilizable. Es
// deliberadamente indulgente porque una URL remota se copia y se pega mal:
// sobran barras, falta el esquema, se pega el endpoint entero… Todo eso acaba
// en la misma base. Sin esquema se asume https, salvo IP/localhost (http).
// Limpieza y esquema comunes a las dos normalizaciones de URL: espacios
// fuera, barras finales fuera, y si falta el esquema se asume https salvo
// IP/localhost (ahí lo normal es http). "" si no había nada.
function _withScheme(u) {
    let b = String(u || "").trim().replace(/\s+/g, "").replace(/\/+$/, "")
    if (b === "")
        return ""
    if (!/^https?:\/\//i.test(b)) {
        const host = b.split("/")[0]
        const local = /^(localhost|\[|\d{1,3}(\.\d{1,3}){3})(:\d+)?$/i.test(host)
        b = (local ? "http://" : "https://") + b
    }
    return b
}

function normalizeBase(u) {
    let b = _withScheme(u)
    if (b === "")
        return ""
    // Pegar el endpoint entero es lo más común: se recorta a su raíz.
    b = b.replace(/\/(chat\/completions|completions|models)$/i, "")
         .replace(/\/+$/, "")
    if (!/\/v1$/i.test(b))
        b += "/v1"
    return b
}

// La raíz del buscador SearXNG, con la misma indulgencia.
function normalizeSearchBase(u) {
    return _withScheme(u).replace(/\/search$/i, "")
}

// Metacaracteres que convierten UN comando permitido en varios (cadenas,
// tuberías, redirecciones, sustitución).
function hasShellOps(cmd) {
    return /[;&|><`\n\r]|\$\(|\(/.test(String(cmd))
}

// Rutas @archivo referenciadas en un mensaje.
function atRefs(t) {
    const out = []
    const re = /(?:^|\s)@(~?[\w./~-]+)/g
    let m
    while ((m = re.exec(String(t))) !== null)
        if (out.indexOf(m[1]) === -1)
            out.push(m[1])
    return out
}

// Separa el razonamiento <think>…</think> (Qwen y compañía) del texto.
function splitThink(raw) {
    const open = raw.indexOf("<think>")
    if (open === -1)
        return { think: "", text: raw }
    const close = raw.indexOf("</think>", open)
    if (close === -1)
        return { think: raw.slice(open + 7), text: raw.slice(0, open) }
    return { think: raw.slice(open + 7, close),
             text: raw.slice(0, open) + raw.slice(close + 8) }
}

// Ordena los ÍNDICES de las notas por relevancia a una consulta. Palabras
// largas MÁS los acrónimos cortos en mayúsculas (QML, SSH, Qt); a igualdad,
// orden original; sin consulta, orden original.
function rankNotes(notes, query) {
    const idx = notes.map((_, i) => i)
    const q = String(query || "")
    if (q.trim() === "")
        return idx
    const words = q.split(/[^\wáéíóúüñÁÉÍÓÚÜÑ]+/)
        .filter(w => w.length > 3 || (w.length >= 2 && /^[A-Z0-9]+$/.test(w)))
        .map(w => w.toLowerCase())
    if (words.length === 0)
        return idx
    const score = notes.map(t => {
        const low = String(t).toLowerCase()
        let s = 0
        for (let i = 0; i < words.length; i++)
            if (low.indexOf(words[i]) !== -1)
                s++
        return s
    })
    return idx.sort((a, b) => (score[b] - score[a]) || (a - b))
}

// ── Relevancia de las habilidades ────────────────────────────────────────────
// Sin acentos y en minúsculas: en castellano "código" y "codigo" tienen que
// casar, o la mitad de las coincidencias se pierden por una tilde.
function fold(s) {
    let out = String(s || "").toLowerCase()
    const from = "áàäâãéèëêíìïîóòöôõúùüûñç"
    const to   = "aaaaaeeeeiiiiooooouuuunc"
    let r = ""
    for (let i = 0; i < out.length; i++) {
        const k = from.indexOf(out[i])
        r += k === -1 ? out[i] : to[k]
    }
    return r
}

// Palabras vacías: son las que aparecen en TODAS las frases, así que puntuar
// con ellas es puntuar ruido. Solo las de cuatro letras o más, que las cortas
// ya las descarta el filtro de longitud.
var STOP = ("para como esta este esto estos estas cuando donde porque pero unas "
    + "unos sobre entre desde hasta tiene tienen hacer hace haga hago puede "
    + "pueden quiero necesito tengo poner pon dime dame sabes creo algo alguna "
    + "algun todo toda todos todas nada mucho muy mas menos bien mal ahora "
    + "luego antes despues aqui alli asi cual cuales quien mismo misma otra "
    + "otro cosa cosas vez veces favor gracias hola sale salen mira mirar ver "
    + "dice dicen anda va van esos esas cada solo sola tambien").split(" ")

// La raíz aproximada de una palabra: sus primeras seis letras. Así "historial"
// casa con "historia" y "logs" con "log", sin montar un lematizador. Se aplica
// solo a partir de siete letras: acortar "servidor" a "servi" lo haría casar
// con "servicio", que es otra cosa.
function stem(w) {
    return w.length >= 7 ? w.slice(0, 6) : w
}

// Palabras con las que vale la pena puntuar: de cuatro letras para arriba, o
// siglas en mayúsculas (QML, SSH, DNS, WHM), que son cortas pero clavan el tema.
function keywords(text) {
    const raw = String(text || "").split(/[^\wáéíóúüñÁÉÍÓÚÜÑ]+/)
    const out = []
    for (let i = 0; i < raw.length; i++) {
        const w = raw[i]
        if (w === "")
            continue
        const sigla = w.length >= 2 && w.length <= 5 && /^[A-Z0-9]+$/.test(w)
        if (!sigla && w.length < 4)
            continue
        const f = fold(w)
        if (!sigla && STOP.indexOf(f) !== -1)
            continue
        const s = stem(f)
        if (out.indexOf(s) === -1)
            out.push(s)
    }
    return out
}

// Las habilidades ordenadas por encaje: [{skill, score}], de más a menos, y a
// igualdad en el orden en que estaban.
//
// El nombre pesa más que la descripción —decir "plesk" es una señal mucho más
// fuerte que que la palabra salga en un párrafo—, pero con un descuento
// importante: **una palabra que aparece en media docena de habilidades no
// distingue nada**. "Servidor" está en el nombre de dos y en la descripción de
// cuatro; sin descontarla, cualquier frase con esa palabra empataba tres
// habilidades y la elección salía a cara o cruz. Es la misma idea que el IDF
// de toda la vida: cuanto más común es un término, menos dice.
//
// Nombre y descripción se pliegan UNA vez por habilidad, no una por cada
// palabra de la consulta: con treinta habilidades y diez palabras, la versión
// ingenua plegaba seiscientas veces los mismos textos.
function rankSkills(skills, text) {
    const words = keywords(text)
    const folded = skills.map(s => ({
        name: fold((s.name || "") + " " + (s.id || "")),
        desc: fold(s.description || "")
    }))
    // 2 = está en el nombre, 1 = en la descripción, 0 = no está.
    const where = (i, w) => folded[i].name.indexOf(w) !== -1 ? 2
                          : folded[i].desc.indexOf(w) !== -1 ? 1 : 0
    const comun = words.map(w => {
        let n = 0
        for (let i = 0; i < skills.length; i++)
            if (where(i, w) > 0)
                n++
        return n >= 3
    })
    const out = skills.map((s, i) => {
        let score = 0
        for (let k = 0; k < words.length; k++) {
            const donde = where(i, words[k])
            if (donde === 0)
                continue
            // Una palabra POCO común en el NOMBRE es la señal más fuerte que
            // hay: quien dice "plesk" o "cPanel" está nombrando el tema. Una
            // palabra común solo suma si está en el nombre, y poco.
            score += comun[k] ? (donde === 2 ? 1 : 0)
                              : (donde === 2 ? 4 : 1)
        }
        return { skill: s, score: score, i: i }
    })
    out.sort((a, b) => (b.score - a.score) || (a.i - b.i))
    return out
}

// Repara los defectos típicos de un JSON generado por un modelo pequeño:
// vallas de Markdown, comas colgantes, comillas simples, literales de Python.
// Si aun así no parsea, devuelve null (nunca inventa argumentos).
function repairJson(raw) {
    let s = String(raw || "").trim()
    if (s === "")
        return ({})
    try { return JSON.parse(s) } catch (e) {}
    s = s.replace(/^```[a-zA-Z]*\s*/, "").replace(/```\s*$/, "").trim()
    const open = s.indexOf("{"), close = s.lastIndexOf("}")
    if (open > 0 || (close !== -1 && close < s.length - 1)) {
        if (open !== -1 && close > open)
            s = s.slice(open, close + 1)
    }
    try { return JSON.parse(s) } catch (e) {}
    let t = s.replace(/\bTrue\b/g, "true").replace(/\bFalse\b/g, "false")
             .replace(/\bNone\b/g, "null")
             .replace(/,(\s*[}\]])/g, "$1")
    try { return JSON.parse(t) } catch (e) {}
    if (t.indexOf('"') === -1) {
        try { return JSON.parse(t.replace(/'/g, '"')) } catch (e) {}
    }
    return null
}

// Un valor de <parameter=…> de Qwen3-Coder, convertido al tipo que aparenta
// (las reglas del parser oficial de Qwen, sin esquema): se quita UN salto de
// línea a cada lado, "null"/"true"/"false" se convierten, los números que
// sobreviven al viaje ida-y-vuelta se convierten (así "0755" y "007" siguen
// siendo texto, que un modo de chmod convertido a 493 sería un destrozo), y
// lo que parece JSON se intenta parsear. El resto, texto tal cual.
function coerceParam(v) {
    let s = String(v)
    if (s.startsWith("\n"))
        s = s.slice(1)
    if (s.endsWith("\n"))
        s = s.slice(0, -1)
    const t = s.trim()
    const low = t.toLowerCase()
    if (low === "null")
        return null
    if (low === "true")
        return true
    if (low === "false")
        return false
    if (/^-?\d+$/.test(t) && String(Number(t)) === t)
        return Number(t)
    if (/^-?\d*\.\d+$/.test(t) && String(Number(t)) === t)
        return Number(t)
    if (t.startsWith("{") || t.startsWith("[")) {
        const j = repairJson(t)
        if (j !== null)
            return j
    }
    return s
}

// Llamadas de herramienta escritas EN EL TEXTO por modelos que no emiten
// tool_calls nativos. Reconoce, por orden:
//   <function=nombre><parameter=k>v</parameter>…</function>   Qwen3-Coder
//       (su formato NATIVO: XML, no JSON — con o sin <tool_call> alrededor)
//   <function=nombre>{…}</function>                           variante Llama
//   <tool_call>{…}</tool_call>                                Qwen/Hermes
//   <|python_tag|>{…}  /  functools[…]                        Llama 3.x (Muse)
//   [TOOL_CALLS] [ … ]                                        Mistral
// Y como última red, un objeto JSON suelto cuyo nombre esté en `knownNames`
// (que se pasa desde el harness, para no depender de él).
// Devuelve {calls:[{name,args}], rest:"texto sin las llamadas"}.
function extractTextToolCalls(raw, knownNames) {
    const text = String(raw || "")
    const known = knownNames || []
    const calls = []
    let rest = text
    const add = (name, argsObj) => {
        if (!name) return
        calls.push({ name: String(name), args: JSON.stringify(argsObj || {}) })
    }
    const argsOf = (o) => o.arguments !== undefined ? o.arguments
                        : o.parameters !== undefined ? o.parameters : {}

    // Bloques <function=…>: el cuerpo puede ser XML de parámetros (Qwen3-
    // Coder) o un JSON (variante de Llama). Se procesan PRIMERO porque el
    // formato de Qwen los envuelve además en <tool_call>, y el paso de JSON
    // de abajo no sabría leerlos.
    const fre = /<function\s*=\s*([A-Za-z0-9_.-]+)\s*>([\s\S]*?)<\/function>/g
    let fm
    let huboXml = false
    while ((fm = fre.exec(text)) !== null) {
        const body = fm[2]
        if (body.indexOf("<parameter=") !== -1) {
            const args = {}
            // El cierre </parameter> es OPCIONAL en el formato de Qwen: el
            // valor acaba donde empieza el siguiente parámetro o el bloque.
            const pre = /<parameter\s*=\s*([A-Za-z0-9_.-]+)\s*>([\s\S]*?)(?=<parameter\s*=|$)/g
            let pm
            while ((pm = pre.exec(body)) !== null)
                args[pm[1]] = coerceParam(pm[2].replace(/<\/parameter>\s*$/, ""))
            add(fm[1], args)
        } else {
            add(fm[1], repairJson(body) || {})
        }
        huboXml = true
    }
    if (huboXml)
        rest = rest.replace(fre, "")
                   .replace(/<tool_call>\s*<\/tool_call>/g, "")

    const blocks = [
        /<tool_call>\s*([\s\S]*?)\s*<\/tool_call>/g,
        /<\|python_tag\|>\s*(\{[\s\S]*?\})\s*(?=<\||$)/g
    ]
    for (let b = 0; b < blocks.length; b++) {
        let m
        while ((m = blocks[b].exec(text)) !== null) {
            const o = repairJson(m[1])
            if (o && o.name) add(o.name, argsOf(o))
        }
        if (calls.length > 0)
            rest = rest.replace(blocks[b], "")
    }

    const lre = /(?:\[TOOL_CALLS\]|functools)\s*(\[[\s\S]*?\])/g
    let lm
    while ((lm = lre.exec(text)) !== null) {
        const arr = repairJson(lm[1])
        if (Array.isArray(arr))
            for (let i = 0; i < arr.length; i++)
                if (arr[i] && arr[i].name) add(arr[i].name, argsOf(arr[i]))
    }
    if (calls.length > 0)
        rest = rest.replace(lre, "")

    if (calls.length === 0) {
        const only = repairJson(text)
        const items = Array.isArray(only) ? only : (only ? [only] : [])
        for (let i = 0; i < items.length; i++) {
            const o = items[i]
            if (o && o.name && known.indexOf(String(o.name)) !== -1)
                add(o.name, argsOf(o))
        }
        if (calls.length > 0)
            rest = ""
    }

    return { calls: calls, rest: rest.trim() }
}

// ── Base64 de texto UTF-8 ────────────────────────────────────────────────────
// Qt.btoa NO vale para esto: convierte la cadena a Latin-1 antes de codificar,
// así que "configuración" llega al otro extremo con un byte inválido donde iba
// la ó (y un guion largo o una « se convierten directamente en "?"). Este
// codifica los bytes UTF-8 de verdad: lo que descodifique `base64 -d` en el
// destino es exactamente el texto original.
var _B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function b64utf8(s) {
    const txt = String(s)
    const bytes = []
    for (let i = 0; i < txt.length; i++) {
        let c = txt.codePointAt(i)
        if (c > 0xFFFF)
            i++                     // pareja sustituta: ya consumida entera
        if (c < 0x80)
            bytes.push(c)
        else if (c < 0x800)
            bytes.push(0xC0 | (c >> 6), 0x80 | (c & 63))
        else if (c < 0x10000)
            bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63))
        else
            bytes.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 63),
                       0x80 | ((c >> 6) & 63), 0x80 | (c & 63))
    }
    let out = ""
    for (let i = 0; i < bytes.length; i += 3) {
        const b0 = bytes[i], b1 = bytes[i + 1], b2 = bytes[i + 2]
        out += _B64[b0 >> 2]
        out += _B64[((b0 & 3) << 4) | ((b1 === undefined ? 0 : b1) >> 4)]
        out += b1 === undefined ? "=" : _B64[((b1 & 15) << 2) | ((b2 === undefined ? 0 : b2) >> 6)]
        out += b2 === undefined ? "=" : _B64[b2 & 63]
    }
    return out
}

// ── Guardarraíl de privacidad ────────────────────────────────────────────────
// Lo que una herramienta lee acaba EN EL CONTEXTO, y de ahí viaja al modelo (y
// a su servidor, si no es local). Antes de entrar se tapan los secretos de
// forma inequívoca: claves privadas, Bearer, y asignaciones de
// password/token/api_key. Solo formas de ALTA confianza — enmascarar de más
// rompería trabajos legítimos —, y el hueco se marca a la vista para que se
// sepa que hay algo tapado en vez de creer que no había nada.
const _SECRETOS = [
    // Bloques PEM enteros (clave privada SSH/TLS).
    { re: /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g,
      to: "[clave privada oculta]" },
    // Cabeceras de autorización.
    { re: /(authorization\s*:\s*bearer\s+)[A-Za-z0-9._~+/=-]{12,}/gi,
      to: "$1[oculto]" },
    // clave = valor en configuraciones, .env… y en JSON, que es como llegan de
    // verdad los argumentos de una herramienta. La comilla de CIERRE del nombre
    // faltaba en el patrón, así que `"password": "secreto"` —la forma más común
    // de todas, y la que se guarda en el historial— se colaba entera: el
    // separador nunca venía pegado al nombre, siempre había una comilla en medio.
    { re: /((?:password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|private[_-]?key|token|credential)["']?\s*[:=]\s*["']?)([^\s"'\n,}]{6,})/gi,
      to: "$1[oculto]" }
]

function redactSecrets(text) {
    let s = String(text || "")
    for (let i = 0; i < _SECRETOS.length; i++)
        s = s.replace(_SECRETOS[i].re, _SECRETOS[i].to)
    return s
}

// ── Detector de comandos DESTRUCTIVOS ────────────────────────────────────────
// Un guardarraíl por encima de la clase de riesgo: hay comandos que, aunque el
// usuario haya aflojado la correa, no deberían correr sin que los mire dos
// veces. No pretende ser exhaustivo (imposible en un shell) ni bloquear —solo
// LEVANTAR LA MANO: fuerza la tarjeta y enseña el motivo en rojo, aunque la
// política dijera "auto". Falso positivo cuesta un clic; falso negativo cuesta
// un disgusto, así que se peca de prudente. Devuelve el motivo, o "" si nada
// llama la atención.
const _PELIGROS = [
    // rm RECURSIVO (-r/-R): el que puede llevarse un árbol entero. Un rm -f de
    // un archivo suelto no salta — borrar un .o de build es rutina.
    { re: /\brm\s+(-[a-z]*\s+)*-[a-z]*r[a-z]*\b/i,
      why: "borrado recursivo (rm -r)" },
    // rm sobre raíz, la carpeta personal, una variable sin expandir o un
    // comodín amplio, aunque sea solo -f.
    { re: /\brm\s+(-[a-z]*\s+)*(\/\s|\/$|~|\$HOME|\$\{HOME|\/\*|\s\*\s|\s\*$)/i,
      why: "rm sobre la raíz, la carpeta personal o un comodín" },
    { re: /\b(mkfs|mke2fs|fdisk|parted|wipefs)\b/i,
      why: "formatear o reparticionar un disco" },
    { re: /\bdd\b[^|;&]*\bof=\s*\/dev\//i,
      why: "dd escribiendo directo a un dispositivo" },
    { re: />\s*\/dev\/(sd|nvme|vd|hd|mmcblk|disk)/i,
      why: "redirección directa a un disco" },
    { re: /:\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;/,
      why: "fork bomb" },
    { re: /\bchmod\s+-[a-z]*R[a-z]*\s+[^|;&]*0*777\b|\bchmod\s+0*777\s+(-[a-z]*R|\/|~|\$HOME)/i,
      why: "chmod 777 recursivo o sobre raíz/carpeta personal" },
    { re: /\bchown\s+-[a-z]*R[a-z]*\b/i,
      why: "chown recursivo (cambia el dueño de un árbol entero)" },
    { re: /\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(sh|bash|zsh|python|perl)\b/i,
      why: "descargar y ejecutar a ciegas (curl | sh)" },
    { re: /\bgit\s+(reset\s+--hard|clean\s+-[a-z]*f|push\s+[^|;&]*--force)/i,
      why: "operación de git que descarta trabajo (reset --hard, clean -f, push --force)" },
    { re: /\b(shutdown|reboot|poweroff|halt|init\s+0|init\s+6)\b/i,
      why: "apagar o reiniciar el equipo" },
    { re: />\s*(\/etc\/(passwd|shadow|fstab|sudoers)|~?\/\.ssh\/)/i,
      why: "sobrescribir un archivo de sistema o de claves sensibles" },
    { re: /\btruncate\s+-s\s*0\b|:\s*>\s*[^|;&]*\.(db|sqlite|sql)\b/i,
      why: "vaciar una base de datos o un archivo" },
    // Barrer la red de casa. Lo escribió el modelo tal cual —un bucle de 254
    // pings en paralelo para ver quién hay en la LAN— no por malicia, sino
    // porque no tenía una herramienta que lo hiciera. Sigue mereciendo tarjeta:
    // desde fuera es indistinguible de un reconocimiento, y en una red ajena
    // puede saltarle la alarma a alguien.
    { re: /\b(nmap|masscan|zmap|arp-scan)\b/i,
      why: "escanear la red" },
    { re: /\bfor\b[^\n]{0,80}\b(seq|\{\d+\.\.\d+\})[^\n]{0,120}&\s*(done|$)/,
      why: "lanzar muchos procesos a la vez en un bucle (barrido o tormenta de procesos)" },
    // Una consola inversa: la máquina llama hacia fuera y entrega el shell.
    { re: /\b(nc|ncat|netcat|socat)\b[^|;&]*\s-e\b|>&\s*\/dev\/tcp\/|\bbash\s+-i\b[^\n]*\/dev\/tcp\//i,
      why: "abrir una consola hacia otra máquina (shell inversa)" },
    // Trabajos programados: lo que se planta ahí se ejecuta solo, después, sin
    // que haya ninguna tarjeta que aprobar.
    { re: /\bcrontab\s+(-r\b|[^-\s])|\bsystemd-run\b|\bat\s+(now|\d)/i,
      why: "programar o borrar tareas que se ejecutarán solas más tarde" },
    { re: /\bhistory\s+-c\b|>\s*~?\/?\.(bash|zsh)_history\b/i,
      why: "borrar el historial de la terminal" },
    // sudo no puede funcionar aquí y conviene decirlo: este proceso no tiene
    // terminal, así que no hay dónde escribir la contraseña. O está configurado
    // sin contraseña para eso, o se queda esperando hasta que lo corta el plazo.
    { re: /(^|[|;&]\s*)sudo\s/,
      why: "usa sudo, y aquí no hay terminal donde escribir la contraseña: si no está configurado sin contraseña, se quedará esperando hasta agotar el plazo" }
]
function dangerScan(cmd) {
    const s = String(cmd || "")
    for (let i = 0; i < _PELIGROS.length; i++)
        if (_PELIGROS[i].re.test(s))
            return _PELIGROS[i].why
    return ""
}

// ── Exfiltración por URL ─────────────────────────────────────────────────────
// El hueco que dejó a la vista el red-team. Descargar una URL es clase
// "external", y eso admite permiso permanente ("Siempre"): una vez concedido, el
// modelo puede descargar sin tarjeta. Y una descarga SACA datos además de
// traerlos — lo que viaje en la URL se lo lleva quien esté al otro lado. El
// ataque es de una línea: una página inyectada le pide al asistente que
// "verifique" abriendo https://recolector/x?d=<lo que sea que tenga a mano>.
//
// Tapar el secreto en la respuesta no sirve de nada aquí: para cuando se tapa,
// ya ha viajado. Lo que se mira es la petición.
//
// No se prohíbe: se fuerza la tarjeta, con el motivo escrito. Es la misma regla
// que el detector de comandos destructivos — un falso positivo cuesta un clic y
// un falso negativo cuesta una credencial.
const _FUGAS = [
    { re: /-----BEGIN [A-Z ]*PRIVATE KEY-----/i,
      why: "la URL lleva dentro una clave privada" },
    { re: /(?:^|[?&#])[^=&#]*(?:pass|passwd|password|secret|api[_-]?key|token|auth|credential|cookie|session)[^=&#]*=[^&#\s]{8,}/i,
      why: "la URL lleva dentro algo con pinta de credencial" },
    // sk-…, ghp_…, xoxb-… y compañía: las formas que tienen las claves de los
    // servicios habituales, que un modelo puede haber leído en un archivo.
    { re: /(?:^|[/?&#=])(?:sk|pk|rk)-[A-Za-z0-9_-]{16,}|\b(?:ghp|gho|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}|\bxox[baprs]-[A-Za-z0-9-]{10,}/,
      why: "la URL lleva dentro lo que parece la clave de un servicio" },
    // Un valor enorme y opaco en la consulta: la forma que tiene un volcado.
    // Los enlaces normales llevan identificadores y palabras, no bloques de
    // trescientos caracteres sin un espacio.
    { re: /[?&][^=&#]{1,40}=[A-Za-z0-9+/=_-]{300,}/,
      why: "la URL lleva un bloque de datos enorme en un parámetro" }
]
// ── A QUÉ RED APUNTA ────────────────────────────────────────────────────────
// La otra mitad del peligro de una URL. La de arriba mira lo que SACA; esta
// mira a DÓNDE entra: 127.0.0.1, la 192.168 de casa, el 169.254.169.254 de los
// metadatos de una nube. Nada de eso está en internet — son máquinas que
// confían en quien las llama porque solo las llama su dueño, y la
// autenticación de muchas es "estar dentro".
//
// El encadenamiento que cierra esto es concreto: una página inyectada le dice
// al asistente "verifica tu router en http://192.168.1.1/admin", el resultado
// entra al contexto, y la siguiente llamada lo saca en la consulta de otra URL.
// El primer eslabón es el barato de romper.
//
// Devuelve el nombre de la zona, o "" si es internet normal.
function urlZone(url) {
    let h = String(url || "").replace(/^[a-z][a-z0-9+.-]*:\/\//i, "")
                             .replace(/^[^/@]*@/, "")
                             .split(/[/?#]/)[0].toLowerCase()
    // El puerto se quita con cuidado: en IPv6 los dos puntos son la dirección,
    // no el puerto. Recortar por el último ":" convertía [2606:4700::1111] —una
    // dirección pública de Cloudflare— en "2606:4700::", que al no tener puntos
    // caía en la regla de "nombre sin puntos = máquina de casa". Un falso
    // positivo aquí no es inofensivo: bloquearía media internet moderna.
    let v6 = false
    if (h.charAt(0) === "[") {
        v6 = true
        h = h.slice(1, h.indexOf("]") === -1 ? h.length : h.indexOf("]"))
    } else if ((h.match(/:/g) || []).length > 1) {
        v6 = true
    } else {
        h = h.replace(/:\d+$/, "")
    }
    if (h === "")
        return ""
    // IPv4 mapeada dentro de IPv6: ::ffff:127.0.0.1 es 127.0.0.1 con otro traje,
    // y el sistema la enruta como tal. Sin desnudarla, el rodeo más barato para
    // saltarse todo lo de abajo era escribir la misma dirección de otra forma.
    const mapeada = h.match(/^(?:::ffff:|::)((?:\d{1,3}\.){3}\d{1,3})$/)
    if (mapeada) {
        h = mapeada[1]
        v6 = false
    }
    if (h === "localhost" || /(^|\.)localhost$/.test(h) || /^127\./.test(h)
            || h === "::1" || h === "0.0.0.0" || h === "::")
        return "la propia máquina"
    // 169.254/16 y fe80::/10. Aquí vive el 169.254.169.254 de AWS/GCP/Azure,
    // que sirve credenciales a quien pregunte.
    if (/^169\.254\./.test(h) || /^fe[89ab]/.test(h))
        return "la red local del enlace (ahí viven los metadatos de las nubes)"
    if (/^10\./.test(h) || /^192\.168\./.test(h)
            || /^172\.(1[6-9]|2\d|3[01])\./.test(h)
            || /^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./.test(h)
            || /^f[cd]/.test(h))
        return "la red local"
    // Un nombre sin puntos (o .local/.internal/.lan) no sale a internet: es una
    // máquina de esta casa resuelta por mDNS o por /etc/hosts. Solo vale para
    // NOMBRES: una IPv6 no tiene puntos y no por eso es de casa.
    if ((!v6 && h.indexOf(".") === -1)
            || /\.(local|internal|lan|home|intranet)$/.test(h))
        return "una máquina de la red local"
    return ""
}

function urlLeakScan(url) {
    const s = String(url || "")
    const z = urlZone(s)
    if (z !== "")
        return "apunta a " + z + ", no a internet"
    for (let i = 0; i < _FUGAS.length; i++)
        if (_FUGAS[i].re.test(s))
            return _FUGAS[i].why
    return ""
}

// ── Escrituras que se convierten en EJECUCIÓN ────────────────────────────────
// El otro hueco que enseñó el red-team, y el que tiene dientes de verdad. La
// ejecución nunca se auto-aprueba —eso aguanta hasta en la configuración más
// floja—, así que una inyección no va a conseguir un `run_command`. Lo que sí
// puede intentar es dar un rodeo: si el usuario ha puesto la escritura en
// "auto", basta con escribir en el sitio correcto y esperar. Un `.bashrc`, un
// `.desktop` en autostart o un hook de git no son archivos: son comandos con
// retardo.
//
// Igual que con los comandos destructivos, esto no prohíbe: fuerza la tarjeta y
// escribe el motivo. Escribir tu propio .bashrc es perfectamente legítimo — lo
// que no es legítimo es que ocurra sin que lo veas.
const _RUTAS_ARRANQUE = [
    { re: /\/\.(bash_profile|bashrc|bash_login|bash_logout|profile|zshrc|zprofile|zshenv|zlogin|kshrc)$/,
      why: "un archivo que se ejecuta al abrir una terminal" },
    { re: /\/\.config\/autostart\//,
      why: "el arranque automático de la sesión gráfica" },
    { re: /\/(\.config|\.local\/share)\/systemd\//,
      why: "una unidad de systemd del usuario" },
    { re: /\/\.ssh\/(authorized_keys|config|rc)$/,
      why: "la configuración de acceso por SSH" },
    { re: /\/(crontab|cron\.[a-z]+)\//, why: "una tarea programada" },
    { re: /\/\.git\/hooks\//, why: "un hook de git, que corre al usar el repositorio" },
    { re: /\/(\.local\/bin|\/usr\/local\/bin|\/bin)\/[^/]+$/,
      why: "una carpeta del PATH: lo que se escriba ahí se ejecuta por su nombre" },
    // El propio shell del escritorio: escribir aquí es cambiar el código que
    // corre en cuanto el vigilante de archivos vea el cambio.
    { re: /\/\.config\/quickshell\//,
      why: "la configuración de este mismo escritorio, que se recarga sola" },
    { re: /\/\.(profile\.d|xprofile|xinitrc|xsession)$/,
      why: "un archivo de inicio de sesión" }
]
function pathDangerScan(path) {
    const s = String(path || "")
    for (let i = 0; i < _RUTAS_ARRANQUE.length; i++)
        if (_RUTAS_ARRANQUE[i].re.test(s))
            return _RUTAS_ARRANQUE[i].why
    return ""
}
