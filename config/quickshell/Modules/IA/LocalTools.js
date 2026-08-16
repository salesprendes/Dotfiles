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
    'resp=$(curl -sSL --compressed --max-time 20 --max-filesize 2000000 -A "$ua" -o "$f" -w "%{content_type}|%{http_code}" -- "$QS_U" 2>/dev/null)',
    'ct=${resp%|*}; code=${resp##*|}',
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
function files(tool, args, ctx) {
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
        return { cmd: ["sh", "-c", FETCH_SH],
                 env: { QS_U: url, QS_PY: PY_DESNUDA, QS_CUT: PY_CORTE,
                        QS_BIN: PY_BINARIO, QS_DIAG: PY_DIAG } }
    }
    }
    return null
}

// ── Escritura ────────────────────────────────────────────────────────────────
// Los dos constructores que TOCAN el disco de verdad: crear/sobrescribir un
// archivo y sustituir un fragmento exacto. Viven aquí por el mismo motivo que
// los de lectura: son jaula, y el subagente escribe con ellos igual que su jefe
// —cambia la pared (su taller, no $HOME), no el mecanismo—. La ruta llega YA
// resuelta y comprobada por quien llama, que es quien sabe contra qué pared
// mide.
function writes(tool, p, args, bak, bakDir) {
    switch (tool) {
    case "write_file":
        // El contenido viaja por entorno (nunca argv) y se escribe con printf;
        // la carpeta destino se crea si falta. Copia de seguridad antes de
        // sobrescribir: es lo que permite Deshacer. Si el archivo no existía, no
        // hay nada que copiar (y deshacer significará borrarlo).
        return { cmd: ["sh", "-c",
            'mkdir -p "$QS_BD" "$(dirname -- "$QS_P")"; '
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
        + 'mkdir -p "$QS_BD"; cp -a -- "$QS_P" "$QS_BAK"; '
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
