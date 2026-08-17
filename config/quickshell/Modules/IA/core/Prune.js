// REDUCIR EL CONTEXTO SIN MODELO. Tres operaciones deterministas que van antes
// —y a veces en lugar— de pagar un resumen:
//
//   · PODAR: sustituir el resultado de una herramienta por su cabecera cuando ya
//     no hace falta verlo literalmente (lo dejó viejo una lectura posterior, el
//     archivo cambió desde entonces, la llamada se repitió igual).
//   · SACUDIR: elidir bloques enormes de código o XML dentro de CUALQUIER
//     mensaje —no solo de las tarjetas— y dejar en su sitio la ruta del archivo
//     donde se guardó, que el agente puede volver a leer. Archivar, no resumir.
//   · PESAR: contar lo que ocupa un hilo exactamente igual que lo cuentan el
//     medidor del panel y el recorte del historial.
//
// LA CACHÉ DE PREFIJO MANDA SOBRE TODO ESTO. Cambiar un mensaje a mitad del
// historial obliga al servidor a reprocesar TODO lo que va detrás: en un
// servidor local eso es volver a hacer el prefill (segundos de espera en el
// turno siguiente), y en uno de pago es la prima de escritura de caché. Así que
// podar en el prefijo profundo puede costar más de lo que ahorra. De ahí las
// tres reglas que gobiernan cuándo se toca algo:
//
//   1. AHORRO MÍNIMO: si lo que se gana no compensa romper la caché, no se toca.
//   2. SUFIJO BARATO: solo se poda donde queda poco detrás que reprocesar.
//   3. PURGA EN FRÍO: cuando la caché ya está fría —o cuando quien llama va a
//      reescribir el hilo entero de todos modos, como la compactación— las dos
//      reglas anteriores se levantan y se poda a fondo.
//
// Todo aquí es JavaScript puro sobre objetos planos (los de PL.plainMsg): ni
// red, ni QML, ni estado. Por eso se puede probar entero desde node.
.pragma library

// ── Qué herramienta habla de qué archivo ─────────────────────────────────────
// Solo las que nombran UN archivo concreto. glob_files, grep_files y ast_search
// reciben una carpeta tan a menudo como un archivo, y meter carpetas en el
// recuento de archivos tocados lo convierte en ruido.
const FICHERO = {
    read_file:  { campo: "path",  modo: "r" },
    read_files: { campo: "paths", modo: "r" },
    lsp:        { campo: "path",  modo: "r" },
    lsp_raw:    { campo: "path",  modo: "r" },
    write_file: { campo: "path",  modo: "w" },
    edit_file:  { campo: "path",  modo: "w" },
    edit_patch: { campo: "path",  modo: "w" },
    edit_lines: { campo: "path",  modo: "w" },
    ast_edit:   { campo: "path",  modo: "w" },
    lsp_rename: { campo: "path",  modo: "w" },
    lsp_fix:    { campo: "path",  modo: "w" }
}

// Herramientas cuyo resultado NO es una salida: es una decisión, un plan, una
// lección o el resumen de toda una rama de trabajo. Podarlas no ahorra
// contexto, borra memoria. La de un subagente es el caso más claro: ese texto
// YA es la compactación de una investigación entera.
const NUNCA = {
    propose_plan: 1, ask_user: 1, todo_write: 1, notify_user: 1,
    learn: 1, remember: 1, memory_update: 1, memory_forget: 1,
    subagent: 1, use_skill: 1
}

// Marcas de que algo salió mal. Se buscan SOLO en los bordes del resultado: un
// archivo de código con la palabra "error" dentro no es un fallo, pero un
// comando que falla lo dice al principio o al final.
const FALLOS = [
    "Traceback (most recent call last)", "command not found",
    "No such file or directory", "Permission denied", "Operation not permitted",
    "error:", "Error:", "ERROR", "fatal:", "Segmentation fault",
    "Falló", "falló", "No se pudo", "no se pudo", "denegad", "rechazad",
    "se agotó el tiempo", "timed out", "Timeout"
]

