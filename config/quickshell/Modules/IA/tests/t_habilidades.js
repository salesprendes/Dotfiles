// QUÉ HABILIDAD SE CARGA SOLA. El puntuador léxico vive en TextUtils.js y es
// JavaScript puro, así que se comprueba aquí sin Quickshell ni modelo: cada
// regla medida (peso del nombre, descuento de palabra común, triggers) tiene
// su comprobación, porque todas se descubrieron rompiéndose.
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

const TU = cargaLib("TextUtils.js")
const STORE = fs.readFileSync(IA + "storage/SkillStore.qml", "utf8")
const SVC = fs.readFileSync(IA + "core/AiService.qml", "utf8")
const CONV = fs.readFileSync(IA + "storage/ConversationStore.qml", "utf8")

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) { ok++; return }
    mal++
    console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : ""))
}

// ── 1. El puntuador, las reglas de siempre ───────────────────────────────────
const HABS = [
    { id: "sql-lento", name: "SQL lento e índices",
      description: "Consultas lentas de Postgres, bloqueos, índices que faltan." },
    { id: "servidor-remoto", name: "Servidores remotos y hosting",
      description: "Entrar por SSH a un servidor y diagnosticarlo sin romper nada." },
    { id: "proxmox", name: "Proxmox",
      description: "Clústeres Proxmox: nodos, máquinas virtuales, almacenamiento." }
]
const top = (t, hs) => { const r = TU.rankSkills(hs || HABS, t); return r[0] }

comprueba("una palabra del nombre gana (peso 4)",
          top("tengo un índice roto").skill.id === "sql-lento")
comprueba("y puntúa al menos el suelo de 2",
          top("tengo un índice roto").score >= 2)
comprueba("nombre más descripción suman sobre solo nombre",
          top("una máquina virtual en proxmox").skill.id === "proxmox"
          && top("una máquina virtual en proxmox").score >= 5)
// Empate a palabra de nombre ("servidor" contra "proxmox"): nadie se despega
// con el margen de 2, así que la carga automática NO debe decidir — es
// exactamente el caso que ahora hereda el router.
const emp = TU.rankSkills(HABS, "un servidor con proxmox")
comprueba("un empate real no se despega",
          emp[0].score - emp[1].score < 2)
comprueba("sin ninguna palabra compartida no puntúa nadie",
          top("hola, buenos días").score === 0)

// ── 2. triggers: puntúan como el nombre y no salen en el catálogo ────────────
const CONTRIG = HABS.map(h => h.id !== "servidor-remoto" ? h
    : Object.assign({}, h, { triggers: "502 hosting caida panel" }))
comprueba("un trigger puntúa como palabra de nombre",
          top("la web da 502", CONTRIG).skill.id === "servidor-remoto"
          && top("la web da 502", CONTRIG).score >= 2)
comprueba("sin triggers ese mismo mensaje no decidía",
          top("la web da 502").score < 2)
comprueba("el catálogo no enseña los triggers",
          STORE.indexOf("s.triggers") === -1
          || !/catalogBlock[\s\S]*s\.triggers/.test(STORE.match(/catalogBlock[\s\S]*?\n    \}/)[0]))
comprueba("el escáner parsea triggers del frontmatter",
          /triggers:\s*trig/.test(STORE) && /^\s*const tg = fm/m.test(STORE))

// ── 3. Cargar y DESCARGAR: la decisión completa ──────────────────────────────
// decideSkill es la función que decide qué habilidad queda puesta tras cada
// mensaje. Se prueba aquí entera porque cada una de sus reglas nació de un
// fallo: la descarga por cambio de tema es fácil de escribir y facilísima de
// escribir mal (descargarla a mitad de tarea con un "sí, hazlo").
const SUELO = 2, MARGEN = 2
const dec = (ult, vent, sticky, owner) =>
    TU.decideSkill(HABS, ult, vent === null ? ult : vent,
                   sticky || "", owner || "", SUELO, MARGEN)

comprueba("un ganador claro se carga",
          dec("mira el índice de esa tabla", null, "").id === "sql-lento")
comprueba("y sustituye a la que hubiera (el tema cambió)",
          dec("mira el índice de esa tabla", null, "proxmox").id === "sql-lento")
comprueba("lo cargado sigue si la ventana aún habla de su tema",
          dec("y ahora reinícialo", "una máquina virtual en proxmox\ny ahora reinícialo",
              "proxmox").id === "proxmox")
