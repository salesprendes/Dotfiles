// EL DESPACHADOR, COMO TABLA.
//
// Esto era un `switch` de 37 casos y 367 líneas dentro de approveTool, y el
// tamaño no era lo peor: cada rama decidía por su cuenta cosas que no le
// tocaban —el plazo, el marco del texto ajeno, la bandera de la red de casa—,
// así que "¿esta llamada está bien acotada?" se contestaba leyendo trescientas
// líneas y esperando no saltarse ninguna.
//
// Al mirarlas de cerca, los 37 casos son tres familias con tres formas:
//
//   ASÍNCRONAS   16 casos, todos `gestor.metodo(args, cb)`. Es una TABLA.
//   COMANDOS     12 casos, todos acaban construyendo {cmd, env}. Es una
//                FUNCIÓN PURA, y por eso vive aquí y se puede probar sin QML.
//   EN PROCESO    9 casos que tocan estado del harness (el plan visible, la
//                memoria, el catálogo de habilidades). Esos se quedan en QML
//                porque de verdad son QML.
//
// Lo que sale de aquí NO se ejecuta: se le entrega al ejecutor, que exige un
// permiso de la puerta (security/Gate.js) y es quien pone el reloj, el tope de
// salida y el cerco de enlaces. Aquí solo se construye.
.pragma library
.import "LocalTools.js" as LT
.import "RemoteTools.js" as RT
.import "../TextUtils.js" as TU
.import "../integrations/WebSearch.js" as WS

// ── Las asíncronas ───────────────────────────────────────────────────────────
// Se resuelven cuando su gestor conteste. `gestor` es el nombre de la propiedad
// del ejecutor donde vive (lsp, jobs, dbg, repl), `metodo` el que hay que
// llamar y `op` lo que hay que meterle a los argumentos, si hace falta.
//
// Que sean datos y no código es lo que hace que añadir una operación del
// depurador sea una línea aquí en vez de otro caso en un switch de cuatrocientas.
const ASINCRONAS = {
    lsp:         { gestor: "lsp",  metodo: "request" },
    lsp_rename:  { gestor: "lsp",  metodo: "request", op: "rename" },
    lsp_fix:     { gestor: "lsp",  metodo: "request", op: "fix" },
    lsp_raw:     { gestor: "lsp",  metodo: "request", op: "raw" },
    job_start:   { gestor: "jobs", metodo: "start" },
    job_view:    { gestor: "jobs", metodo: "view" },
    job_input:   { gestor: "jobs", metodo: "input" },
    job_ctl:     { gestor: "jobs", metodo: "ctl" },
    python_exec: { gestor: "repl", metodo: "exec" },
    debug_start: { gestor: "dbg",  metodo: "start" },
    debug_ctl:   { gestor: "dbg",  metodo: "ctl" },
    debug_view:  { gestor: "dbg",  metodo: "view" },
    debug_eval:  { gestor: "dbg",  metodo: "evaluate" }
}

// Los argumentos que le tocan a una asíncrona (con su `op` puesta si la lleva).
function argsAsincrona(nombre, args) {
    const d = ASINCRONAS[nombre]
    if (!d || d.op === undefined)
        return args
    const a = ({})
    for (const k in args)
        a[k] = args[k]
    a.op = d.op
    return a
}

// ── Las que escriben ─────────────────────────────────────────────────────────
// Cuáles dejan copia previa para deshacer, y en qué argumento va la ruta. Lo
// necesita quien llama para apuntar la copia en la tarjeta ANTES de construir:
// el nombre del respaldo es parte del comando.
const ESCRIBEN = {
    write_file: "path", edit_file: "path", edit_patch: "path",
    edit_lines: "path", ast_edit: "path"
}

function rutaDeEscritura(nombre, args) {
    const campo = ESCRIBEN[nombre]
    return campo === undefined ? "" : String((args || ({}))[campo] || "")
}

// edit_patch en seco solo enseña el diff: no hay nada que deshacer, así que no
// se gasta una copia.
function dejaCopia(nombre, args) {
    if (ESCRIBEN[nombre] === undefined)
        return false
    return !(nombre === "edit_patch" && (args || ({})).dry_run === true)
}