// Cuántas tarjetas recientes son intocables. Es una regla DURA, no una
// puntuación: lo que el modelo tiene delante ahora mismo no se toca por muy
// mal que puntúe, porque es justo lo que está usando.
const PROTEGIDOS = 6
// Por debajo de esto no hay nada que ganar y sí algo que perder.
const MINIMO = 500
// A partir de aquí el tamaño pesa en la decisión.
const GORDA = 4000
// Lo que se conserva del principio: bastante para reconocer qué había, poco
// para que no cueste.
const CABEZA = 200
// Cuánto tiene que llevar parada la conversación para dar la caché por fría.
// El proveedor con retención más larga que se usa aquí guarda una hora
// (Anthropic "long"); purgar antes de eso reventaría un prefijo todavía
// caliente, que es justo lo que la purga quiere evitar.
const FRIA_MS = 3600000

function _args(s) {
    try {
        const o = JSON.parse(String(s || ""))
        return (o && typeof o === "object") ? o : ({})
    } catch (e) { return ({}) }
}

function _norm(p) {
    const s = String(p === undefined || p === null ? "" : p).trim()
    return s.length > 1 && s.charAt(s.length - 1) === "/" ? s.slice(0, -1) : s
}

// Las rutas de las que habla una llamada.
function rutas(nombre, args) {
    const d = FICHERO[nombre]
    if (!d)
        return []
    const o = _args(args)
    if (d.campo === "paths") {
        const a = o.paths
        if (!Array.isArray(a))
            return []
        const out = []
        for (let i = 0; i < a.length; i++) {
            const p = _norm(a[i])
            if (p !== "")
                out.push(p)
        }
        return out
    }
    const p = _norm(o[d.campo])
    return p === "" ? [] : [p]
}

// "r", "w" o "" si no habla de un archivo. Un edit_patch con dry_run MIRA, no
// escribe: contarlo como escritura diría que el archivo cambió cuando no.
function modo(nombre, args) {
    const d = FICHERO[nombre]
    if (!d)
        return ""
    if (d.modo === "w" && _args(args).dry_run === true)
        return "r"
    return d.modo
}

// ── La clave de supersesión ──────────────────────────────────────────────────
// QUÉ LECTURA DEJA VIEJA A CUÁL. La versión anterior daba por superada cualquier
// lectura cuyo archivo se volviera a mirar después, y eso destrozaba el caso más
// normal del harness: read_file admite offset/limit y su propia salida termina
// diciendo «sigue con offset=401». Leer un archivo grande por tramos es EL
// camino previsto, y con la regla vieja los tres primeros tramos se borraban
// como si fueran copias rancias del cuarto.
//
// La clave lleva por eso dos partes: la base (el archivo, la operación) y un
// selector opcional (el tramo). Y la regla es la de oh-my-pi:
//
//   · misma clave exacta  → la anterior está superada
//   · una lectura SIN selector supera a las que sí lo llevan del mismo archivo
//     (leerlo entero deja viejos todos sus tramos)
//   · dos tramos distintos NO se tocan
//
// Devuelve "" cuando la herramienta no participa (ahí manda 'duplicada', que es
// la comparación literal de nombre + argumentos).
function claveLectura(nombre, args) {
    const o = _args(args)
    if (nombre === "read_file") {
        const p = _norm(o.path)
        if (p === "")
            return ""
        const off = parseInt(o.offset)
        const lim = parseInt(o.limit)
        const tramo = (off > 0 || lim > 0)
            ? (off > 0 ? off : 1) + "-" + (lim > 0 ? lim : "")
            : ""
        // 'numbered' cambia la FORMA del texto, no el trozo: una lectura
        // numerada y otra sin numerar del mismo tramo se superan entre sí.
        return tramo === "" ? p : p + "\u0000" + tramo
    }
    if (nombre === "read_files") {
        const rs = rutas(nombre, args)
        return rs.length === 0 ? "" : rs.slice().sort().join("\u0001")
    }
    if (nombre === "lsp") {
        const p = _norm(o.path)
        return p === "" ? "" : p + "\u0001" + String(o.op || "")
    }
    if (nombre === "list_dir") {
        const p = _norm(o.path)
        return p === "" ? "" : "dir:" + p
    }
    return ""
}

function _base(clave) {
    const i = clave.indexOf("\u0000")
    return i < 0 ? clave : clave.slice(0, i)
}

function _falla(txt) {
    const bordes = txt.slice(0, 300) + "\n" + txt.slice(-300)
    for (let i = 0; i < FALLOS.length; i++)
        if (bordes.indexOf(FALLOS[i]) !== -1)
            return true
    return false
}