// LA REGLA QUE PROTEGE LA TAREA A MEDIAS: un mensaje sin palabras con contenido
// no dice que el tema haya cambiado, dice que sigas.
comprueba("un «sí, hazlo» no descarga nada",
          dec("sí, hazlo", null, "proxmox").id === "proxmox")
comprueba("ni un «vale» a secas",
          dec("vale", null, "sql-lento").id === "sql-lento")
// Y LA QUE LIBERA EL CONTEXTO: tema nuevo, con palabras, y la cargada no casa
// ni una.
const cambio = dec("entra por ssh y mira el correo", null, "sql-lento")
comprueba("un tema nuevo con palabras propias descarga la vieja",
          cambio.id === "servidor-remoto" || cambio.id === "")
comprueba("descargar sin sustituta deja el hilo limpio",
          dec("qué hora es en Tokio", null, "proxmox").id === "")
comprueba("y al descargar se le pregunta al modelo por la nueva",
          dec("qué hora es en Tokio", null, "proxmox").ask === true)
comprueba("con algo cargado y sin tema nuevo no se pregunta nada",
          dec("sí, hazlo", null, "proxmox").ask === false)
comprueba("una sola palabra compartida basta para NO descargar",
          dec("y el almacenamiento", null, "proxmox").id === "proxmox")
// Lo reciente manda: sin esto, el tema viejo seguía en la ventana empatando con
// el nuevo y el cambio tardaba tres mensajes en llegar.
comprueba("el último mensaje decide el cambio aunque la ventana traiga el tema viejo",
          dec("hay un índice que falta en esa tabla",
              "una máquina virtual en proxmox\nreinicia el nodo\nhay un índice que falta en esa tabla",
              "proxmox").id === "sql-lento")
// Una habilidad desactivada en Ajustes desaparece del catálogo: no puede
// quedarse cargada.
comprueba("una habilidad que ya no está en el catálogo se cae sola",
          dec("sí, hazlo", null, "habilidad-borrada").id === "")

// El recorte de vocabulario de un use_skill caduca con la misma regla.
comprueba("el veto de vocabulario sobrevive mientras su tema siga",
          dec("y ahora reinicia la máquina virtual", null, "", "proxmox").owner === "proxmox")
comprueba("y se suelta cuando el tema se va",
          dec("mira el índice de esa tabla", null, "", "proxmox").owner === "")
comprueba("pero no lo suelta un «sí, hazlo»",
          dec("sí, hazlo", null, "", "proxmox").owner === "proxmox")
comprueba("el dueño se apunta al recortar en ToolRunner",
          /skills\.toolsOwner = /.test(fs.readFileSync(IA + "tools/ToolRunner.qml", "utf8")))
comprueba("y descargar suelta el recorte, no solo el dueño",
          /if \(d\.owner === ""\)\s*\n\s*activeSkillTools = \[\]/.test(STORE))
comprueba("resetThread olvida al dueño",
          /resetThread[\s\S]*?toolsOwner = ""/.test(STORE))
comprueba("SkillStore delega la decisión, no la duplica",
          /TU\.decideSkill\(/.test(STORE))

// ── 4. La ventana y el router: presencia de las costuras en QML ──────────────
// La lógica vive en QML y aquí no corre; lo que sí se puede vigilar es que las
// costuras no se descosan en un refactor — igual que t_endpoint vigila
// AiService.
comprueba("la relevancia se mide contra el último mensaje Y la ventana",
          SVC.indexOf("skillStore.update(t, conv.recentUserText(3))") !== -1)
comprueba("y la ventana existe en ConversationStore",
          /function recentUserText\(n\)/.test(CONV))
comprueba("el router solo actúa con el hilo sin habilidad",
          /if \(d\.ask\)\s*\n\s*_askRouter/.test(STORE)
          && dec("y el almacenamiento", null, "proxmox").ask === false)
comprueba("y no pisa una habilidad ya cargada al volver",
          /store\.stickyId !== ""/.test(STORE))
comprueba("el router no paga llamadas por ruido sin palabras",
          /TU\.keywords\(t\)\.length === 0/.test(STORE))
comprueba("ni repite la misma pregunta",
          /t === _routerAsked/.test(STORE))
comprueba("va sin streaming y con pocos tokens",
          /stream: false, max_tokens: 64/.test(STORE))
comprueba("y un fallo del router no toca nada",
          /if \(code !== 0\)\s*\n\s*return/.test(STORE))
comprueba("resetThread olvida también lo del router",
          /resetThread[\s\S]*?_routerAsked = ""/.test(STORE))

console.log(ok + " bien, " + mal + " mal")
process.exit(mal === 0 ? 0 : 1)