const FUERA = "Ruta fuera de la carpeta personal."

// ── Construir el comando ─────────────────────────────────────────────────────
//   nombre  la herramienta
//   args    argumentos ya reparados
//   ctx     { home, toolCtx, bak, undoDir, iaDir, searchCtx, searchBroken }
//
//   →  { cmd, env }   listo para el ejecutor
//      { error }      motivo que vuelve al modelo (no se ejecuta nada)
//      null           esta familia no la construye: pruébese en otra
function construir(nombre, args, ctx) {
    const a = args || ({})
    const c = ctx || ({})
    switch (nombre) {

    case "ast_edit": {
        const p = LT.safePath(a.path, c.home)
        if (p === "") return { error: FUERA }
        return LT.astEdit(a, c.toolCtx, c.bak, c.undoDir)
    }

    // ── Edición anclada por hash: UNA puerta, UN motor ───────────────────────
    // edit_patch es el camino bueno (varios hunks, atómico, con recuperación de
    // anclas) y edit_lines es la puerta estrecha de siempre, traducida a un
    // parche de un solo hunk: así el anclaje vive implementado en UN sitio y no
    // puede divergir entre las dos.
    case "edit_patch": {
        const p = LT.safePath(a.path, c.home)
        if (p === "") return { error: FUERA }
        return LT.hashPatch(a, c.toolCtx, c.bak, c.undoDir, c.iaDir)
    }
    case "edit_lines": {
        const st = parseInt(a.start), en = parseInt(a.end)
        if (!(st >= 1) || !(en >= st))
            return { error: "Rango inválido: start debe ser ≥1 y end ≥ start." }
        const p = LT.safePath(a.path, c.home)
        if (p === "") return { error: FUERA }
        const hunk = {
            op: String(a.text || "") === "" ? "delete" : "replace",
            at: String(st) + (a.start_hash ? "#" + a.start_hash : ""),
            to: String(en) + (a.end_hash ? "#" + a.end_hash : ""),
            text: String(a.text || "")
        }
        return LT.hashPatch({ path: a.path, hunks: [hunk] },
                            c.toolCtx, c.bak, c.undoDir, c.iaDir)
    }
    case "edit_file":
    case "write_file": {
        const p = LT.safePath(a.path, c.home)
        if (p === "") return { error: FUERA }
        return LT.writes(nombre, p, a, c.bak, c.undoDir, c.toolCtx)
    }

    case "run_command": {
        const cmd = a.command || ""
        if (cmd === "") return { error: "Comando vacío." }
        // El comando viaja por ENTORNO, como todo lo demás del harness. En el
        // argv lo leía cualquier proceso de la máquina en /proc/<pid>/cmdline
        // mientras corría, y un comando puede llevar dentro una contraseña que
        // el usuario acaba de dictar.
        //
        // El reloj NO se pone aquí: lo pone la envoltura de la puerta. Hubo un
        // `timeout 20` metido en este comando además del plazo de la política
        // (40 s): ganaba el de dentro, así que la política decía una cosa y
        // pasaba otra. Un plazo que no es el que se anuncia no es un plazo.
        const env = ({ QS_CMD: String(cmd) })
        if (String(a.cwd || "") !== "") {
            // La carpeta de trabajo pasa por la misma jaula que las rutas de
            // las demás herramientas. Sin esto el modelo escribía `cd /x && …`
            // en cada comando, que funciona pero mete un `cd` sin comprobar en
            // todas partes.
            const d = LT.safePath(a.cwd, c.home)
            if (d === "")
                return { error: "La carpeta de trabajo debe estar dentro de la "
                              + "carpeta personal." }
            env.QS_CWD = d
            env.QS_PARED = c.home
            env.QS_P = d          // para que el cerco de enlaces la mire
        }
        return { cmd: ["sh", "-c", LT.SH_MANDATO], env: env }
    }

    case "ssh_exec": {
        const cmd = String(a.command || "").trim()
        if (cmd === "") return { error: "Comando vacío." }
        const r = RT.connect(a, "ssh", "-p", c.toolCtx)
        if (r.error !== undefined) return { error: r.error }
        // El comando remoto viaja como UN argumento a ssh; el shell remoto lo
        // ejecuta tal cual. Es crudo a propósito (por eso lleva tarjeta).
        return { cmd: r.t.argv.concat(["--", cmd + " 2>&1 | tail -c 16000"]),
                 env: r.t.env }
    }

    // Subir y bajar son el mismo scp con el origen y el destino cambiados de
    // sitio: se resuelven juntos para que no puedan divergir.
    case "sftp_get":
    case "sftp_put": {
        const baja = nombre === "sftp_get"
        const local = LT.safePath(a.local_path, c.home)
        if (local === "")
            return { error: (baja ? "El destino" : "El origen")
                          + " local debe estar dentro de tu carpeta personal." }
        const rp = String(a.remote_path || "").trim()
        if (rp === "") return { error: "Falta la ruta remota." }
        const r = RT.connect(a, "scp", "-P", c.toolCtx)
        if (r.error !== undefined) return { error: r.error }
        // scp recibe las rutas como ARGUMENTOS (no dentro de un shell), así que
        // un nombre raro no puede convertirse en otra orden. El último elemento
        // del argv es el user@host; el resto son las opciones.
        const dest = r.t.argv[r.t.argv.length - 1]
        const base = r.t.argv.slice(0, r.t.argv.length - 1)
        return { cmd: base.concat(baja ? [dest + ":" + rp, local]
                                       : [local, dest + ":" + rp]),
                 env: r.t.env }
    }

    case "service_ctl": {
        const acciones = ["start", "stop", "restart", "reload", "enable", "disable"]
        const accion = String(a.action || "")
        const unidad = String(a.unit || "").trim()
        if (acciones.indexOf(accion) === -1) return { error: "Acción inválida." }
        if (unidad === "" || unidad[0] === "-") return { error: "Unidad inválida." }
        // Sin sh: systemctl recibe la unidad como argumento literal. Las de
        // sistema pasarán por polkit (el agente propio del shell).
        return { cmd: a.user === true
                      ? ["systemctl", "--user", accion, "--", unidad]
                      : ["systemctl", accion, "--", unidad],
                 env: ({}) }
    }

    case "kill_process": {
        const pid = parseInt(a.pid)
        if (!isFinite(pid) || pid <= 1) return { error: "PID inválido." }
        const sigs = ["TERM", "KILL", "HUP", "INT"]
        const sig = sigs.indexOf(String(a.signal || "")) !== -1 ? a.signal : "TERM"
        return { cmd: ["sh", "-c",
                    'ps -p "$QS_PID" -o comm= 2>/dev/null; kill -s ' + sig
                    + ' -- "$QS_PID" && echo "Señal ' + sig + ' enviada."'
                    + ' || echo "No se pudo (PID inexistente o de otro usuario)."'],
                 env: ({ QS_PID: String(pid) }) }
    }

    case "web_search": {
        const q = String(a.query || "").trim()
        if (q === "") return { error: "Consulta vacía." }
        // Ya se sabe de este encargo que no hay buscador: se contesta sin tocar
        // la red. Antes cada intento costaba una conexión y, sobre todo, una
        // ronda entera de razonamiento del modelo. 'yaSabido' le dice a quien
        // llama que no hace falta vigilar esta tarjeta: el pestillo ya está
        // echado.
        if (c.searchBroken === true)
            return { error: WS.failureText("", true), yaSabido: true }
        // Sin configuración de búsqueda no hay a quién preguntar. Es un caso
        // que no puede darse desde el ejecutor —que solo la calcula para esta
        // herramienta—, pero un constructor que revienta con una excepción se
        // lleva por delante el shell entero, y eso no lo arregla ningún
        // comentario.
        if (!c.searchCtx)
            return { error: WS.failureText("", true), yaSabido: true }
        // La cascada (tu SearXNG, el que nombre el mensaje, los locales, la API
        // con clave) la arma WebSearch.js; aquí solo se le pasa la
        // configuración.
        return WS.command(q, c.searchCtx, TU.normalizeSearchBase, a)
    }

    }
    return null
}