// ── Contabilidad de archivos ─────────────────────────────────────────────────
// Qué se leyó y qué se tocó, contado por el harness. Va al resumen COMO DATO,
// no como pregunta al modelo: pedirle a un modelo que recuerde la lista de
// archivos que tocó es pedirle que la invente a la tercera compactación.
//
//   → [{ ruta, modo: "R"|"W"|"RW", lecturas, escrituras, ultimo }]
//     lo tocado más tarde primero, que es lo que sigue en juego.
function ficheros(msgs) {
    const mapa = ({})
    const orden = []
    for (let i = 0; i < msgs.length; i++) {
        const m = msgs[i]
        // Una tarjeta rechazada no pasó: contarla diría que el archivo cambió.
        if (m.role !== "tool" || m.toolStatus !== "done")
            continue
        const md = modo(m.toolName, m.toolArgs)
        if (md === "")
            continue
        const rs = rutas(m.toolName, m.toolArgs)
        for (let k = 0; k < rs.length; k++) {
            const p = rs[k]
            if (!mapa[p]) {
                mapa[p] = { ruta: p, lecturas: 0, escrituras: 0, ultimo: i }
                orden.push(p)
            }
            if (md === "w")
                mapa[p].escrituras++
            else
                mapa[p].lecturas++
            mapa[p].ultimo = i
        }
    }
    const out = []
    for (let i = 0; i < orden.length; i++) {
        const f = mapa[orden[i]]
        f.modo = f.escrituras > 0 ? (f.lecturas > 0 ? "RW" : "W") : "R"
        out.push(f)
    }
    out.sort(function (a, b) { return b.ultimo - a.ultimo })
    return out
}

function _cuenta(n, uno, varios) {
    return n + " " + (n === 1 ? uno : varios)
}

// El bloque de texto que viaja al resumen y se pega tal cual al resultado.
function bloqueFicheros(fichs, tope) {
    if (!fichs || fichs.length === 0)
        return ""
    const n = Math.max(1, tope || 24)
    const lineas = []
    for (let i = 0; i < fichs.length && i < n; i++) {
        const f = fichs[i]
        const c = []
        if (f.lecturas > 0)
            c.push(_cuenta(f.lecturas, "lectura", "lecturas"))
        if (f.escrituras > 0)
            c.push(_cuenta(f.escrituras, "escritura", "escrituras"))
        lineas.push((f.modo + "  ").slice(0, 3) + " " + f.ruta
                    + "  (" + c.join(", ") + ")")
    }
    if (fichs.length > n)
        lineas.push("… y " + (fichs.length - n) + " archivo(s) más")
    return lineas.join("\n")
}

// ── El peso ──────────────────────────────────────────────────────────────────
// Lo que ocupa un hilo en el contexto, contado EXACTAMENTE como lo cuentan el
// medidor del panel y el recorte del historial: si aquí se contara de otra
// manera, la decisión de "ya cabe" se tomaría con una regla distinta de la que
// dijo "no cabe".
function pesar(msgs) {
    let c = 0
    for (let i = 0; i < msgs.length; i++)
        c += pesarUno(msgs[i])
    return c
}

function pesarUno(m) {
    if (m.role === "user" || m.role === "assistant")
        return String(m.content || "").length
    if (m.role === "tool" && m.toolStatus !== "pending")
        return String(m.toolArgs || "").length + String(m.toolResult || "").length
    return 0
}

// Cuánto queda DETRÁS de cada mensaje. Es la factura de tocarlo: el servidor
// tiene que reprocesar todo eso si el prefijo cambia aquí.
function sufijos(msgs) {
    const s = new Array(msgs.length)
    let acc = 0
    for (let i = msgs.length - 1; i >= 0; i--) {
        s[i] = acc
        acc += pesarUno(msgs[i])
    }
    return s
}

// ¿Está fría la caché? Con la conversación parada más de una hora, el prefijo
// que el servidor tenía guardado ya no existe, así que reescribirlo es gratis y
// se puede podar a fondo. 'ahora' y las marcas vienen en milisegundos; una marca
// ausente (historial viejo, sin el campo) no se toma por antigua: no saberlo no
// es lo mismo que saber que está frío.
function friaDesde(msgs, ahora, tope) {
    let ultima = 0
    for (let i = msgs.length - 1; i >= 0; i--) {
        const at = Number(msgs[i].at || 0)
        if (at > 0) {
            ultima = at
            break
        }
    }
    if (ultima <= 0)
        return false
    return (ahora - ultima) >= (tope === undefined ? FRIA_MS : tope)
}

