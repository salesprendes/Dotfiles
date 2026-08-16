// Quién puede hacer qué, y cuándo hay que preguntar. Es la política de
// aprobación del harness ENTERA, y vive fuera del singleton por dos razones:
// no toca nada de QML (son listas y comparaciones) y es exactamente el tipo de
// regla que uno quiere poder leer de un vistazo sin bucear en tres mil líneas.
//
// La idea de fondo (tomada de OpenWorker) es que la aprobación NO se decide
// herramienta por herramienta sino por CLASE DE RIESGO: el usuario dice hasta
// dónde llega el agente y el harness reparte. Poner una fila por herramienta
// era pedirle que repitiera cuarenta veces la misma decisión.
.pragma library

// ── Clases de riesgo ─────────────────────────────────────────────────────────
// El harness ha crecido (shell, git, MCP, LSP, depurador, Python, REPL,
// trabajos, red, subagentes): esto ya NO es una comodidad, es la pieza de
// seguridad. Cinco clases y un principio: la aprobación se decide por lo que
// una herramienta PUEDE HACER, no por su nombre.
//
//   read      no cambia nada — la tarjeta puede saltarse
//   external  efecto FUERA del equipo pero sin destruir (abrir URL, buscar,
//             delegar): aprobable "para siempre" en la conversación
//   write     modifica archivos (locales o remotos): SIEMPRE pregunta
//   exec      ejecuta comandos / actúa sobre servicios: SIEMPRE pregunta
//   critical  poder ARBITRARIO sobre el equipo (shell, ssh, Python): NUNCA se
//             auto-aprueba, ni en modo auto ni con una excepción del usuario.
//             Es la línea que un agente muy capaz no debe poder cruzar solo.
// Y dos clases que no son riesgo sino PAUSA: preguntar y proponer plan.
const RIESGO_ESCRITURA = ["write_file", "edit_file", "edit_lines", "edit_patch",
                          // La memoria del usuario también es un archivo suyo:
                          // cambiar o borrar una nota es escribir, aunque no lo
                          // parezca por el nombre. Estaban cayendo en "read".
                          "remember", "memory_update", "memory_forget",
                          "sftp_get", "sftp_put",
                          "lsp_rename", "ast_edit", "lsp_fix", "lsp_raw"]
// CRÍTICAS: ejecutan código o comandos ARBITRARIOS. Un run_command puede hacer
// cualquier cosa que el resto de clases hace por separado —y más—, así que su
// aprobación no se delega jamás en el modo ni en un "permitir siempre". El
// usuario ve cada una. python_exec y debug_eval evalúan expresiones que llegan
// a todo el proceso; ssh_exec es un shell remoto.
const RIESGO_CRITICO   = ["run_command", "ssh_exec", "python_exec", "debug_eval"]
// job_input y job_ctl son EJECUCIÓN aunque parezcan menores: teclear en un
// proceso vivo es actuar sobre el equipo (y por eso el usuario ve el texto
// EXACTO en la tarjeta antes de que entre), y una señal puede tumbar trabajo.
const RIESGO_EJECUCION = ["service_ctl", "kill_process", "debug_start",
                          "job_start", "job_input", "job_ctl"]
// debug_ctl actúa sobre una sesión que el usuario YA aprobó al arrancarla:
// external permite el "Siempre" de la conversación, que es lo que hace
// llevadero avanzar paso a paso.
const RIESGO_EXTERNO   = ["open_url", "fetch_url", "web_search", "subagent",
                          "debug_ctl"]

// La heurística que clasifica una herramienta MCP por su NOMBRE: un servidor
// puede publicar cualquier cosa, y tratarlas todas como "external" era optimista
// —un mcp__db__execute_sql o un mcp__fs__delete no son "abrir una URL". Lo que
// suena a lectura se queda en external; el resto sube a exec (pregunta siempre).
const MCP_LECTURA = /(^|_)(get|list|read|find|search|query|fetch|show|describe|lookup|count|status|info|view|inspect)($|_)/i
function _mcpClass(name) {
    const corto = String(name).replace(/^mcp__[^_]*__/, "")
    return MCP_LECTURA.test(corto) ? "external" : "exec"
}

// Herramientas de contabilidad del propio harness: no tocan el equipo, y pedir
// permiso para ellas convertiría cada turno en un formulario. Leer una
// habilidad que el usuario instaló es leer el manual, no actuar.
const CONTABILIDAD = ["use_skill", "todo_write", "notify_user", "learn"]

const MODOS = ["careful", "normal", "auto"]

