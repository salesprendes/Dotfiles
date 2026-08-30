.pragma library

// El motor de búsqueda de Spotlight: puntuar y ordenar. JS puro y sin nada de
// QML a propósito, para que se pueda probar con node (ver tests/t_busqueda.js);
// buscar es lógica, y la lógica que solo se puede comprobar abriendo un panel
// no se comprueba nunca.
//
// ── QUÉ TENÍA MAL LO DE ANTES ───────────────────────────────────────────────
// El lanzador del shell hacía `searchText.includes(q)`: subcadena a pelo y sin
// ordenar. Eso significa que "code" ponía al mismo nivel «Visual Studio Code»
// y «Decodificador de audio», y que el orden lo decidía el sistema de archivos.
//
// ── LO QUE HACE ESTE ────────────────────────────────────────────────────────
// Una escalera de calidad de coincidencia, de mejor a peor, y la posición en la
// escalera pesa más que cualquier otra cosa:
//
//   exacto  >  empieza por  >  empieza una palabra  >  contiene  >  difuso
//
// «fire» encuentra Firefox por prefijo (5000) y no se queda a la altura de un
// «Bonfire» cualquiera, que solo contiene (500).
//
// ── DOS COSAS QUE LA REFERENCIA NO HACE ─────────────────────────────────────
//
// 1. ACENTOS. DankMaterialShell compara en minúsculas y ya. En castellano eso
//    es inservible: «musica» no encuentra «Música», y nadie escribe el acento
//    cuando busca con prisa. Aquí se normaliza quitando diacríticos, así que
//    «musica», «música» y «MÚSICA» son la misma consulta. También arregla la ñ
//    de rebote y las tildes catalanas.
//
// 2. FRECENCIA DE VERDAD. Allí es `usageCount * 50`: frecuencia pura, sin
//    memoria del CUÁNDO. Con eso, la app que abriste doscientas veces hace un
//    año le gana para siempre a la que usas cada mañana desde marzo. Aquí lo
//    usado envejece (ver frecency), así que la lista se adapta a lo que haces
//    AHORA en vez de fosilizarse.

// ── Pesos ───────────────────────────────────────────────────────────────────
// La distancia entre escalones es grande a propósito: un peldaño mejor de
// coincidencia tiene que ganar SIEMPRE, por mucha frecencia que traiga el otro.
// Si no, lo que usas mucho se te cuela delante de lo que has escrito.
var W = {
    exact: 10000,
    prefix: 5000,
    wordStart: 3000,
    substring: 500,
    fuzzy: 100,

    // Los campos secundarios valen menos que el nombre: acertar en el nombre
    // es más señal que acertar en la descripción.
    subtitleFactor: 0.5,
    keywordFactor: 0.35,

    // Tope de lo que puede aportar el uso. Menos que un escalón, siempre.
    frecencyMax: 1800,

    // Empujón por tipo, para desempatar entre coincidencias igual de buenas:
    // con "term" escrito, una app llamada Terminal va antes que un emoji cuyo
    // nombre también contiene "term".
    type: {
        app: 1000,
        command: 700,
        setting: 650,
        clipboard: 600,
        calc: 1200,     // una cuenta resuelta es siempre lo que buscabas
        file: 550,
        emoji: 500,
        action: 450
    }
}

// ── Normalización ───────────────────────────────────────────────────────────
// Minúsculas y sin diacríticos. NFD separa la letra de su tilde y el rango
// U+0300–U+036F es el de los diacríticos combinantes, así que quitarlos deja
// la letra base. La ñ también se descompone (n + tilde) y queda en «n», que es
// lo que uno quiere al buscar sin teclearla.
function norm(text) {
    if (text === undefined || text === null)
        return ""
    return String(text)
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")   // diacríticos combinantes
        .toLowerCase()
        .trim()
}

var SEPS = /[\s\-_./]+/

// Parte en palabras un texto QUE YA VIENE NORMALIZADO. Separada de words()
// a propósito: normalizar es lo caro (NFD + regex de diacríticos) y quien
// llama aquí dentro ya lo ha hecho una vez.
function splitWords(normText) {
    var raw = normText.split(SEPS)
    var out = []
    for (var i = 0; i < raw.length; i++)
        if (raw[i].length > 0)
            out.push(raw[i])
    return out
}

