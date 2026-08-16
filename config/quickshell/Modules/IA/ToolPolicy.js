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
// Cuatro clases, de menor a mayor:
//   read      no cambia nada — la tarjeta puede saltarse
//   external  efecto FUERA del equipo pero sin destruir (abrir URL, buscar,
//             delegar, herramientas MCP): aprobable "para siempre" en la
//             conversación
//   write     modifica archivos (locales o remotos): SIEMPRE pregunta
//   exec      ejecuta comandos / actúa sobre servicios: SIEMPRE pregunta
// Y dos clases que no son riesgo sino PAUSA: preguntar y proponer plan.
const RIESGO_ESCRITURA = ["write_file", "edit_file", "edit_lines",
                          "remember", "sftp_get", "sftp_put",
                          "lsp_rename", "ast_edit", "lsp_fix", "lsp_raw"]
// job_input y job_ctl son EJECUCIÓN aunque parezcan menores: teclear en un
// proceso vivo es actuar sobre el equipo (y por eso el usuario ve el texto
// EXACTO en la tarjeta antes de que entre), y una señal puede tumbar trabajo.
const RIESGO_EJECUCION = ["run_command", "ssh_exec", "service_ctl",
                          "kill_process", "python_exec", "debug_start",
                          "job_start", "job_input", "job_ctl"]
// debug_ctl y debug_eval actúan sobre una sesión que el usuario YA aprobó al
// arrancarla (debug_start es exec): external permite el "Siempre" de la
// conversación, que es justo lo que hace llevadero avanzar paso a paso.
const RIESGO_EXTERNO   = ["open_url", "fetch_url", "web_search", "subagent",
                          "debug_ctl", "debug_eval"]

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
        return "external"
    if (RIESGO_EJECUCION.indexOf(name) !== -1)
        return "exec"
    if (RIESGO_ESCRITURA.indexOf(name) !== -1)
        return "write"
    if (RIESGO_EXTERNO.indexOf(name) !== -1)
        return "external"
    return "read"
}

// ¿Se puede ofrecer "permitir siempre en esta conversación"? Solo si no
// destruye ni ejecuta: leer y los externos benignos. Es la regla de OpenWorker
// que adopto — "el shell pregunta para siempre".
function canStandingAllow(name) {
    const r = riskClass(name)
    return r === "read" || r === "external"
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
    if (CONTABILIDAD.indexOf(name) !== -1)
        return "auto"
    return modeGrants(modo, riskClass(name)) ? "auto" : "ask"
}

// Política efectiva: la excepción del usuario manda; si no hay, decide el modo
// sobre la clase de riesgo.
function policy(name, modo, overrides) {
    const over = (overrides || {})[name]
    if (over === "ask" || over === "auto" || over === "off")
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
