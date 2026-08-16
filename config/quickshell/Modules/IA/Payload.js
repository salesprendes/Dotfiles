// El historial que VIAJA al modelo, y la traducción de una fila del ListModel a
// objeto plano. Dos operaciones puramente estructurales: entra el hilo tal como
// lo guarda el harness y sale el array de mensajes del contrato OpenAI. Sin
// red, sin estado, sin QML — el ListModel llega como argumento.
.pragma library

// Un mensaje del ListModel como objeto plano con TODOS sus campos. Lo usan la
// instantánea del historial y la cola de compactación: cada uno llevaba su copia
// de la lista, y añadir un campo obligaba a acertar en tres sitios.
function plainMsg(m) {
    return { role: m.role, content: m.content, reasoning: m.reasoning,
             modelName: m.modelName, ms: m.ms, tokens: m.tokens,
             toolName: m.toolName, toolArgs: m.toolArgs,
             toolId: m.toolId, toolResult: m.toolResult,
             toolStatus: m.toolStatus, attachNote: m.attachNote,
             ts: m.ts, undoPath: m.undoPath, toolBatch: m.toolBatch }
}

// Tope de mensajes como red de seguridad detrás del presupuesto de caracteres.
// El recorte de verdad lo hace el presupuesto (que sale de la ventana real del
// modelo); esto solo evita que un hilo de mil turnos cortos se recorra entero.
const MAX_MENSAJES = 48

// Recorte por DETRÁS y reconstrucción del protocolo de herramientas: cada
// tarjeta resuelta se traduce al par assistant(tool_calls) + tool(result) que
// exige el contrato OpenAI.
//
//   msgs   el ListModel del hilo
//   opts   { charBudget, systemPrompt, images: [base64], advisorNote,
//            keepReasoning, imagesFirst }
function build(msgs, opts) {
    const out = []
    let chars = 0
    let razonados = 0
    let i = msgs.count - 1
    while (i >= 0 && out.length < MAX_MENSAJES) {
        const m = msgs.get(i)
        if (m.role === "tool") {
            // Un LOTE de tarjetas contiguas (el modelo pidió varias de golpe)
            // debe viajar como UN solo mensaje assistant con tool_calls:[N]
            // seguido de N resultados — es lo que exige el contrato. Antes cada
            // tarjeta iba como su propio assistant de una sola llamada: los
            // servidores tolerantes lo tragaban, pero es inválido y a un modelo
            // local lo despista.
            const batch = []
            let tag = null
            while (i >= 0) {
                const t = msgs.get(i)
                if (t.role !== "tool")
                    break
                // Dos RONDAS seguidas sin texto entre medias también son
                // tarjetas contiguas: la marca de lote las separa (los
                // resultados de la primera informaron a la segunda, y ese orden
                // debe conservarse). Historiales viejos sin marca se agrupan por
                // contigüidad, como antes.
                const tb = String(t.toolBatch || "")
                if (tag !== null && tb !== tag)
                    break
                tag = tb
                if (t.toolStatus !== "pending")
                    batch.unshift({ id: t.toolId, name: t.toolName,
                                    args: t.toolArgs, result: t.toolResult,
                                    content: t.content })
                i--
            }
            if (batch.length === 0)
                continue
            const calls = []
            let said = ""
            for (let k = 0; k < batch.length; k++) {
                calls.push({ id: batch[k].id, type: "function",
                             "function": { name: batch[k].name,
                                           arguments: batch[k].args } })
                if (batch[k].content !== "")
                    said = batch[k].content
                // Lo que pesa en agente son las herramientas: sus argumentos y
                // resultados cuentan contra el presupuesto igual que la prosa, o
                // el recorte se queda corto.
                chars += batch[k].args.length + batch[k].result.length
            }
            for (let k = batch.length - 1; k >= 0; k--)
                out.unshift({ role: "tool", tool_call_id: batch[k].id,
                              content: batch[k].result })
            out.unshift({ role: "assistant", content: said,
                          tool_calls: calls })
            if (chars > opts.charBudget && out.length > 0)
                break
            continue
        }
        if (m.role !== "user" && m.role !== "assistant") {
            i--
            continue
        }
        chars += m.content.length
        if (chars > opts.charBudget && out.length > 0)
            break
        // Su propio razonamiento de vuelta: hay modelos (Qwen 3.8) que saben
        // retomar una tarea larga donde la dejaron si se lo devuelves, en vez de
        // volver a razonarla entera. Solo los DOS últimos turnos suyos: el
        // razonamiento pesa mucho más que la respuesta, y el de hace seis turnos
        // ya no describe el problema que tiene delante.
        if (opts.keepReasoning && m.role === "assistant"
                && String(m.reasoning || "") !== "" && razonados < 2) {
            razonados++
            chars += m.reasoning.length
            out.unshift({ role: m.role, content: m.content,
                          reasoning_content: m.reasoning })
            i--
            continue
        }
        out.unshift({ role: m.role, content: m.content })
        i--
    }
    // Las imágenes del turno en curso se cuelgan del último mensaje de usuario,
    // en el formato multimodal del contrato.
    const imgs = opts.images || []
    if (imgs.length > 0)
        for (let k = out.length - 1; k >= 0; k--)
            if (out[k].role === "user") {
                // El orden importa en algunas familias: Gemma 4 pide
                // expresamente las imágenes ANTES del texto. Es la clase de
                // detalle que no cuesta nada respetar y que cambia el
                // resultado; los demás siguen recibiéndolas detrás.
                const fotos = []
                for (let j = 0; j < imgs.length; j++)
                    fotos.push({ type: "image_url", image_url: {
                        url: "data:image/png;base64," + imgs[j] } })
                const texto = { type: "text", text: out[k].content }
                out[k] = { role: "user",
                           content: opts.imagesFirst ? fotos.concat([texto])
                                                     : [texto].concat(fotos) }
                break
            }
    // La observación del supervisor viaja PEGADA al prompt de sistema y no como
    // un segundo mensaje 'system' a mitad del array: eso último es válido en el
    // contrato pero hay servidores que lo ignoran o lo reordenan, y una opinión
    // que a veces llega no sirve de nada.
    out.unshift({ role: "system", content: opts.systemPrompt
        + (opts.advisorNote && opts.advisorNote !== ""
           ? "\n\n" + opts.advisorNote : "") })
    return out
}

