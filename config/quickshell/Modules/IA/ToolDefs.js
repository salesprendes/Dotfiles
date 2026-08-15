// Definiciones (esquemas JSON) de TODAS las herramientas del harness.
// Son datos estáticos, sin lógica ni estado — por eso viven aquí y no
// ahogando a AiService.qml. Cada función devuelve un array de esquemas en
// el formato de la API de OpenAI. La lógica de ejecutar cada herramienta
// sigue en AiService (approveTool y los constructores de comando).
.pragma library

function core() {
    return [
        // La carga diferida de la revelación progresiva: el prompt anuncia qué
        // habilidades hay, esta herramienta trae el texto de una. Solo aparece
        // si hay alguna instalada y activa, para no ofrecer una puerta a un
        // cuarto vacío.
        { type: "function", "function": {
            name: "use_skill",
            description: "Lee las instrucciones completas de una habilidad instalada por el usuario. Úsala ANTES de trabajar cuando la tarea encaje con la descripción de una habilidad.",
            parameters: { type: "object",
                properties: { name: { type: "string", description: "Nombre de la habilidad" } },
                required: ["name"] } } },
        { type: "function", "function": {
            name: "run_command",
            description: "Ejecuta un comando de shell (sh) en el equipo del usuario y devuelve su salida.",
            parameters: { type: "object",
                properties: { command: { type: "string", description: "Comando sh a ejecutar" } },
                required: ["command"] } } },
        { type: "function", "function": {
            name: "open_url",
            description: "Abre una URL en el navegador del usuario.",
            parameters: { type: "object",
                properties: { url: { type: "string" } },
                required: ["url"] } } },
        { type: "function", "function": {
            name: "read_file",
            description: "Lee un archivo de texto de la carpeta personal. Admite leer por tramos (offset/limit en líneas) para archivos grandes, y numerar las líneas con su hash (numbered) para luego editarlas con edit_lines sin reproducir el texto.",
            parameters: { type: "object",
                properties: { path: { type: "string", description: "Ruta, admite ~" },
                              offset: { type: "integer", description: "Primera línea (1 = principio)" },
                              limit: { type: "integer", description: "Cuántas líneas (por defecto 400)" },
                              numbered: { type: "boolean", description: "Devolver 'N#hash|contenido' para editar por rango" } },
                required: ["path"] } } },
        // El read_many_files de qwen-code: a un modelo local, que paga cara
        // cada ronda, leer cinco archivos en UNA llamada le ahorra cuatro
        // viajes enteros de ida y vuelta.
        { type: "function", "function": {
            name: "read_files",
            description: "Lee VARIOS archivos de una vez (máx. 8) y devuelve cada uno bajo su cabecera. Más barato que encadenar read_file cuando ya sabes qué archivos necesitas.",
            parameters: { type: "object",
                properties: { paths: { type: "array", items: { type: "string" },
                                       description: "Rutas, admiten ~" } },
                required: ["paths"] } } },
        { type: "function", "function": {
            name: "list_dir",
            description: "Lista el contenido de una carpeta de la carpeta personal del usuario.",
            parameters: { type: "object",
                properties: { path: { type: "string" } },
                required: ["path"] } } },
        { type: "function", "function": {
            name: "write_file",
            description: "Escribe un archivo de texto dentro de la carpeta personal del usuario (entregables: informes, scripts, notas). Sobrescribe si existe.",
            parameters: { type: "object",
                properties: { path: { type: "string" },
                              content: { type: "string" } },
                required: ["path", "content"] } } },
        { type: "function", "function": {
            name: "learn",
            description: "Guarda una LECCIÓN sobre cómo funciona este equipo o estos servidores, para no repetir el mismo tropiezo: una particularidad, un puerto, una ruta, un comando que aquí necesita algo especial. Si ya la sabías, vuelve a guardarla: sube su confianza. No la uses para datos personales del usuario (eso es remember).",
            parameters: { type: "object",
                properties: { lesson: { type: "string", description: "La lección, en una frase" } },
                required: ["lesson"] } } },
        { type: "function", "function": {
            name: "remember",
            description: "Guarda una nota corta en la memoria persistente del asistente (preferencias del usuario, datos útiles entre conversaciones). Si el dato ya existe pero cambió, usa memory_update en vez de guardar otra nota.",
            parameters: { type: "object",
                properties: { note: { type: "string" } },
                required: ["note"] } } },
        { type: "function", "function": {
            name: "memory_update",
            description: "Corrige una nota de la memoria por su número [#n]: el dato nuevo SUSTITUYE al viejo, en vez de convivir con él.",
            parameters: { type: "object",
                properties: { id: { type: "integer", description: "El número que aparece como [#n]" },
                              note: { type: "string", description: "El texto corregido" } },
                required: ["id", "note"] } } },
        { type: "function", "function": {
            name: "memory_forget",
            description: "Retira una nota de la memoria por su número [#n] cuando ya no es cierta o no sirve.",
            parameters: { type: "object",
                properties: { id: { type: "integer" } },
                required: ["id"] } } },
        // ── Cosecha de Claude Code (el TodoWrite/WebFetch/Grep/FileEdit de su
        // esqueleto, en pequeño) ─────────────────────────────────────────────
        { type: "function", "function": {
            name: "todo_write",
            description: "Sustituye tu plan de trabajo visible por esta lista de pasos. Úsala en tareas de 3+ pasos: al empezar (todos pending), al arrancar un paso (in_progress, solo uno a la vez) y al terminarlo (completed). En tareas triviales no la uses.",
            parameters: { type: "object",
                properties: { todos: { type: "array", items: { type: "object",
                    properties: { content: { type: "string", description: "El paso, en imperativo corto" },
                                  status: { type: "string", "enum": ["pending", "in_progress", "completed"] } },
                    required: ["content", "status"] } } },
                required: ["todos"] } } },
        { type: "function", "function": {
            name: "fetch_url",
            description: "Descarga una URL y devuelve su contenido como texto plano (HTML convertido, máx. 20 kB). Para leer documentación, artículos o APIs.",
            parameters: { type: "object",
                properties: { url: { type: "string" } },
                required: ["url"] } } },
        { type: "function", "function": {
            name: "grep_files",
            description: "Busca un texto o expresión regular dentro de los archivos de una carpeta de la carpeta personal (recursivo, devuelve archivo:línea).",
            parameters: { type: "object",
                properties: { pattern: { type: "string" },
                              path: { type: "string", description: "Carpeta donde buscar, admite ~" } },
                required: ["pattern", "path"] } } },
        { type: "function", "function": {
            name: "edit_file",
            description: "Edita un archivo por sustitución exacta: reemplaza old_string (que debe aparecer UNA sola vez) por new_string. Para cambios quirúrgicos; para crear o reescribir entero, write_file.",
            parameters: { type: "object",
                properties: { path: { type: "string" },
                              old_string: { type: "string" },
                              new_string: { type: "string" } },
                required: ["path", "old_string", "new_string"] } } },
        { type: "function", "function": {
            name: "edit_lines",
            description: "Sustituye un rango de líneas de un archivo. Léelo antes con read_file numbered:true y pasa los hashes que viste en los extremos del rango: si el archivo cambió desde entonces, la edición se rechaza en vez de estropearlo. Es la forma fiable de editar sin reproducir el texto original.",
            parameters: { type: "object",
                properties: { path: { type: "string" },
                              start: { type: "integer", description: "Primera línea del rango (1 = principio)" },
                              end: { type: "integer", description: "Última línea del rango, incluida" },
                              start_hash: { type: "string", description: "El hash que viste en la línea 'start'" },
                              end_hash: { type: "string", description: "El hash que viste en la línea 'end'" },
                              text: { type: "string", description: "Lo que sustituye al rango; vacío para borrarlo" } },
                required: ["path", "start", "end", "text"] } } },
        { type: "function", "function": {
            name: "glob_files",
            description: "Encuentra archivos por patrón de nombre (p. ej. *.qml) bajo una carpeta de la carpeta personal.",
            parameters: { type: "object",
                properties: { pattern: { type: "string" },
                              path: { type: "string" } },
                required: ["pattern", "path"] } } },
        { type: "function", "function": {
            name: "web_search",
            description: "Busca en la web (SearXNG) y devuelve títulos, URLs y fragmentos de los primeros resultados. Para saber qué páginas existen; para leer una, fetch_url. Si el usuario nombra su propia instancia, pásala en 'instance'.",
            parameters: { type: "object",
                properties: { query: { type: "string" },
                              instance: { type: "string", description: "URL de un SearXNG concreto; vacío = el configurado o uno público" } },
                required: ["query"] } } },
        { type: "function", "function": {
            name: "notify_user",
            description: "Muestra una notificación de escritorio al usuario. Para avisar de que una tarea larga terminó o necesita su atención.",
            parameters: { type: "object",
                properties: { title: { type: "string" },
                              body: { type: "string" } },
                required: ["title"] } } },
        // El plan NO es un modo que el usuario elija de antemano: lo decide el
        // agente al leer el encargo. Si la tarea lleva tres pasos o toca algo
        // irreversible, propone y espera; si es pequeña, la hace y ya. Mientras
        // hay un plan pendiente, el harness congela todo lo demás (ver
        // _advanceTools): proponer y ejecutar a la vez sería proponer de
        // boquilla.
        { type: "function", "function": {
            name: "propose_plan",
            description: "Presenta tu plan al usuario para que lo apruebe. Úsalo cuando hayas explorado lo suficiente: resume qué vas a cambiar, dónde, y cómo verificarás que salió bien. Mientras no lo apruebe no ejecutes nada; si lo rechaza, revísalo con lo que te diga.",
            parameters: { type: "object",
                properties: { plan: { type: "string", description: "El plan, en pasos breves" } },
                required: ["plan"] } } },
        // El primitivo de humano-en-el-bucle (de OpenWorker): en vez de
        // adivinar o de plantarse, el agente PREGUNTA y espera. No ejecuta
        // nada — la tarjeta se queda pendiente hasta que el usuario elige una
        // opción o escribe, y su respuesta vuelve como resultado.
        { type: "function", "function": {
            name: "ask_user",
            description: "Pregunta al usuario y espera su respuesta. Úsala cuando una decisión o un dato dependan de él (elegir entre alternativas, confirmar un supuesto, pedir un valor que no puedes deducir) en vez de adivinar. Ofrece opciones cortas si las hay; el usuario siempre puede responder con texto libre.",
            parameters: { type: "object",
                properties: {
                    question: { type: "string", description: "La pregunta, clara y concreta" },
                    options: { type: "array", items: { type: "string" },
                               description: "Respuestas rápidas sugeridas (2-4)" } },
                required: ["question"] } } },
        { type: "function", "function": {
            name: "subagent",
            description: "Delega una tarea de INVESTIGACIÓN en un subagente autónomo de solo lectura (busca, lee archivos y páginas, y devuelve un informe). Úsalo para exploraciones largas que ensuciarían esta conversación; lo que haya que escribir o ejecutar te toca a ti después.",
            parameters: { type: "object",
                properties: { task: { type: "string", description: "El encargo, con todo el contexto necesario" },
                              label: { type: "string", description: "Etiqueta corta para la interfaz" } },
                required: ["task"] } } },
        { type: "function", "function": {
            name: "list_mcp_resources",
            description: "Lista los recursos (documentos, datos) que publica un servidor MCP conectado.",
            parameters: { type: "object",
                properties: { server: { type: "string" } },
                required: ["server"] } } },
        { type: "function", "function": {
            name: "read_mcp_resource",
            description: "Lee un recurso concreto de un servidor MCP conectado, por su URI.",
            parameters: { type: "object",
                properties: { server: { type: "string" },
                              uri: { type: "string" } },
                required: ["server", "uri"] } } }
    ]
}