function words(text) {
    return splitWords(norm(text))
}

// ── Coincidencia ────────────────────────────────────────────────────────────
// Estas tres reciben el texto YA partido en palabras, no el texto crudo. Antes
// cada una llamaba a words() por su cuenta y volvía a normalizar lo mismo: por
// cada candidato que no coincidía se hacían cuatro NFD idénticos, en cada
// pulsación de tecla.

// ¿Empieza alguna PALABRA del texto por la consulta? Es lo que hace que "code"
// encuentre «Visual Studio Code» sin tener que escribir desde el principio.
function wordStarts(ws, query) {
    for (var i = 0; i < ws.length; i++)
        if (ws[i].indexOf(query) === 0)
            return true
    return false
}

// Iniciales: "vsc" → «Visual Studio Code». Solo con consultas cortas y varias
// palabras, porque en cuanto se alarga produce coincidencias absurdas.
function initials(ws, query) {
    if (query.length < 2 || query.length > 5 || ws.length < 2)
        return false
    var acronym = ""
    for (var i = 0; i < ws.length; i++)
        acronym += ws[i].charAt(0)
    return acronym.indexOf(query) === 0
}

// Distancia de edición, con dos filas en vez de la matriz entera: solo hace
// falta la anterior para calcular la actual, y esto se llama muchas veces.
//
// Y ACOTADA por 'max': solo interesa saber si la distancia cabe en el
// presupuesto de erratas, no cuánto vale exactamente cuando se pasa. Eso
// permite calcular únicamente la banda de celdas a 'max' de la diagonal —el
// resto no puede dar un resultado que quepa— y abandonar en cuanto una fila
// entera se sale. Pasa de O(largo × largo) a O(largo × max).
function editDistance(a, b, max) {
    var la = a.length, lb = b.length
    if (la === 0) return lb
    if (lb === 0) return la
    var tope = max === undefined ? Infinity : max
    var prev = new Array(lb + 1)
    var curr = new Array(lb + 1)
    for (var j = 0; j <= lb; j++) prev[j] = j
    for (var i = 1; i <= la; i++) {
        var desde = i - tope, hasta = i + tope
        if (desde < 1) desde = 1
        if (hasta > lb) hasta = lb
        curr[0] = i
        // Las celdas justo fuera de la banda, a los DOS lados, tienen que
        // quedar inalcanzables: la fila siguiente lee una columna más a cada
        // lado, y sin esto leería un valor viejo de dos iteraciones atrás.
        if (desde > 1) curr[desde - 1] = tope + 1
        if (hasta < lb) curr[hasta + 1] = tope + 1
        var fila = tope + 1
        for (var k = desde; k <= hasta; k++) {
            var cost = a.charCodeAt(i - 1) === b.charCodeAt(k - 1) ? 0 : 1
            var v = prev[k] + 1
            var izq = curr[k - 1] + 1
            if (izq < v) v = izq
            var diag = prev[k - 1] + cost
            if (diag < v) v = diag
            curr[k] = v
            if (v < fila) fila = v
        }
        if (fila > tope)
            return tope + 1        // ya no puede bajar: sobra seguir
        var tmp = prev; prev = curr; curr = tmp
    }
    return prev[lb]
}

// Tolerancia a erratas. Escala con la consulta: en tres letras un fallo ya es
// mucho, en diez, tres siguen siendo la misma palabra mal escrita. Y no se
// aplica por debajo de tres letras — con dos, todo se parece a todo.
function typoBudget(len) {
    return len < 3 ? 0 : len <= 5 ? 1 : len <= 8 ? 2 : 3
}

function fuzzy(ws, query) {
    var budget = typoBudget(query.length)
    if (budget === 0)
        return 0
    var qlen = query.length
    var best = 0
    for (var i = 0; i < ws.length; i++) {
        var w = ws[i]
        // Descarte por longitud antes de calcular: si difieren en más que el
        // presupuesto, la distancia no puede entrar y calcularla es tirar
        // trabajo. Con miles de candidatos, esto es la diferencia.
        var dif = w.length - qlen
        if (dif > budget || -dif > budget)
            continue
        var d = editDistance(w, query, budget)
        if (d > budget)
            continue
        var s = 1 - d / (w.length > qlen ? w.length : qlen)
        if (s > best)
            best = s
    }
    return best
}