// ── El plan de poda ──────────────────────────────────────────────────────────
// Puntúa cada tarjeta que NO esté protegida por una regla dura y poda las que
// no llegan a cero. Los números salen de una idea sencilla: lo que cuesta caro
// volver a averiguar puntúa alto (un fallo, un cambio escrito, algo en lo que
// se apoyó una llamada posterior) y lo que ya está contestado en otra parte
// puntúa negativo (una llamada repetida, una lectura que otra posterior deja
// vieja, una lectura de un archivo que se ha modificado desde entonces).
//
// No hay reglas para "resultado vacío" ni "búsqueda sin resultados" pese a ser
// candidatos obvios: por debajo de MINIMO no se toca nada, y esos casos siempre
// caen ahí. Una regla que no puede dispararse nunca es peor que no tenerla —
// para eso está ahora la bandera 'toolUseless', que la pone la propia
// herramienta al terminar y sí sabe si su salida informó de algo.
//
//   msgs   el hilo entero como objetos planos
//   opts   { protegidos, minimo, gorda, cabeza,
//            sufijoMaximo   solo podar donde quede menos que esto detrás
//                           (undefined = sin guardia: quien llama va a
//                           reescribir el hilo igualmente)
//            ahorroMinimo   no tocar nada si el total ahorrado no llega aquí }
//   →      { marcas: {índice: textoRecortado}, ahorro, podados, tarjetas,
//            frenado: "" | "ahorro" }
function planificar(msgs, opts) {
    const o = opts || ({})
    const prot = o.protegidos === undefined ? PROTEGIDOS : o.protegidos
    const min = o.minimo === undefined ? MINIMO : o.minimo
    const gorda = o.gorda === undefined ? GORDA : o.gorda
    const cabeza = o.cabeza === undefined ? CABEZA : o.cabeza
    const ahorroMinimo = o.ahorroMinimo === undefined ? 0 : o.ahorroMinimo

    const cartas = []
    for (let i = 0; i < msgs.length; i++)
        if (msgs[i].role === "tool")
            cartas.push(i)

    const intocable = ({})
    for (let k = Math.max(0, cartas.length - prot); k < cartas.length; k++)
        intocable[cartas[k]] = true

    // Una sola pasada saca todo lo que hace falta saber del hilo, y luego cada
    // candidata se decide mirando tablas. La versión ingenua —por cada tarjeta,
    // recorrer todas las posteriores buscando su ruta dentro del resultado— es
    // cuadrática sobre textos de cien kilobytes, y compactar es justo el momento
    // en que el hilo es más grande.
    //
    //   escritos     archivos escritos alguna vez: siguen en juego
    //   ultimaEscr   última tarjeta que ESCRIBIÓ esa ruta
    //   ultimoUso    última tarjeta que nombra esa ruta (para 'referida')
    //   ultimaClave  última tarjeta con esa clave de lectura
    //   ultimaIgual  última tarjeta con exactamente la misma llamada
    const escritos = ({})
    const ultimaEscr = ({})
    const ultimoUso = ({})
    const ultimaClave = ({})
    const ultimaIgual = ({})
    const suyas = []
    const claves = []
    for (let k = 0; k < cartas.length; k++) {
        const m = msgs[cartas[k]]
        const rs = rutas(m.toolName, m.toolArgs)
        suyas.push(rs)
        const cl = claveLectura(m.toolName, m.toolArgs)
        claves.push(cl)
        const escribe = modo(m.toolName, m.toolArgs) === "w"
        for (let j = 0; j < rs.length; j++) {
            ultimoUso[rs[j]] = k
            if (escribe) {
                escritos[rs[j]] = true
                ultimaEscr[rs[j]] = k
            }
        }
        if (cl !== "")
            ultimaClave[cl] = k
        ultimaIgual[m.toolName + " " + m.toolArgs] = k
    }
    const todasLasRutas = Object.keys(ultimoUso)

    const sufijo = o.sufijoMaximo === undefined ? null : sufijos(msgs)

    const marcas = ({})
    let ahorro = 0
    let podados = 0
    for (let k = 0; k < cartas.length; k++) {
        const i = cartas[k]
        const m = msgs[i]
        if (m.toolStatus !== "done" || NUNCA[m.toolName])
            continue
        const res = String(m.toolResult || "")
        // La bandera la pone la herramienta al terminar: ella sabe si su salida
        // informó de algo (cero coincidencias, ningún diagnóstico, nada nuevo en
        // el trabajo). Un resultado así no vale nada a ninguna edad, así que se
        // salta la ventana protegida — pero no la guardia de caché.
        const inutil = m.toolUseless === true && !_falla(res)
        if (intocable[i] && !inutil)
            continue
        if (res.length < min)
            continue
        // GUARDIA DE CACHÉ: tocar esto obliga al servidor a reprocesar todo lo
        // que va detrás. Si eso es mucho, sale más caro que lo que ahorra.
        if (sufijo !== null && sufijo[i] > o.sufijoMaximo)
            continue

        const mias = suyas[k]
        const cl = claves[k]
        // Lo que viene DESPUÉS es lo que decide si esto sigue haciendo falta.
        const duplicada = ultimaIgual[m.toolName + " " + m.toolArgs] > k
        // Superada: otra lectura posterior la deja vieja. Con la misma clave
        // exacta, o con la clave BASE cuando esta lleva selector (leer el
        // archivo entero deja viejos sus tramos, pero un tramo no deja viejo a
        // otro tramo distinto).
        let superada = false
        if (cl !== "") {
            const b = _base(cl)
            superada = ultimaClave[cl] > k || (b !== cl && ultimaClave[b] > k)
        }
        // Desfasada: el archivo se ESCRIBIÓ después de esta lectura, así que
        // este texto ya no es lo que hay en disco. No es que sobre: es que
        // miente, y eso vale para cualquier tramo.
        let desfasada = false, viva = false, referida = false
        for (let j = 0; j < mias.length; j++) {
            if (escritos[mias[j]])
                viva = true
            if (ultimaEscr[mias[j]] !== undefined && ultimaEscr[mias[j]] > k
                    && modo(m.toolName, m.toolArgs) === "r")
                desfasada = true
        }
        for (let j = 0; j < todasLasRutas.length; j++) {
            const p = todasLasRutas[j]
            // Una ruta AJENA, usada después, que aparece en este resultado: la
            // llamada posterior salió de aquí. Es el caso del grep que dice
            // dónde mirar — ese sí hay que conservarlo.
            if (ultimoUso[p] > k && mias.indexOf(p) === -1
                    && res.indexOf(p) !== -1) {
                referida = true
                break
            }
        }
        const error = _falla(res)
        const escribe = modo(m.toolName, m.toolArgs) === "w"
        const puntos = (error ? 5 : 0) + (escribe ? 4 : 0) + (referida ? 4 : 0)
                     + (viva ? 3 : 0) - (duplicada ? 5 : 0) - (superada ? 5 : 0)
                     - (desfasada ? 5 : 0) - (res.length > gorda ? 2 : 0)
                     - (inutil ? 8 : 0)
        if (puntos > 0)
            continue

        const trozo = inutil ? "" : res.slice(0, cabeza)
        const motivo = inutil ? " (la herramienta no encontró nada)"
                     : desfasada ? " (ese archivo cambió después de leerlo)"
                     : superada ? " (ese archivo se volvió a mirar después)"
                     : duplicada ? " (esa misma llamada se repitió después)" : ""
        const corte = trozo + (trozo !== "" && res.length > trozo.length ? "\n" : "")
                    + "[… " + (res.length - trozo.length)
                    + " caracteres recortados al compactar" + motivo
                    + "; vuelve a pedirlo si lo necesitas]"
        // Un recorte que engorda no es un recorte.
        if (corte.length >= res.length)
            continue
        marcas[i] = corte
        ahorro += res.length - corte.length
        podados++
    }
    // AHORRO MÍNIMO: romper la caché de prefijo tiene un precio fijo; si lo que
    // se gana no lo compensa, es mejor no tocar nada. Se decide con el total,
    // no tarjeta a tarjeta, porque el precio se paga UNA vez.
    if (ahorro < ahorroMinimo)
        return { marcas: ({}), ahorro: 0, podados: 0,
                 tarjetas: cartas.length, frenado: "ahorro", posible: ahorro }
    return { marcas: marcas, ahorro: ahorro, podados: podados,
             tarjetas: cartas.length, frenado: "", posible: ahorro }
}