function riskClass(name) {
    // Preguntar no es un efecto: es una pausa. Clase propia para que la tarjeta
    // se pinte como pregunta y nunca se auto-apruebe ni se permita "siempre"
    // (un permiso permanente sobre preguntar sería responder solo).
    if (name === "ask_user")
        return "ask"
    if (name === "propose_plan")
        return "plan"
    if (String(name).startsWith("mcp__"))
        return _mcpClass(name)
    if (RIESGO_CRITICO.indexOf(name) !== -1)
        return "critical"
    if (RIESGO_EJECUCION.indexOf(name) !== -1)
        return "exec"
    if (RIESGO_ESCRITURA.indexOf(name) !== -1)
        return "write"
    if (RIESGO_EXTERNO.indexOf(name) !== -1)
        return "external"
    return "read"
}

// El nivel numérico de riesgo (0..4), para la auditoría y para que la UI lo
// pinte de un vistazo. Es la misma escala que pidió el usuario:
//   0 read       automático
//   1 external   automático + registro
//   2 write      aprobación
//   3 exec       aprobación
//   4 critical   nunca automático
// (ask y plan son pausas, no riesgo: nivel -1, jamás automáticas.)
const NIVEL = ({ read: 0, external: 1, write: 2, exec: 3, critical: 4,
                 ask: -1, plan: -1 })
function riskLevel(name) {
    const n = NIVEL[riskClass(name)]
    return n === undefined ? 0 : n
}

// ¿Se puede ofrecer "permitir siempre en esta conversación"? Solo si no
// destruye ni ejecuta: leer y los externos benignos. Es la regla de OpenWorker
// que adopto — "el shell pregunta para siempre". Lo crítico queda fuera por
// definición: no hay permiso permanente que valga para un shell.
function canStandingAllow(name) {
    const r = riskClass(name)
    return r === "read" || r === "external"
}

// ¿Puede esta herramienta ejecutarse SIN que el humano lo vea, alguna vez? Lo
// crítico nunca — es la garantía dura, independiente del modo y de cualquier
// excepción que el usuario haya podido poner. Es la línea que un agente capaz
// no cruza solo.
function neverAuto(name) {
    return riskClass(name) === "critical"
}

// ── El plazo de cada herramienta ─────────────────────────────────────────────
// Cuánto se espera a que UNA llamada termine antes de darla por colgada.
//
// Por qué hace falta. Hasta ahora no había ningún reloj: el ejecutor arrancaba
// el proceso y esperaba a que saliera, y de los treinta y dos constructores de
// comando solo TRES traían su propio `timeout`. Un `find` sobre un montaje de
// red caído, un `du` en un árbol enorme, un SSH a una máquina que se traga los
// paquetes: la tarjeta se quedaba en "Ejecutando…" para siempre. Y como solo
// corre una herramienta a la vez, eso no colgaba una llamada — colgaba el turno.
//
// El plazo va por NOMBRE y no por clase de riesgo, porque el riesgo no dice
// nada de lo que tarda algo: `read_file` y `disk_query` son las dos "lectura", y
// una contesta en un milisegundo y la otra puede recorrerte el disco. La clase
// solo sirve de red para lo que no esté en la lista (una herramienta MCP nueva,
// por ejemplo).
//
// Los números son generosos a propósito. Esto no es un ajuste de rendimiento:
// es el interruptor que impide que algo se quede colgado para siempre, y matar
// un trabajo legítimo por apretar el reloj sería cambiar un fallo raro por otro
// peor y más frecuente.
const PLAZO_S = ({
    // Red y máquinas ajenas.
    web_search: 50, fetch_url: 30, open_url: 10,
    ssh_exec: 90, server_status: 60, server_logs: 60, hosting_query: 90,
    sftp_ls: 60, sftp_get: 300, sftp_put: 300,
    // Las que pueden recorrer medio disco.
    glob_files: 45, grep_files: 45, ast_search: 45, ast_edit: 60,
    list_dir: 30, read_files: 45, disk_query: 60, package_query: 90,
    journal_query: 45, process_query: 30, network_query: 45,
    // Las que hablan con un proceso de larga vida que ya está levantado.
    lsp: 45, lsp_fix: 45, lsp_raw: 45, lsp_rename: 60,
    debug_start: 60, debug_eval: 60, debug_ctl: 60, debug_view: 30,
    // Una celda de Python puede ser un cálculo de verdad. Tres minutos es lo que
    // separa "esto tarda" de "esto no va a terminar nunca".
    python_exec: 180,
    // Los trabajos en segundo plano se lanzan y se sueltan: lo que se espera
    // aquí es el arranque, no el trabajo.
    job_start: 30, job_ctl: 30, job_view: 30, job_list: 20, job_input: 20,
    // Un subagente trae SU propio reloj (600 s como mucho). Esto es la red por
    // debajo de esa red: solo salta si aquel no ha llegado a sonar.
    subagent: 660,
    // El comando del usuario ya va envuelto en `timeout 20` dentro del shell.
    run_command: 40
})
const PLAZO_CLASE = ({ read: 30, external: 60, write: 45, exec: 60, critical: 60 })
function deadlineMs(name) {
    const s = PLAZO_S[name]
    if (s !== undefined)
        return s * 1000
    // Un servidor MCP es de otro: puede tardar lo que quiera, y no hay forma de
    // saber cuánto es razonable. Un minuto es suficiente para lo que contesta y
    // corto para lo que no va a contestar.
    if (String(name).startsWith("mcp__"))
        return 60000
    const c = PLAZO_CLASE[riskClass(name)]
    return (c === undefined ? 30 : c) * 1000
}