// Consulta de VARIAS palabras. "vis stu cod" tiene que encontrar «Visual
// Studio Code», y "firefox privada" la acción de ventana privada de Firefox.
// Sin esto, en cuanto metías un espacio la consulta dejaba de parecerse a nada
// y solo salvaba el resultado la subcadena literal — o sea, tenías que escribir
// las palabras enteras, seguidas y en el mismo orden que el nombre.
//
// Cada trozo de la consulta tiene que ESTRENAR una palabra del texto, y cada
// palabra del texto sirve para un trozo como mucho. Sin exigir que vayan
// seguidas ni en orden: "code visual" encuentra lo mismo que "visual code",
// que es como la gente escribe cuando va con prisa. La referencia (DMS) sí las
// exige consecutivas y en orden, y por eso allí "code visual" no encuentra nada.
function phraseMatch(ws, qw) {
    if (qw.length < 2 || qw.length > ws.length)
        return false
    var usada = new Array(ws.length)
    for (var j = 0; j < qw.length; j++) {
        var hallada = false
        for (var i = 0; i < ws.length; i++) {
            if (usada[i] || ws[i].indexOf(qw[j]) !== 0)
                continue
            usada[i] = true
            hallada = true
            break
        }
        if (!hallada)
            return false
    }
    return true
}

// La escalera, sobre un texto ya normalizado y ya partido en palabras.
function scoreText(text, ws, query, qw) {
    if (!text)
        return 0
    if (text === query)
        return W.exact
    if (text.indexOf(query) === 0)
        return W.prefix
    if (wordStarts(ws, query) || initials(ws, query))
        return W.wordStart
    // Mismo peldaño que una palabra suelta: acertar tres trozos de tres
    // palabras distintas es tan buena señal como acertar una entera.
    if (qw && phraseMatch(ws, qw))
        return W.wordStart
    if (text.indexOf(query) !== -1)
        return W.substring
    var f = fuzzy(ws, query)
    return f > 0 ? f * W.fuzzy : 0
}

// Forma pública, para quien tenga texto crudo y una sola cosa que puntuar.
function textScore(text, query) {
    var t = norm(text)
    var qw = query.indexOf(" ") !== -1 ? splitWords(query) : null
    return scoreText(t, splitWords(t), query, qw)
}

// ── Frecencia ───────────────────────────────────────────────────────────────
// Frecuencia CON memoria del cuándo. Cada uso vale más cuanto más reciente:
// hoy cuenta entero, ayer casi entero, y lo de hace un mes ya casi no pesa.
// La vida media son diez días — bastante para que lo de la semana pasada siga
// contando, poco para que lo del año pasado mande.
//
// 'stats' es { count, last } con 'last' en milisegundos.
function frecency(stats, now) {
    if (!stats || !stats.count)
        return 0
    var days = Math.max(0, (now - (stats.last || 0)) / 86400000)
    var decay = Math.pow(0.5, days / 10)
    // Raíz sobre el contador: la diferencia entre 1 y 4 usos importa mucho más
    // que entre 100 y 400. Sin ella, un puñado de apps muy usadas aplastarían
    // el ranking para siempre.
    var weight = Math.sqrt(stats.count) * decay
    return Math.min(W.frecencyMax, weight * 300)
}

// ── Puntuación de un elemento ───────────────────────────────────────────────
// item: { id, name, subtitle, keywords: [], type }
// Normaliza y parte los campos de un elemento UNA vez y se lo guarda encima.
// Sin esto, cada pulsación repetía el NFD y el split de cada candidato: con
// 2.500 emojis eran ~30.000 normalizaciones por tecla, todas del mismo texto.
// El caché vive en el propio elemento, así que muere con él — y las fuentes
// crean elementos nuevos cuando cambia el catálogo, así que no se queda viejo.
function prep(item) {
    var p = item._p
    if (p)
        return p
    p = { name: norm(item.name), sub: norm(item.subtitle), kw: null }
    p.nameW = splitWords(p.name)
    p.subW = p.sub ? splitWords(p.sub) : []
    if (item.keywords && item.keywords.length) {
        p.kw = []
        for (var i = 0; i < item.keywords.length; i++) {
            var t = norm(item.keywords[i])
            p.kw.push({ t: t, w: splitWords(t) })
        }
    }
    item._p = p
    return p
}