// ── El transporte ────────────────────────────────────────────────────────────
// Cómo sale la petición de esta máquina. Estaba en una línea —curl con la
// cabecera de autorización y `-d <json entero>` en los argumentos— y esa línea
// tenía dos problemas, uno de seguridad y otro que rompía el harness sin más:
//
//   · TODO iba en el argv, que en Linux es de LECTURA PÚBLICA a través de
//     /proc/<pid>/cmdline. Cualquier proceso de la máquina podía leer la clave
//     de API y, de paso, la conversación entera: el prompt, el historial, los
//     resultados de herramientas y lo que hubiera dentro de ellos.
//   · Y el argv tiene un tope POR ARGUMENTO de 128 kB (MAX_ARG_STRLEN, 32
//     páginas). Medido: 130 kB pasa, 200 kB devuelve E2BIG. O sea que adjuntar
//     una captura —cien kilobytes largos en base64— o llegar a una conversación
//     de treinta y dos mil componentes hacía que la petición fallara antes de
//     salir. No era un riesgo teórico: era un fallo que ya estaba ahí.
//
// El entorno NO vale como sustituto: tiene el mismo límite (comprobado, 200 kB
// también revienta). Así que el cuerpo entra por la ENTRADA ESTÁNDAR y el shell
// lo vuelca a un temporal con umask 077, y las cabeceras van por un fichero de
// configuración de curl escrito por el propio shell — el mismo patrón que ya
// usaban las claves de Brave y Kagi en la búsqueda.
//
// Lo que queda en el argv es lo que no es secreto: las banderas y la URL.
const SH_ENVIO = [
    'umask 077',
    'c=$(mktemp) || exit 97',
    'f=$(mktemp) || { rm -f "$c"; exit 97; }',
    'trap \'rm -f "$c" "$f"\' EXIT INT TERM',
    '{',
    '  printf \'header = "Content-Type: application/json"\\n\'',
    '  [ -n "$QS_AUTH" ] && printf \'header = "Authorization: Bearer %s"\\n\' "$QS_AUTH"',
    '  [ -n "$QS_HDR" ] && printf \'header = "%s"\\n\' "$QS_HDR"',
    '  [ -n "$QS_TITLE" ] && printf \'header = "X-Title: Quickshell"\\n\'',
    '} > "$c"',
    // Si quien llama no cierra su entrada, esto esperaría para siempre y la
    // conversación se quedaría muda sin decir por qué. Quince segundos y un
    // código propio: un cuelgue diagnosticable es infinitamente mejor que un
    // cuelgue mudo.
    'timeout 15 cat > "$f" || exit 98',
    'curl -sS $QS_FLAGS -K "$c" -d @"$f" "$QS_URL"'
].join("\n")

