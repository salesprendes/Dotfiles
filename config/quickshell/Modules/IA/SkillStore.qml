import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "TextUtils.js" as TU

// HABILIDADES: carpetas sueltas en Modules/IA/skills/<nombre>/SKILL.md, con el
// mismo formato que las de Claude Code (frontmatter YAML con name/description y
// el cuerpo en Markdown).
//
// Se cargan con REVELACIÓN PROGRESIVA — al prompt de sistema va el catálogo
// (nombre y descripción, ordenado por lo que venga a cuento) y el texto entero
// solo cuando hace falta. Así se pueden tener veinte habilidades sin gastar
// contexto en las diecinueve que hoy no pintan nada.
//
// Quién decide que "hace falta": el modelo con use_skill, y también el propio
// harness (ver `update`) — que no todos los modelos se acuerdan de pedir lo que
// necesitan.
Scope {
    id: store

    // El harness: de él salen la carpeta, el modo agente, el presupuesto de
    // contexto y la última pregunta del usuario (la consulta contra la que se
    // mide la relevancia).
    property var svc

    property var skills: []            // [{id, name, description, text, body, allowedTools}]

    // Habilitadas: el mapa de Ajustes manda, y lo que no esté en el mapa cuenta
    // como habilitada (instalar una carpeta ya es decir que la quieres).
    function enabled(id) {
        const m = Settings.aiSkills || ({})
        return m[id] !== false
    }
    function setEnabled(id, on) {
        const m = Object.assign({}, Settings.aiSkills)
        m[id] = on
        Settings.aiSkills = m
    }
    readonly property var activeSkills: skills.filter(s => enabled(s.id))

    // Una habilidad por su id o por su nombre, sin distinguir mayúsculas: es
    // como la pide el modelo.
    function find(nameOrId) {
        const want = String(nameOrId || "").trim().toLowerCase()
        return activeSkills.find(x => x.id.toLowerCase() === want
                                   || x.name.toLowerCase() === want) || null
    }

    // ── El escaneo ───────────────────────────────────────────────────────────
    // Vocabulario acotado por la habilidad en uso (allowed-tools). Vacío = sin
    // límite. Se olvida al cambiar de conversación.
    property var activeSkillTools: []

    // Estado del reintento tras reescanear (habilidad creada tras arrancar).
    property string _retryName: ""
    property int _retryIndex: -1
    // Aviso de "el catálogo ya está al día": lleva la tarjeta que esperaba (o
    // -1) para que el harness la reintente sin que aquí se sepa qué es una
    // tarjeta.
    signal rescanned(int pending, string want)

    property bool scanning: scan.running
    function rescan() {
        if (!scan.running)
            scan.running = true
    }

    Process {
        id: scan
        running: true
        // Una sola pasada: por cada SKILL.md, un separador con su id y el
        // archivo ENTERO (tope de 24 kB). Antes solo se leía el frontmatter y el
        // cuerpo se iba a buscar con otro proceso al invocarla; teniéndolo ya en
        // memoria, invocar una habilidad es instantáneo y —lo que importa— el
        // harness puede decidir él mismo cargarla.
        command: ["sh", "-c",
            'for f in "$QS_DIR"/*/SKILL.md; do [ -f "$f" ] || continue; '
            + 'd=$(dirname -- "$f"); printf "===QS-SKILL===%s\\n" "$(basename -- "$d")"; '
            + 'head -c 24000 -- "$f"; printf "\\n"; done']
        environment: ({ QS_DIR: store.svc ? store.svc.skillsDir : "" })
        stdout: StdioCollector { id: scanOut }
        onExited: {
            const parts = (scanOut.text || "").split("===QS-SKILL===")
            const found = []
            for (let i = 1; i < parts.length; i++) {
                const nl = parts[i].indexOf("\n")
                if (nl < 0)
                    continue
                const id = parts[i].slice(0, nl).trim()
                const head = parts[i].slice(nl + 1)     // el archivo entero
                // Frontmatter: el bloque entre las dos primeras líneas "---".
                let name = id, desc = "", allowed = []
                const fm = head.match(/^---\s*\n([\s\S]*?)\n---/)
                if (fm) {
                    // allowed-tools: la habilidad puede declarar a QUÉ
                    // herramientas se limita mientras esté en uso (formato de
                    // Anthropic/OpenWorker). Admite lista en línea ("a, b, c") y
                    // lista YAML de guiones.
                    const at = fm[1].match(/^allowed[-_]tools:\s*(.*)$/m)
                    if (at) {
                        const inline = at[1].trim().replace(/^\[|\]$/g, "")
                        if (inline !== "")
                            allowed = inline.split(",").map(x => x.trim().replace(/^["']|["']$/g, ""))
                                            .filter(x => x !== "")
                        else {
                            const rest = fm[1].slice(fm[1].indexOf(at[0]) + at[0].length)
                            const items = rest.match(/^\s*-\s*(.+)$/gm) || []
                            allowed = items.map(l => l.replace(/^\s*-\s*/, "").trim()
                                                      .replace(/^["']|["']$/g, ""))
                        }
                    }
                    const n = fm[1].match(/^name:\s*(.+)$/m)
                    const d = fm[1].match(/^description:\s*(.+)$/m)
                    if (n) name = n[1].trim().replace(/^["']|["']$/g, "")
                    if (d) desc = d[1].trim().replace(/^["']|["']$/g, "")
                }
                // 'text' es lo que devuelve use_skill (el archivo tal cual) y
                // 'body' lo que se inyecta al cargarla sola: sin el frontmatter,
                // que en el prompt no aporta nada.
                found.push({ id: id, name: name, description: desc,
                             allowedTools: allowed,
                             text: head.trim(),
                             body: (fm ? head.slice(fm[0].length) : head).trim() })
            }
            store.skills = found
            // El historial puede haberse restaurado ANTES de que este escaneo
            // termine: con el catálogo ya en la mano, se recarga la habilidad que
            // el hilo restaurado traía a cuento.
            if (store.stickyId === "" && store.svc && store.svc.lastUserText !== "")
                store.update(store.svc.lastUserText)
            // Reescaneo por fallo (regla de OpenWorker): si el modelo pidió una
            // habilidad que aún no estaba y por eso se reescaneó, se avisa para
            // que se reintente la lectura ahora que sí aparece.
            if (store._retryName !== "") {
                const want = store._retryName
                const idx = store._retryIndex
                store._retryName = ""
                store._retryIndex = -1
                store.rescanned(idx, want)
            }
        }
    }

    // Pide un reescaneo porque el modelo nombró una habilidad que no está, y
    // apunta la tarjeta que hay que reintentar después. Devuelve false si ya
    // había un reintento en marcha (entonces se contesta que no existe).
    function rescanFor(want, index) {
        if (_retryName !== "" || scan.running)
            return false
        _retryName = String(want)
        _retryIndex = index
        rescan()
        return true
    }

    // ── Qué habilidad hace falta AHORA ───────────────────────────────────────
    // La revelación progresiva de Claude Code confía en que el modelo, viendo la
    // lista, se acuerde de pedir la que toca. Un modelo grande lo hace; uno local
    // pequeño, la mitad de las veces no — y entonces la habilidad no existe en la
    // práctica. Así que aquí el harness también mira: puntúa las habilidades
    // contra lo que acaba de pedir el usuario y, si una encaja claramente, le
    // CARGA sus instrucciones sin esperar a que las pida. Sigue pudiendo pedir
    // cualquier otra con use_skill.
    readonly property var ranked:
        (svc && svc.agentMode) ? TU.rankSkills(activeSkills, svc.lastUserText) : []

    // Cuándo se considera que encaja "claramente": que se nombre su tema (una
    // palabra propia de su nombre vale 4) o que coincidan varios términos de su
    // descripción. Y además tiene que DESPEGARSE de la segunda: ante una duda
    // entre dos, no se carga ninguna y decide el modelo con el catálogo delante.
    // Cargar la equivocada cuesta más que no cargar ninguna.
    readonly property int floorScore: 2
    readonly property int margin: 2

    // La habilidad cargada es PEGAJOSA: una vez dentro, acompaña a la
    // conversación hasta que otra le gane el puesto o el hilo muera. Antes se
    // recalculaba contra el ÚLTIMO mensaje y nada más: un "sí, hazlo" sin
    // palabras clave la descargaba a mitad de tarea — justo cuando el agente
    // empezaba a ejecutar lo que la habilidad enseña. Es lo mismo que hacen los
    // harness grandes: en Claude Code una skill invocada queda en el hilo, no se
    // evapora con el siguiente mensaje.
    property string stickyId: ""
    readonly property var autoSkill:
        activeSkills.find(s => s.id === stickyId) || null

    // La decisión, al enviar cada mensaje del usuario: si hay un ganador claro se
    // carga (o sustituye a la anterior — el tema cambió); si no lo hay, se queda
    // la que estuviera, que la ausencia de palabras clave en un "vale, sigue" no
    // es información.
    function update(text) {
        if (!svc || !svc.agentMode)
            return
        const r = TU.rankSkills(activeSkills, text)
        if (r.length === 0 || r[0].score < floorScore)
            return
        if (r.length > 1 && r[0].score - r[1].score < margin)
            return
        stickyId = r[0].skill.id
    }

    // Todo lo que pertenece al HILO y no al catálogo.
    function resetThread() {
        stickyId = ""
        activeSkillTools = []
    }

    // ── Lo que entra al prompt ───────────────────────────────────────────────
    // Presupuesto del catálogo, como todo lo demás: proporcional a la ventana del
    // modelo. Con ventana holgada caben las descripciones enteras de muchas
    // habilidades; con una modesta, entran las que vienen a cuento y el resto se
    // anuncian solo por su nombre — que para pedirlas basta.
    readonly property int catalogBudget:
        Math.max(1000, Math.min(8000, Math.round((svc ? svc.charBudget : 0) * 0.12)))

    // Cuánto texto de UNA habilidad entra al contexto. Lo comparten la carga
    // automática y use_skill: antes use_skill pasaba por el tope genérico de
    // resultados (~8,6k con ventana de 32k) y la auto-carga por el suyo de 12k,
    // así que la misma habilidad llegaba entera o amputada según la puerta por la
    // que entrara.
    readonly property int textCap:
        Math.max(2000, Math.min(12000, Math.round((svc ? svc.charBudget : 0) * 0.3)))

    readonly property string catalogBlock: {
        const r = ranked
        if (r.length === 0)
            return ""
        let block = "\nHabilidades disponibles (instrucciones que el usuario ha "
                  + "instalado). Si la tarea encaja con una, LEE sus instrucciones "
                  + "con la herramienta use_skill ANTES de trabajar, y síguelas:"
        // Por orden de encaje y con la descripción COMPLETA: es lo que decide si
        // se usa o no, y recortarla a mitad de frase se comía justo la parte que
        // dice cuándo viene a cuento.
        let chars = 0
        const resto = []
        for (let i = 0; i < r.length; i++) {
            const s = r[i].skill
            // La que ya va cargada entera no se anuncia otra vez.
            if (autoSkill && s.id === autoSkill.id)
                continue
            const line = "\n- " + s.name + ": " + s.description
            if (chars + line.length > catalogBudget && chars > 0) {
                resto.push(s.name)
                continue
            }
            chars += line.length
            block += line
        }
        if (resto.length > 0)
            block += "\nInstaladas también, por si vienen al caso (pídelas por "
                   + "su nombre con use_skill): " + resto.join(", ") + "."
        return block
    }

    // Las instrucciones de la habilidad que el harness ha decidido cargar.
    readonly property string activeBlock: {
        const s = autoSkill
        if (!s)
            return ""
        return "\n\nINSTRUCCIONES DE LA HABILIDAD «" + s.name + "», cargadas "
             + "porque encajan con lo que te acaban de pedir. Síguelas; no "
             + "hace falta que la pidas con use_skill.\n"
             + s.body.slice(0, textCap)
    }
}
