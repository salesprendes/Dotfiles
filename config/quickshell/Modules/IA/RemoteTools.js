// Servidores remotos: SSH / SFTP / Plesk / cPanel. La misma división que en
// local — CONSULTAS curadas (el harness construye el comando, el modelo solo
// elige host y unos filtros → auto-aprobables y heredadas por el subagente) y
// ACCIONES crudas (ejecutar por SSH, subir/bajar archivos → siempre con
// tarjeta), que las arma quien las aprueba.
//
// Transporte: ssh/scp con clave (agente) o, si el host tiene contraseña,
// sshpass tomándola por ENTORNO (SSHPASS) — jamás en argv, que se ve en `ps`.
// Cualquier dato del modelo que entre en un comando REMOTO viaja en base64 y se
// descodifica en el otro extremo (`printf %s B64 | base64 -d`): el base64 no
// lleva comillas ni metacaracteres, así que no hay forma de que un nombre de
// dominio "creativo" se convierta en otra orden.
//
// El contexto (servidores guardados, contraseñas en memoria, si hay sshpass)
// llega como argumento en vez de leerse de Settings: así este archivo no sabe
// nada del shell y se puede razonar sobre él solo.
//   ctx = { hosts: [...], pass: {nombre: clave}, haveSshpass: bool }
.pragma library

.import "TextUtils.js" as TU

// Resolución del destino. La idea es que el harness FUNCIONE SOLO: si el
// usuario dice "entra en root@1.2.3.4 con la contraseña X y mírame los logs",
// eso basta — no hay que registrar nada antes. Los servidores guardados existen
// como comodidad (escribir "web1" en vez de repetir credenciales), no como
// requisito.
//
// 'host' admite las dos formas: el nombre de uno guardado, o un destino suelto
// tipo [usuario@]host[:puerto]. Los parámetros user/port/password de la llamada
// siempre mandan sobre lo guardado.
function resolveHost(spec, args, ctx) {
    const raw = String(spec || "").trim()
    if (raw === "")
        return null
    const saved = (ctx.hosts || []).find(h => h.name === raw)
    let host = saved
        ? { name: saved.name, host: saved.host, user: saved.user,
            port: saved.port, saved: true }
        : null
    if (!host) {
        // Destino suelto del mensaje: [usuario@]host[:puerto]
        let rest = raw, user = "root", port = 22
        const at = rest.indexOf("@")
        if (at > 0) { user = rest.slice(0, at); rest = rest.slice(at + 1) }
        const colon = rest.lastIndexOf(":")
        if (colon > 0 && /^\d+$/.test(rest.slice(colon + 1))) {
            port = parseInt(rest.slice(colon + 1))
            rest = rest.slice(0, colon)
        }
        if (rest === "")
            return null
        host = { name: raw, host: rest, user: user, port: port, saved: false }
    }
    // Lo que venga en la llamada pisa: el mensaje es la última palabra.
    const a = args || ({})
    if (String(a.user || "").trim() !== "") host.user = String(a.user).trim()
    if (parseInt(a.port) > 0) host.port = parseInt(a.port)
    return host
}

// Prefijo argv del transporte + entorno, según haya contraseña o no.
function transport(bin, host, portFlag, explicitPw, ctx) {
    const pw = String(explicitPw || "").trim() !== ""
        ? String(explicitPw).trim() : ((ctx.pass || {})[host.name] || "")
    // Marca de contraseña-sin-sshpass: quien llama lo detecta y avisa.
    if (pw !== "" && !ctx.haveSshpass)
        return { argv: [], env: {}, needsSshpass: true }
    const port = String(host.port || 22)
    const opts = ["-o", "StrictHostKeyChecking=accept-new",
                  "-o", "ConnectTimeout=12", "-o", "ServerAliveInterval=5",
                  "-o", "NumberOfPasswordPrompts=1", portFlag, port]
    const dest = (host.user || "root") + "@" + host.host
    if (pw !== "")
        return { argv: ["sshpass", "-e", bin].concat(opts).concat([dest]),
                 env: { SSHPASS: pw } }
    // Sin contraseña: clave/agente, y BatchMode para que no se cuelgue
    // pidiéndola por un terminal que no existe.
    return { argv: [bin].concat(opts).concat(["-o", "BatchMode=yes", dest]),
             env: {} }
}

// Destino + transporte de una llamada remota, con los dos fallos que siempre
// hay que contar antes de intentar nada: no sé a qué máquina, o hay contraseña
// y no está sshpass. Los tres sitios que abren una conexión repetían estas
// mismas comprobaciones y sus mismos mensajes.
// Devuelve {host, t} o {error}.
function connect(args, bin, portFlag, ctx) {
    const host = resolveHost(args.host, args, ctx)
    if (!host)
        return { error: "Falta el servidor. Dime el destino (por ejemplo "
            + "root@1.2.3.4) o el nombre de uno guardado." }
    const t = transport(bin, host, portFlag, args.password, ctx)
    if (t.needsSshpass)
        return { error: "Falta 'sshpass' para entrar con contraseña. "
            + "Instálalo (pacman -S sshpass) o usa una clave SSH." }
    return { host: host, t: t }
}

