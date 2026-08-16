// Constructores de comando de las herramientas LOCALES de solo lectura: leer
// archivos, listar, buscar, y consultar el sistema (systemctl, journalctl, ss,
// df, pacman…). Es la JAULA, y por eso vive sola en un archivo: el agente
// principal y el subagente construyen sus comandos aquí, de modo que hay UN
// sitio que auditar cuando uno se pregunta "¿qué puede hacer esto que no toca
// nada?".
//
// Todas las funciones devuelven {cmd, env} | {error} | null. El null significa
// "esta herramienta no es mía", que es lo que permite encadenar las tres
// familias sin que ninguna sepa de las otras.
//
// Regla invariable: TODO argumento del modelo viaja por ENTORNO. Nada se
// interpola en la línea de comandos, así que un nombre de archivo creativo no
// puede convertirse en otra orden.
.pragma library

// Expande ~ y comprueba que la ruta quede dentro de la carpeta personal: las
// herramientas de archivos NO salen de $HOME, y los ".." no cuelan. "" = fuera.
//
// El tercer parámetro es la RAÍZ DE TRABAJO, y solo la usan los subagentes: una
// pared más estrecha que $HOME, dentro de la cual además lo relativo cuelga de
// ella (que es como habla quien trabaja en un taller: "Bar/Bar.qml", no la ruta
// entera). Sin él, todo se comporta exactamente igual que siempre — la tilde
// sigue siendo $HOME y una ruta relativa sigue siendo un error.
function safePath(p, home, root) {
    let path = String(p).trim()
    const pared = root || home
    if (path === "~")
        path = home
    else if (path.startsWith("~/"))
        path = home + path.slice(1)
    else if (root && path !== "" && !path.startsWith("/"))
        path = root + "/" + path
    if (!path.startsWith(pared + "/") && path !== pared)
        return ""
    if (path.indexOf("..") !== -1)
        return ""
    return path
}

// Hash corto de una línea, definido UNA vez y compartido por quien numera
// (read_file) y quien verifica (edit_lines): si divergieran, el ancla nunca
// casaría. Es un FNV-1a de 16 bits en base36 — no busca resistencia
// criptográfica, solo detectar que la línea ya no es la que el modelo vio. Se
// ignoran los espacios del final, que cambian sin querer decir nada.
const PY_HASH =
    'def h(s):\n'
    + '    v=2166136261\n'
    + '    for c in s.rstrip().encode("utf-8",errors="replace"):\n'
    + '        v=((v^c)*16777619)&0xFFFFFFFF\n'
    + '    v&=0xFFFF\n'
    + '    d="0123456789abcdefghijklmnopqrstuvwxyz"; o=""\n'
    + '    for _ in range(3):\n'
    + '        o=d[v%36]+o; v//=36\n'
    + '    return o\n'

// ── Consultas del sistema ────────────────────────────────────────────────────
// No cambian nada (systemctl status, journalctl, ss, df, pacman -Q…): cuentan
// como lectura para la auto-aprobación y también las hereda el subagente, que
// así sabe diagnosticar solo.
function sysQuery(tool, args, ctx) {
    switch (tool) {
    case "system_status":
        return { cmd: ["sh", "-c",
            'echo "== uptime"; uptime; '
            + 'echo "== memoria"; free -h; '
            + 'echo "== discos"; df -h -x tmpfs -x devtmpfs -x efivarfs; '
            + 'echo "== unidades fallidas"; systemctl --failed --no-legend --no-pager | head -n 10; '
            + 'systemctl --user --failed --no-legend --no-pager | head -n 5; '
            + 'echo "== temperatura"; sensors 2>/dev/null | grep -E "°C" | head -n 8'],
            env: {} }
    case "journal_query": {
        const lines = Math.min(Math.max(parseInt(args.lines) || 60, 1), 200)
        let script = 'journalctl --no-pager -o short-iso -n ' + lines
        const env = {}
        if (String(args.unit || "").trim() !== "") {
            script += ' -u "$QS_UNIT"'
            env.QS_UNIT = String(args.unit).trim()
        }
        const prios = ["emerg", "alert", "crit", "err", "warning", "notice", "info", "debug"]
        if (prios.indexOf(String(args.priority || "")) !== -1)
            script += ' -p ' + args.priority
        if (String(args.since || "").trim() !== "") {
            script += ' --since "$QS_SINCE"'
            env.QS_SINCE = String(args.since).trim()
        }
        if (String(args.grep || "").trim() !== "") {
            script += ' -g "$QS_GREP"'
            env.QS_GREP = String(args.grep).trim()
        }
        return { cmd: ["sh", "-c", script + ' | tail -c 16000'], env: env }
    }
    case "service_query": {
        const scope = args.user === true ? " --user" : ""
        const list = String(args.list || "")
        if (list === "failed")
            return { cmd: ["sh", "-c", 'systemctl' + scope + ' --failed --no-pager --no-legend'], env: {} }
        if (list === "timers")
            return { cmd: ["sh", "-c", 'systemctl' + scope + ' list-timers --no-pager | head -n 25'], env: {} }
        if (list === "running")
            return { cmd: ["sh", "-c", 'systemctl' + scope + ' list-units --type=service --state=running --no-pager --no-legend | head -n 40'], env: {} }
        const unit = String(args.name || "").trim()
        if (unit === "")
            return { error: "Falta la unidad o un listado (failed/timers/running)." }
        return { cmd: ["sh", "-c", 'systemctl' + scope + ' status --no-pager -l -n 15 -- "$QS_UNIT" | head -c 8000; exit 0'],
                 env: { QS_UNIT: unit } }
    }
    case "process_query": {
        const f = String(args.filter || "").trim()
        if (f !== "")
            return { cmd: ["sh", "-c", 'pgrep -af -- "$QS_F" | head -n 30'], env: { QS_F: f } }
        const key = args.sort === "mem" ? "-%mem" : "-%cpu"
        return { cmd: ["sh", "-c",
            'ps axo pid,user,%cpu,%mem,etime,comm --sort=' + key + ' | head -n 16'], env: {} }
    }
    case "network_query": {
        switch (String(args.kind || "")) {
        case "interfaces": return { cmd: ["sh", "-c", 'ip -br addr'], env: {} }
        case "routes":     return { cmd: ["sh", "-c", 'ip route; echo; ip -6 route | head -n 10'], env: {} }
        case "ports":      return { cmd: ["sh", "-c", 'ss -tulpn 2>/dev/null | head -n 40'], env: {} }
        case "ping": {
            const h = String(args.host || "").trim()
            if (h === "") return { error: "Falta el host." }
            return { cmd: ["sh", "-c", 'ping -c 3 -W 2 -- "$QS_H" 2>&1 | tail -n 5'], env: { QS_H: h } }
        }
        }
        return { error: "kind debe ser interfaces, routes, ports o ping." }
    }
    case "disk_query": {
        let p = String(args.path || "").trim()
        if (p === "")
            return { cmd: ["sh", "-c", 'df -h -x tmpfs -x devtmpfs -x efivarfs'], env: {} }
        // df/du no expanden la tilde: se hace aquí (sin clamp — un admin
        // también mira /var; la consulta sigue siendo solo lectura).
        if (p === "~") p = ctx.home
        else if (p.startsWith("~/")) p = ctx.home + p.slice(1)
        return { cmd: ["sh", "-c",
            'df -h -- "$QS_P" 2>/dev/null; echo; du -xh -d1 -- "$QS_P" 2>/dev/null | sort -rh | head -n 15'],
            env: { QS_P: p } }
    }
    case "package_query": {
        const n = String(args.name || "").trim()
        const env = { QS_N: n }
        switch (String(args.op || "")) {
        case "info":
            if (n === "") return { error: "Falta el nombre." }
            return { cmd: ["sh", "-c", 'pacman -Qi -- "$QS_N" 2>/dev/null || pacman -Si -- "$QS_N" 2>/dev/null || echo "No existe."'], env: env }
        case "search":
            if (n === "") return { error: "Falta el término." }
            return { cmd: ["sh", "-c", 'pacman -Ss -- "$QS_N" | head -n 30'], env: env }
        case "updates":
            return { cmd: ["sh", "-c", 'checkupdates 2>/dev/null || pacman -Qu 2>/dev/null || echo "Al día (o sin caché de sincronización)."'], env: {} }
        case "orphans":
            return { cmd: ["sh", "-c", 'pacman -Qtdq 2>/dev/null || echo "Sin huérfanos."'], env: {} }
        case "owns":
            if (n === "") return { error: "Falta la ruta." }
            return { cmd: ["sh", "-c", 'pacman -Qo -- "$QS_N" 2>&1'], env: env }
        }
        return { error: "op debe ser info, search, updates, orphans u owns." }
    }
    }
    return null
}

// ── Leer una página web ──────────────────────────────────────────────────────
// Lo que devuelve fetch_url no es "el HTML": es lo que el modelo va a LEER, y
// cada carácter que entre ahí cuesta contexto en todas las rondas siguientes.
// Desnudar las etiquetas con expresiones regulares —lo que se hacía antes— saca
// el artículo, sí, pero también el menú, el pie, el aviso de galletas y los
// treinta enlaces de la barra lateral: veinte mil caracteres de los que sirven
// dos mil. Por eso ahora hay una CASCADA de extractores, del bueno al basto:
//
//   trafilatura   saca el cuerpo del artículo y tira el resto (lo mejor)
//   w3m -dump     renderiza como un navegador de texto: respeta tablas y listas
//   el desnudado  el de siempre, que no depende de nada instalado
//
// Y antes de todo eso, una comprobación que faltaba: si lo descargado NO es
// HTML (una API que devuelve JSON, un XML, un texto plano), no se desnuda nada
// — quitarle las "etiquetas" a un XML es destruirlo.
const PY_DESNUDA =
    "import sys,re,html\n"
    // errors=replace: una web en Latin-1 (las viejas en español) no debe tirar
    // la herramienta entera por un byte — los que no sean UTF-8 salen como "" y
    // el resto del texto se conserva.
    + "sys.stdin.reconfigure(errors='replace')\n"
    + "t=sys.stdin.read()\n"
    + "t=re.sub(r'(?is)<(script|style|nav|footer|aside|noscript)[^>]*>.*?</\\1>',' ',t)\n"
    + "t=re.sub(r'(?s)<[^>]+>',' ',t)\n"
    + "t=html.unescape(t)\n"
    + "t=re.sub(r'[ \\t]+',' ',t)\n"
    + "t=re.sub(r'\\n\\s*\\n+','\\n\\n',t)\n"
    + "sys.stdout.write(t.strip())\n"

