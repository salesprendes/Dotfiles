// LA CONVERSACIÓN COMO TRANSCRIPCIÓN, para que la lea el archivero.
//
// Hasta ahora la compactación le mandaba al resumidor el MISMO array de mensajes
// que viaja al modelo en un turno normal: con su protocolo de herramientas
// reconstruido, un assistant con tool_calls por cada ronda, el resultado íntegro
// de cada tarjeta. Eso tiene tres problemas y ninguna ventaja:
//
//   · Cuesta lo mismo que el turno más caro de la conversación. Resumir es la
//     operación que debería ser barata, y era la más cara.
//   · Si el contexto acaba de DESBORDAR, la petición de resumen desborda
//     también — o sea que justo cuando más falta hace, no se puede hacer.
//   · El protocolo de herramientas no significa nada en una petición sin
//     herramientas. Se pagaba una estructura que el resumidor no usa.
//
// Aquí se aplana a texto: quién dijo qué, qué se llamó y qué salió, con cada
// resultado ACOTADO. Dos mil caracteres bastan para resumir lo que hizo una
// herramienta; los treinta mil de un `cat` no aportan nada a un resumen y sí lo
// empeoran, porque entierran la conversación bajo la salida.
//
// JavaScript puro sobre objetos planos (los de PL.plainMsg): sin red, sin QML.
.pragma library

// Cuánto de cada resultado llega al resumen.
const TOPE_RESULTADO = 2000
// Y cuánto de sus argumentos: el patrón de un grep importa, el contenido entero
// de un write_file no (ya está en el archivo).
const TOPE_ARGS = 600

function _txt(v) {
    return String(v === undefined || v === null ? "" : v)
}

function _acota(t, tope, que) {
    if (t.length <= tope)
        return t
    return t.slice(0, tope) + "\n[… " + (t.length - tope) + " caracteres más de "
         + que + "]"
}

// Los argumentos como `nombre=valor`, con los valores largos acotados. Se
// escriben a mano y no con JSON.stringify del objeto entero porque el contenido
// de un write_file son diez mil caracteres que el resumen no necesita.
function argumentos(cadena, tope) {
    const t = tope === undefined ? TOPE_ARGS : tope
    let o = null
    try { o = JSON.parse(_txt(cadena)) } catch (e) {}
    if (!o || typeof o !== "object")
        return _acota(_txt(cadena), t, "argumentos")
    const partes = []
    for (const k in o) {
        let v = o[k]
        if (typeof v === "string")
            v = JSON.stringify(v.length > t ? v.slice(0, t) + "…" : v)
        else
            v = JSON.stringify(v)
        if (v === undefined)
            v = "null"
        partes.push(k + "=" + String(v))
    }
    return partes.join(", ")
}

// Una fila del hilo como una o dos líneas de transcripción. Devuelve "" cuando
// esa fila no pinta nada en un resumen.
function linea(m, opts) {
    const o = opts || ({})
    const topeRes = o.topeResultado === undefined ? TOPE_RESULTADO : o.topeResultado
    if (m.role === "user")
        return "[Usuario]: " + _txt(m.content)
    if (m.role === "assistant") {
        const c = _txt(m.content)
        // El RAZONAMIENTO no entra nunca. Es efímero, pesa más que la respuesta,
        // y hay clasificadores (el de Anthropic) que rechazan una entrada que
        // reproduce el pensamiento del propio modelo como texto.
        return c === "" ? "" : "[Asistente]: " + c
    }
    if (m.role !== "tool")
        // Las notas del harness ("contexto compactado", "reintentando") y los
        // errores de transporte no son conversación: son ruido de la máquina.
        return ""
    if (m.toolStatus === "pending")
        return ""
    const llamada = "[Llamada]: " + _txt(m.toolName) + "("
                  + argumentos(m.toolArgs, o.topeArgs) + ")"
    if (m.toolStatus === "rejected")
        return llamada + "\n[Rechazada]: " + _acota(_txt(m.toolResult), 400, "motivo")
    const dijo = _txt(m.content)
    return (dijo !== "" ? "[Asistente]: " + dijo + "\n" : "")
         + llamada + "\n[Resultado]: "
         + _acota(_txt(m.toolResult), topeRes, "resultado")
}

// El hilo entero como texto.
//
//   msgs   objetos planos
//   opts   { topeResultado, topeArgs, tope, saltarInutiles }
//   →      { texto, omitidos }  omitidos = filas viejas que no cupieron
//
// Cuando no cabe todo se tira de lo MÁS VIEJO, no de lo más nuevo: en una
// compactación incremental lo viejo ya está contado en el estado acumulado que
// viaja aparte, y lo nuevo es justo lo que nadie ha resumido todavía.
function serializar(msgs, opts) {
    const o = opts || ({})
    const tope = o.tope === undefined ? 0 : o.tope
    const saltar = o.saltarInutiles !== false
    const filas = []
    let total = 0
    let omitidos = 0
    for (let i = msgs.length - 1; i >= 0; i--) {
        const m = msgs[i]
        // Lo que la herramienta marcó como que no informó de nada se cae ENTERO
        // —la llamada y el resultado—: la región se descarta después del resumen
        // de todos modos, así que excluirla no cuesta caché y mantiene la basura
        // fuera de la entrada del resumidor.
        if (saltar && m.role === "tool" && m.toolUseless === true)
            continue
        const l = linea(m, o)
        if (l === "")
            continue
        if (tope > 0 && total + l.length > tope && filas.length > 0) {
            omitidos = i + 1
            break
        }
        filas.unshift(l)
        total += l.length + 2
    }
    const cabeza = omitidos > 0
        ? "[… " + omitidos + " mensajes anteriores omitidos por tamaño …]\n\n" : ""
    return { texto: cabeza + filas.join("\n\n"), omitidos: omitidos }
}