// item: { id, name, subtitle, keywords: [], type }
function score(item, query, qw, stats, now) {
    if (!item)
        return 0
    var bonus = W.type[item.type] || 0

    // Sin consulta manda el uso: es la lista de "lo de siempre" que uno espera
    // al abrir el buscador sin escribir nada.
    if (!query)
        return bonus + frecency(stats, now) * 2

    var p = prep(item)
    var best = scoreText(p.name, p.nameW, query, qw)

    if (best === 0 && p.sub)
        best = scoreText(p.sub, p.subW, query, qw) * W.subtitleFactor

    if (best === 0 && p.kw) {
        for (var i = 0; i < p.kw.length; i++) {
            var k = scoreText(p.kw[i].t, p.kw[i].w, query, qw)
            if (k > 0) {
                best = k * W.keywordFactor
                break
            }
        }
    }

    // Sin coincidencia NO hay resultado, por mucho que se haya usado. Un
    // buscador que enseña lo que no has pedido deja de ser un buscador.
    if (best === 0)
        return 0

    return best + bonus + frecency(stats, now)
}

// ── Ordenación ──────────────────────────────────────────────────────────────
// statsFor(id) devuelve { count, last } o null.
function rank(items, query, statsFor, now, limit) {
    var q = norm(query)
    // Las palabras de la consulta se parten AQUÍ, una vez por búsqueda. Dentro
    // de score() sería una vez por candidato: el mismo split repetido miles de
    // veces para un texto de dos palabras que no cambia.
    var qw = q.indexOf(" ") !== -1 ? splitWords(q) : null
    var when = now || Date.now()
    var out = []
    for (var i = 0; i < items.length; i++) {
        var it = items[i]
        var s = score(it, q, qw, statsFor ? statsFor(it.id) : null, when)
        if (s > 0)
            out.push({ item: it, score: s, order: i })
    }
    // Desempate por el orden de entrada: sin él, dos elementos con la misma
    // puntuación pueden salir en un orden u otro según cómo ordene el motor, y
    // la lista baila entre pulsaciones aunque no cambie nada.
    out.sort(function (a, b) {
        return b.score - a.score || a.order - b.order
    })
    if (limit && out.length > limit)
        out = out.slice(0, limit)
    return out
}

// ── Prefijos de modo ────────────────────────────────────────────────────────
// Un carácter al principio acota la búsqueda a un tipo. Es más rápido que
// apuntar a una ficha con el ratón y no hay que soltar el teclado.
//
//   =  calcular      >  comando       :  emoji
//   /  archivo       ?  ajustes       @  portapapeles
//
// Se devuelve también el texto SIN el prefijo, que es lo que hay que buscar.
// El "?" de ajustes se retiró: los ajustes salen en el modo general, así que
// el prefijo solo servía para EXCLUIR todo lo demás — y nadie abre un buscador
// para ver únicamente ajustes. Los otros cinco sí ganan algo acotando (una
// cuenta, un emoji, un comando, el portapapeles, un archivo).
var PREFIXES = { "=": "calc", ">": "command", ":": "emoji",
                 "/": "file", "@": "clipboard" }

function parseQuery(raw) {
    var text = String(raw === undefined || raw === null ? "" : raw)
    var head = text.charAt(0)
    var mode = PREFIXES[head]
    if (mode) {
        // TODOS los prefijos se quitan, "/" incluido.
        //
        // El "/" se conservaba con la idea de que "/etc/hosts" se leyera como
        // ruta absoluta y no como el archivo "etc/hosts". Nunca llegó a
        // funcionar —Services/FileSearch le quita la barra igualmente en
        // _limpia(), y fd/find solo recorren $HOME, así que a /etc no se
        // llegaba de ninguna manera— y a cambio rompía lo que sí importa:
        //
        // esta cadena es la que Spotlight le pasa a rank(), y rank descarta
        // todo lo que puntúe 0. Buscar "/script.sh" comparaba "/script.sh"
        // contra el nombre "script.sh", puntuaba 0, y el archivo que fd
        // acababa de encontrar se tiraba a la basura sin decir nada.
        return { mode: mode, text: text.substring(1).trim(), prefixed: true }
    }
    return { mode: "", text: text.trim(), prefixed: false }
}

