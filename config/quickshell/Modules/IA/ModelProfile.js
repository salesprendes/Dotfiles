// QUÉ SABE HACER EL MODELO QUE HAY DELANTE.
//
// Un harness que trata a todos los modelos igual acaba mandando a todos el
// mínimo común denominador. Aquí se reconoce la familia por su id y se saca lo
// que ese modelo concreto admite: cuánto contexto, si piensa y CÓMO se le
// regula, con qué parámetros de muestreo lo recomiendan sus autores, si ve
// imágenes y en qué orden las quiere.
//
// LA REGLA QUE NO SE ROMPE: un modelo que no se reconoce se lleva el perfil
// GENÉRICO, y con el genérico el harness se comporta EXACTAMENTE como antes de
// que este archivo existiera. Nada de lo de aquí toca a nadie que no esté
// nombrado. Por eso todo lo específico está detrás de `family !== ""` y por eso
// las funciones de abajo devuelven su entrada intacta cuando no hay perfil.
//
// ── Lo que se aprende leyendo cuatro familias seguidas ───────────────────────
// No hay UNA forma de encender el pensamiento. Hay tres, y ninguna se parece:
//
//   kwargs    Qwen 3.6 y 3.8 — un objeto en la petición
//             ("chat_template_kwargs": {"enable_thinking": true})
//   sysline   Muse Glimmer — una línea DENTRO del prompt de sistema
//             ("Reasoning strength: xhigh")
//   systoken  Gemma 4 — un token al PRINCIPIO del prompt de sistema ("<|think|>")
//
// Por eso el perfil no dice "piensa sí o no" sino POR DÓNDE se le dice, y hay
// dos funciones de aplicación: tune() toca la petición y systemFor() toca el
// prompt. Un modelo nuevo se añade rellenando una ficha, no tocando el harness.
.pragma library

const GENERICO = ({
    family: "",              // "" = desconocido
    label: "",
    // none = no piensa · optional = se le puede apagar · always = siempre piensa
    thinking: "none",
    thinkVia: "",            // kwargs | sysline | systoken
    thinkToken: "",          // el token, si va por systoken
    // Niveles de esfuerzo que admite ([] = no tiene esa palanca)
    efforts: [],
    effortVia: "",           // field | sysline
    effortLine: "",          // la plantilla de la línea, si va por sysline
    // ¿El servidor entiende chat_template_kwargs?
    templateKwargs: false,
    // ¿Sabe reaprovechar SU PROPIO razonamiento de turnos anteriores?
    preserveThinking: false,
    vision: false,
    video: false,
    // ¿Quiere las imágenes ANTES del texto? (Gemma 4 lo pide expresamente)
    imagesFirst: false,
    ctx: 0,                  // 0 = que decida la heurística de siempre
    maxOut: 0,               // 0 = no se manda max_tokens
    rounds: 0,               // 0 = el tope de herramientas de siempre
    sampling: null,          // null = manda la temperatura del usuario
    // Los interruptores de texto "/think" y "/no_think" de Qwen3. Los modelos
    // con bandera propia no los quieren: ahí solo serían ruido en el mensaje.
    softSwitch: true
})

function _perfil(extra) {
    const p = ({})
    for (const k in GENERICO)
        p[k] = GENERICO[k]
    for (const k in extra)
        p[k] = extra[k]
    return p
}

// ── Qwen 3.8 ─────────────────────────────────────────────────────────────────
// Dos modelos con contratos distintos, y la diferencia importa: al de 2.4T no
// se le pueden mandar imágenes (es solo texto) ni se le puede apagar el
// pensamiento. Mandarle una captura sería un error del servidor, y el usuario
// vería "algo falló" sin saber por qué.
//
// Muestreo: son los valores que recomiendan sus autores, y en un Qwen no son un
// detalle — con la temperatura equivocada el mismo modelo pasa de resolver la
// tarea a irse por las ramas. Hay dos juegos porque pensando y sin pensar
// quieren cosas distintas.
const Q38_PENSANDO = ({ temperature: 1.0, top_p: 0.95, top_k: 20, min_p: 0.0,
                        presence_penalty: 0.0, repetition_penalty: 1.0 })