// El texto que ve el MODELO cuando se le corta una llamada. Importa que diga
// tres cosas: que fue el reloj y no la herramienta, cuánto esperó, y qué hacer
// distinto. Sin lo tercero, un modelo pequeño vuelve a llamar exactamente igual.
function deadlineText(name, ms) {
    const seg = Math.round(ms / 1000)
    return "La herramienta " + name + " no terminó en " + seg + " segundos y se "
         + "ha cortado. NO es un error de tus argumentos ni de la herramienta: "
         + "es que estaba tardando demasiado.\n"
         + "Si la vuelves a usar, ACOTA el trabajo — una carpeta más concreta, "
         + "menos resultados, un patrón más estrecho, un archivo en vez de un "
         + "árbol entero. Repetir la misma llamada dará el mismo corte."
}

// El modo efectivo, tolerante con un ajuste corrompido o de una versión vieja.
function mode(setting) {
    return MODOS.indexOf(setting) !== -1 ? setting : "normal"
}

// Lo que el modo concede a cada clase de riesgo. Lo que no aparece, pregunta.
function modeGrants(modo, risk) {
    if (modo === "auto")
        return risk !== "ask"          // preguntar nunca se auto-responde
    if (modo === "normal")
        return risk === "read"
    return false                        // careful: hasta leer se pregunta
}

// Lo que dicta el modo para una herramienta SIN excepciones de por medio. Lo
// consultan la política efectiva y el guardado de excepciones: antes cada uno
// llevaba su copia del mismo cálculo, y divergir aquí significaría que el
// contador de excepciones mintiera.
function naturalPolicy(name, modo) {
    // Lo crítico jamás es automático, diga lo que diga el modo.
    if (neverAuto(name))
        return "ask"
    if (CONTABILIDAD.indexOf(name) !== -1)
        return "auto"
    return modeGrants(modo, riskClass(name)) ? "auto" : "ask"
}

// Política efectiva: la excepción del usuario manda; si no hay, decide el modo
// sobre la clase de riesgo. La ÚNICA excepción a "la excepción manda": un
// usuario no puede poner "auto" sobre una herramienta crítica — apagarla (off)
// sí, dejarla en preguntar sí, pero auto-aprobar un shell para siempre, no. Es
// una salvaguarda contra un permiso concedido a la ligera que luego se olvida.
function policy(name, modo, overrides) {
    const over = (overrides || {})[name]
    if (over === "off")
        return "off"
    if (over === "auto" && neverAuto(name))
        return "ask"
    if (over === "ask" || over === "auto")
        return over
    return naturalPolicy(name, modo)
}

// Cuántas excepciones hay puestas: el panel lo enseña para que un permiso
// olvidado no viva escondido bajo un modo que dice otra cosa.
function overrideCount(overrides) {
    const p = overrides || {}
    let n = 0
    for (const k in p)
        if (p[k] === "ask" || p[k] === "auto" || p[k] === "off")
            n++
    return n
}

// Guardar una excepción. El modo ya dice lo que hace falta: una que COINCIDE
// con él no se guarda, se borra. Así el contador dice la verdad y volver al
// valor de siempre limpia de verdad en vez de dejar rastro. Devuelve el mapa
// nuevo (quien llama lo asigna al ajuste).
function withOverride(overrides, name, v, modo) {
    const p = Object.assign({}, overrides)
    if (v === naturalPolicy(name, modo))
        delete p[name]
    else
        p[name] = v
    return p
}

