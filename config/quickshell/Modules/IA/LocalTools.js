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
function safePath(p, home) {
    let path = String(p).trim()
    if (path === "~")
        path = home
    else if (path.startsWith("~/"))
        path = home + path.slice(1)
    if (!path.startsWith(home + "/") && path !== home)
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

// ── Archivos y red, en solo lectura ──────────────────────────────────────────
// Leer, listar, grep, glob y descargar. La misma jaula ($HOME clampado, todo
// por entorno) que comparten el agente principal y el subagente.
function files(tool, args, ctx) {
    switch (tool) {
    case "read_file": {
        const p = safePath(args.path, ctx.home)
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
            + 'out=[]\n'
            + 'for p in os.environ["QS_LIST"].split("\\n"):\n'
            + '    p=p.strip()\n'
            + '    if not p: continue\n'
            + '    ap=os.path.realpath(os.path.abspath(os.path.expanduser(p)))\n'
            + '    cab="\\n--- %s ---\\n" % p\n'
            + '    if ap!=home and not ap.startswith(home+os.sep):\n'
            + '        out.append(cab+"[fuera de la carpeta personal]"); continue\n'
            + '    try: s=open(ap,encoding="utf-8",errors="replace").read(8000)\n'
            + '    except OSError as e: out.append(cab+"[no se pudo leer: %s]"%e); continue\n'
            + '    out.append(cab+s)\n'
            + 'print("".join(out)[:24000])\n'],
            env: { QS_LIST: lista.map(String).join("\n") } }
    }
    case "list_dir": {
        const p = safePath(args.path, ctx.home)
        if (p === "") return { error: "Ruta fuera de la carpeta personal." }
        return { cmd: ["sh", "-c", 'ls -lah -- "$QS_P" | head -n 80'], env: { QS_P: p } }
    }
    case "grep_files": {
        const p = safePath(args.path, ctx.home)
        if (p === "") return { error: "Ruta fuera de la carpeta personal." }
        return { cmd: ["sh", "-c",
            'timeout 15 grep -rnIi --exclude-dir=.git -e "$QS_PAT" -- "$QS_P" | head -c 16000'],
            env: { QS_PAT: String(args.pattern || ""), QS_P: p } }
    }
    case "glob_files": {
        const p = safePath(args.path, ctx.home)
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
        const p = safePath(args.path, ctx.home)
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
        return { cmd: ["sh", "-c",
            'curl -sSL --max-time 20 --max-filesize 2000000 -- "$QS_U" | '
            // errors=replace: una web en Latin-1 (las viejas en español) no debe
            // tirar la herramienta entera por un byte — los que no sean UTF-8
            // salen como "�" y el resto del texto se conserva.
            + 'python3 -c "import sys,re,html; sys.stdin.reconfigure(errors=\'replace\'); t=sys.stdin.read(); '
            + "t=re.sub(r'(?is)<(script|style)[^>]*>.*?</\\\\1>',' ',t); "
            + "t=re.sub(r'(?s)<[^>]+>',' ',t); t=html.unescape(t); "
            + "t=re.sub(r'[ \\\\t]+',' ',t); t=re.sub(r'\\\\n\\\\s*\\\\n+','\\\\n\\\\n',t); "
            + 'print(t.strip()[:20000])"'], env: { QS_U: url } }
    }
    }
    return null
}

// ── Edición estructural (ast_edit) ───────────────────────────────────────────
// La reescritura de ast-grep sobre UN archivo, con copia previa para el botón
// Deshacer y el diff en el resultado — el modelo ve exactamente qué cambió,
// que con una reescritura estructural no siempre es lo que uno imagina.
// El bak lo decide quien llama (es quien lo anota en la tarjeta).
function astEdit(args, ctx, bak, bakDir) {
    const p = safePath(args.path, ctx.home)
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