const Q38_DIRECTO  = ({ temperature: 0.7, top_p: 0.80, top_k: 20, min_p: 0.0,
                        presence_penalty: 1.5, repetition_penalty: 1.0 })

// ── Qwen 3.6 ─────────────────────────────────────────────────────────────────
// La generación anterior: mismo mecanismo de pensamiento (kwargs) y la misma
// ventana enorme, pero SIN reasoning_effort — esa palanca la estrena 3.8. Su
// ficha solo fija temperatura, top_p y top_k; lo que no dice, no se manda.
const Q36_PENSANDO = ({ temperature: 1.0, top_p: 0.95, top_k: 20 })
const Q36_DIRECTO  = ({ temperature: 0.7, top_p: 0.80, top_k: 20 })

// ── Muse Glimmer y Gemma 4 ───────────────────────────────────────────────────
// Curiosamente coinciden en el muestreo (temp 1.0 / top_p 0.95 / top_k 64) y en
// no distinguir entre pensar y no pensar: un solo juego para todo.
const TOP64 = ({ temperature: 1.0, top_p: 0.95, top_k: 64 })

const RE_Q38 = /qwen-?3\.8\b/i
const RE_Q36 = /qwen-?3\.6\b/i
// El Qwen 3.8 de 2.4T (95B activos): la mezcla de expertos grande, solo texto.
const RE_Q38_MOE = /2\.4t|a95b/i
const RE_MUSE = /muse[-_ ]?glimmer/i
const RE_GEMMA4 = /gemma-?4\b/i
// Los pequeños de Gemma 4 (embeddings por capa, pensados para el dispositivo):
// la mitad de ventana que sus hermanos mayores.
const RE_GEMMA4_E = /\be[24]b\b/i
// Los "-assistant" de Muse y de Gemma NO son modelos de chat: son borradores
// para decodificación especulativa (78M, 0,4B, 3B) que vive DENTRO del
// servidor. Si alguien pone uno como modelo, mejor el perfil genérico que
// prometerle las capacidades del hermano grande.
const RE_DRAFTER = /-(assistant|drafter|draft)\b/i