// Las comillas dentro de un valor romperían el fichero de configuración de curl,
// que las usa para delimitar. La cabecera extra la escribe el usuario y la clave
// puede ser cualquier cosa: se escapan las dos.
function _cfgVal(v) {
    // El salto de línea es el separador del fichero de configuración de curl,
    // igual que la comilla es su delimitador. Escapar solo las comillas dejaba
    // que un valor con un "\n" dentro CERRARA la línea y escribiera directivas
    // nuevas: otra cabecera, un --output, un proxy. Se cortan los saltos y los
    // retornos de carro (que en HTTP son media inyección de cabecera por sí
    // solos) antes de escapar nada más.
    return String(v || "").replace(/[\r\n]+/g, " ")
                          .replace(/\\/g, "\\\\").replace(/"/g, '\\"')
}

// o = { url, maxTime, stream, bearer, extraHeader, title, netFlags }
// Devuelve { cmd, env, body }: el cuerpo lo escribe quien llama en la entrada
// estándar del proceso, y CIERRA la entrada al terminar.
function transport(req, o) {
    const flags = ["--connect-timeout", "15",
                   "--max-time", String(o.maxTime || 300),
                   "-X", "POST"]
        .concat(o.stream ? ["-N", "--no-buffer"] : [])
        .concat(o.netFlags || [])
    return {
        cmd: ["sh", "-c", SH_ENVIO],
        env: { QS_URL: String(o.url || ""),
               QS_FLAGS: flags.join(" "),
               QS_AUTH: _cfgVal(o.bearer),
               QS_HDR: _cfgVal(o.extraHeader),
               QS_TITLE: o.title ? "1" : "" },
        body: JSON.stringify(req)
    }
}

// Qué le pasó al transporte, dicho para que se pueda arreglar. Los dos códigos
// propios son del shell de arriba; el resto los pone curl.
function transportError(code) {
    if (code === 97)
        return "no se pudo crear el archivo temporal de la petición (¿disco lleno?)"
    if (code === 98)
        return "la petición no llegó a enviarse: el cuerpo no terminó de escribirse"
    return ""
}

// Una consulta GET con las mismas credenciales, para la sonda del catálogo de
// modelos. No lleva cuerpo, así que no tiene el problema del tamaño — pero la
// clave iba igualmente en el argv, y una clave a la vista es una clave a la
// vista aunque la petición sea pequeña. Mismo fichero de configuración, misma
// jaula, y así "Probar" sigue probando EXACTAMENTE lo que va a viajar.
const SH_SONDA = [
    'umask 077',
    'c=$(mktemp) || exit 97',
    'trap \'rm -f "$c"\' EXIT INT TERM',
    '{',
    '  [ -n "$QS_AUTH" ] && printf \'header = "Authorization: Bearer %s"\\n\' "$QS_AUTH"',
    '  [ -n "$QS_HDR" ] && printf \'header = "%s"\\n\' "$QS_HDR"',
    '  [ -n "$QS_TITLE" ] && printf \'header = "X-Title: Quickshell"\\n\'',
    '} > "$c"',
    'curl -sS --max-time 15 $QS_FLAGS -K "$c" -w "\\n__QS %{http_code}" "$QS_URL"'
].join("\n")

function probeTransport(o) {
    return {
        cmd: ["sh", "-c", SH_SONDA],
        env: { QS_URL: String(o.url || ""),
               QS_FLAGS: (o.netFlags || []).join(" "),
               QS_AUTH: _cfgVal(o.bearer),
               QS_HDR: _cfgVal(o.extraHeader),
               QS_TITLE: o.title ? "1" : "" }
    }
}