// ── Calculadora ─────────────────────────────────────────────────────────────
// Evaluador propio de expresiones aritméticas. NUNCA eval(): lo que se teclea
// en un buscador va a parar aquí, y `eval` convertiría la barra de búsqueda en
// una consola con los permisos del shell — basta pegar algo copiado de una web
// para que se ejecute. Esto solo entiende números y seis operadores; cualquier
// otra cosa no es que falle, es que no existe.
//
// Analizador descendente recursivo sobre una lista de símbolos:
//   expr   := term (('+' | '-') term)*
//   term   := unary (('*' | '/' | '%') unary)*
//   unary  := ('-' | '+')? power
//   power  := atom ('^' unary)?          (asociativo a la derecha)
//   atom   := número | '(' expr ')'
function tokenizeMath(src) {
    var out = []
    var i = 0
    var s = String(src).replace(/,/g, ".")
    while (i < s.length) {
        var c = s.charAt(i)
        if (c === " " || c === "\t") { i++; continue }
        if ("+-*/%^()".indexOf(c) !== -1) { out.push(c); i++; continue }
        if (c >= "0" && c <= "9" || c === ".") {
            var j = i
            while (j < s.length && (s.charAt(j) >= "0" && s.charAt(j) <= "9" || s.charAt(j) === "."))
                j++
            var num = parseFloat(s.substring(i, j))
            if (!isFinite(num))
                return null
            out.push(num)
            i = j
            continue
        }
        return null      // cualquier otro carácter: no es una expresión
    }
    return out
}

function calc(src) {
    var t = tokenizeMath(src)
    if (!t || t.length === 0)
        return null
    var pos = 0

    function peek() { return pos < t.length ? t[pos] : null }
    function eat(x) { if (peek() === x) { pos++; return true } return false }

    function atom() {
        if (eat("(")) {
            var v = expr()
            if (v === null || !eat(")")) return null
            return v
        }
        var p = peek()
        if (typeof p === "number") { pos++; return p }
        return null
    }
    function power() {
        var base = atom()
        if (base === null) return null
        if (eat("^")) {
            var e = unary()
            if (e === null) return null
            return Math.pow(base, e)
        }
        return base
    }
    function unary() {
        if (eat("-")) { var v = unary(); return v === null ? null : -v }
        if (eat("+")) return unary()
        return power()
    }
    function term() {
        var v = unary()
        if (v === null) return null
        for (;;) {
            if (eat("*")) { var r = unary(); if (r === null) return null; v = v * r }
            else if (eat("/")) {
                var d = unary()
                if (d === null) return null
                // Dividir por cero da Infinity en JS y eso se pintaría como un
                // resultado: no lo es.
                if (d === 0) return null
                v = v / d
            }
            else if (eat("%")) {
                var m = unary()
                if (m === null || m === 0) return null
                v = v % m
            }
            else return v
        }
    }
    function expr() {
        var v = term()
        if (v === null) return null
        for (;;) {
            if (eat("+")) { var a = term(); if (a === null) return null; v = v + a }
            else if (eat("-")) { var b = term(); if (b === null) return null; v = v - b }
            else return v
        }
    }

    var value = expr()
    // Sobra algún símbolo → la expresión no era válida entera ("2+3 4").
    if (value === null || pos !== t.length || !isFinite(value))
        return null
    return value
}

// Formato del resultado: sin decimales de más y sin notación científica salvo
// cuando de verdad hace falta.
function formatNumber(n) {
    if (!isFinite(n))
        return ""
    var abs = Math.abs(n)

    // Más allá del entero seguro de JavaScript, los dígitos SON MENTIRA:
    // 1e20 + 1 === 1e20, así que enseñar "100000000000000000000" da una
    // exactitud que no existe. Una calculadora que miente es peor que una que
    // dice "≈1e20". Por debajo del límite, los enteros salen enteros.
    if (Number.isInteger(n) && abs <= Number.MAX_SAFE_INTEGER)
        return String(n)
    if (abs !== 0 && (abs < 1e-6 || abs > Number.MAX_SAFE_INTEGER))
        return n.toExponential(6).replace(/\.?0+e/, "e")

    // toFixed(10) y luego parseFloat: quita la basura del coma flotante
    // (0.1 + 0.2 = 0.30000000000000004) sin dejar ceros de relleno detrás.
    return String(parseFloat(n.toFixed(10)))
}