function sysQuery() {
    return [
        { type: "function", "function": {
            name: "system_status",
            description: "Estado general del equipo: carga, memoria, discos, unidades systemd fallidas y temperatura. El primer vistazo de cualquier diagnóstico.",
            parameters: { type: "object", properties: {} } } },
        { type: "function", "function": {
            name: "journal_query",
            description: "Lee el journal de systemd con filtros: unidad, prioridad (err, warning…), desde cuándo (-1h, today) y patrón de texto.",
            parameters: { type: "object",
                properties: { unit: { type: "string" },
                              priority: { type: "string", description: "emerg|alert|crit|err|warning|notice|info|debug" },
                              since: { type: "string", description: "p. ej. -1h, -2d, today" },
                              grep: { type: "string" },
                              lines: { type: "integer", description: "máx. 200, por defecto 60" } },
                required: [] } } },
        { type: "function", "function": {
            name: "service_query",
            description: "Estado de una unidad systemd (status con sus últimas líneas de log) o listados: failed, timers, running. user=true para unidades de usuario.",
            parameters: { type: "object",
                properties: { name: { type: "string", description: "Unidad; vacío si se pide un listado" },
                              list: { type: "string", "enum": ["failed", "timers", "running"] },
                              user: { type: "boolean" } },
                required: [] } } },
        { type: "function", "function": {
            name: "process_query",
            description: "Procesos: los que más CPU o memoria consumen, o búsqueda por nombre.",
            parameters: { type: "object",
                properties: { sort: { type: "string", "enum": ["cpu", "mem"] },
                              filter: { type: "string", description: "Buscar por nombre en vez de ordenar" } },
                required: [] } } },
        { type: "function", "function": {
            name: "network_query",
            description: "Red: interfaces y direcciones, rutas, puertos a la escucha, o un ping corto a un host.",
            parameters: { type: "object",
                properties: { kind: { type: "string", "enum": ["interfaces", "routes", "ports", "ping"] },
                              host: { type: "string", description: "Solo para ping" } },
                required: ["kind"] } } },
        { type: "function", "function": {
            name: "disk_query",
            description: "Discos: ocupación de los sistemas de archivos y, si se da una ruta, qué carpetas de primer nivel pesan más.",
            parameters: { type: "object",
                properties: { path: { type: "string" } },
                required: [] } } },
        { type: "function", "function": {
            name: "package_query",
            description: "Paquetes (pacman): info de uno instalado, búsqueda, actualizaciones pendientes, huérfanos, o a qué paquete pertenece un archivo.",
            parameters: { type: "object",
                properties: { op: { type: "string", "enum": ["info", "search", "updates", "orphans", "owns"] },
                              name: { type: "string" } },
                required: ["op"] } } }
    ]
}