// El hilo con el plan aplicado, sin tocar el original.
function aplicar(msgs, plan) {
    const out = []
    for (let i = 0; i < msgs.length; i++) {
        const corte = plan.marcas[i]
        if (corte === undefined) {
            out.push(msgs[i])
            continue
        }
        const c = ({})
        for (const k in msgs[i])
            c[k] = msgs[i][k]
        c.toolResult = corte
        out.push(c)
    }
    return out
}

// ── Sacudir ──────────────────────────────────────────────────────────────────
// Lo que la poda no alcanza: un bloque de código de veinte mil caracteres que el
// USUARIO pegó, o que el modelo escribió en su respuesta. No es el resultado de
// ninguna herramienta, así que ninguna regla de arriba lo mira, y sin embargo
// suele ser lo más gordo del hilo.
//
// Aquí no se resume ni se tira: se ARCHIVA. El bloque se guarda en un archivo y
// en su lugar queda la ruta, que el agente puede volver a leer con read_file. Es
// la diferencia entre perder el detalle y aparcarlo.
const BLOQUE_MINIMO = 2000

// Los tramos [inicio, fin) de los bloques cercados (``` o ~~~) de un texto.
// Conservador a propósito: un cerco sin cerrar no da tramo — mejor no tocar que
// cortar por la mitad.
function bloques(texto) {
    const out = []
    let dentro = false, ini = -1, pos = 0
    while (pos <= texto.length) {
        let fin = texto.indexOf("\n", pos)
        if (fin === -1)
            fin = texto.length
        const linea = texto.slice(pos, fin)
        const t = linea.replace(/^\s+/, "")
        if (t.indexOf("```") === 0 || t.indexOf("~~~") === 0) {
            if (!dentro) {
                dentro = true
                ini = pos
            } else {
                dentro = false
                out.push({ ini: ini, fin: fin })
                ini = -1
            }
        }
        if (fin === texto.length)
            break
        pos = fin + 1
    }
    return out
}