// Un dato del modelo, listo para viajar dentro de un comando remoto.
// TU.b64utf8, no Qt.btoa: btoa trabaja en Latin-1 y cualquier tilde ("sesión",
// un dominio con ñ) llegaba al servidor como byte inválido.
function rarg(v) {
    return '"$(printf %s ' + TU.b64utf8(String(v)) + ' | base64 -d)"'
}

// Las herramientas remotas que NO cambian nada. Es también la lista que decide
// si sshQuery se hace cargo de una llamada.
const CONSULTAS = ["server_status", "server_logs", "sftp_ls", "hosting_query"]

// CONSULTAS remotas (solo lectura). Comparten builder con el subagente.
function query(tool, args, ctx) {
    if (CONSULTAS.indexOf(tool) === -1)
        return null
    const conn = connect(args, "ssh", "-p", ctx)
    if (conn.error !== undefined)
        return conn
    const host = conn.host, t = conn.t
    let remote = ""
    switch (tool) {
    case "server_status":
        remote = 'echo "== uptime"; uptime; echo "== memoria"; free -h; '
               + 'echo "== discos"; df -h -x tmpfs -x devtmpfs 2>/dev/null; '
               + 'echo "== fallidas"; systemctl --failed --no-legend --no-pager 2>/dev/null | head -n 10; '
               + 'echo "== top"; ps axo pid,%cpu,%mem,comm --sort=-%cpu | head -n 8'
        break
    case "server_logs": {
        const lines = Math.min(Math.max(parseInt(args.lines) || 60, 1), 300)
        const path = String(args.path || "").trim()
        if (path !== "") {
            // Un archivo de log concreto (nginx, apache, plesk…).
            remote = 'tail -n ' + lines + ' -- ' + rarg(path)
            if (String(args.grep || "").trim() !== "")
                remote += ' | grep -iF -- ' + rarg(args.grep)
        } else {
            remote = 'journalctl --no-pager -o short-iso -n ' + lines
            if (String(args.unit || "").trim() !== "")
                remote += ' -u ' + rarg(args.unit)
            const prios = ["emerg","alert","crit","err","warning","notice","info","debug"]
            if (prios.indexOf(String(args.priority || "")) !== -1)
                remote += ' -p ' + args.priority
            if (String(args.since || "").trim() !== "")
                remote += ' --since ' + rarg(args.since)
            if (String(args.grep || "").trim() !== "")
                remote += ' -g ' + rarg(args.grep)
        }
        remote += ' 2>&1 | tail -c 16000'
        break
    }
    case "sftp_ls": {
        const path = String(args.path || ".").trim() || "."
        remote = 'ls -lah -- ' + rarg(path) + ' 2>&1 | head -n 100'
        break
    }
    case "hosting_query":
        return hostingRead(host, t, args)
    }
    return { cmd: t.argv.concat([remote]), env: t.env }
}

// Lecturas de Plesk / cPanel: cada 'op' es un comando FIJO del panel; lo único
// variable (un dominio, una cuenta) entra en base64.
function hostingRead(host, t, args) {
    const panel = String(args.panel || "")
    const op = String(args.op || "")
    const name = String(args.name || "").trim()
    let remote = ""
    if (panel === "plesk") {
        switch (op) {
        case "version": remote = 'plesk version'; break
        case "domains": remote = 'plesk bin domain --list'; break
        case "subscriptions": remote = 'plesk bin subscription --list'; break
        case "databases": remote = 'plesk bin database --list'; break
        case "domain_info":
            if (name === "") return { error: "Falta el dominio." }
            remote = 'plesk bin domain --info ' + rarg(name); break
        default: return { error: "op de Plesk no válida (version, domains, subscriptions, databases, domain_info)." }
        }
    } else if (panel === "cpanel") {
        switch (op) {
        case "version": remote = 'whmapi1 version'; break
        case "accounts": remote = 'whmapi1 listaccts'; break
        case "account_info":
            if (name === "") return { error: "Falta la cuenta." }
            remote = 'whmapi1 accountsummary user=' + rarg(name); break
        case "domains": remote = 'whmapi1 get_domain_info'; break
        case "disk": remote = 'whmapi1 getdiskusage'; break
        default: return { error: "op de cPanel no válida (version, accounts, account_info, domains, disk)." }
        }
    } else {
        return { error: "panel debe ser 'plesk' o 'cpanel'." }
    }
    // Panel bajo sudo si el usuario no es root (habitual con Plesk/WHM).
    const wrapped = (host.user && host.user !== "root")
        ? 'sudo -n sh -c ' + rarg(remote) : remote
    return { cmd: t.argv.concat([wrapped + ' 2>&1 | tail -c 16000']), env: t.env }
}