// ── Subagentes: la CONCESIÓN ─────────────────────────────────────────────────
// Un subagente no es "otro chat con las mismas herramientas". Es un trabajador
// con una concesión explícita: qué familias alcanza y dentro de qué paredes.
// Aquí vive el "qué"; las paredes las pone AgentWorkspace.
//
// Cuatro reglas que no se negocian:
//
//   1. Nunca alcanza lo CRÍTICO ni lo de EJECUCIÓN. Un subagente corre sin
//      tarjetas —esa es su razón de ser—, y un bucle autónomo con shell tiraría
//      abajo todo lo que se construyó en la política. Ni en modo auto, ni con
//      una excepción del usuario, ni pidiéndolo.
//   2. Nunca más que su jefe: lo que el usuario apagó, el subagente tampoco lo
//      tiene.
//   3. Escribir es una concesión APARTE y se aprueba a mano: un subagente con
//      escritura nace de una tarjeta, no de un modo permisivo.
//   4. No delega. La recursión de subagentes no tiene fondo ni presupuesto.
const SUB_ESCRITURA = ["write_file", "edit_file", "edit_patch"]
const SUB_RED = ["fetch_url", "web_search"]
// Lo que no toca ni pidiéndolo: delegar (regla 4), la memoria del jefe —que es
// del usuario y del hilo, no del encargo— y las pausas, que solo significan
// algo frente a un humano que está mirando.
const SUB_NUNCA = ["subagent", "remember", "memory_update", "memory_forget",
                   "learn", "ask_user", "propose_plan", "use_skill",
                   "todo_write", "notify_user"]

// Las capacidades, en el orden en que crecen. "read" siempre está.
const CAPS = ["read", "net", "write"]

// Lo que trae puesto cada papel cuando el jefe no pide capacidades a mano. Un
// investigador necesita la red; un revisor de código, no (y dársela solo
// alarga el encargo). El constructor es el único que nace con escritura, y aun
// así confinada y con tarjeta.
const ROL_CAPS = ({
    research: { net: true,  write: false },
    review:   { net: false, write: false },
    debug:    { net: false, write: false },
    build:    { net: false, write: true }
})
const SUB_ROLES = ["research", "review", "debug", "build"]

// La concesión efectiva. 'requested' es lo que pidió el modelo (array o null);
// modo y overrides son los del usuario, para la regla 2.
function subagentGrant(role, requested, modo, overrides) {
    const base = ROL_CAPS[role] || ROL_CAPS.research
    const g = { read: true, net: base.net === true, write: base.write === true,
                denied: [] }
    if (Array.isArray(requested)) {
        g.net = requested.indexOf("net") !== -1
        g.write = requested.indexOf("write") !== -1
    }
    // Regla 2, herramienta por herramienta: si el usuario apagó write_file pero
    // dejó edit_file, el subagente pierde una y conserva la otra. Y si pierde
    // todas las de una familia, la capacidad entera se cae —así la tarjeta no
    // anuncia un permiso que luego no existe.
    const mirar = SUB_ESCRITURA.concat(SUB_RED)
    for (let i = 0; i < mirar.length; i++)
        if (policy(mirar[i], modo, overrides) === "off")
            g.denied.push(mirar[i])
    if (g.write && _todasFuera(SUB_ESCRITURA, g.denied))
        g.write = false
    if (g.net && _todasFuera(SUB_RED, g.denied))
        g.net = false
    return g
}
function _todasFuera(nombres, denied) {
    for (let i = 0; i < nombres.length; i++)
        if (denied.indexOf(nombres[i]) === -1)
            return false
    return true
}

// ¿Alcanza este subagente esta herramienta? La única puerta: la consultan el
// catálogo que se le anuncia al modelo y el constructor de comandos, de modo
// que no puede haber una herramienta anunciada que luego no ejecute ni —lo que
// importa— una ejecutable que no estuviera anunciada.
function subagentAllows(name, grant) {
    if (!grant)
        return false
    if (SUB_NUNCA.indexOf(name) !== -1)
        return false
    if ((grant.denied || []).indexOf(name) !== -1)
        return false
    const r = riskClass(name)
    if (r === "read")
        return true
    if (r === "external")
        return grant.net === true && SUB_RED.indexOf(name) !== -1
    if (r === "write")
        return grant.write === true && SUB_ESCRITURA.indexOf(name) !== -1
    return false                       // critical, exec, ask, plan: jamás
}

// Las capacidades concedidas, para pintarlas. Códigos, no texto: la traducción
// es de la interfaz.
function grantCaps(grant) {
    const out = ["read"]
    if (grant && grant.net)
        out.push("net")
    if (grant && grant.write)
        out.push("write")
    return out
}

// ¿Tiene que verlo el usuario antes de arrancar? Escribir sí, siempre: es la
// única capacidad que deja rastro en el disco, y una tarjeta al nacer sustituye
// a las veinte que no habrá después.
function grantNeedsApproval(grant) {
    return !!(grant && grant.write)
}
