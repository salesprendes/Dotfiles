// A QUÉ HABILIDAD VA CADA FRASE. La batería anterior (t_habilidades) comprueba
// las REGLAS del puntuador con habilidades de mentira; esta comprueba el
// RESULTADO con las de verdad: carga los SKILL.md del disco, los parsea igual
// que SkillStore y pasa un corpus de frases como las escribe el usuario.
//
// Existe porque el enrutado se rompe en silencio y por la puerta de atrás. Los
// tres modos, todos medidos aquí:
//
//   · SUBCADENA. El puntuador busca la raíz de la palabra DENTRO del texto de
//     la habilidad, así que "ayer" casaba con "layer-shell" y "pasa" con
//     "repasa": frases de incidencias que aterrizaban en Quickshell.
//   · PALABRA COMÚN. Una palabra que aparece en tres habilidades deja de
//     distinguir (descuento tipo IDF). Nombrar "Plesk" de pasada en dos
//     descripciones ajenas dejó a la habilidad de Plesk sin poder ganar con su
//     propio nombre.
//   · EMPATE. Con margen de 2, dos habilidades a la misma puntuación no
//     deciden NADA y la elección cae al router. Es el modo bueno: se prefiere
//     un empate a acertar por los pelos.
//
// Si esta batería falla tras editar una descripción, el fallo es real: alguien
// le quitó a una habilidad la palabra con la que se la llamaba.
const fs = require("fs")
const vm = require("vm")
const path = require("path")

const IA = path.resolve(__dirname, "..") + "/"

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

const TU = cargaLib("TextUtils.js")
const STORE = fs.readFileSync(IA + "storage/SkillStore.qml", "utf8")

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) { ok++; return }
    mal++
    console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : ""))
}