// El recorte final. Se hace en PYTHON y no con `head -c` porque el tope es de
// caracteres, no de bytes: cortar 20 000 bytes a mitad de una eñe deja basura
// en el contexto del modelo.
const PY_CORTE =
    "import sys\n"
    + "sys.stdin.reconfigure(errors='replace')\n"
    + "t=sys.stdin.read()\n"
    + "sys.stdout.write(t[:20000] + ('\\n\\n[...cortado a 20 000 caracteres]' if len(t)>20000 else ''))\n"

// ¿Esto es texto? Sale 0 si sí, 1 si no. Dos señales, y ninguna depende de que
// el servidor haya dicho la verdad en la cabecera:
//   un byte NUL       ningún texto lo lleva, y el gzip empieza por 1f 8b 08 00
//   bytes de control  el ruido binario está lleno; el texto, ni uno
// No se comprueba que sea UTF-8 válido a propósito: media web vieja española
// está en Latin-1 y es perfectamente legible.
const PY_BINARIO =
    "import sys\n"
    + "d=sys.stdin.buffer.read(8192)\n"
    + "if not d or b'\\x00' in d: sys.exit(1)\n"
    + "malos=sum(1 for b in d if b<9 or 13<b<32)\n"
    + "sys.exit(1 if malos>len(d)*0.02 else 0)\n"

// EL DIAGNÓSTICO de una página que ya se ha extraído. Imprime una palabra —o
// nada, si está bien— y el shell traduce cada una a un mensaje distinto.
//
// La razón de separar los casos: "no hay contenido" no le dice al modelo qué
// hacer, y un modelo sin instrucción reintenta. Saber que es un muro anti-robot
// (no vuelvas a este sitio), que la URL no existe (no inventes una parecida) o
// que la pinta JavaScript (esto no se arregla con fetch_url) sí cambia lo que
// hace a continuación, que es lo único que importa.
const PY_DIAG =
    "import sys,re\n"
    + "t=sys.stdin.read().strip()\n"
    + "reto=r'just a moment|verifying your browser|checking your browser|captcha|"
    + "enable javascript|javascript is required|unusual traffic|are you a robot|"
    + "acceso denegado|access denied|attention required'\n"
    // El 404 BLANDO: servidores que devuelven 200 con una página de "no
    // encontrado" dentro. El código HTTP no los delata; el título, sí. Se mira
    // solo el principio del texto (título y encabezado) para no confundirlo con
    // un artículo que hable de errores 404.
    + "malaurl=r'page not found|p[áa]gina no encontrada|404 not found|error 404'\n"
    + "if re.search(reto,t[:3000],re.I): print('reto')\n"
    + "elif re.search(malaurl,t[:300],re.I): print('inexistente')\n"
    // El armazón de una tienda —cabecera, buscador, "mi cesta"— pasa de 200
    // caracteres sin esfuerzo, así que el umbral son 350. Comprobado: las
    // propias documentaciones de Quickshell dan 87 kB de HTML y 89 caracteres
    // de texto, porque las pinta JavaScript. No es un falso positivo: es
    // exactamente lo que hay.
    + "elif len(t)<350: print('corta')\n"

// La marca de "esto lo dice el harness, no la página". Hace falta porque lo que
// SÍ viene de la página se le entrega al modelo enmarcado como contenido ajeno
// (ver WebSearch.fence), y enmarcar así un mensaje propio sería mentirle: le
// estaríamos diciendo que un aviso nuestro lo ha escrito un desconocido.
const FETCH_KO = "[[FETCH_KO]]"

// ── RECETAS POR SITIO ────────────────────────────────────────────────────────
// Doce sitios de los que el agente tira todo el rato, y en casi todos hay una
// puerta de servicio mejor que la de delante.
//
// Lo medido con npm: el JSON del registro son 804 975 bytes y lo que de verdad
// se quiere de ahí son 285. Raspar el HTML de esa página es sacar esos mismos
// 285 bytes de una interfaz pintada con JavaScript. La receta no es "un
// extractor mejor": es no tener que extraer.
//
// Una receta solo dice DÓNDE preguntar y CÓMO resumir. Todo lo demás —la
// comprobación de a qué red apunta cada salto, el tope de tamaño, el cerco de
// contenido externo, la caché— es exactamente el mismo camino de siempre.
//
// Y si falla, no se nota: si la API contesta cualquier cosa que no sea 2xx, o
// si el formateador no saca nada (porque el JSON cambió de forma, que pasará),
// se reintenta la URL ORIGINAL por el camino de siempre. Una receta rota no
// puede dejar esto peor que no tenerla.
function _enc(s) { return encodeURIComponent(String(s)) }