// Los datos de CONEXIÓN que llevan todas las herramientas remotas, más lo
// propio de cada una en medio. Iban copiados en las siete: cambiar la
// descripción de 'host' obligaba a acertar siete veces.
function _target(own) {
    const p = { host: { type: "string",
                        description: "[usuario@]host[:puerto] o nombre guardado" } }
    for (const k in (own || {}))
        p[k] = own[k]
    p.user = { type: "string" }
    p.port = { type: "integer" }
    p.password = { type: "string", description: "Si el usuario la dio en el mensaje" }
    return p
}

function sshQuery() {
    return [
        { type: "function", "function": {
            name: "server_status",
            description: "Estado de un servidor remoto por SSH: carga, memoria, discos, servicios fallidos y top de procesos. host admite root@1.2.3.4[:puerto] o el nombre de uno guardado.",
            parameters: { type: "object",
                properties: _target(),
                required: ["host"] } } },
        { type: "function", "function": {
            name: "server_logs",
            description: "Logs de un servidor remoto: el journal (con unit/priority/since/grep) o, si das 'path', las últimas líneas de un archivo de log concreto (nginx, apache, plesk…).",
            parameters: { type: "object",
                properties: _target({
                    path: { type: "string", description: "Ruta de un archivo de log; vacío = journal" },
                    unit: { type: "string" }, priority: { type: "string" },
                    since: { type: "string" }, grep: { type: "string" },
                    lines: { type: "integer" } }),
                required: ["host"] } } },
        { type: "function", "function": {
            name: "sftp_ls",
            description: "Lista un directorio de un servidor remoto.",
            parameters: { type: "object",
                properties: _target({ path: { type: "string" } }),
                required: ["host"] } } },
        { type: "function", "function": {
            name: "hosting_query",
            description: "Consulta de solo lectura a un panel de hosting remoto. panel: 'plesk' (op: version, domains, subscriptions, databases, domain_info) o 'cpanel'/WHM (op: version, accounts, account_info, domains, disk).",
            parameters: { type: "object",
                properties: _target({
                    panel: { type: "string", "enum": ["plesk", "cpanel"] },
                    op: { type: "string" },
                    name: { type: "string", description: "Dominio o cuenta, según la op" } }),
                required: ["host", "panel", "op"] } } }
    ]
}

