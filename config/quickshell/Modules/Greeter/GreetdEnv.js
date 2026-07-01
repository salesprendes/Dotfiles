.pragma library
//  ╔══════════════════════════════════════════════════════════╗
//  ║   GreetdEnv — helpers puros (sin estado): parseo + argv     ║
//  ╚══════════════════════════════════════════════════════════╝

// /etc/passwd → [{ name, full, shell }]  (solo cuentas humanas)
function parsePasswd(txt) {
    const out = []
    if (!txt) return out
    const lines = txt.split("\n")
    for (let i = 0; i < lines.length; i++) {
        const f = lines[i].split(":")
        if (f.length < 7) continue
        const uid = parseInt(f[2], 10)
        const sh = f[6] || ""
        if (uid >= 1000 && uid < 65000
                && sh.indexOf("nologin") === -1 && sh.indexOf("false") === -1) {
            const gecos = (f[4] || "").split(",")[0].trim()
            out.push({ name: f[0], full: gecos !== "" ? gecos : f[0], shell: sh })
        }
    }
    return out
}

// Volcado concatenado de los .desktop de sesión (con separador
// "@@SESSION@@<ruta>\n<contenido>") → [{ id, name, exec }]
function parseSessions(dump) {
    const out = []
    if (!dump) return out
    const blocks = dump.split("@@SESSION@@")
    for (let b = 0; b < blocks.length; b++) {
        const blk = blocks[b]
        if (!blk.trim()) continue
        const nl = blk.indexOf("\n")
        if (nl < 0) continue
        const path = blk.substring(0, nl).trim()
        const body = blk.substring(nl + 1)
        let name = "", exec = "", hidden = false, inEntry = false
        const lines = body.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const ln = lines[i].trim()
            if (ln.startsWith("[")) { inEntry = (ln === "[Desktop Entry]"); continue }
            if (!inEntry) continue
            if (ln.startsWith("Name=") && !name)          name = ln.substring(5).trim()
            else if (ln.startsWith("Exec=") && !exec)     exec = ln.substring(5).trim()
            else if (ln.startsWith("Hidden=true") || ln.startsWith("NoDisplay=true")) hidden = true
        }
        if (exec && !hidden) {
            const id = path.substring(path.lastIndexOf("/") + 1).replace(/\.desktop$/, "")
            out.push({ id: id, name: name || id, exec: exec })
        }
    }
    return out
}

// argv para Greetd.launch(): ejecuta la sesión a través del shell de
// LOGIN del usuario (para heredar PATH/perfil completos) y 'exec' para
// no dejar un shell colgando de padre. Igual que entrar desde una TTY.
function launchArgv(loginShell, sessionExec) {
    const sh = (loginShell && loginShell !== "") ? loginShell : "/bin/sh"
    return [sh, "-l", "-c", "exec " + sessionExec]
}