function of(id) {
    const s = String(id || "")
    if (s === "" || RE_DRAFTER.test(s))
        return GENERICO

    if (RE_Q38.test(s)) {
        const moe = RE_Q38_MOE.test(s)
        return _perfil({
            family: "qwen3.8",
            label: moe ? "Qwen 3.8 · 2.4T-A95B" : "Qwen 3.8 · 27B",
            thinking: moe ? "always" : "optional",
            thinkVia: "kwargs",
            efforts: ["low", "medium", "xhigh"],
            effortVia: "field",
            templateKwargs: true,
            preserveThinking: true,
            vision: !moe, video: !moe,
            ctx: 262144,
            // La ficha reparte el presupuesto: hasta 262k para razonar y hasta
            // 131k para la respuesta. Se manda el de respuesta porque muchos
            // servidores traen un tope por defecto ridículo y truncan a mitad
            // de un archivo.
            maxOut: 131072,
            // Está entrenado para tareas largas de varios pasos: ocho rondas de
            // herramientas se le quedan cortas justo cuando empieza a ser útil.
            rounds: 16,
            sampling: ({ think: Q38_PENSANDO, instruct: Q38_DIRECTO }),
            softSwitch: false
        })
    }

    if (RE_Q36.test(s)) {
        return _perfil({
            family: "qwen3.6",
            label: "Qwen 3.6 · " + (/35b|a3b/i.test(s) ? "35B-A3B" : "27B"),
            thinking: "optional",
            thinkVia: "kwargs",
            // Sin reasoning_effort: esa palanca la estrena 3.8. Aquí el
            // pensamiento se enciende y se apaga, y ya.
            efforts: [],
            templateKwargs: true,
            preserveThinking: true,
            vision: true, video: true,
            ctx: 262144,
            // Su ficha da dos cifras: 32k para consultas normales y 82k para
            // problemas complejos (matemáticas, programación). Se manda la
            // grande porque es un TOPE, no una reserva, y el trabajo de este
            // harness es justo el del segundo caso.
            maxOut: 81920,
            rounds: 16,
            sampling: ({ think: Q36_PENSANDO, instruct: Q36_DIRECTO }),
            softSwitch: false
        })
    }

    if (RE_MUSE.test(s)) {
        return _perfil({
            family: "muse",
            label: "Muse Glimmer · 30B",
            // No hay "no pensar": hay CUÁNTO pensar, y el mínimo es 'low'.
            thinking: "always",
            thinkVia: "sysline",
            efforts: ["low", "medium", "high", "xhigh"],
            effortVia: "sysline",
            effortLine: "Reasoning strength: ",
            vision: true,
            // El vídeo lo ve como fotogramas sueltos, no como vídeo: el harness
            // manda imágenes, así que no hay nada que anunciar.
            video: false,
            ctx: 131072,
            rounds: 16,          // multi-paso, recuperación de fallos, horizonte largo
            sampling: ({ think: TOP64, instruct: TOP64 }),
            softSwitch: false
        })
    }

    if (RE_GEMMA4.test(s)) {
        const pequeno = RE_GEMMA4_E.test(s)
        return _perfil({
            family: "gemma4",
            label: "Gemma 4 · " + (pequeno ? "E2B/E4B" : "31B/26B"),
            thinking: "optional",
            thinkVia: "systoken",
            thinkToken: "<|think|>",
            efforts: [],
            vision: true,
            // Su ficha pide expresamente las imágenes ANTES del texto. Es la
            // clase de detalle que no cuesta nada respetar y que cambia el
            // resultado.
            imagesFirst: true,
            ctx: pequeno ? 131072 : 262144,
            rounds: 12,
            sampling: ({ think: TOP64, instruct: TOP64 }),
            softSwitch: false
        })
    }

    return GENERICO
}

// ── Aplicar el perfil a la PETICIÓN ──────────────────────────────────────────
// Devuelve la MISMA petición si el modelo no se reconoce, que es lo que
// garantiza que nada de esto afecte a los demás.
//
//   opts  { thinking: bool|null   pensar en esta llamada (null = sí)
//           effort: "low"|"medium"|"high"|"xhigh"|""
//           tuning: bool          usar el muestreo recomendado
//           keepThinking: bool    reaprovechar su razonamiento anterior
//           maxOut: bool          mandar el tope de salida
//           degraded: {}          lo que este servidor ya rechazó }
function tune(req, p, opts) {
    if (!p || p.family === "")
        return req
    const o = opts || ({})
    const fuera = o.degraded || ({})
    const piensa = _piensa(p, o)

    if (p.thinkVia === "kwargs" && p.templateKwargs && !fuera.templateKwargs) {
        const kw = ({})
        if (p.thinking === "optional")
            kw.enable_thinking = piensa
        // Reaprovechar su propio razonamiento es lo que le permite retomar una
        // tarea larga donde la dejó en vez de volver a razonarla entera.
        if (p.preserveThinking)
            kw.preserve_thinking = !!o.keepThinking
        req.chat_template_kwargs = kw
    }

    // El esfuerzo: la palanca que el harness puede mover mejor que un humano,
    // porque sabe QUÉ está pidiendo en cada momento (ver effortFor). Aquí solo
    // se aplica el que viaja como campo; el que va en el prompt lo pone
    // systemFor.
    if (piensa && p.effortVia === "field" && !fuera.effort) {
        const n = effortLevel(p, o.effort)
        if (n !== "")
            req.reasoning_effort = n
    }

    if (o.tuning !== false && p.sampling && !fuera.sampling) {
        const s = piensa ? p.sampling.think : p.sampling.instruct
        for (const k in s)
            req[k] = s[k]
    }

    if (o.maxOut !== false && p.maxOut > 0 && !fuera.maxOut
            && req.max_tokens === undefined)
        req.max_tokens = p.maxOut

    return req
}