// Qué se puede sacudir de un hilo: bloques grandes dentro del texto de mensajes
// de usuario y de asistente. Las tarjetas NO entran aquí — de esas se encarga la
// poda, que sabe cuáles siguen haciendo falta.
//
//   →  [{ idx, ini, fin, texto }]  en orden de documento
function sacudibles(msgs, opts) {
    const o = opts || ({})
    const min = o.minimo === undefined ? BLOQUE_MINIMO : o.minimo
    const prot = o.protegidos === undefined ? 2 : o.protegidos
    const corte = Math.max(0, msgs.length - prot)
    const out = []
    for (let i = 0; i < corte; i++) {
        const m = msgs[i]
        if (m.role !== "user" && m.role !== "assistant")
            continue
        const t = String(m.content || "")
        if (t.length < min)
            continue
        const bs = bloques(t)
        for (let k = 0; k < bs.length; k++) {
            const largo = bs[k].fin - bs[k].ini
            if (largo < min)
                continue
            out.push({ idx: i, ini: bs[k].ini, fin: bs[k].fin,
                       texto: t.slice(bs[k].ini, bs[k].fin) })
        }
    }
    return out
}

// Sustituye los tramos de un mensaje por sus marcas. Se aplican de ATRÁS hacia
// delante: al revés, el primer reemplazo desplazaría las posiciones de los
// siguientes y el segundo cortaría donde no es.
function sacudir(texto, tramos) {
    const orden = tramos.slice().sort(function (a, b) { return b.ini - a.ini })
    let t = texto
    for (let i = 0; i < orden.length; i++)
        t = t.slice(0, orden[i].ini) + orden[i].marca + t.slice(orden[i].fin)
    return t
}

// La marca que queda en el hueco: dice qué había, cuánto ocupaba y —lo único
// que importa de verdad— cómo recuperarlo.
function marcaArchivo(largo, ruta) {
    return "[bloque de " + largo + " caracteres archivado en " + ruta
         + " — léelo con read_file si lo necesitas]"
}