function sshAction() {
    return [
        { type: "function", "function": {
            name: "ssh_exec",
            description: "Ejecuta un comando de shell en un servidor remoto por SSH y devuelve su salida. Para administrar (incluido Plesk/cPanel con 'plesk bin …' o 'whmapi1 …'). Requiere aprobación.",
            parameters: { type: "object",
                properties: _target({
                    command: { type: "string", description: "Comando a ejecutar en el servidor" } }),
                required: ["host", "command"] } } },
        { type: "function", "function": {
            name: "sftp_get",
            description: "Descarga un archivo de un servidor remoto a la carpeta personal local.",
            parameters: { type: "object",
                properties: _target({
                    remote_path: { type: "string" },
                    local_path: { type: "string", description: "Destino local (dentro de $HOME)" } }),
                required: ["host", "remote_path", "local_path"] } } },
        { type: "function", "function": {
            name: "sftp_put",
            description: "Sube un archivo de la carpeta personal local a un servidor remoto.",
            parameters: { type: "object",
                properties: _target({
                    local_path: { type: "string", description: "Origen local (dentro de $HOME)" },
                    remote_path: { type: "string" } }),
                required: ["host", "local_path", "remote_path"] } } }
    ]
}

function sysAction() {
    return [
        { type: "function", "function": {
            name: "service_ctl",
            description: "Actúa sobre una unidad systemd: start, stop, restart, reload, enable o disable. user=true para unidades de usuario; las de sistema pueden pedir autenticación.",
            parameters: { type: "object",
                properties: { action: { type: "string", "enum": ["start", "stop", "restart", "reload", "enable", "disable"] },
                              unit: { type: "string" },
                              user: { type: "boolean" } },
                required: ["action", "unit"] } } },
        { type: "function", "function": {
            name: "kill_process",
            description: "Envía una señal a un proceso por PID (TERM por defecto; KILL solo si TERM no bastó). Averigua antes el PID con process_query.",
            parameters: { type: "object",
                properties: { pid: { type: "integer" },
                              signal: { type: "string", "enum": ["TERM", "KILL", "HUP", "INT"] } },
                required: ["pid"] } } }
    ]
}