// ── Las habilidades del disco, leídas como las lee SkillStore ────────────────
// Mismas expresiones y misma normalización de triggers (comillas fuera, comas
// a espacios). Si SkillStore cambia de formato, esto se entera aquí.
const DIR = IA + "skills/"
const skills = fs.readdirSync(DIR)
    .filter(d => fs.existsSync(DIR + d + "/SKILL.md"))
    .map(d => {
        const t = fs.readFileSync(DIR + d + "/SKILL.md", "utf8")
        const fm = t.match(/^---\n([\s\S]*?)\n---/)
        const cabecera = fm ? fm[1] : ""
        const uno = (k) => {
            const m = cabecera.match(new RegExp("^" + k + ":\\s*(.+)$", "m"))
            return m ? m[1].trim().replace(/^["']|["']$/g, "") : ""
        }
        const tg = cabecera.match(/^triggers:\s*(.+)$/m)
        return {
            id: d,
            name: uno("name"),
            description: uno("description"),
            triggers: tg ? tg[1].trim().replace(/^\[|\]$/g, "")
                                .replace(/["']/g, "").replace(/,/g, " ") : ""
        }
    })

comprueba("hay habilidades que medir", skills.length >= 20, skills.length)

// El suelo y el margen salen del propio SkillStore: si allí se aflojan, aquí
// se mide con los nuevos, no con una copia que se quedó vieja.
const suelo = Number((STORE.match(/floorScore:\s*(\d+)/) || [])[1])
const margen = Number((STORE.match(/margin:\s*(\d+)/) || [])[1])
comprueba("el suelo y el margen se leen de SkillStore",
          suelo >= 1 && margen >= 1, "suelo=" + suelo + " margen=" + margen)

function decide(q) {
    const r = TU.rankSkills(skills, q)
    const claro = r.length > 0 && r[0].score >= suelo
               && (r.length === 1 || r[0].score - r[1].score >= margen)
    return { claro: claro, gana: r[0] ? r[0].skill.id : "", r: r }
}

// ── 1. Toda habilidad tiene disparadores ─────────────────────────────────────
// La descripción la lee el modelo en el catálogo y por eso está escrita para
// humanos; los disparadores son el vocabulario crudo con el que el usuario
// llama a la puerta ("certbot", "hap", "crashloopbackoff"). Sin ellos la
// habilidad depende de que la descripción, por casualidad, use sus palabras.
const sinDisp = skills.filter(s => s.triggers === "").map(s => s.id)
comprueba("todas las habilidades declaran triggers", sinDisp.length === 0, sinDisp.join(", "))

// ── 2. El corpus ─────────────────────────────────────────────────────────────
// 'ok' admite varias: cuando una avería cabe de verdad en dos habilidades (un
// vzdump es Proxmox y es copias), acertar cualquiera vale. 'router: true'
// marca las frases que NO deben decidirse solas —demasiado genéricas—: ahí lo
// único que se exige es que nadie gane con claridad equivocada.
const CORPUS = [
{ q: "renuévame el certificado de let's encrypt", ok: "certificados-tls" },
{ q: "certbot no renueva", ok: "certificados-tls" },
{ q: "el certificado ha caducado y sale el candado en rojo", ok: "certificados-tls" },
{ q: "acme challenge falla al validar", ok: "certificados-tls" },
{ q: "necesito un wildcard con dns-01", ok: "certificados-tls" },
{ q: "en curl falla el ssl pero en el navegador va", ok: "certificados-tls" },

{ q: "el pipeline de github actions falla solo a veces", ok: "ci-cd" },
{ q: "el build va bien en local pero se rompe en el runner", ok: "ci-cd" },
{ q: "el workflow tarda 40 minutos, la caché no funciona", ok: "ci-cd" },
{ q: "jenkins no coge los secretos", ok: "ci-cd" },

{ q: "en el catalyst tengo un puerto en err-disabled", ok: "cisco" },
{ q: "configura un trunk en el switch cisco", ok: "cisco" },
{ q: "sácame el show run del router", ok: "cisco" },
{ q: "spanning-tree bloqueando un puerto en el IOS", ok: "cisco" },

{ q: "quiero montar copias de seguridad con borg", ok: "copias-restauracion" },
{ q: "hay que restaurar una carpeta borrada del backup", ok: "copias-restauracion" },
{ q: "revisa el plan de recuperación y la regla 3-2-1", ok: "copias-restauracion" },
{ q: "el rsync nocturno no está copiando nada", ok: "copias-restauracion" },

{ q: "los correos del dominio caen en spam", ok: "correo-entregabilidad" },
{ q: "configura spf dkim y dmarc", ok: "correo-entregabilidad" },
{ q: "la cola de postfix está llena de rebotes", ok: "correo-entregabilidad" },
{ q: "estamos en una blacklist y no sale el correo", ok: "correo-entregabilidad" },

{ q: "en el whm no arranca el cpsrvd", ok: "cpanel" },
{ q: "crea una cuenta con whmapi1", ok: "cpanel" },
{ q: "una cuenta de cpanel se ha quedado sin cuota", ok: "cpanel" },

{ q: "escríbeme una habilidad nueva para el asistente", ok: "crear-habilidades" },
{ q: "esta skill no se activa nunca, arréglala", ok: "crear-habilidades" },
{ q: "cómo se escribe un SKILL.md", ok: "crear-habilidades" },

{ q: "esto no funciona y no sé por qué", ok: "depuracion-sistematica", router: true },
{ q: "falla de forma intermitente, busca la causa raíz", ok: "depuracion-sistematica" },
{ q: "necesito reproducir el fallo antes de tocar nada", ok: "depuracion-sistematica" },

{ q: "vamos a desplegar a producción esta tarde", ok: "despliegues" },
{ q: "hay que hacer rollback del release de ayer", ok: "despliegues" },
{ q: "prepara un canary para el nuevo servicio", ok: "despliegues" },
{ q: "cómo hago la migración de base de datos sin cortar", ok: ["despliegues", "sql-lento"] },

{ q: "el equipo se ha quedado sin espacio en disco", ok: "diagnostico-linux" },
{ q: "un servicio de systemd no arranca tras actualizar", ok: "diagnostico-linux" },
{ q: "mira el journalctl a ver qué dice", ok: "diagnostico-linux" },
{ q: "pacman falla al actualizar el arch", ok: "diagnostico-linux" },

{ q: "el smart del disco da sectores reubicados", ok: "discos-raid" },
{ q: "tengo un raid degradado con mdadm", ok: "discos-raid" },
{ q: "hay que sustituir un disco del pool zfs", ok: "discos-raid" },
{ q: "errores de E/S en el nvme", ok: "discos-raid" },

{ q: "el dominio no resuelve desde fuera", ok: "dns-dominios" },
{ q: "cambia los nameservers y mira la propagación", ok: "dns-dominios" },
{ q: "haz un dig del registro MX", ok: ["dns-dominios", "correo-entregabilidad"] },
{ q: "el TTL sigue apuntando al servidor viejo", ok: "dns-dominios" },

{ q: "esto antes iba, busca qué commit lo rompió", ok: "git-forense" },
{ q: "haz un bisect para encontrar la regresión", ok: "git-forense" },
{ q: "quién tocó esta función, mira el blame", ok: "git-forense" },
{ q: "prepara los cambios en commits limpios", ok: "git-forense" },

{ q: "en el huawei entra en system-view y crea la vlan", ok: "huawei" },
{ q: "sácame el display current-configuration", ok: "huawei" },
{ q: "monta un eth-trunk en el cloudengine", ok: "huawei" },
{ q: "el switch S5700 no guarda la configuración", ok: "huawei" },

{ q: "está todo caído y los clientes llamando", ok: "incidentes" },
{ q: "urgente, producción parada", ok: "incidentes" },
{ q: "escribe el postmortem de la caída de ayer", ok: "incidentes" },

{ q: "tengo un pod en crashloopbackoff", ok: "kubernetes-k3s" },
{ q: "el statefulset no recrea el pod", ok: "kubernetes-k3s" },
{ q: "mira los pods del namespace con kubectl", ok: "kubernetes-k3s" },
{ q: "hay que llegar al volumen de longhorn desde el host", ok: "kubernetes-k3s" },

{ q: "en el mikrotik hay que tocar el firewall sin quedarme fuera", ok: "mikrotik" },
{ q: "haz un export de la configuración del routeros", ok: "mikrotik" },
{ q: "el hap no hace nat", ok: "mikrotik" },
{ q: "entra por winbox y activa el safe mode", ok: "mikrotik" },

{ q: "este script de python tarda muchísimo, perfílalo", ok: "perfilar-rendimiento" },
{ q: "compara los tiempos con hyperfine", ok: "perfilar-rendimiento" },
{ q: "el proceso se come la CPU, busca el cuello de botella", ok: "perfilar-rendimiento" },

{ q: "planifica esto por fases antes de escribir código", ok: "planificar-cambios" },
{ q: "cómo lo harías, diséñame el cambio", ok: "planificar-cambios" },

{ q: "en el plesk una suscripción se ha quedado sin web", ok: "plesk" },
{ q: "pasa un plesk repair al dominio", ok: "plesk" },
{ q: "dónde están los logs de plesk bin", ok: "plesk" },

{ q: "una VM se ha quedado bloqueada en el proxmox", ok: "proxmox" },
{ q: "arranca el contenedor lxc con pct", ok: "proxmox" },
{ q: "el nodo sale en gris y no hay quórum", ok: "proxmox" },
{ q: "haz un vzdump de la máquina antes de tocarla", ok: ["proxmox", "copias-restauracion"] },

{ q: "edita el panel de quickshell sin romperlo", ok: "quickshell-qml" },
{ q: "hay un binding loop en este qml", ok: "quickshell-qml" },
{ q: "pasa el qmllint antes de recargar el shell", ok: "quickshell-qml" },

{ q: "se pierden paquetes y hay latencia alta", ok: "redes-datacenter" },
{ q: "mide el ancho de banda con iperf3", ok: "redes-datacenter" },
{ q: "el bonding lacp no levanta", ok: "redes-datacenter" },
{ q: "sospecho de la MTU en el bridge", ok: "redes-datacenter" },

{ q: "refactoriza esto que es un lío", ok: "refactorizar" },
{ q: "extrae la función y renombra las variables", ok: "refactorizar" },
{ q: "limpia este código sin cambiar el comportamiento", ok: "refactorizar" },

{ q: "revísame el código de este archivo", ok: "revision-codigo" },
{ q: "audita el pull request antes de mezclarlo", ok: "revision-codigo" },

{ q: "se ha subido una API key al repositorio", ok: "secretos-filtrados" },
{ q: "pasa gitleaks antes de publicar", ok: "secretos-filtrados" },
{ q: "hay una contraseña en un commit, límpiala del historial", ok: "secretos-filtrados" },
{ q: "hay que rotar el token filtrado", ok: "secretos-filtrados" },

{ q: "quiero escribir un servidor MCP para esta API", ok: "servidor-mcp" },
{ q: "cómo diseño las herramientas del MCP", ok: "servidor-mcp" },

{ q: "conéctate por ssh al servidor y mira qué pasa", ok: "servidor-remoto" },
{ q: "entra en el VPS y revisa la web", ok: "servidor-remoto" },

{ q: "escríbeme un script de bash para el cron", ok: "shell-robusto" },
{ q: "este comando con rm -rf me da miedo, hazlo seguro", ok: "shell-robusto" },
{ q: "el script falla con nombres de archivo con espacios", ok: "shell-robusto" },

{ q: "esta consulta tarda muchísimo, mira el explain", ok: "sql-lento" },
{ q: "mysql se está comiendo el servidor", ok: "sql-lento" },
{ q: "hay que crear un índice en esa tabla", ok: "sql-lento" },
{ q: "el slow query log está lleno", ok: "sql-lento" },

{ q: "escribe los tests de esta función", ok: "tests-tdd" },
{ q: "hazlo con TDD", ok: "tests-tdd" },
{ q: "este test es flaky y falla a veces", ok: ["tests-tdd", "ci-cd"] },

{ q: "el AP de unifi no adopta, se queda en adopting", ok: "ubiquiti-unifi" },
{ q: "el wifi va lento en la planta de arriba", ok: "ubiquiti-unifi" },
{ q: "hazme un set-inform por ssh al punto de acceso", ok: "ubiquiti-unifi" },
{ q: "quiero una VLAN por SSID", ok: "ubiquiti-unifi" },

{ q: "no me compliques el código, cambio mínimo", ok: "directrices-karpathy" },
{ q: "dime las suposiciones que estás haciendo", ok: "directrices-karpathy" },
]

const ids = skills.map(s => s.id)
let erroneas = 0, sinMargen = 0
for (let i = 0; i < CORPUS.length; i++) {
    const c = CORPUS[i]
    const buenas = Array.isArray(c.ok) ? c.ok : [c.ok]
    for (let k = 0; k < buenas.length; k++)
        comprueba("la frase " + (i + 1) + " apunta a una habilidad que existe",
                  ids.indexOf(buenas[k]) !== -1, buenas[k])
    const d = decide(c.q)
    const acierta = buenas.indexOf(d.gana) !== -1
    const detalle = d.r.slice(0, 3).map(x => x.skill.id + ":" + x.score).join("  ")
    if (c.router) {
        // Genérica: vale que no decida, pero NO vale que decida mal.
        comprueba("«" + c.q + "» no se decide sola con la habilidad equivocada",
                  !d.claro || acierta, detalle)
        if (!d.claro) sinMargen++
        continue
    }
    comprueba("«" + c.q + "» → " + buenas.join("|"), acierta && d.claro, detalle)
    if (!acierta) erroneas++
    else if (!d.claro) sinMargen++
}

// El corpus no vale de nada si deja habilidades sin probar: cada una tiene que
// tener al menos una frase que la reclame.
const reclamadas = ({})
for (let i = 0; i < CORPUS.length; i++)
    for (const o of (Array.isArray(CORPUS[i].ok) ? CORPUS[i].ok : [CORPUS[i].ok]))
        reclamadas[o] = true
const huerfanas = ids.filter(i => !reclamadas[i])
comprueba("todas las habilidades tienen frases en el corpus",
          huerfanas.length === 0, huerfanas.join(", "))

// ── 3. Las trampas que ya costaron un enrutado malo ──────────────────────────
// El puntuador busca SUBCADENAS, así que un disparador puede robar frases de
// otra habilidad por dentro de una palabra. Estas tres estaban puestas y se
// cazaron midiendo; quedan clavadas para que no vuelvan.
const trampa = (sid, frag) => {
    const s = skills.filter(x => x.id === sid)[0]
    return !s || (s.name + " " + s.id + " " + s.triggers).toLowerCase().indexOf(frag) === -1
}
comprueba("quickshell no reclama «ayer» (estaba dentro de layer-shell)",
          trampa("quickshell-qml", "ayer"))
comprueba("revisión de código no reclama «pasa» (estaba dentro de repasa)",
          trampa("revision-codigo", "pasa"))
comprueba("k3s no reclama «contenedor» (se lo quitaba a Proxmox)",
          trampa("kubernetes-k3s", "contenedor"))

// ── 4. Cambiar de tema con el catálogo REAL ──────────────────────────────────
// t_habilidades prueba las reglas de decideSkill con habilidades de mentira;
// aquí se prueban con las 33 de verdad, que es donde los disparadores se pisan
// unos a otros. Cada línea: qué había cargado + qué escribe el usuario → qué
// debe quedar cargado ("" = descargada).
const RELEVO = [
    { de: "proxmox", q: "el certificado del dominio ha caducado", a: "certificados-tls" },
    { de: "certificados-tls", q: "y ahora el correo no llega", a: "correo-entregabilidad" },
    { de: "plesk", q: "escríbeme un script de bash para el cron", a: "shell-robusto" },
    // Sin tema: se libera el contexto y se le pregunta al modelo por si el
    // encaje era semántico.
    { de: "kubernetes-k3s", q: "qué hora es en tokio", a: "", pregunta: true },
    { de: "cisco", q: "pásame un resumen de lo que has hecho", a: "", pregunta: true },
    // Continuaciones: NO son un cambio de tema.
    { de: "kubernetes-k3s", q: "sí, hazlo", a: "kubernetes-k3s" },
    { de: "kubernetes-k3s", q: "vale, adelante", a: "kubernetes-k3s" },
    { de: "sql-lento", q: "y el índice de la otra tabla", a: "sql-lento" },
    // Lo reciente manda: la ventana viene llena de Proxmox y aun así el pod
    // manda, porque el último mensaje decide solo.
    { de: "proxmox", q: "y ahora reinicia el pod que está en crashloop",
      v: "arranca la vm 105 del proxmox\nmira el nodo\ny ahora reinicia el pod que está en crashloop",
      a: "kubernetes-k3s" },
]
for (const c of RELEVO) {
    const d = TU.decideSkill(skills, c.q, c.v === undefined ? c.q : c.v,
                             c.de, "", suelo, margen)
    comprueba("«" + c.q + "» con " + c.de + " puesta → " + (c.a || "descargada"),
              d.id === c.a, d.id || "(descargada)")
    if (c.pregunta)
        comprueba("…y se le pregunta al modelo por la nueva", d.ask === true)
}

console.log(ok + " bien, " + mal + " mal"
            + (erroneas || sinMargen ? "   (" + erroneas + " erróneas, "
                                       + sinMargen + " sin margen)" : ""))
process.exit(mal === 0 ? 0 : 1)