const RECETAS = [
    // GitHub. Sin token: 60 peticiones por hora, y cuando se agotan la API
    // contesta 403 y se cae sola al HTML. A propósito — para subir a 5000 habría
    // que leer la credencial de `gh`, y eso es darle al agente acceso a los
    // repositorios privados sin haberlo dicho en ninguna parte.
    { id: "gh_repo",  re: /^https?:\/\/(?:www\.)?github\.com\/([^/?#]+)\/([^/?#]+)\/?(?:[?#].*)?$/i,
      url: m => "https://api.github.com/repos/" + _enc(m[1]) + "/" + _enc(m[2].replace(/\.git$/, "")) },
    { id: "gh_issue", re: /^https?:\/\/(?:www\.)?github\.com\/([^/?#]+)\/([^/?#]+)\/issues\/(\d+)/i,
      url: m => "https://api.github.com/repos/" + _enc(m[1]) + "/" + _enc(m[2]) + "/issues/" + m[3] },
    { id: "gh_pr",    re: /^https?:\/\/(?:www\.)?github\.com\/([^/?#]+)\/([^/?#]+)\/pull\/(\d+)/i,
      url: m => "https://api.github.com/repos/" + _enc(m[1]) + "/" + _enc(m[2]) + "/pulls/" + m[3] },
    // Un archivo concreto: el crudo, que ya es texto y no necesita formateador.
    { id: "texto",    re: /^https?:\/\/(?:www\.)?github\.com\/([^/?#]+)\/([^/?#]+)\/blob\/([^/?#]+)\/(.+?)(?:[?#].*)?$/i,
      url: m => "https://raw.githubusercontent.com/" + m[1] + "/" + m[2] + "/" + m[3] + "/" + m[4] },

    // GitLab quiere la ruta del proyecto entera codificada, barras incluidas.
    { id: "gl_repo",  re: /^https?:\/\/gitlab\.com\/((?!-\/)[^?#]+?)\/?(?:[?#].*)?$/i,
      url: m => "https://gitlab.com/api/v4/projects/" + _enc(m[1].replace(/\/$/, "")) },

    { id: "npm",      re: /^https?:\/\/(?:www\.)?npmjs\.com\/package\/((?:@[^/?#]+\/)?[^/?#]+)/i,
      url: m => "https://registry.npmjs.org/" + m[1] },
    { id: "pypi",     re: /^https?:\/\/pypi\.org\/project\/([^/?#]+)/i,
      url: m => "https://pypi.org/pypi/" + _enc(m[1]) + "/json" },
    { id: "crates",   re: /^https?:\/\/crates\.io\/crates\/([^/?#]+)/i,
      url: m => "https://crates.io/api/v1/crates/" + _enc(m[1]) },

    // arXiv: vale igual el /abs/ que el /pdf/, que es lo que suele pegar el
    // modelo cuando encuentra el enlace de descarga.
    { id: "arxiv",    re: /^https?:\/\/(?:www\.)?arxiv\.org\/(?:abs|pdf)\/([0-9]{4}\.[0-9]{4,5}(?:v\d+)?|[a-z-]+\/\d{7}(?:v\d+)?)/i,
      url: m => "https://export.arxiv.org/api/query?id_list=" + _enc(m[1].replace(/v\d+$/, "")) },

    // Stack Overflow: se piden las RESPUESTAS, no la pregunta. De un enlace a
    // Stack Overflow lo que se quiere es la respuesta aceptada, y el enunciado
    // ya viene en la propia URL — el formateador saca el título del final de la
    // dirección, que para eso lo lleva. Así hace falta una sola petición.
    { id: "so",       re: /^https?:\/\/(?:[a-z]+\.)?stackoverflow\.com\/questions\/(\d+)/i,
      url: m => "https://api.stackexchange.com/2.3/questions/" + m[1]
                + "/answers?site=stackoverflow&filter=withbody&sort=votes&order=desc" },

    { id: "hn",       re: /^https?:\/\/news\.ycombinator\.com\/item\?id=(\d+)/i,
      url: m => "https://hn.algolia.com/api/v1/items/" + m[1] },

    { id: "mdn",      re: /^https?:\/\/developer\.mozilla\.org\/([a-zA-Z-]+)\/docs\/([^?#]+?)\/?(?:[?#].*)?$/i,
      url: m => "https://developer.mozilla.org/" + m[1] + "/docs/" + m[2] + "/index.json" },

    // ReadTheDocs publica el FUENTE de cada página junto al HTML. Sphinx lo pone
    // en _sources con la extensión original, así que se prueba .rst y, si no,
    // .md — y si tampoco, al camino de siempre. 19 kB de texto limpio contra 62
    // de HTML, y sin barra lateral ni menús.
    { id: "texto",    re: /^https?:\/\/([a-z0-9-]+)\.readthedocs\.io\/([a-z-]+)\/([^/]+)\/(.+?)\/?(?:[?#].*)?$/i,
      url: m => "https://" + m[1] + ".readthedocs.io/" + m[2] + "/" + m[3]
                + "/_sources/" + m[4].replace(/\.html$/, "") + ".rst.txt" },

    // docs.rs no tiene API cómoda —el JSON de rustdoc viene comprimido en zstd—
    // así que aquí sí se lee el HTML, pero recortado al bloque de documentación
    // antes de tocarlo. El resto de la página es navegación de cajones.
    { id: "docsrs",   re: /^https?:\/\/docs\.rs\/.+/i, url: m => m[0] }
]

// La primera receta que case, o null. El orden importa: las de ruta larga
// (issues, pull, blob) van antes que la del repositorio a secas.
function receta(u) {
    const s = String(u || "")
    for (let i = 0; i < RECETAS.length; i++) {
        const m = s.match(RECETAS[i].re)
        if (m)
            return { id: RECETAS[i].id, url: RECETAS[i].url(m) }
    }
    return null
}

// El formateador de las recetas: recibe por la entrada estándar lo que
// contestó la API y escribe el resumen. Si algo no cuadra —el JSON cambió de
// forma, el campo ya no está, la API devolvió un error con cara de éxito—
// sale con código 1 SIN escribir nada, y quien llama lo entiende como "la
// receta no valió" y reintenta la URL original por el camino de siempre.
const PY_RECETA = [
    'import html as _h',
    'import json',
    'import os',
    'import re',
    'import sys',
    '',
    'CRUDO = sys.stdin.read()',
    'FMT = os.environ.get("QS_FMT", "")',
    'URL0 = os.environ.get("QS_U0", "")',
    '',
    '',
    'def corta(s, n):',
    '    s = " ".join(str(s or "").split())',
    '    return s if len(s) <= n else s[:n].rstrip() + "…"',
    '',
    '',
    '# Para los cuerpos largos (README, respuesta, documentación) hay que recortar',
    '# SIN aplastar: un README en una sola línea pierde los títulos, las listas y los',
    '# bloques de código, que es justo lo que hace legible un README.',
    'def bloque(s, n):',
    '    s = re.sub(r"\\n\\s*\\n\\s*\\n+", "\\n\\n", str(s or "").replace("\\r", "")).strip()',
    '    return s if len(s) <= n else s[:n].rstrip() + "\\n…[recortado]"',
    '',
    '',
    '# HTML a texto, para los tres que devuelven cuerpos en HTML dentro del JSON',
    '# (Stack Overflow, MDN) y para docs.rs. No pretende ser un extractor: el bloque',
    '# ya viene acotado, aquí solo se quitan las etiquetas conservando los saltos que',
    '# significan algo y los bloques de código, que en una respuesta técnica SON la',
    '# respuesta.',
    'def texto(h):',
    '    h = re.sub(r"(?is)<(script|style)\\b.*?</\\1>", " ", str(h or ""))',
    '    h = re.sub(r"(?is)<pre\\b[^>]*>(.*?)</pre>", lambda m: "\\n```\\n" + m.group(1) + "\\n```\\n", h)',
    '    h = re.sub(r"(?i)<br\\s*/?>", "\\n", h)',
    '    h = re.sub(r"(?i)</(p|div|li|h[1-6]|tr|section)>", "\\n", h)',
    '    h = re.sub(r"(?i)<li\\b[^>]*>", "\\n  · ", h)',
    '    h = re.sub(r"(?s)<[^>]+>", "", h)',
    '    h = _h.unescape(h)',
    '    h = re.sub(r"[ \\t]+", " ", h)',
    '    h = re.sub(r"\\n\\s*\\n\\s*\\n+", "\\n\\n", h)',
    '    return h.strip()',
    '',
    '',
    'def fecha(s):',
    '    return str(s or "")[:10]',
    '',
    '',
    'def linea(k, v):',
    '    v = str(v or "").strip()',
    '    return (k + ": " + v) if v else ""',
    '',
    '',
    'def imprime(filas):',
    '    salida = "\\n".join(f for f in filas if f)',
    '    if len(salida.strip()) < 12:      # nada aprovechable → que caiga al HTML',
    '        raise SystemExit(1)',
    '    print(salida)',
    '',
    '',
    'def js():',
    '    return json.loads(CRUDO)',
    '',
    '',
    '# El campo que IDENTIFICA la respuesta. Sin él no hay resumen que valga: un',
    '# "npm:   / Versiones: 0" es peor que no contestar, porque el modelo se lo cree.',
    '# Un JSON vacío o de otra forma tiene que salir por aquí, no por la puerta de',
    '# delante a medio vestir.',
    'def exige(v):',
    '    if not str(v or "").strip():',
    '        raise SystemExit(1)',
    '    return v',
    '',
    '',
    '# ── npm ──────────────────────────────────────────────────────────────────────',
    'def npm():',
    '    d = js()',
    '    ult = (d.get("dist-tags") or {}).get("latest", "")',
    '    v = (d.get("versions") or {}).get(ult, {})',
    '    rep = (v.get("repository") or {}).get("url", "") if isinstance(v.get("repository"), dict) else ""',
    '    deps = list((v.get("dependencies") or {}).keys())',
    '    tiempos = d.get("time") or {}',
    '    exige(d.get("name")); exige(ult)',
    '    imprime([',
    '        "npm: " + str(d.get("name", "")) + "  " + str(ult),',
    '        linea("Descripción", corta(d.get("description"), 300)),',
    '        linea("Licencia", v.get("license")),',
    '        linea("Publicado", fecha(tiempos.get(ult))),',
    '        linea("Versiones", str(len(d.get("versions") or {}))),',
    '        linea("Repositorio", re.sub(r"^git\\+|\\.git$", "", rep)),',
    '        linea("Web", v.get("homepage")),',
    '        linea("Dependencias (%d)" % len(deps), ", ".join(deps[:12]) + ("…" if len(deps) > 12 else "")),',
    '        "",',
    '        bloque(d.get("readme"), 1800),',
    '    ])',
    '',
    '',
    '# ── PyPI ─────────────────────────────────────────────────────────────────────',
    'def pypi():',
    '    d = js()',
    '    i = d.get("info") or {}',
    '    exige(i.get("name"))',
    '    urls = d.get("urls") or []',
    '    req = i.get("requires_dist") or []',
    '    imprime([',
    '        "PyPI: " + str(i.get("name", "")) + "  " + str(i.get("version", "")),',
    '        linea("Resumen", corta(i.get("summary"), 300)),',
    '        linea("Licencia", corta(i.get("license") or (i.get("classifiers") or [""])[0], 120)),',
    '        linea("Python", i.get("requires_python")),',
    '        linea("Publicado", fecha(urls[0].get("upload_time")) if urls else ""),',
    '        linea("Web", i.get("home_page") or (i.get("project_urls") or {}).get("Homepage")),',
    '        linea("Requiere (%d)" % len(req), ", ".join(r.split(";")[0].strip() for r in req[:12])),',
    '        "",',
    '        bloque(i.get("description"), 1800),',
    '    ])',
    '',
    '',
    '# ── crates.io ────────────────────────────────────────────────────────────────',
    'def crates():',
    '    d = js()',
    '    c = d.get("crate") or {}',
    '    vs = [v.get("num", "") for v in (d.get("versions") or [])[:5]]',
    '    exige(c.get("name"))',
    '    imprime([',
    '        "crates.io: " + str(c.get("name", "")) + "  " + str(c.get("max_stable_version") or c.get("max_version", "")),',
    '        linea("Descripción", corta(c.get("description"), 300)),',
    '        linea("Descargas", "{:,}".format(c.get("downloads", 0)).replace(",", ".")),',
    '        linea("Actualizado", fecha(c.get("updated_at"))),',
    '        linea("Repositorio", c.get("repository")),',
    '        linea("Documentación", c.get("documentation")),',
    '        linea("Categorías", ", ".join(c.get("keywords") or [])),',
    '        linea("Últimas versiones", ", ".join(vs)),',
    '    ])',
    '',
    '',
    '# ── GitHub ───────────────────────────────────────────────────────────────────',
    'def gh_repo():',
    '    d = js()',
    '    if d.get("message"):                       # 403 de cuota, 404…',
    '        raise SystemExit(1)',
    '    exige(d.get("full_name"))',
    '    lic = (d.get("license") or {}).get("spdx_id", "")',
    '    imprime([',
    '        "GitHub: " + str(d.get("full_name", "")),',
    '        linea("Descripción", corta(d.get("description"), 300)),',
    '        linea("Estrellas", "{:,}".format(d.get("stargazers_count", 0)).replace(",", ".")',
    '              + "  ·  forks: " + str(d.get("forks_count", 0))',
    '              + "  ·  issues abiertas: " + str(d.get("open_issues_count", 0))),',
    '        linea("Lenguaje", d.get("language")),',
    '        linea("Licencia", lic if lic != "NOASSERTION" else ""),',
    '        linea("Rama por defecto", d.get("default_branch")),',
    '        linea("Último cambio", fecha(d.get("pushed_at"))),',
    '        linea("Temas", ", ".join(d.get("topics") or [])),',
    '        linea("Web", d.get("homepage")),',
    '        linea("Archivado", "sí" if d.get("archived") else ""),',
    '    ])',
    '',
    '',
    'def gh_issue(clase="Issue"):',
    '    d = js()',
    '    if d.get("message"):',
    '        raise SystemExit(1)',
    '    extra = []',
    '    if "merged" in d:',
    '        extra = [linea("Estado", ("fusionada" if d.get("merged") else d.get("state", ""))),',
    '                 linea("Cambios", "+%s −%s en %s archivos"',
    '                       % (d.get("additions", 0), d.get("deletions", 0), d.get("changed_files", 0)))]',
    '    else:',
    '        extra = [linea("Estado", d.get("state", ""))]',
    '    exige(d.get("title"))',
    '    imprime([',
    '        clase + " #" + str(d.get("number", "")) + ": " + str(d.get("title", "")),',
    '        linea("Quien la abrió", (d.get("user") or {}).get("login")),',
    '        linea("Abierta", fecha(d.get("created_at"))),',
    '    ] + extra + [',
    '        linea("Etiquetas", ", ".join(l.get("name", "") for l in (d.get("labels") or []))),',
    '        linea("Comentarios", str(d.get("comments", 0))),',
    '        "",',
    '        bloque(d.get("body"), 2500),',
    '    ])',
    '',
    '',
    'def gh_pr():',
    '    gh_issue("Pull request")',
    '',
    '',
    '# ── GitLab ───────────────────────────────────────────────────────────────────',
    'def gl_repo():',
    '    d = js()',
    '    if d.get("message") or d.get("error"):',
    '        raise SystemExit(1)',
    '    exige(d.get("path_with_namespace"))',
    '    imprime([',
    '        "GitLab: " + str(d.get("path_with_namespace", "")),',
    '        linea("Descripción", corta(d.get("description"), 300)),',
    '        linea("Estrellas", str(d.get("star_count", 0)) + "  ·  forks: " + str(d.get("forks_count", 0))),',
    '        linea("Rama por defecto", d.get("default_branch")),',
    '        linea("Último cambio", fecha(d.get("last_activity_at"))),',
    '        linea("Temas", ", ".join(d.get("topics") or [])),',
    '        linea("Web", d.get("web_url")),',
    '    ])',
    '',
    '',
    '# ── Hacker News ──────────────────────────────────────────────────────────────',
    'def hn():',
    '    d = js()',
    '    exige(d.get("title") or d.get("url") or d.get("text"))',
    '    hijos = d.get("children") or []',
    '',
    '    def rama(n, prof, salida):',
    '        if prof > 1 or len(salida) >= 10:',
    '            return',
    '        t = texto(n.get("text") or "")',
    '        if t:',
    '            salida.append(("  " * prof) + "· " + str(n.get("author") or "?") + ": " + corta(t, 500))',
    '        for h in (n.get("children") or []):',
    '            rama(h, prof + 1, salida)',
    '',
    '    coms = []',
    '    for h in hijos:',
    '        rama(h, 0, coms)',
    '    imprime([',
    '        "Hacker News: " + str(d.get("title") or "(sin título)"),',
    '        linea("Enlace", d.get("url")),',
    '        linea("Puntos", str(d.get("points") or 0) + "  ·  autor: " + str(d.get("author") or "?")',
    '              + "  ·  " + fecha(d.get("created_at"))),',
    '        "",',
    '        "Comentarios más arriba:" if coms else "",',
    '    ] + coms)',
    '',
    '',
    '# ── Stack Overflow ───────────────────────────────────────────────────────────',
    '# El título sale de la propia URL: el enlace lo lleva en el nombre y así basta',
    '# UNA petición, la de las respuestas, que es lo que se quiere de un enlace a',
    '# Stack Overflow.',
    'def so():',
    '    d = js()',
    '    items = d.get("items") or []',
    '    if not items:',
    '        raise SystemExit(1)',
    '    m = re.search(r"/questions/\\d+/([^/?#]+)", URL0)',
    '    titulo = m.group(1).replace("-", " ") if m else "(pregunta)"',
    '    filas = ["Stack Overflow: " + titulo,',
    '             linea("Respuestas", str(len(items))',
    '                   + ("  ·  hay una aceptada" if any(a.get("is_accepted") for a in items) else "")),',
    '             ""]',
    '    for a in items[:3]:',
    '        filas.append("── %s%s votos ──"',
    '                     % ("ACEPTADA · " if a.get("is_accepted") else "", a.get("score", 0)))',
    '        filas.append(bloque(texto(a.get("body")), 2000))',
    '        filas.append("")',
    '    imprime(filas)',
    '',
    '',
    '# ── arXiv ────────────────────────────────────────────────────────────────────',
    'def arxiv():',
    '    d = CRUDO',
    '    def uno(tag):',
    '        m = re.search(r"(?is)<entry>.*?<%s>(.*?)</%s>" % (tag, tag), d)',
    '        return _h.unescape(m.group(1)).strip() if m else ""',
    '    autores = re.findall(r"(?is)<author>\\s*<name>(.*?)</name>", d)',
    '    cats = re.findall(r\'(?i)<category[^>]*term="([^"]+)"\', d)',
    '    if not uno("title"):',
    '        raise SystemExit(1)',
    '    imprime([',
    '        "arXiv: " + corta(uno("title"), 250),',
    '        linea("Autores", ", ".join(a.strip() for a in autores[:12])',
    '              + ("…" if len(autores) > 12 else "")),',
    '        linea("Publicado", fecha(uno("published")) + "  ·  revisado: " + fecha(uno("updated"))),',
    '        linea("Categorías", ", ".join(dict.fromkeys(cats))),',
    '        "",',
    '        "Resumen:",',
    '        " ".join(uno("summary").split()),',
    '    ])',
    '',
    '',
    '# ── MDN ──────────────────────────────────────────────────────────────────────',
    'def mdn():',
    '    doc = (js() or {}).get("doc") or {}',
    '    exige(doc.get("title"))',
    '    filas = ["MDN: " + str(doc.get("title", "")),',
    '             linea("Resumen", corta(doc.get("summary"), 400)), ""]',
    '    resumen = " ".join(str(doc.get("summary") or "").split())',
    '    for s in (doc.get("body") or []):',
    '        v = s.get("value") or {}',
    '        if s.get("type") == "prose" and v.get("content"):',
    '            # La primera sección de prosa suele SER el resumen otra vez.',
    '            if " ".join(texto(v["content"]).split()) == resumen:',
    '                continue',
    '            if v.get("title"):',
    '                filas.append("── " + str(v["title"]) + " ──")',
    '            filas.append(texto(v["content"]))',
    '    salida = "\\n".join(f for f in filas if f)',
    '    if len(salida) > 12000:',
    '        salida = salida[:12000].rstrip() + "\\n…[recortado]"',
    '    imprime([salida])',
    '',
    '',
    '# ── docs.rs ──────────────────────────────────────────────────────────────────',
    '# Sin API cómoda (el JSON de rustdoc viene en zstd), así que se lee el HTML pero',
    '# recortado antes al bloque de documentación: lo demás son cajones de navegación',
    '# con cientos de nombres de items.',
    'def docsrs():',
    '    m = re.search(r\'(?is)<(section|div)[^>]*id="main-content".*?>(.*)\', CRUDO)',
    '    cuerpo = m.group(2) if m else CRUDO',
    '    cuerpo = re.split(r"(?i)</(section|main)>", cuerpo)[0]',
    '    t = texto(cuerpo)',
    '    if len(t) < 80:',
    '        raise SystemExit(1)',
    '    imprime(["docs.rs", "", bloque(t, 12000)])',
    '',
    '',
    '# ── Texto tal cual ───────────────────────────────────────────────────────────',
    'def crudo():',
    '    if len(CRUDO.strip()) < 12:',
    '        raise SystemExit(1)',
    '    print(CRUDO)',
    '',
    '',
    'TABLA = {"npm": npm, "pypi": pypi, "crates": crates, "gh_repo": gh_repo,',
    '         "gh_issue": gh_issue, "gh_pr": gh_pr, "gl_repo": gl_repo, "hn": hn,',
    '         "so": so, "arxiv": arxiv, "mdn": mdn, "docsrs": docsrs, "texto": crudo}',
    '',
    'fn = TABLA.get(FMT)',
    'if fn is None:',
    '    raise SystemExit(1)',
    'try:',
    '    fn()',
    'except SystemExit:',
    '    raise',
    'except Exception:',
    '    # Cualquier sorpresa en la forma del JSON —que la habrá, las APIs cambian—',
    '    # se sale en silencio: quien llama lo interpreta como "la receta no valió" y',
    '    # reintenta la URL original por el camino de siempre.',
    '    raise SystemExit(1)'
].join("\n")

// A QUÉ MÁQUINA APUNTA DE VERDAD ESTA DIRECCIÓN, antes de mandarle nada.
//
// Contesta "ok <servidor> <puerto> <ip>" o "ko <motivo>". El motivo se le enseña
// al modelo tal cual, así que va escrito para que pueda decidir con él.
//
// Tres reglas, y las tres importan:
//   · Se miran TODAS las direcciones del nombre, no la primera. Publicar dos
//     registros —uno público y otro privado— y confiar en que el cliente elija
//     el bueno es el rodeo clásico; aquí una sola mala tumba el nombre entero.
//   · Se desnuda la IPv4 metida en IPv6 (::ffff:127.0.0.1), que es la misma
//     dirección con otro traje y que el módulo ipaddress no marca como local si
//     no se le pide.
//   · Se rechaza también lo reservado, lo multicast y el 0.0.0.0, que no son
//     "red de casa" pero tampoco son internet, y alguno (el 0.0.0.0) es un alias
//     conocido del propio equipo.
const PY_RESOLVE = [
    'import ipaddress, os, socket',
    'from urllib.parse import urlsplit',
    'u = os.environ.get("QS_HOP", "")',
    'lan = os.environ.get("QS_LAN", "") == "1"',
    'p = urlsplit(u)',
    'if p.scheme not in ("http", "https"):',
    '    print("ko Solo se descargan direcciones http(s)."); raise SystemExit',
    'host = p.hostname or ""',
    'if not host:',
    '    print("ko Esa dirección no dice a qué servidor ir."); raise SystemExit',
    'try:',
    '    port = p.port or (443 if p.scheme == "https" else 80)',
    'except ValueError:',
    '    print("ko El puerto de esa dirección no es un número."); raise SystemExit',
    'try:',
    '    infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)',
    'except OSError:',
    '    print("ko No existe el servidor \'%s\' (el nombre no resuelve)." % host)',
    '    raise SystemExit',
    'buenas = []',
    'for info in infos:',
    '    bruta = info[4][0]',
    '    ip = ipaddress.ip_address(bruta)',
    '    mapeada = getattr(ip, "ipv4_mapped", None)',
    '    if mapeada is not None:',
    '        ip = mapeada',
    // "No es global" en vez de una lista de banderas: la lista se queda corta y
    // se nota tarde. Comprobado en Python 3.14 — 100.64.0.0/10, el rango que
    // usan las operadoras para su NAT y que ocupa Tailscale, da is_private
    // FALSO, así que una lista de banderas lo dejaba pasar. is_global recoge de
    // una vez lo privado, el bucle, el enlace local, lo reservado, el 0.0.0.0 y
    // el CGNAT. El multicast se pide aparte porque ahí sí dice que es global.
    '    interna = (not ip.is_global) or ip.is_multicast',
    '    if interna and not lan:',
    '        print("ko \'%s\' apunta a %s, que es una máquina de la red local o "',
    '              "la propia máquina, no internet. No se lee ni se le pide "',
    '              "nada: lo que hay ahí dentro suele estar sin contraseña "',
    '              "precisamente porque solo se llega desde aquí. Si de verdad "',
    '              "hace falta, pídeselo al usuario con la dirección escrita."',
    '              % (host, ip))',
    '        raise SystemExit',
    '    buenas.append(bruta)',
    'if not buenas:',
    '    print("ko No se pudo resolver \'%s\'." % host); raise SystemExit',
    // TODAS las buenas, no la primera. --resolve acepta una lista separada por
    // comas, y dársela entera conserva el respaldo de curl entre direcciones:
    // fijar solo la primera rompía los sitios con IPv6 y IPv4 donde el IPv6 no
    // tira — que es media internet doméstica. Salió probando con un nombre que
    // resuelve a ::1 y a 127.0.0.1: se fijaba el ::1 y no conectaba nunca.
    // curl quiere la IPv6 entre corchetes aquí, y solo aquí.
    'lista = ",".join(("[" + b + "]") if ":" in b else b for b in buenas)',
    'print("ok %s %s %s" % (host, port, lista))'
].join("\n")

const FETCH_SH = [
    // Con agente de usuario de navegador: hay bastantes sitios que responden 403
    // a un curl pelado, y esa negativa llegaba al modelo como "página vacía".
    'ua="Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"',
    'f=$(mktemp) || { echo "' + FETCH_KO + ' No se pudo crear un archivo temporal."; exit 0; }',
    'trap \'rm -f "$f"\' EXIT INT TERM',
    // --compressed NO es un detalle de rendimiento, es corrección. Hay sitios
    // (Amazon, sin ir más lejos) que devuelven gzip aunque el cliente no lo
    // pida, y sin descomprimir lo que entraba al contexto del modelo eran
    // VEINTE MIL caracteres de basura binaria por descarga — el tope entero,
    // reenviado en todas las rondas siguientes. Los tiempos de respuesta
    // crecían ronda a ronda y parecía que el modelo se atascaba; lo que se
    // atascaba era su contexto, lleno de ruido.
    // ── UN SALTO CADA VEZ, Y CADA UNO MIRADO ────────────────────────────────
    // Aquí había un `curl -sSL`: seguía las redirecciones ÉL, y nosotros solo
    // veíamos dónde acabó la última. Eso tapaba la exfiltración —el cuerpo de
    // una máquina de casa no llegaba al modelo— pero dejaba dos cosas fuera:
    //
    //   · Los saltos INTERMEDIOS. `público → 192.168.1.1/admin/reboot →
    //     público` acaba en una IP pública, así que pasaba el filtro… después de
    //     haber hecho la petición al router. Para eso no hace falta leer la
    //     respuesta: la petición YA es la acción.
    //   · El instante entre resolver y conectar. Comprobar la IP a la que se
    //     llegó es tarde por definición; el GET ya salió.
    //
    // Así que ahora manda el harness: `--max-redirs 0`, y por cada salto se
    // resuelve el nombre PRIMERO, se miran TODAS las direcciones que devuelve
    // (basta una privada para negarse: publicar dos registros, uno bueno y otro
    // malo, es el truco clásico), y se conecta con `--resolve`, que fija la IP
    // ya comprobada. Entre la comprobación y la conexión ya no hay ventana:
    // curl no vuelve a preguntarle al DNS.
    //
    // QS_LAN=1 lo levanta quien ya enseñó la tarjeta con la dirección local
    // escrita y se la aprobaron. Sin esa aprobación explícita, la red de casa no
    // se lee ni se toca.
    // La descarga es una FUNCIÓN porque ahora se usa dos veces: primero para
    // intentar la receta del sitio (la puerta de servicio: una API que contesta
    // JSON en vez de una página pintada con JavaScript) y, si eso no vale,
    // para la URL original por el camino de siempre. Deja en $code, $ct y $f lo
    // que haya contestado el último salto.
    'descargar() {',
    '  u="$1"; salto=0',
    '  while :; do',
    '    v=$(QS_HOP="$u" python3 -c "$QS_RES" 2>/dev/null)',
    '    case "$v" in',
    '      ok\\ *) ;;',
    // Una negativa por red interna NO se reintenta por otro camino: es la misma
    // máquina prohibida en los dos casos, y repetirla solo la pediría dos veces.
    '      ko\\ *) echo "' + FETCH_KO + ' ${v#ko }"; exit 0 ;;',
    '      *) echo "' + FETCH_KO + ' No se pudo comprobar a qué máquina apunta esa dirección."; exit 0 ;;',
    '    esac',
    '    set -- $v; host=$2; port=$3; ip=$4',
    '    resp=$(curl -sS --compressed --max-time 20 --max-filesize 2000000 --max-redirs 0 --resolve "$host:$port:$ip" -A "$ua" -o "$f" -w "%{content_type}|%{http_code}|%{remote_ip}|%{redirect_url}" -- "$u" 2>/dev/null)',
    // El troceo va de izquierda a derecha y la URL queda LA ÚLTIMA a propósito:
    // es el único campo que puede llevar una barra vertical dentro.
    '    ct=${resp%%|*}; r=${resp#*|}; code=${r%%|*}; r=${r#*|}',
    '    ip=${r%%|*}; siguiente=${r#*|}',
    '    case "$code" in',
    '      30[12378])',
    '        salto=$((salto+1))',
    '        [ "$salto" -gt 5 ] && { echo "' + FETCH_KO + ' Esa dirección da más de cinco redirecciones seguidas; no se sigue más."; exit 0; }',
    '        [ -n "$siguiente" ] || break',
    '        u="$siguiente"; continue ;;',
    '    esac',
    '    break',
    '  done',
    '}',
    '',
    // ── LA PUERTA DE SERVICIO ────────────────────────────────────────────────
    // Si el sitio tiene receta, se prueba primero. Medido con npm: el JSON del
    // registro son 804 975 bytes y lo que se quiere de ahí son 285 — raspar la
    // página sería sacar esos mismos 285 bytes de una interfaz de JavaScript.
    //
    // Y si no sale bien —la API contesta 404, o cambió de forma y el formateador
    // no saca nada— no se nota: se cae a la URL original. Una receta rota no
    // puede dejar esto peor que no tenerla.
    'if [ -n "$QS_RURL" ]; then',
    '  descargar "$QS_RURL"',
    '  case "$code" in',
    '    2*) salida=$(python3 -c "$QS_REC" < "$f" 2>/dev/null)',
    '        [ -n "$salida" ] && { printf "%s\\n" "$salida"; exit 0; } ;;',
    '  esac',
    'fi',
    'descargar "$QS_U"',
    '',
    // El CÓDIGO HTTP va PRIMERO, antes incluso de mirar si llegó algo. Un 404
    // con el cuerpo vacío —que es lo normal— caía si no en la rama de "sin
    // respuesta o error de red", y eso es mentira: el servidor contestó
    // perfectamente, y lo que dijo fue que esa dirección no existe. La
    // diferencia importa: ante un error de red se reintenta, ante un 404 no.
    // Se mira el código de DESPUÉS de las redirecciones, que es el que vale.
    'case "$code" in',
    // 403 y 429 casi nunca son "no tienes permiso": son el muro anti-robot del
    // sitio. Decírselo así al modelo le ahorra probar otras cinco rutas del
    // mismo dominio, que es lo que hacía.
    '  403|429)',
    '    echo "' + FETCH_KO + ' El sitio bloquea el acceso automático (HTTP $code): es un muro anti-robot, no un problema de la URL. Sin un navegador de verdad no vas a entrar; no pruebes más páginas de este mismo sitio."; exit 0 ;;',
    '  404|410)',
    '    echo "' + FETCH_KO + ' Esa URL no existe (HTTP $code). No inventes otra parecida a ojo: si no sabes la dirección buena, esto es una búsqueda, no una descarga."; exit 0 ;;',
    '  4*)',
    '    echo "' + FETCH_KO + ' El servidor rechazó la petición (HTTP $code)."; exit 0 ;;',
    '  5*)',
    '    echo "' + FETCH_KO + ' El servidor falló (HTTP $code). Puede ser temporal; si es importante, prueba una sola vez más, más tarde."; exit 0 ;;',
    'esac',
    '[ -s "$f" ] || { echo "' + FETCH_KO + ' No se pudo descargar la página (sin respuesta, demasiado grande, o error de red)."; exit 0; }',
    // Lo que no es un documento de texto no se intenta leer: un PDF, una imagen
    // o un binario desnudados a la fuerza son mojibake, y mojibake en el
    // contexto es peor que un error — ocupa igual y no dice nada.
    'case "$ct" in',
    '  image/*|audio/*|video/*|application/pdf|application/zip|application/octet-stream|application/x-*|font/*)',
    '    echo "' + FETCH_KO + ' Eso no es una página de texto ($ct). fetch_url solo lee texto: HTML, JSON, XML o texto plano."; exit 0 ;;',
    'esac',
    // Y el mismo cerco por CONTENIDO, para los servidores que mienten en la
    // cabecera o que responden comprimido sin avisar.
    'python3 -c "$QS_BIN" < "$f" || { echo "' + FETCH_KO + ' Lo descargado no es texto legible (parece un binario o venía comprimido de forma que no se ha podido leer)."; exit 0; }',
    'case "$ct" in',
    // Lo que no es HTML se entrega TAL CUAL: es dato, no maquetación.
    '  *json*|*xml*|*javascript*|text/plain*|text/csv*|"")',
    '    python3 -c "$QS_CUT" < "$f"; exit 0 ;;',
    'esac',
    'texto=""',
    'aviso=""',
    'if command -v trafilatura >/dev/null 2>&1; then',
    // Las tablas SE CONSERVAN: media respuesta útil de una página de producto
    // (precios, versiones, características) vive dentro de una tabla.
    '  texto=$(trafilatura --no-comments -i "$f" 2>/dev/null)',
    'fi',
    'if [ -z "$texto" ] && command -v w3m >/dev/null 2>&1; then',
    '  texto=$(w3m -dump -T text/html -cols 100 "$f" 2>/dev/null)',
    'fi',
    'if [ -z "$texto" ]; then',
    '  texto=$(python3 -c "$QS_PY" < "$f")',
    // El aviso va SOLO cuando se ha usado el extractor basto, y desaparece en
    // cuanto se instala cualquiera de los otros dos. Es una línea, y es la
    // diferencia entre "esta página se lee fatal" y saber por qué. Se añade
    // DESPUÉS del recorte, o el recorte se lo comería justo en las páginas
    // largas, que son donde más falta hace.
    '  aviso="[extracción básica: instala w3m o trafilatura y estas páginas se leerán mucho mejor]"',
    'fi',
    // El diagnóstico se hace sobre el texto YA extraído, no sobre el HTML: ahí
    // las marcas están limpias y no hay falsos positivos de un script que
    // casualmente mencione "captcha".
    'case "$(printf "%s" "$texto" | python3 -c "$QS_DIAG")" in',
    '  reto)',
    '    echo "' + FETCH_KO + ' Esta página exige un navegador con JavaScript (reto anti-robot). No insistas con esta URL ni con otras del mismo sitio: sin navegador no vas a sacar nada de ahí."; exit 0 ;;',
    '  inexistente)',
    '    echo "' + FETCH_KO + ' La página dice que no existe (un 404 disfrazado de respuesta correcta). No inventes otra URL parecida."; exit 0 ;;',
    '  corta)',
    '    echo "' + FETCH_KO + ' La página apenas trae texto: su contenido lo pinta JavaScript, que aquí no se ejecuta. Con los listados de tienda y las páginas de resultados pasa SIEMPRE, y no hay forma de arreglarlo desde fetch_url."; exit 0 ;;',
    'esac',
    '[ -n "$texto" ] || texto="' + FETCH_KO + ' (la página no tenía texto legible)"',
    'printf "%s" "$texto" | python3 -c "$QS_CUT"',
    '[ -n "$aviso" ] && printf "\\n\\n%s\\n" "$aviso"',
    'exit 0'
].join("\n")

// ── Archivos y red, en solo lectura ──────────────────────────────────────────
// Leer, listar, grep, glob y descargar. La misma jaula ($HOME clampado, todo
// por entorno) que comparten el agente principal y el subagente.
// La pared de esta llamada: el taller del subagente si lo hay, y si no la
// carpeta personal. Se pega al entorno de cualquier constructor que mande una
// ruta, para que el envoltorio pueda comprobar a dónde apunta DE VERDAD.
function conPared(r, ctx) {
    if (r && r.env && r.env.QS_P !== undefined)
        r.env.QS_PARED = String((ctx && (ctx.root || ctx.home)) || "")
    return r
}

function files(tool, args, ctx) {
    return conPared(_files(tool, args, ctx), ctx)
}

function _files(tool, args, ctx) {
    switch (tool) {
    case "read_file": {
        const p = safePath(args.path, ctx.home, ctx.root)
        if (p === "") return { error: "Ruta fuera de la carpeta personal." }
        const off = Math.max(1, parseInt(args.offset) || 1)
        const lim = Math.max(1, Math.min(2000, parseInt(args.limit) || 400))
        // Lectura por TRAMOS de líneas: antes solo llegaban los primeros 16 kB,
        // lo que en un archivo grande es inútil. Y en modo 'numbered', cada
        // línea sale como N#hash|contenido para que edit_lines pueda comprobar
        // después que nada se movió.
        return { cmd: ["python3", "-c", PY_HASH
            + 'import os,sys\n'
            + 'p=os.environ["QS_P"]; off=int(os.environ["QS_OFF"]); lim=int(os.environ["QS_LIM"])\n'
            + 'num=os.environ["QS_NUM"]=="1"\n'
            + 'try: lines=open(p,encoding="utf-8",errors="replace").read().split("\\n")\n'
            + 'except OSError as e: print("No se pudo leer:",e); raise SystemExit\n'
            + 'total=len(lines); sel=lines[off-1:off-1+lim]\n'
            + 'out=[]\n'
            + 'for i,l in enumerate(sel):\n'
            + '    n=off+i\n'
            + '    out.append(f"{n}#{h(l)}|{l}" if num else l)\n'
            // Etiqueta de instantánea del archivo ENTERO: el modelo la
            // devuelve en edit_patch y así el motor sabe de un vistazo si el
            // archivo es el mismo que leyó.
            + 'if num:\n'
            + '    v=2166136261\n'
            + '    for c in "\\n".join(lines).encode("utf-8",errors="replace"):\n'
            + '        v=((v^c)*16777619)&0xFFFFFFFF\n'
            + '    print("[%s#%04x] %d lineas · edita con edit_patch usando las anclas N#hash"\n'
            + '          % (os.path.basename(p), v&0xFFFF, total))\n'
            + 'body="\\n".join(out)[:16000]\n'
            + 'print(body)\n'
            + 'end=off-1+len(sel)\n'
            + 'if end<total: print(f"\\n[…{total-end} lineas mas; sigue con offset={end+1}]")\n'],
            env: { QS_P: p, QS_OFF: String(off), QS_LIM: String(lim),
                   QS_NUM: args.numbered ? "1" : "0" } }
    }
    case "read_files": {
        const lista = Array.isArray(args.paths) ? args.paths.slice(0, 8) : []
        if (lista.length === 0)
            return { error: "Falta la lista 'paths' (hasta 8 rutas)." }
        // Cada ruta se resuelve y se acota en python: aquí realpath ya sigue los
        // enlaces, así que un symlink que escapa de $HOME se rechaza
        // directamente (más estricto que el aviso del caso de un solo archivo, y
        // suficiente para una lectura en lote).
        return { cmd: ["python3", "-c",
            'import os\n'
            + 'home=os.path.realpath(os.path.expanduser("~"))\n'
            + 'taller=os.environ.get("QS_ROOT") or ""\n'
            + 'raiz=os.path.realpath(taller) if taller else home\n'
            + 'out=[]\n'
            + 'for p in os.environ["QS_LIST"].split("\\n"):\n'
            + '    p=p.strip()\n'
            + '    if not p: continue\n'
            + '    cab="\\n--- %s ---\\n" % p\n'
            + '    q=os.path.join(raiz,p) if (taller and not p.startswith(("/","~"))) else p\n'
            + '    ap=os.path.realpath(os.path.abspath(os.path.expanduser(q)))\n'
            + '    if ap!=raiz and not ap.startswith(raiz+os.sep):\n'
            + '        out.append(cab+"[fuera del area de trabajo]"); continue\n'
            + '    try: s=open(ap,encoding="utf-8",errors="replace").read(8000)\n'
            + '    except OSError as e: out.append(cab+"[no se pudo leer: %s]"%e); continue\n'
            + '    out.append(cab+s)\n'
            + 'print("".join(out)[:24000])\n'],
            env: { QS_LIST: lista.map(String).join("\n"),
                   QS_ROOT: ctx.root || "" } }
    }
    case "list_dir": {
        const p = safePath(args.path, ctx.home, ctx.root)
        if (p === "") return { error: "Ruta fuera de la carpeta personal." }
        return { cmd: ["sh", "-c", 'ls -lah -- "$QS_P" | head -n 80'], env: { QS_P: p } }
    }
    case "grep_files": {
        const p = safePath(args.path, ctx.home, ctx.root)
        if (p === "") return { error: "Ruta fuera de la carpeta personal." }
        return { cmd: ["sh", "-c",
            'timeout 15 grep -rnIi --exclude-dir=.git -e "$QS_PAT" -- "$QS_P" | head -c 16000'],
            env: { QS_PAT: String(args.pattern || ""), QS_P: p } }
    }
    case "glob_files": {
        const p = safePath(args.path, ctx.home, ctx.root)
        if (p === "") return { error: "Ruta fuera de la carpeta personal." }
        const tipo = ["file", "dir", "any"].indexOf(String(args.type || "")) !== -1
                     ? String(args.type) : "file"
        const orden = String(args.sort || "") === "mtime" ? "mtime" : "name"
        const tope = Math.max(1, Math.min(1000, parseInt(args.limit) || 200))
        // El respeto a .gitignore se delega a GIT cuando la ruta está en un
        // repo: `git ls-files -co --exclude-standard` da la semántica exacta
        // (anidados, negaciones, .git/info/exclude, el global del usuario)
        // gratis, que reimplementarla a mano es una fuente de sorpresas. Fuera
        // de un repo, un os.walk que salta el ruido de siempre.
        return { cmd: ["python3", "-c",
            'import os,sys,fnmatch,subprocess\n'
            + 'raiz=os.environ["QS_P"]; pat=os.environ["QS_PAT"]\n'
            + 'tipo=os.environ["QS_TYPE"]; orden=os.environ["QS_SORT"]\n'
            + 'tope=int(os.environ["QS_LIMIT"]); usarvcs=os.environ["QS_VCS"]=="1"\n'
            + 'base=raiz if os.path.isdir(raiz) else os.path.dirname(raiz)\n'
            + 'RUIDO={".git","node_modules","__pycache__",".venv","venv",'
            + '".mypy_cache",".pytest_cache",".ruff_cache","target",".cache"}\n'
            + 'rutas=[]; via="walk"\n'
            + 'if usarvcs:\n'
            + '    try:\n'
            + '        top=subprocess.run(["git","-C",base,"rev-parse","--show-toplevel"],\n'
            + '            capture_output=True,text=True,timeout=5)\n'
            + '        if top.returncode==0:\n'
            + '            r=subprocess.run(["git","-C",base,"ls-files","-co",\n'
            + '                "--exclude-standard","-z"],capture_output=True,text=True,timeout=20)\n'
            + '            if r.returncode==0:\n'
            + '                via="git"\n'
            + '                for rel in r.stdout.split("\\0"):\n'
            + '                    if rel: rutas.append(os.path.join(base,rel))\n'
            + '    except Exception: pass\n'
            + 'if via=="walk":\n'
            + '    for dp,dns,fns in os.walk(base):\n'
            + '        dns[:]=[d for d in dns if d not in RUIDO]\n'
            + '        if tipo in ("dir","any"):\n'
            + '            for d in dns: rutas.append(os.path.join(dp,d))\n'
            + '        for f in fns: rutas.append(os.path.join(dp,f))\n'
            + '        if len(rutas)>60000: break\n'
            + 'elif tipo in ("dir","any"):\n'
            + '    vistos=set()\n'
            + '    for f in list(rutas):\n'
            + '        d=os.path.dirname(f)\n'
            + '        while d.startswith(base) and d not in vistos:\n'
            + '            vistos.add(d); rutas.append(d); d=os.path.dirname(d)\n'
            // El patrón casa contra el NOMBRE, salvo que lleve una barra: ahí
            // se compara contra la ruta relativa entera ("src/**/*.py").
            + 'conbarra="/" in pat\n'
            + 'sel=[]\n'
            + 'for r in rutas:\n'
            + '    try:\n'
            + '        esdir=os.path.isdir(r)\n'
            + '    except OSError: continue\n'
            + '    if tipo=="file" and esdir: continue\n'
            + '    if tipo=="dir" and not esdir: continue\n'
            + '    cand=os.path.relpath(r,base) if conbarra else os.path.basename(r)\n'
            + '    if fnmatch.fnmatch(cand,pat) or (conbarra and fnmatch.fnmatch(cand,pat.lstrip("/"))):\n'
            + '        sel.append(r)\n'
            + 'def mt(x):\n'
            + '    try: return os.stat(x).st_mtime\n'
            + '    except OSError: return 0\n'
            + 'if orden=="mtime": sel.sort(key=mt,reverse=True)\n'
            + 'else: sel.sort()\n'
            + 'total=len(sel); sel=sel[:tope]\n'
            + 'import datetime\n'
            + 'for r in sel:\n'
            + '    if orden=="mtime":\n'
            + '        ts=datetime.datetime.fromtimestamp(mt(r)).strftime("%Y-%m-%d %H:%M")\n'
            + '        print(ts+"  "+r)\n'
            + '    else: print(r)\n'
            + 'if total==0: print("(sin coincidencias)")\n'
            + 'if total>len(sel): print("\\n[..."+str(total-len(sel))+" mas; sube limit o afina el patron]")\n'
            + 'nota="respetando .gitignore" if via=="git" else "sin repo git: saltando ruido comun"\n'
            + 'print("["+str(total)+" coincidencias, orden "+orden+", "+nota+"]")\n'],
            env: { QS_P: p, QS_PAT: String(args.pattern || "*"),
                   QS_TYPE: tipo, QS_SORT: orden, QS_LIMIT: String(tope),
                   QS_VCS: args.ignore_vcs === false ? "0" : "1" } }
    }
    case "ast_search": {
        // Búsqueda ESTRUCTURAL con ast-grep: el patrón es código con
        // metavariables ($X casa un nodo, $$$ una lista), no una regex. "$F($$$)"
        // encuentra llamadas aunque cambien los espacios o salten de línea —
        // donde grep ve texto, esto ve el árbol de sintaxis.
        const p = safePath(args.path, ctx.home, ctx.root)
        if (p === "") return { error: "Ruta fuera de la carpeta personal." }
        const pat = String(args.pattern || "").trim()
        if (pat === "") return { error: "Falta el patrón (código con $METAVARIABLES)." }
        const lang = String(args.lang || "").trim()
        let script = 'command -v ast-grep >/dev/null 2>&1 || '
                   + '{ echo "Falta ast-grep. Instálalo: pacman -S ast-grep"; exit 0; }; '
                   + 'timeout 20 ast-grep run --pattern "$QS_PAT"'
        const env = { QS_PAT: pat, QS_P: p }
        if (lang !== "") {
            script += ' --lang "$QS_LANG"'
            env.QS_LANG = lang
        }
        script += ' -- "$QS_P" 2>&1 | head -c 16000'
        return { cmd: ["sh", "-c", script], env: env }
    }
    case "fetch_url": {
        const url = String(args.url || "").trim()
        if (!/^https?:\/\//i.test(url)) return { error: "Solo URLs http(s)." }
        // QS_LAN queda vacío a propósito: solo lo levanta ToolRunner, que es
        // quien sabe si la dirección local pasó por una tarjeta aprobada.
        //
        // QS_U0 es la dirección que escribió el modelo, y viaja aunque haya
        // receta: el formateador de Stack Overflow saca de ahí el enunciado de
        // la pregunta —el enlace lo lleva en el nombre— y así hace falta una
        // sola petición, la de las respuestas, que es lo que se quiere de un
        // enlace a Stack Overflow.
        const rec = receta(url)
        return { cmd: ["sh", "-c", FETCH_SH],
                 env: { QS_U: url, QS_U0: url, QS_LAN: "", QS_RES: PY_RESOLVE,
                        QS_RURL: rec ? rec.url : "", QS_FMT: rec ? rec.id : "",
                        QS_REC: rec ? PY_RECETA : "",
                        QS_PY: PY_DESNUDA, QS_CUT: PY_CORTE,
                        QS_BIN: PY_BINARIO, QS_DIAG: PY_DIAG } }
    }
    }
    return null
}

// ── EL RELOJ Y EL TOPE DE SALIDA, DENTRO DEL COMANDO ─────────────────────────
// El reloj y el TOPE DE SALIDA, los dos dentro del comando.
//
// El reloj: quien mata es coreutils, así que el proceso sale por su propio
// pie, `onExited` llega una sola vez y no hay ninguna carrera que arbitrar
// desde QML. `-k 5`: si a los N segundos no se ha ido con un TERM educado,
// cinco después se le manda un KILL.
//
// El tope: StdioCollector se lo guarda TODO en memoria y no tiene límite.
// Un `yes` o un bucle que escupe —cosa que un modelo escribe sin querer— son
// un gigabyte por segundo dentro del plazo, y eso no es una herramienta que
// falla: es Quickshell entero muriéndose por falta de memoria, con la barra,
// el fondo y las notificaciones dentro. Así que cada flujo pasa por `head`,
// que corta a los N bytes y cierra la tubería; el que siga escribiendo se
// lleva un SIGPIPE y muere, que es exactamente lo que debe pasarle.
//
// Los dos flujos siguen separados (el 5 es el desvío que lo permite sin
// mezclarlos) y el código de salida es el DE LA HERRAMIENTA, no el de `head`:
// se apunta en un archivo antes de que la tubería lo pise. Comprobado:
// salida sin salto final intacta, código 3 conservado, corte por plazo con
// 124 limpio y desbordamiento con 141.
const SH_ACOTADO = [
    'umask 077',
    'd=$(mktemp -d) || exit 97',
    'trap \'rm -rf "$d"\' EXIT INT TERM',
    'n=$1; shift',
    // ── EL CERCO, OTRA VEZ, PERO MIRANDO LA RUTA DE VERDAD ──────────────────
    // safePath comprueba la ruta como TEXTO: que empiece por la carpeta
    // permitida y que no lleve "..". Eso para lo evidente, pero un enlace
    // simbólico no es texto:
    //
    //     ~/proyecto/notas  ->  /etc/passwd
    //
    // se escribe entero dentro de la carpeta personal y apunta fuera. Y el
    // modelo puede haber creado ese enlace él mismo en una llamada anterior.
    //
    // Así que aquí se resuelve con readlink -f —que sigue todos los enlaces del
    // camino— y se vuelve a comprobar contra la pared. Va en el envoltorio y no
    // en cada constructor porque los diez pasan la ruta en QS_P: un solo sitio
    // que auditar, y ninguno que se pueda olvidar.
    //
    // Sin QS_PARED no hay cerco: las consultas del sistema (df sobre /var) miran
    // fuera de casa a propósito y no lo ponen.
    'if [ -n "$QS_PARED" ] && [ -n "$QS_P" ]; then',
    '  real=$(readlink -f -- "$QS_P" 2>/dev/null) || real="$QS_P"',
    '  case "$real" in',
    '    "$QS_PARED"|"$QS_PARED"/*) ;;',
    '    *) printf "%s\\n" "La ruta lleva fuera de la carpeta permitida: sigue un enlace simbólico que acaba en $real. No se toca." >&2; exit 96 ;;',
    '  esac',
    'fi',
    '{ { timeout -k 5 "$n" "$@"; echo $? > "$d/s"; } 2>&1 1>&5'
        + ' | head -c 131072 > "$d/e"; } 5>&1 | head -c 2097152 > "$d/o"',
    'cat "$d/o"',
    'cat "$d/e" >&2',
    'exit "$(cat "$d/s" 2>/dev/null || echo 97)"'
].join("\n")



// Envuelve un comando: plazo en segundos y salida acotada. Lo usan el ejecutor
// de herramientas y el de hooks — dos sitios que lanzan comandos del usuario o
// del modelo, y los dos con el mismo par de problemas.
function acotado(segundos, cmd) {
    return ["sh", "-c", SH_ACOTADO, "sh", String(segundos)].concat(cmd)
}

// ── Escritura ────────────────────────────────────────────────────────────────
// Los dos constructores que TOCAN el disco de verdad: crear/sobrescribir un
// archivo y sustituir un fragmento exacto. Viven aquí por el mismo motivo que
// los de lectura: son jaula, y el subagente escribe con ellos igual que su jefe
// —cambia la pared (su taller, no $HOME), no el mecanismo—. La ruta llega YA
// resuelta y comprobada por quien llama, que es quien sabe contra qué pared
// mide.
function writes(tool, p, args, bak, bakDir, ctx) {
    return conPared(_writes(tool, p, args, bak, bakDir), ctx)
}

function _writes(tool, p, args, bak, bakDir) {
    switch (tool) {
    case "write_file":
        // El contenido viaja por entorno (nunca argv) y se escribe con printf;
        // la carpeta destino se crea si falta. Copia de seguridad antes de
        // sobrescribir: es lo que permite Deshacer. Si el archivo no existía, no
        // hay nada que copiar (y deshacer significará borrarlo).
        return { cmd: ["sh", "-c",
            // El umask va en un subshell y solo alrededor del directorio de
            // copias: ahí dentro hay archivos enteros del usuario y no tiene por
            // qué listarlo nadie más. El archivo que se escribe queda con el
            // modo de siempre — que un archivo pedido por el usuario nazca
            // ilegible para su propio grupo sería una sorpresa, no una mejora.
            '(umask 077; mkdir -p "$QS_BD"); mkdir -p "$(dirname -- "$QS_P")"; '
            // Dos casos, y hay que poder distinguirlos DESPUÉS: si el archivo
            // existía se copia, y si no existía se deja una señal. Sin la señal,
            // Deshacer no puede saber si la falta de copia significa "era nuevo,
            // bórralo" o "la copia falló" — y en el segundo caso borraría un
            // archivo que sí existía. Un botón de deshacer que destruye es lo
            // contrario de un botón de deshacer.
            + 'if [ -f "$QS_P" ]; then cp -a -- "$QS_P" "$QS_BAK" || exit 1; '
            + 'else : > "$QS_BAK.nuevo"; fi; '
            + 'printf %s "$QS_C" > "$QS_P" && echo "Escrito: $QS_P ($(wc -c < "$QS_P") bytes)"'],
            env: { QS_P: p, QS_C: String(args.content || ""),
                   QS_BAK: bak, QS_BD: bakDir } }
    case "edit_file":
        // Sustitución exacta con la regla de unicidad del FileEditTool: 0
        // apariciones = error, 2+ = error (pide más contexto), 1 = edita. Todo
        // por entorno y en python3, que no re-interpreta nada.
        return { cmd: ["python3", "-c",
            'import os,sys,shutil\n'
            + 'p=os.environ["QS_P"]; old=os.environ["QS_OLD"]; new=os.environ["QS_NEW"]\n'
            + 'try: s=open(p,encoding="utf-8",errors="replace").read()\n'
            + 'except OSError as e: print("No se pudo leer:",e); sys.exit(0)\n'
            + 'n=s.count(old)\n'
            + 'if n==0: print("old_string no aparece en el archivo."); sys.exit(0)\n'
            + 'if n>1: print("old_string aparece",n,"veces; amplia el contexto para que sea unico."); sys.exit(0)\n'
            + 'os.makedirs(os.environ["QS_BD"],exist_ok=True); shutil.copy2(p,os.environ["QS_BAK"])\n'
            + 'open(p,"w",encoding="utf-8").write(s.replace(old,new,1))\n'
            + 'print("Editado:",p)'],
            env: { QS_P: p, QS_OLD: String(args.old_string || ""),
                   QS_NEW: String(args.new_string || ""),
                   QS_BAK: bak, QS_BD: bakDir } }
    }
    return null
}

// ── Edición estructural (ast_edit) ───────────────────────────────────────────
// La reescritura de ast-grep sobre UN archivo, con copia previa para el botón
// Deshacer y el diff en el resultado — el modelo ve exactamente qué cambió,
// que con una reescritura estructural no siempre es lo que uno imagina.
// El bak lo decide quien llama (es quien lo anota en la tarjeta).
function astEdit(args, ctx, bak, bakDir) {
    return conPared(_astEdit(args, ctx, bak, bakDir), ctx)
}

function _astEdit(args, ctx, bak, bakDir) {
    const p = safePath(args.path, ctx.home, ctx.root)
    if (p === "") return { error: "Ruta fuera de la carpeta personal." }
    const pat = String(args.pattern || "").trim()
    const rw = args.rewrite === undefined ? null : String(args.rewrite)
    if (pat === "") return { error: "Falta el patrón (código con $METAVARIABLES)." }
    if (rw === null) return { error: "Falta rewrite (puede ser \"\" para borrar lo casado)." }
    const lang = String(args.lang || "").trim()
    let ag = 'ast-grep run --pattern "$QS_PAT" --rewrite "$QS_RW"'
    const env = { QS_PAT: pat, QS_RW: rw, QS_P: p, QS_BAK: bak, QS_BD: bakDir }
    if (lang !== "") {
        ag += ' --lang "$QS_LANG"'
        env.QS_LANG = lang
    }
    return { cmd: ["sh", "-c",
        'command -v ast-grep >/dev/null 2>&1 || '
        + '{ echo "Falta ast-grep. Instálalo: pacman -S ast-grep"; exit 0; }; '
        + '[ -f "$QS_P" ] || { echo "No existe el archivo."; exit 0; }; '
        + '(umask 077; mkdir -p "$QS_BD"); cp -a -- "$QS_P" "$QS_BAK"; '
        + 'timeout 20 ' + ag + ' --update-all -- "$QS_P" 2>&1; '
        + 'if cmp -s -- "$QS_BAK" "$QS_P"; then '
        + 'echo "El patrón no casó con nada: el archivo queda igual."; '
        + 'else echo "Cambios aplicados:"; '
        + 'diff -u -- "$QS_BAK" "$QS_P" | tail -n +3 | head -c 6000; fi'],
        env: env }
}

// ── Edición anclada por hash (hashline) ──────────────────────────────────────
// La puerta al motor bin/hashline.py: un parche de VARIOS hunks anclados por
// contenido, aplicado todo-o-nada, con recuperación de anclas que se movieron.
// Es el camino de edición preferente del harness — más barato que reproducir el
// texto viejo y más seguro que editar por número de línea a secas.
// El bak lo decide quien llama (es quien lo anota en la tarjeta).
function hashPatch(args, ctx, bak, bakDir, iaDir) {
    return conPared(_hashPatch(args, ctx, bak, bakDir, iaDir), ctx)
}

function _hashPatch(args, ctx, bak, bakDir, iaDir) {
    const p = safePath(args.path, ctx.home, ctx.root)
    if (p === "") return { error: "Ruta fuera de la carpeta personal." }
    const hunks = Array.isArray(args.hunks) ? args.hunks : null
    if (!hunks || hunks.length === 0)
        return { error: "Falta 'hunks': una lista de cambios anclados, "
                      + "p. ej. [{\"op\":\"replace\",\"at\":\"42#nd\",\"text\":\"…\"}]." }
    if (hunks.length > 40)
        return { error: "Demasiados hunks (" + hunks.length + "): parte el trabajo." }
    return { cmd: ["python3", iaDir + "/bin/hashline.py"],
             env: { QS_P: p,
                    QS_HUNKS: JSON.stringify(hunks),
                    QS_TAG: String(args.tag || ""),
                    QS_DRY: args.dry_run === true ? "1" : "0",
                    QS_WIN: String(Math.max(0, Math.min(400,
                        parseInt(args.recover_window) || 40))),
                    QS_BAK: bak, QS_BD: bakDir } }
}