function _piensa(p, o) {
    if (p.thinking === "always")
        return true
    if (p.thinking === "none")
        return false
    return (o.thinking === null || o.thinking === undefined) ? true : !!o.thinking
}

// El nivel que de verdad admite este modelo. Si se le pide uno que no tiene, se
// baja al más cercano por debajo: pedir "xhigh" a quien solo llega a "high" debe
// darle "high", no quedarse sin nada.
function effortLevel(p, querido) {
    const q = String(querido || "")
    if (!p.efforts || p.efforts.length === 0)
        return ""
    if (p.efforts.indexOf(q) !== -1)
        return q
    if (q === "")
        return ""
    const ESCALA = ["low", "medium", "high", "xhigh"]
    let i = ESCALA.indexOf(q)
    if (i === -1)
        return ""
    for (; i >= 0; i--)
        if (p.efforts.indexOf(ESCALA[i]) !== -1)
            return ESCALA[i]
    return p.efforts[0]
}

// ── Aplicar el perfil al PROMPT DE SISTEMA ───────────────────────────────────
// Para las familias que no encienden el pensamiento con un campo de la petición
// sino escribiendo en el propio prompt. Devuelve el texto tal cual si no hay
// nada que añadir.
function systemFor(texto, p, opts) {
    if (!p || p.family === "")
        return texto
    const o = opts || ({})
    if ((o.degraded || ({})).systemHint)
        return texto
    const piensa = _piensa(p, o)
    let s = String(texto)

    // La línea de intensidad de Muse: primero, para que no se pierda entre
    // instrucciones.
    if (piensa && p.effortVia === "sysline") {
        const n = effortLevel(p, o.effort)
        if (n !== "")
            s = p.effortLine + n + "\n" + s
    }
    // El token de Gemma va al PRINCIPIO del todo, y por eso se pone el último:
    // si hubiera línea de intensidad, el token tiene que quedar por delante.
    if (piensa && p.thinkVia === "systoken" && p.thinkToken !== "")
        s = p.thinkToken + "\n" + s
    return s
}

// ── Degradación elegante ─────────────────────────────────────────────────────
// Un servidor OpenAI-compatible puede no entender alguno de estos campos y
// contestar con un 400. La respuesta correcta NO es dejar de mandarlos siempre
// —el que sí los entiende los aprovecha— sino apagar EL QUE MOLESTA en ESTE
// servidor y reintentar. Devuelve la clave a apagar, o "".
function offenderOf(msg) {
    const m = String(msg || "").toLowerCase()
    if (m.indexOf("chat_template_kwargs") !== -1
            || m.indexOf("enable_thinking") !== -1
            || m.indexOf("preserve_thinking") !== -1)
        return "templateKwargs"
    if (m.indexOf("reasoning_effort") !== -1)
        return "effort"
    if (m.indexOf("reasoning_content") !== -1)
        return "reasoning"
    if (m.indexOf("max_tokens") !== -1 || m.indexOf("max tokens") !== -1)
        return "maxOut"
    if (m.indexOf("top_k") !== -1 || m.indexOf("min_p") !== -1
            || m.indexOf("repetition_penalty") !== -1
            || m.indexOf("presence_penalty") !== -1)
        return "sampling"
    return ""
}

// Cómo se llama cada cosa cuando hay que contárselo al usuario.
function offenderLabel(k) {
    switch (k) {
    case "templateKwargs": return "las opciones de plantilla (pensamiento)"
    case "effort":         return "el nivel de esfuerzo de razonamiento"
    case "reasoning":      return "el reenvío de su propio razonamiento"
    case "maxOut":         return "el tope de longitud de respuesta"
    case "sampling":       return "los parámetros de muestreo recomendados"
    case "systemHint":     return "las marcas de pensamiento del prompt"
    }
    return k
}
