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
            description: "ÚLTIMO RECURSO: ejecuta un comando de shell en el equipo del usuario. Antes de usarla, mira si hay una herramienta que haga eso mismo — read_file, list_dir, grep_files, git_status, git_diff, system_status, journal_query, service_query, process_query, disk_query, package_query, network_query, http_request… Esas se ejecutan solas o con una tarjeta ligera; esta interrumpe al usuario SIEMPRE, porque un shell puede hacer cualquier cosa y nadie puede leer un comando largo y estar seguro de lo que hace. Úsala cuando de verdad no haya otra: un comando de compilación, una herramienta del proyecto, algo sin herramienta propia.",
            parameters: { type: "object",
                properties: { command: { type: "string", description: "Comando sh a ejecutar" },
                              cwd: { type: "string", description: "Carpeta desde la que ejecutarlo, dentro de la carpeta personal. Mejor esto que un 'cd x && …' delante del comando." } },
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
            description: "Descarga una URL y devuelve su contenido (máx. 20 000 caracteres). El HTML se convierte a texto legible; lo que no es HTML —JSON, XML, texto— llega tal cual, así que sirve igual para leer una API. Cada página que abras se queda en el contexto de esta conversación: si vas a abrir tres o más, delega en un subagente con role:'research' y capabilities:['net']. Con links:true trae además los enlaces (para navegar el sitio) y con head:true solo comprueba si la URL existe, sin traer nada.",
            parameters: { type: "object",
                properties: { url: { type: "string" },
                              links: { type: "boolean", description: "Añadir al final los enlaces de la página, con su texto y ya resueltos a absolutos. Es lo que permite NAVEGAR un sitio: ir a una sección, seguir al siguiente paso, encontrar la página buena. No descargues el HTML a mano para buscar href con grep." },
                              head: { type: "boolean", description: "No traer el contenido: solo si la URL existe, qué código HTTP devuelve, de qué tipo es, cuánto ocupa y a dónde acaba llevando tras las redirecciones. Para comprobar un enlace sin gastar contexto." } },
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
            name: "edit_patch",
            description: "LA FORMA PREFERENTE DE EDITAR. Aplica VARIOS cambios a un archivo en UNA llamada, anclados por hash de contenido y todo-o-nada (si un ancla falla no se escribe nada). Lee antes con read_file numbered:true: cada línea sale como N#hash|texto y ese N#hash es el ancla. No reproduces el texto viejo, solo dices dónde y qué poner — mucho más barato y sin riesgo de pegar mal. Si el archivo se movió desde que lo leíste, el motor BUSCA a dónde fue el ancla y lo reajusta solo (en un rango exige el mismo desplazamiento en los dos extremos, así no se confunde entre cien líneas iguales). Ops: replace (at..to), insert_before, insert_after, delete (at..to). Usa dry_run:true para ver el diff antes.",
            parameters: { type: "object",
                properties: { path: { type: "string" },
                              tag: { type: "string", description: "La etiqueta [archivo#tag] que imprimió read_file, para detectar que el archivo cambió entero" },
                              hunks: { type: "array", description: "Los cambios; no pueden solaparse",
                                items: { type: "object",
                                  properties: {
                                    op: { type: "string", "enum": ["replace", "insert_before", "insert_after", "delete"] },
                                    at: { type: "string", description: "Ancla de inicio, p. ej. \"42#nd\" (vale pegar la línea entera tal cual salió)" },
                                    to: { type: "string", description: "Ancla final para rangos de replace/delete; omítela para una sola línea" },
                                    text: { type: "string", description: "Lo que se pone (no hace falta en delete)" } },
                                  required: ["at"] } },
                              dry_run: { type: "boolean", description: "true = solo enseñar el diff, sin escribir" },
                              recover_window: { type: "integer", description: "Cuántas líneas buscar al reajustar un ancla movida (40 por defecto)" } },
                required: ["path", "hunks"] } } },
        { type: "function", "function": {
            name: "edit_lines",
            description: "Sustituye UN rango de líneas (la versión simple de edit_patch, que es la que conviene si vas a hacer más de un cambio). Léelo antes con read_file numbered:true y pasa los hashes de los extremos: si el archivo se movió, el motor reajusta el ancla o rechaza la edición en vez de estropearla.",
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
            description: "Encuentra archivos por patrón bajo una carpeta. RESPETA .gitignore cuando la ruta está en un repo git (no devuelve node_modules, build ni estado ignorado). El patrón casa contra el nombre (*.qml) o, si lleva una barra, contra la ruta relativa (src/**/*.py). Con sort=mtime devuelve lo MÁS RECIENTE primero con su fecha — la forma de responder a '¿qué se tocó última­mente?'.",
            parameters: { type: "object",
                properties: { pattern: { type: "string", description: "*.qml, test_*.py, src/**/*.ts" },
                              path: { type: "string" },
                              type: { type: "string", "enum": ["file", "dir", "any"],
                                      description: "Qué devolver (file por defecto)" },
                              sort: { type: "string", "enum": ["name", "mtime"],
                                      description: "mtime = modificados primero, con fecha" },
                              limit: { type: "integer", description: "Tope de resultados (200 por defecto, máx. 1000)" },
                              ignore_vcs: { type: "boolean", description: "false = NO respetar .gitignore (por defecto sí)" } },
                required: ["pattern", "path"] } } },
        { type: "function", "function": {
            name: "web_search",
            description: "Busca en la web. Pregunta a todas las fuentes configuradas a la vez y funde las respuestas: lo que coinciden varias sube arriba y se marca con «N fuentes» — cuantas más fuentes coincidan, más fiable es el resultado. Devuelve título, URL, fecha cuando la hay, y un fragmento. PARA COMPRAR O COMPARAR (productos, hoteles, alquileres): el precio suele venir ya en el fragmento o en el título, así que muchas veces no hace falta abrir nada; y si hay que abrir, elige comparadores (idealo, Klarna, buscadores de vuelos/hoteles) antes que la página de resultados de una tienda, porque esas se pintan con JavaScript y fetch_url no las lee. Si el usuario nombra su propia instancia de SearXNG, pásala en 'instance'. Si la pregunta exige abrir VARIAS páginas y comparar, delega en un subagente con role:'research' y capabilities:['net']: el ruido se queda en su contexto en vez de en esta conversación.",
            parameters: { type: "object",
                properties: { query: { type: "string" },
                              domains: { type: "array", items: { type: "string" },
                                         description: "Buscar SOLO en estos dominios, p. ej. [\"doc.qt.io\"]. Úsalo cuando sepas dónde está la respuesta buena: quita casi todo el ruido" },
                              exclude_domains: { type: "array", items: { type: "string" },
                                                 description: "Dominios que NO quieres ver" },
                              recency: { type: "string", "enum": ["day", "week", "month", "year"],
                                         description: "Solo resultados de este último periodo. Imprescindible para precios, versiones y noticias; contraproducente para conceptos que no cambian" },
                              limit: { type: "integer", description: "Cuántos resultados (1-10, por defecto 8)" },
                              depth: { type: "string", "enum": ["quick", "research"], description: "'quick' pregunta solo a las dos mejores fuentes: úsalo para lo que tiene UNA respuesta y se comprueba solo — la web oficial de algo, la versión actual, una definición, un dato que ya casi sabes. 'research' (por defecto) pregunta a todas y funde por consenso: úsalo cuando el dato importa y conviene contrastarlo — precios, comparativas, disponibilidad, cualquier cosa que vayas a afirmar. Preguntar a siete buscadores algo trivial gasta cuota que hará falta luego" },
                              instance: { type: "string", description: "URL de un SearXNG concreto; vacío = el configurado" } },
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
            description: "Delega una tarea en un subagente autónomo: contexto propio, permisos propios y taller propio. Devuelve un informe —o datos comprobados, si le das output_schema—. Úsalo para exploraciones largas que ensuciarían esta conversación, para revisar código, para diagnosticar averías y (con capabilities:[\"write\"]) para producir entregables en una copia aislada que luego revisas tú. Puedes lanzar VARIOS a la vez en el mismo turno (hasta 4) y corren en paralelo: reparte una búsqueda amplia en trozos. NUNCA tiene shell, ni Python, ni puede delegar a su vez; lo que haya que ejecutar te toca a ti.",
            parameters: { type: "object",
                properties: { task: { type: "string", description: "El encargo, con todo el contexto necesario" },
                              label: { type: "string", description: "Etiqueta corta para la interfaz" },
                              role: { type: "string", "enum": ["research", "review", "debug", "build"],
                                      description: "research (rastrear, por defecto), review (revisar código), debug (diagnosticar una avería), build (producir archivos en su taller)" },
                              brief: { type: "string", description: "Lo que TÚ ya sabes y no debe redescubrir: rutas, hallazgos previos, decisiones tomadas. Tus búsquedas web recientes y las páginas que ya has abierto se le adjuntan SOLAS, así que no las copies aquí: escribe lo que has deducido, no lo que has leído" },
                              workspace: { type: "string", description: "Carpeta a la que se acota (por defecto toda la carpeta personal). Si el encargo es sobre un proyecto, pásala: el subagente deja de traer ruido de otros sitios, y si escribe, su taller sale de ahí" },
                              capabilities: { type: "array", items: { type: "string", "enum": ["net", "write"] },
                                              description: "Permisos extra. 'net' descargar y buscar en la web; 'write' escribir en su taller (una copia aparte del repositorio, o una carpeta vacía). Leer va siempre incluido. Pedir 'write' hace que el usuario tenga que aprobarlo." },
                              output: { type: "string", description: "Forma que debe tener el informe, p. ej. 'lista de hallazgos con archivo:línea y arreglo'" },
                              output_schema: { type: "object", description: "Esquema JSON del resultado (type/properties/required/items/enum). Si lo das, el subagente devuelve JSON comprobado en vez de prosa, y se le hace corregirlo si no cumple. Úsalo cuando vayas a PROCESAR la respuesta." },
                              max_rounds: { type: "integer", description: "Tope de rondas de herramientas (1-12; por defecto 5 para 'research' y 8 para el resto). Es un tope de seguridad, no un objetivo: subirlo NO hace mejor el informe. En una búsqueda web lo que se va a encontrar sale en las tres primeras rondas, y de ahí en adelante solo crece el contexto. Déjalo sin poner salvo que el encargo tenga muchas partes independientes" },
                              budget_s: { type: "integer", description: "Tope de segundos (30-600, por defecto 180)" } },
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
                properties: { kind: { type: "string", "enum": ["interfaces", "routes", "ports", "ping", "neighbors"], description: "neighbors = quién hay en la red local, de la tabla de vecinos del núcleo (instantáneo y sin mandar paquetes; no escanees a mano con un bucle de pings)" },
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

// Herramientas de DESARROLLO (las ideas de oh-my-pi adaptadas al harness):
// el servidor de lenguaje, la edición estructural, el depurador DAP y la
// celda de Python persistente.
function dev() {
    return [
        { type: "function", "function": {
            name: "lsp",
            description: "Pregunta al servidor de lenguaje (LSP) sobre un archivo: diagnostics (errores y avisos tras editar), hover (tipo y documentación), definition (dónde se define), references (dónde se usa), symbols (el índice del archivo) y actions (qué ARREGLOS RÁPIDOS ofrece el servidor en una línea con error — luego se aplican con lsp_fix). line y col en base 1, como los enseña read_file. Úsala tras cada edición para comprobar que no rompiste nada.",
            parameters: { type: "object",
                properties: { op: { type: "string",
                                    "enum": ["diagnostics", "hover", "definition",
                                             "references", "symbols", "actions"] },
                              path: { type: "string", description: "Archivo, admite ~" },
                              line: { type: "integer", description: "Línea (base 1), para hover/definition/references" },
                              col: { type: "integer", description: "Columna (base 1)" } },
                required: ["op", "path"] } } },
        { type: "function", "function": {
            name: "lsp_rename",
            description: "Renombra un símbolo EN TODO EL PROYECTO con el servidor de lenguaje: cambia la definición y todas sus referencias de una vez, con copia previa de cada archivo tocado. Más seguro que buscar y reemplazar texto.",
            parameters: { type: "object",
                properties: { path: { type: "string" },
                              line: { type: "integer", description: "Línea del símbolo (base 1)" },
                              col: { type: "integer", description: "Columna del símbolo (base 1)" },
                              new_name: { type: "string" } },
                required: ["path", "line", "col", "new_name"] } } },
        { type: "function", "function": {
            name: "lsp_fix",
            description: "Aplica un ARREGLO RÁPIDO que ofrece el servidor de lenguaje (importar lo que falta, quitar lo que sobra, corregir la firma, organizar imports). Mira antes los disponibles con lsp op=actions y pasa aquí su índice. Deja copia previa para deshacer.",
            parameters: { type: "object",
                properties: { path: { type: "string" },
                              line: { type: "integer", description: "Línea del problema (base 1)" },
                              col: { type: "integer", description: "Columna (base 1, opcional)" },
                              index: { type: "integer", description: "Cuál de los arreglos listados (0 = el primero)" },
                              kind: { type: "string", description: "Filtrar por tipo, p. ej. quickfix o source.organizeImports" } },
                required: ["path", "line", "index"] } } },
        { type: "function", "function": {
            name: "lsp_raw",
            description: "Manda una petición CRUDA al servidor de lenguaje (método LSP y parámetros JSON) y devuelve su respuesta tal cual. Para lo que no cubren las demás: textDocument/formatting, textDocument/foldingRange, callHierarchy, typeDefinition, implementation… Si el método empieza por textDocument/ y no pasas textDocument, se pone el del archivo.",
            parameters: { type: "object",
                properties: { path: { type: "string", description: "Archivo que da el contexto y el servidor" },
                              method: { type: "string", description: "p. ej. textDocument/typeDefinition" },
                              params: { type: "object", description: "Parámetros del método (JSON)" } },
                required: ["path", "method"] } } },
        { type: "function", "function": {
            name: "ast_search",
            description: "Búsqueda ESTRUCTURAL de código con ast-grep: el patrón es código con metavariables ($X casa un nodo, $$$ una lista), no una regex. \"console.log($$$)\" encuentra todas las llamadas aunque cambien espacios o líneas. Para buscar texto plano usa grep_files.",
            parameters: { type: "object",
                properties: { pattern: { type: "string", description: "Patrón de código, p. ej. \"if ($X == null) $$$\"" },
                              path: { type: "string", description: "Archivo o carpeta" },
                              lang: { type: "string", description: "Lenguaje si la extensión no basta (js, ts, python, rust, go, c, cpp…)" } },
                required: ["pattern", "path"] } } },
        { type: "function", "function": {
            name: "ast_edit",
            description: "Reescritura ESTRUCTURAL de UN archivo con ast-grep: casa el patrón sobre el árbol de sintaxis y lo sustituye por rewrite (las metavariables del patrón se reutilizan: patrón \"foo($A, $B)\" con rewrite \"bar($B, $A)\"). Devuelve el diff de lo que cambió y deja copia para deshacer.",
            parameters: { type: "object",
                properties: { pattern: { type: "string" },
                              rewrite: { type: "string", description: "Código de reemplazo; \"\" borra lo casado" },
                              path: { type: "string", description: "UN archivo" },
                              lang: { type: "string" } },
                required: ["pattern", "rewrite", "path"] } } },
        { type: "function", "function": {
            name: "python_exec",
            description: "Ejecuta código en un Python PERSISTENTE: variables, funciones e imports sobreviven entre llamadas (como un cuaderno). Si la última línea es una expresión, devuelve su valor. Trae un PRELUDIO en proceso (sin lanzar procesos, con jaula en la carpeta personal): read(path), ls(path), grep(patrón, ruta), glob('*.py', ruta), find, stat, write(path, texto). Y tool(nombre, **args) para las herramientas ricas del harness: tool('lsp', op='diagnostics', path='~/x.py'), tool('ast_search', ...), tool('system_status'). Ideal para analizar datos, cruzar varios archivos o calcular sobre lo leído sin salir de la celda.",
            parameters: { type: "object",
                properties: { code: { type: "string" },
                              reset: { type: "boolean", description: "true = kernel nuevo, estado a cero" },
                              timeout: { type: "integer", description: "Segundos por celda (30 por defecto, máx. 120)" } },
                required: ["code"] } } },
        { type: "function", "function": {
            name: "job_start",
            description: "Lanza un comando EN SEGUNDO PLANO que sigue vivo entre turnos: compilaciones, instalaciones, pruebas largas, descargas. A diferencia de run_command no muere a los 20 s. Con pty=true el proceso cree estar en un terminal de verdad, que es lo que necesitan sudo, ssh o cualquier cosa que pregunte algo por teclado. Contesta tras unos segundos de gracia: si ya terminó, con su salida; si sigue, con su id para vigilarlo con job_view.",
            parameters: { type: "object",
                properties: { command: { type: "string", description: "Comando sh" },
                              pty: { type: "boolean", description: "true si el programa pregunta algo o exige terminal" },
                              label: { type: "string", description: "Etiqueta corta para la interfaz" },
                              cwd: { type: "string", description: "Directorio de trabajo (dentro de la carpeta personal)" },
                              wait: { type: "integer", description: "Segundos de gracia antes de contestar (2 por defecto, máx. 30)" } },
                required: ["command"] } } },
        { type: "function", "function": {
            name: "job_list",
            description: "Lista los trabajos en segundo plano con su estado, duración y código de salida.",
            parameters: { type: "object", properties: {} } } },
        { type: "function", "function": {
            name: "job_view",
            description: "Mira un trabajo: estado, duración y la cola de su salida. Es la forma de seguir una compilación o de leer el error que la tumbó.",
            parameters: { type: "object",
                properties: { id: { type: "integer" },
                              tail: { type: "integer", description: "Cuántos caracteres de cola (4000 por defecto)" } },
                required: ["id"] } } },
        { type: "function", "function": {
            name: "job_input",
            description: "Escribe en la entrada de un trabajo que está esperando (responder \"s\", elegir una opción, aceptar una huella). NUNCA envíes contraseñas ni claves por aquí: quedarían en la conversación y viajarían al modelo — para eso deja que el programa use el agente de polkit o una clave SSH.",
            parameters: { type: "object",
                properties: { id: { type: "integer" },
                              text: { type: "string", description: "Lo que se teclea" },
                              newline: { type: "boolean", description: "false para no pulsar Intro" },
                              eof: { type: "boolean", description: "true para cerrar su entrada (Ctrl-D)" } },
                required: ["id"] } } },
        { type: "function", "function": {
            name: "job_ctl",
            description: "Corta un trabajo (kill = KILL, signal = la que digas: INT, TERM, HUP, QUIT) o retira de la lista los ya terminados (clear). La señal va al GRUPO, así que muere la tubería entera.",
            parameters: { type: "object",
                properties: { action: { type: "string", "enum": ["kill", "signal", "clear"] },
                              id: { type: "integer" },
                              signal: { type: "string", "enum": ["INT", "TERM", "HUP", "QUIT", "KILL"] } },
                required: ["action"] } } },
        { type: "function", "function": {
            name: "debug_start",
            description: "Depura de verdad, con el depurador del lenguaje (gdb o lldb para C, C++, Rust, Zig, Swift y Objective-C; debugpy para Python; delve para Go; js-debug para JavaScript y TypeScript; netcoredbg para C# y F#; y Ruby, PHP, Kotlin, Dart, Elixir y Bash). Dos formas: 'program' arranca un programa tuyo con puntos de ruptura, o 'attach_pid' se engancha a un proceso QUE YA ESTÁ CORRIENDO (un servicio que va mal, un cuelgue que no se puede reproducir relanzando). Contesta cuando el programa pare en una ruptura o termine, con la pila y la salida. Después: debug_view para mirar pila, variables e hilos; debug_ctl para avanzar; debug_eval para evaluar expresiones en el marco parado.",
            parameters: { type: "object",
                properties: { program: { type: "string", description: "Script o binario, dentro de la carpeta personal. Uno de program o attach_pid." },
                              attach_pid: { type: "integer", description: "Engancharse a este proceso en marcha en vez de arrancar nada. Tiene que ser un proceso tuyo." },
                              args: { type: "array", items: { type: "string" } },
                              breakpoints: { type: "array", items: { type: "string" },
                                             description: "\"archivo:línea\" y, opcionalmente, una CONDICIÓN detrás: [\"~/p/main.py:42\", \"~/p/main.py:87 if n > 100\"]. Con condición solo para cuando la expresión es cierta." },
                              stop_on_entry: { type: "boolean", description: "Parar en la primera línea" },
                              lang: { type: "string",
                                      "enum": ["python", "go", "native", "c", "cpp", "rust", "zig",
                                               "swift", "objc", "javascript", "typescript", "node",
                                               "csharp", "fsharp", "ruby", "php", "kotlin", "dart",
                                               "elixir", "bash"],
                                      description: "Solo si la extensión no lo dice (un binario compilado, o al engancharse a un proceso)" } } } } },
        { type: "function", "function": {
            name: "debug_ctl",
            description: "Controla la sesión de depuración: continue (hasta la siguiente ruptura), next (paso por encima), step (entrar), out (salir del marco), pause, bp_add / bp_clear (con file y line) y stop (cerrar la sesión). Tras cada avance contesta con dónde paró, la pila y la salida nueva.",
            parameters: { type: "object",
                properties: { action: { type: "string",
                                        "enum": ["continue", "next", "step", "out",
                                                 "pause", "bp_add", "bp_clear", "stop"] },
                              file: { type: "string", description: "Para bp_add/bp_clear" },
                              line: { type: "integer" },
                              condition: { type: "string", description: "bp_add: expresión que debe ser CIERTA para parar, p. ej. \"i == 500\" o \"user is None\"" },
                              hit_condition: { type: "string", description: "bp_add: parar según el número de pasadas, p. ej. \">5\"" },
                              log_message: { type: "string", description: "bp_add: en vez de parar, registrar este mensaje ({var} interpola)" } },
                required: ["action"] } } },
        { type: "function", "function": {
            name: "debug_view",
            description: "Mira la sesión de depuración sin tocarla: stack (la pila del hilo parado), vars (variables del marco N, con frame), threads, status (estado y salida del programa).",
            parameters: { type: "object",
                properties: { what: { type: "string",
                                      "enum": ["stack", "vars", "threads", "status"] },
                              frame: { type: "integer", description: "Índice del marco para vars (0 = donde paró)" } },
                required: ["what"] } } },
        { type: "function", "function": {
            name: "debug_eval",
            description: "Evalúa una expresión en el marco donde el programa está parado (variables reales del proceso vivo): \"len(items)\", \"ptr->next\", \"mi_dict['clave']\".",
            parameters: { type: "object",
                properties: { expression: { type: "string" },
                              frame: { type: "integer", description: "Índice del marco (0 por defecto)" } },
                required: ["expression"] } } }
    ]
}
