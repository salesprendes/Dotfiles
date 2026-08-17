// LA RÁFAGA DE LECTURAS Y EL CACHÉ DEL SUPERVISOR. Las dos se apoyan en lo
// mismo: reconocer un comando de SOLO LECTURA. Y esa es una lista blanca que
// decide si una llamada a una máquina ajena se ejecuta SIN tarjeta, así que
// cada falso positivo aquí es un agujero — de ahí que la mitad de esta batería
// sean comandos que NO deben colarse.
const fs = require("fs")
const vm = require("vm")
const path = require("path")

const IA = require("path").resolve(__dirname, "..") + "/"

function cargaLib(rel, cache) {
    cache = cache || ({})
    if (cache[rel])
        return cache[rel]
    const ruta = path.resolve(IA, rel)
    let src = fs.readFileSync(ruta, "utf8")
    const importa = []
    src = src.replace(/^\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/mg, (m, f, n) => {
        importa.push({ f: path.relative(IA, path.resolve(path.dirname(ruta), f)), n: n })
        return ""
    })
    src = src.replace(/^\.pragma library$/m, "")
    const nombres = []
    const re = /^(?:function|const|let|var)\s+(\w+)/mg
    let m2
    while ((m2 = re.exec(src)) !== null)
        if (nombres.indexOf(m2[1]) === -1)
            nombres.push(m2[1])
    const caja = ({})
    vm.createContext(caja)
    for (let i = 0; i < importa.length; i++)
        caja[importa[i].n] = cargaLib(importa[i].f, cache)
    vm.runInContext(src + ";__x={" + nombres.map(n => n + ":" + n).join(",") + "};", caja)
    cache[rel] = caja.__x
    return caja.__x
}

const TP = cargaLib("tools/ToolPolicy.js")
const RUNNER = fs.readFileSync(IA + "tools/ToolRunner.qml", "utf8")
const SUP = fs.readFileSync(IA + "agents/AgentSupervisor.qml", "utf8")

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) { ok++; return }
    mal++
    console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : ""))
}

// ── 1. Lo que SÍ es leer ─────────────────────────────────────────────────────
const LEE = [
    "uptime", "free -h", "df -h", "ls -la /var/log", "cat /etc/os-release",
    "ps aux", "ss -tlnp", "journalctl -u nginx -n 50",
    "uptime; free -h; df -h; systemctl --failed",
    "systemctl status nginx", "systemctl is-active bsbdata-api",
    "sudo k3s kubectl get pods -A", "kubectl describe pod x -n y",
    "kubectl get svc -A --request-timeout=8s", "kubectl logs influxdb-0 -n x",
    "docker ps", "git status", "git log --oneline -5",
    "journalctl -u x -n 50 | grep -i error", "mount", "lsblk",
    "FOO=1 uptime", "/usr/bin/ls /tmp", "dig +short A example.com"
]
for (const c of LEE)
    comprueba("lee: " + c, TP.readOnlyCommand(c) === true)

// ── 2. Lo que NO puede colarse ───────────────────────────────────────────────
// Cada uno de estos, tomado por lectura, sería una ejecución sin tarjeta en
// una máquina de producción.
const NO_LEE = [
    "rm -rf /tmp/x", "mv a b", "cp a b", "chmod 777 /etc", "chown root x",
    "dd if=/dev/zero of=/dev/sda", "kill -9 123", "reboot", "shutdown -h now",
    "systemctl restart nginx", "systemctl stop bsbdata-api",
    "kubectl delete pod x", "kubectl apply -f x.yaml", "kubectl scale sts x --replicas=0",
    "kubectl edit svc x", "k3s kubectl delete pod x",
    "docker rm -f x", "git push", "git commit -m x", "git reset --hard",
    "echo hola > /tmp/f", "cat a >> b", "ls; rm x", "ls && rm x",
    "cat f | tee /tmp/g", "bash -c ls", "sh -c 'ls'", "python3 x.py",
    "node x.js", "npm install", "make", "curl -o /tmp/f http://x",
    "wget -O /tmp/f http://x", "curl -d 'a=1' http://x",
    "ls $(rm x)", "ls `rm x`", "nc -l 1234", "crontab -e", "passwd",
    "useradd malo", "iptables -F", "swapoff -a", "truncate -s 0 /var/log/x",
    "ln -sf /etc/passwd /tmp/x", "touch /etc/cron.d/x", "",
    "unknownbinary --que-sea", "kubectl", "systemctl"
]
for (const c of NO_LEE)
    comprueba("NO lee: " + JSON.stringify(c), TP.readOnlyCommand(c) === false)

// ── 3. La firma ──────────────────────────────────────────────────────────────
const k = (tool, host, cmd) =>
    TP.verdictKey(tool, JSON.stringify({ host: host, command: cmd }))

comprueba("dos lecturas del mismo host comparten firma",
          k("ssh_exec", "web1", "kubectl get pods -A") !== null
          && k("ssh_exec", "web1", "kubectl get pods -A")
             === k("ssh_exec", "web1", "cat /etc/os-release"))
// El host manda: una ráfaga concedida sobre una máquina no puede valer para
// otra, que es justo la confusión que convertiría "mira mi servidor" en
// "ejecuta en el de producción".
comprueba("otro host es otra firma",
          k("ssh_exec", "web1", "uptime") !== k("ssh_exec", "web2", "uptime"))
comprueba("otra herramienta es otra firma",
          k("ssh_exec", "", "uptime") !== k("run_command", "", "uptime"))
comprueba("un comando que escribe no tiene firma",
          k("ssh_exec", "web1", "rm -rf /x") === null)
comprueba("una herramienta que no ejecuta comandos tampoco",
          TP.verdictKey("write_file", JSON.stringify({ path: "x" })) === null)
comprueba("argumentos ilegibles no rompen nada",
          TP.verdictKey("ssh_exec", "{no es json") === null)
comprueba("y sin comando tampoco hay firma",
          TP.verdictKey("ssh_exec", JSON.stringify({ host: "a" })) === null)

// ── 4. Las costuras en QML ───────────────────────────────────────────────────
// La garantía dura: lo crítico sigue sin auto-aprobarse por el NOMBRE de la
// herramienta. La única salida es la ráfaga, que exige firma de solo lectura.
comprueba("neverAuto sigue mandando salvo ráfaga",
          /if \(TP\.neverAuto\(name\)\)\s*\n\s*return inBurst\(name, argsJson\) \? "auto" : "ask"/.test(RUNNER))
comprueba("ssh_exec sigue siendo crítico", TP.neverAuto("ssh_exec") === true)
comprueba("y no admite permiso permanente", TP.canStandingAllow("ssh_exec") === false)
comprueba("la ráfaga solo se concede con firma válida",
          /function allowBurst[\s\S]{0,300}?if \(k === null\)\s*\n\s*return false/.test(RUNNER))
comprueba("la ráfaga muere al cambiar de hilo",
          /function resetThread\(\)[\s\S]{0,200}?burstAllow = \(\{\}\)/.test(RUNNER))
comprueba("y al empezar un encargo nuevo",
          fs.readFileSync(IA + "core/AiService.qml", "utf8")
            .indexOf("tools.burstAllow = ({})") !== -1)
comprueba("el supervisor cachea por firma canónica",
          /const firma = TP\.verdictKey\(m\.toolName, m\.toolArgs\)/.test(SUP))
comprueba("y cae a la firma exacta si no la hay",
          /\|\| \(String\(m\.toolName\)/.test(SUP))

console.log(ok + " bien, " + mal + " mal")
process.exit(mal === 0 ? 0 : 1)
