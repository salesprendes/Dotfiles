import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "../TextUtils.js" as TU
import "Payload.js" as PL
import "Prune.js" as PR
import "Transcript.js" as TR

// El ciclo de vida del contexto: cuatro reductores, del más barato al más caro, y
// cada uno se usa cuando el anterior no llega.
//
//   PODAR      determinista, sin modelo y sin coste. Sustituye resultados de
//              herramienta que ya no hacen falta literalmente.
//   SACUDIR    determinista. Archiva a un fichero los bloques enormes que la poda
//              no alcanza y deja en su sitio la ruta para recuperarlos.
//   RESUMIR    una llamada al modelo. Sustituye el historial viejo por un traspaso
//              estructurado y conserva literales los últimos turnos.
//   TRASPASAR  una llamada al modelo y una conversación nueva sembrada con el
//              documento de continuación. Para cuando el hilo ya no da más.
//
// Tres cosas lo separan de un simple resumidor:
//
//   · La caché de prefijo manda. Tocar un mensaje viejo obliga al servidor a
//     reprocesar todo lo que va detrás, así que podar automáticamente solo se hace
//     donde eso es barato, o con la caché ya fría. Lo que se pide a mano no lleva
//     esa brida.
//   · Al archivero se le manda una transcripción, no el protocolo de herramientas
//     con los resultados íntegros. Resumir cuesta una fracción y, sobre todo, cabe
//     cuando el contexto acaba de desbordar.
//   · El resumen es incremental: el texto del resumen anterior no se vuelve a
//     resumir —resumir un resumen es la forma clásica de perder datos— sino que
//     entra aparte como estado acumulado, con órdenes de actualizarlo casilla a
//     casilla.
//
// Es una operación del harness y no un mensaje del chat: viaja por su propio
// proceso, sin streaming y sin herramientas. Metiéndola por el flujo normal, en
// modo agente el modelo puede contestar al "resume esto" con una tool_call, y esa
// tarjeta se tomaría como resumen.
Scope {
    id: comp

    property var svc
    property var conv
    property var tools

    property bool compacting: false
    // El aviso de "casi lleno" se da UNA vez por conversación.
    property bool warned: false
    // Los turnos recientes que sobreviven al resumen (ver aiCompactKeep).
    property var _keepTail: []
    property bool _retried: false

    // "resumen" | "traspaso": los dos usan el mismo transporte y la misma
    // transcripción, y se diferencian en la orden final y en qué se hace con
    // la respuesta.
    property string _modo: "resumen"
    // Por qué se está compactando; decide qué pasa DESPUÉS de conseguirlo.
    //   ""          lo pidió el usuario  → seguir con la cola
    //   "auto"      el umbral tras un turno → seguir con la cola
    //   "overflow"  el modelo dijo que no cabe → reintentar el turno
    //   "midturn"   el bucle de herramientas se pasó → seguir el turno
    property string _motivo: ""

    property string _guion: ""      // la transcripción que viaja
    property string _previo: ""     // el estado acumulado del resumen anterior
    property string _fich: ""       // la contabilidad de archivos
    property int _ahorro: 0
    property int _sustituidos: 0

    // Cuánto puede ocupar la cola literal. Sin tope, unos últimos turnos llenos de
    // salidas gordas hacen que compactar no baje nada: se paga el resumen y el
    // medidor sigue en rojo.
    readonly property real _topeCola: 0.5
    // Si tras podar el hilo baja de aquí, ya cabe.
    readonly property real _yaCabe: 0.7
    // La transcripción no puede comerse la ventana: es la entrada del resumen, y
    // el resumen tiene que caber junto a ella.
    readonly property int _topeGuion: Math.round(svc ? svc.charBudget * 0.6 : 60000)

    // Cuánto puede quedar detrás de una tarjeta para que valga la pena tocarla, y
    // cuánto hay que ahorrar para que compense romper el prefijo. Proporcionales a
    // la ventana: en un modelo pequeño reprocesar treinta mil caracteres es
    // carísimo y en uno grande es calderilla.
    readonly property int _sufijoBarato: Math.round(svc ? svc.charBudget * 0.12 : 6000)
    readonly property int _ahorroMinimo:
        Math.max(6000, Math.round(svc ? svc.charBudget * 0.05 : 6000))

    readonly property string _archivero:
        "Eres el archivero de una conversación entre un usuario y su asistente. "
        + "Resumes con fidelidad y NUNCA continúas la conversación ni contestas "
        + "a lo que se pregunta dentro de ella."

    // El formato con casillas no es cosmético: es lo que permite que la
    // actualización siguiente sea mecánica —mover lo terminado de En curso a
    // Hecho— en vez de una reescritura entera, que es donde un resumen pierde
    // datos generación tras generación.
    readonly property string _secciones:
        "## Resumen corto\n"
        + "[2 o 3 frases en primera persona sobre QUÉ cambió, no sobre el proceso.]\n\n"
        + "## Encargo\n"
        + "[Qué pidió el usuario. Si son varias tareas, todas.]\n\n"
        + "## Restricciones y preferencias\n"
        + "- [Lo que el usuario exigió o prefirió, y sigue vigente.]\n\n"
        + "## Progreso\n\n"
        + "### Hecho\n"
        + "- [x] [Lo terminado, con su detalle.]\n\n"
        + "### En curso\n"
        + "- [ ] [Lo que está a medias ahora mismo.]\n\n"
        + "### Atascado\n"
        + "- [Lo que falló y sigue sin resolverse, con el error exacto.]\n\n"
        + "## Decisiones\n"
        + "- **[Decisión]**: [por qué]\n\n"
        + "## Datos críticos\n"
        + "- [Rutas, servidores, nombres, valores e identificadores EXACTOS que "
        + "harán falta. Nunca contraseñas ni claves.]\n\n"
        + "## Siguientes pasos\n"
        + "1. [Qué toca ahora]\n"

    readonly property string _reglas:
        "Conserva EXACTOS las rutas de archivo, los nombres de función, los "
        + "mensajes de error y los resultados de comando que importen. "
        + "Si la conversación termina en una pregunta sin contestar o en una "
        + "petición esperando respuesta del usuario («pega aquí la salida», "
        + "«¿cuál de las dos?»), DEBES conservarla literalmente en «Datos "
        + "críticos»: es lo que deja al usuario colgado si se pierde. "
        + "No inventes nada. Escribe en el idioma del usuario. "
        + "Responde SOLO con el resumen, sin preámbulo ni comentario."

    readonly property string _ordenNueva:
        "Vas a COMPACTAR la conversación de arriba: tu respuesta sustituirá todo "
        + "lo anterior y será lo único que quede. Escribe un traspaso con "
        + "EXACTAMENTE estas secciones (omite una solo si no aplica):\n\n"
        + _secciones + "\n" + _reglas

    readonly property string _ordenActualiza:
        "Arriba tienes el ESTADO ACUMULADO de compactaciones anteriores y, "
        + "después, lo que ha pasado desde entonces. Devuelve el estado "
        + "ACTUALIZADO con las mismas secciones. No lo reescribas: actualízalo.\n\n"
        + "- Conserva TODA la información del estado anterior salvo la que lo "
        + "posterior contradiga o deje sin sentido.\n"
        + "- Progreso: mueve a «Hecho» lo que estaba «En curso» y ya se terminó.\n"
        + "- «Atascado»: quita lo que se haya resuelto, añade lo que se haya roto.\n"
        + "- «Decisiones»: conserva todas las anteriores y añade las nuevas.\n"
        + "- «Siguientes pasos»: reescríbelos según dónde está el trabajo ahora.\n"
        + "- Si hay una pregunta pendiente nueva, sustituye a la anterior; si la "
        + "anterior ya se contestó, quítala.\n\n"
        + _secciones + "\n" + _reglas

    readonly property string _ordenTraspaso:
        "Escribe un DOCUMENTO DE TRASPASO para otra instancia de ti mismo, que "
        + "no tendrá acceso a esta conversación y tiene que poder seguir sin "
        + "preguntar nada. Estado técnico exacto, no abstracciones: rutas, "
        + "símbolos, comandos ejecutados, fallos observados, decisiones y el "
        + "trabajo a medias que condiciona el paso siguiente.\n\n"
        + _secciones + "\n" + _reglas

    function _orden() {
        if (comp._modo === "traspaso")
            return comp._ordenTraspaso
        let t = comp._previo !== "" ? comp._ordenActualiza : comp._ordenNueva
        if (comp._fich !== "")
            t += "\n\nArchivos tocados (lo sabe el harness; NO los repitas en tu "
               + "resumen, se añaden solos):\n" + comp._fich
        return t
    }

    // Utilidades del hilo
    function _plano() {
        const out = []
        for (let i = 0; i < comp.conv.messages.count; i++)
            out.push(PL.plainMsg(comp.conv.messages.get(i)))
        return out
    }

    // El texto del último resumen del hilo, que es el estado acumulado.
    function _estadoPrevio() {
        for (let i = comp.conv.messages.count - 1; i >= 0; i--) {
            const m = comp.conv.messages.get(i)
            if (m.role === "assistant" && m.compactOf > 0)
                return String(m.content || "")
        }
        return ""
    }

    // La poda sobre el hilo real, sin reconstruirlo: solo cambia el texto de unos
    // resultados, así que las posiciones no se mueven y las rutas ya resueltas que
    // guarda el runner por posición siguen valiendo.
    function _podarHilo(plan) {
        for (const k in plan.marcas)
            comp.conv.messages.setProperty(Number(k), "toolResult", plan.marcas[k])
        comp.conv.save()
    }

    // Cómo se poda según quién lo pida: a mano no hay bridas, y en automático
    // manda la caché salvo que ya esté fría o que quien llame vaya a reescribir el
    // hilo de todos modos.
    function _reglasPoda(auto, msgs) {
        if (!auto)
            return ({})
        if (PR.friaDesde(msgs, Date.now()))
            return ({})       // caché fría: reescribir el prefijo es gratis
        return ({ sufijoMaximo: comp._sufijoBarato,
                  ahorroMinimo: comp._ahorroMinimo })
    }

    // La mitad barata de compactar: sin llamar a nadie y sin perder el hilo
    // literal. Cuando el contexto va justo por culpa de cuatro salidas gordas
    // —lo normal en modo agente— esto basta y sale gratis.
    function prune(auto) {
        if (svc.busy || compacting)
            return 0
        const hilo = _plano()
        const plan = PR.planificar(hilo, _reglasPoda(auto, hilo))
        if (plan.frenado === "ahorro") {
            if (!auto)
                conv.pushInfo(I18n.tr("Not worth pruning yet: only %1 chars, and rewriting the cached prefix costs more.")
                              .arg(plan.posible))
            return 0
        }
        if (plan.podados === 0) {
            if (!auto)
                conv.pushInfo(I18n.tr("Nothing to prune: every tool result is still in play."))
            return 0
        }
        _podarHilo(plan)
        conv.pushInfo(I18n.tr("Pruned %1 stale tool results (%2 chars): no summary needed.")
                      .arg(plan.podados).arg(plan.ahorro))
        return plan.ahorro
    }

    // Lo que la poda no alcanza: un bloque de código enorme pegado por el usuario
    // o escrito por el modelo. No es resultado de ninguna herramienta, así que
    // ninguna regla de la poda lo mira, y suele ser lo más gordo del hilo. No se
    // resume ni se tira: se archiva en un fichero y en su hueco queda la ruta.
    property var _colaArchivo: []
    function shake() {
        if (svc.busy || compacting || _colaArchivo.length > 0)
            return 0
        const hilo = _plano()
        const tramos = PR.sacudibles(hilo, ({}))
        if (tramos.length === 0) {
            conv.pushInfo(I18n.tr("Nothing to shake out: no oversized blocks in the messages."))
            return 0
        }
        const sello = String(Date.now())
        const cola = []
        let total = 0
        for (let i = 0; i < tramos.length; i++) {
            const ruta = svc.dataDir + "/archivo/" + sello + "-" + i + ".txt"
            cola.push({ idx: tramos[i].idx, ini: tramos[i].ini, fin: tramos[i].fin,
                        texto: tramos[i].texto, ruta: ruta,
                        marca: PR.marcaArchivo(tramos[i].texto.length, ruta) })
            total += tramos[i].texto.length - cola[i].marca.length
        }
        comp._colaArchivo = cola
        comp._archivados = 0
        comp._ahorroSacudida = total
        _siguienteArchivo()
        return total
    }
    property int _archivados: 0
    property int _ahorroSacudida: 0

    function _siguienteArchivo() {
        if (comp._archivados >= comp._colaArchivo.length) {
            comp._aplicarSacudida()
            return
        }
        const t = comp._colaArchivo[comp._archivados]
        comp._archTexto = t.texto
        archProc.environment = ({ QS_OUT: t.ruta })
        archProc.stdinEnabled = true
        archProc.running = true
    }
    property string _archTexto: ""

    Process {
        id: archProc
        // El bloque puede ser enorme, así que entra por la entrada estándar y no
        // por el entorno, que tiene el mismo tope por variable que el argv.
        command: ["sh", "-c",
            'd=$(dirname -- "$QS_OUT") && mkdir -p -- "$d" && umask 077 && cat > "$QS_OUT"']
        onStarted: {
            archProc.write(comp._archTexto)
            comp._archTexto = ""
            archProc.stdinEnabled = false
        }
        onExited: (code) => {
            if (code !== 0) {
                // Un bloque que no se pudo archivar no se elide: perderlo para
                // ahorrar contexto es lo que esto no debe hacer.
                comp._colaArchivo[comp._archivados].fallo = true
            }
            comp._archivados++
            comp._siguienteArchivo()
        }
    }

    // Con todo ya en disco se reescriben los mensajes, de atrás hacia delante
    // dentro de cada uno: al revés, el primer reemplazo desplazaría las posiciones
    // de los siguientes.
    function _aplicarSacudida() {
        const porMensaje = ({})
        let n = 0
        let ganado = 0
        for (let i = 0; i < comp._colaArchivo.length; i++) {
            const t = comp._colaArchivo[i]
            // Un bloque que no se pudo archivar no se elide, y tampoco cuenta en
            // lo ahorrado.
            if (t.fallo)
                continue
            if (!porMensaje[t.idx])
                porMensaje[t.idx] = []
            porMensaje[t.idx].push(t)
            ganado += t.texto.length - t.marca.length
            n++
        }
        comp._ahorroSacudida = ganado
        for (const k in porMensaje) {
            const idx = Number(k)
            const m = comp.conv.messages.get(idx)
            if (!m)
                continue
            comp.conv.messages.setProperty(idx, "content",
                PR.sacudir(String(m.content || ""), porMensaje[k]))
        }
        comp._colaArchivo = []
        comp.conv.save()
        if (n === 0) {
            comp.conv.pushInfo(I18n.tr("Could not archive the blocks: nothing was removed."))
            return
        }
        comp.conv.pushInfo(I18n.tr("Shook out %1 blocks (%2 chars) into %3 — readable with read_file.")
                           .arg(n).arg(comp._ahorroSacudida)
                           .arg(comp.svc.dataDir + "/archivo/"))
    }

    // COMPACTAR
    function compact(motivo) {
        const razon = String(motivo || "")
        if (compacting || svc.notConfigured || conv.messages.count < 2)
            return false
        // Mitad de turno es el único caso en que el servicio está ocupado a
        // propósito: el bucle de herramientas ha parado en una frontera segura y
        // espera a que esto termine.
        if (svc.busy && razon !== "midturn")
            return false
        // Con una tarjeta esperando aprobación no se compacta: resolverla a mitad
        // de resumen dejaría el protocolo a medias.
        for (let i = 0; i < conv.messages.count; i++)
            if (conv.messages.get(i).role === "tool"
                    && conv.messages.get(i).toolStatus === "pending")
                return false

        // Sin bridas de caché: se va a reescribir el hilo entero de todos modos,
        // así que el prefijo está muerto y podar a fondo sale gratis.
        const todo = _plano()
        const plan = PR.planificar(todo, ({}))
        const podado = PR.aplicar(todo, plan)
        _ahorro = plan.ahorro

        // Solo se pregunta cuando la compactación no la pidió el usuario. Si la
        // pidió él, quiere un resumen; dárselo podado y sin resumir sería
        // contestar a otra cosa.
        if (razon !== "" && plan.podados > 0
                && PR.pesar(podado) <= svc.charBudget * _yaCabe) {
            _podarHilo(plan)
            warned = false
            conv.pushInfo(I18n.tr("Pruned %1 stale tool results (%2 chars): no summary needed.")
                          .arg(plan.podados).arg(plan.ahorro))
            _seguir(razon)
            return true
        }

        compacting = true
        _retried = false
        _modo = "resumen"
        _motivo = razon
        _previo = _estadoPrevio()
        _fich = PR.bloqueFicheros(PR.ficheros(podado), 24)

        // Se aparta ANTES de pedir el resumen: los últimos K turnos vuelven
        // después LITERALES, tarjetas de herramienta incluidas — el resumen es
        // para lo viejo, no para lo que aún tienes en la retina. Ya podados,
        // eso sí, salvo las últimas tarjetas, que la poda no toca nunca.
        _keepTail = []
        if (Settings.aiCompactKeep > 0) {
            let users = 0, cut = -1
            for (let i = podado.length - 1; i >= 0; i--)
                if (podado[i].role === "user") {
                    users++
                    if (users >= Settings.aiCompactKeep) {
                        cut = i
                        break
                    }
                }
            if (cut >= 0) {
                // Si la cola sigue siendo enorme se recorta por turnos enteros,
                // nunca por debajo del último del usuario: esa es la pregunta
                // viva y tirarla dejaría al modelo sin saber qué se le pidió.
                const usuarios = []
                for (let i = cut; i < podado.length; i++)
                    if (podado[i].role === "user")
                        usuarios.push(i)
                const tope = svc.charBudget * _topeCola
                let ini = cut
                for (let k = 0; k + 1 < usuarios.length; k++) {
                    if (PR.pesar(podado.slice(ini)) <= tope)
                        break
                    ini = usuarios[k + 1]
                }
                _keepTail = podado.slice(ini)
            }
        }
        _sustituidos = podado.length - _keepTail.length

        // El resumen anterior no viaja dos veces: sale del cuerpo y entra como
        // estado en la orden final.
        const cuerpo = []
        for (let i = 0; i < podado.length; i++)
            if (!(podado[i].role === "assistant" && podado[i].compactOf > 0))
                cuerpo.push(podado[i])
        _guion = TR.serializar(cuerpo, ({ tope: comp._topeGuion })).texto

        conv.pushInfo(I18n.tr("Compacting the context…"))
        _send()
        return true
    }

    // Compactar reescribe ESTE hilo; traspasar abre otro. Cuando una sesión ya
    // no da más de sí, un documento de continuación en una conversación limpia
    // es mejor que un resumen apretado dentro de la vieja.
    function handoff() {
        if (svc.busy || compacting || svc.notConfigured || conv.messages.count < 2)
            return false
        compacting = true
        _retried = false
        _modo = "traspaso"
        _motivo = ""
        _previo = ""
        _keepTail = []
        const hilo = _plano()
        _fich = PR.bloqueFicheros(PR.ficheros(hilo), 24)
        _guion = TR.serializar(hilo, ({ tope: comp._topeGuion })).texto
        conv.pushInfo(I18n.tr("Writing the handoff document…"))
        _send()
        return true
    }

    // Cancelar: una compactación en vuelo pertenece al hilo que la pidió. Si
    // llegara después de cambiar de conversación, borraría LA NUEVA.
    function cancel() {
        if (!compacting)
            return
        proc.running = false
        compacting = false
        _keepTail = []
        _guion = ""
    }

    // Qué pasa después de conseguirlo. Un desbordamiento y una compactación a
    // mitad de turno dejan un turno A MEDIAS: hay que retomarlo, no volver a la
    // cola como si el turno hubiera terminado.
    function _seguir(razon) {
        if (razon === "overflow" || razon === "midturn")
            Qt.callLater(comp.svc.start)
        else
            Qt.callLater(comp.svc.dequeue)
    }

    function _send() {
        // Dos mensajes y ya: la conversación aplanada a texto y la orden. Sin
        // protocolo de herramientas, sin resultados íntegros, sin razonamiento.
        const msgs = [
            { role: "system", content: svc.systemFor(comp._archivero, "compact") },
            { role: "user",
              content: (comp._previo !== ""
                        ? "<estado-acumulado>\n" + comp._previo + "\n</estado-acumulado>\n\n"
                        : "")
                     + "<conversacion>\n" + comp._guion + "\n</conversacion>\n\n"
                     + comp._orden() }
        ]
        const req = { model: svc.model, messages: msgs,
                      temperature: 0.2, stream: false }
        // Resumir es trabajo mecánico: se le pide el esfuerzo mínimo. Pagar
        // pensamiento profundo por un resumen es justo el gasto que el reparto
        // por tarea existe para evitar.
        svc.tuneRequest(req, "compact")
        const t = svc.chatCommand(req, 180)
        comp._body = t.body
        proc.command = t.cmd
        proc.environment = t.env
        proc.stdinEnabled = true
        proc.running = true
    }

    property string _body: ""

    // El resumen corto que el modelo escribe en su primera sección: sirve para
    // la nota del hilo y para el título, y sale gratis porque viene en la misma
    // respuesta en vez de en una segunda llamada.
    function _corto(texto) {
        const m = /##\s*Resumen corto\s*\n+([\s\S]*?)(?:\n##\s|\s*$)/.exec(texto)
        if (!m)
            return ""
        return m[1].trim().replace(/\s+/g, " ").slice(0, 200)
    }

    Process {
        id: proc
        stdout: StdioCollector { id: outCol }
        stderr: StdioCollector {}
        onStarted: {
            proc.write(comp._body)
            comp._body = ""
            proc.stdinEnabled = false
        }
        onExited: (code) => {
            if (!comp.compacting)          // cancelada por /limpiar o similar
                return
            let j = null
            try { j = JSON.parse(outCol.text) } catch (e) {}
            const m = j && j.choices && j.choices[0] && j.choices[0].message
            const texto = m ? TU.splitThink(String(m.content || "")).text.trim() : ""
            if (code !== 0 || texto === "") {
                const why = (j && j.error && (j.error.message || j.error.code))
                          || comp.svc.transportError(code)
                          || (code !== 0 ? "curl " + code : I18n.tr("No response received"))
                // Un tropiezo transitorio merece UN reintento; después se desiste
                // con motivo y el historial queda como estaba.
                if (comp.svc.isTransient(String(why)) && !comp._retried) {
                    comp._retried = true
                    retry.restart()
                    return
                }
                const razon = comp._motivo
                comp.compacting = false
                comp._keepTail = []
                comp._guion = ""
                comp.conv.pushInfo(I18n.tr("Compaction failed: %1").arg(String(why).slice(0, 200)))
                // Un desbordamiento que además no se puede compactar deja el
                // turno muerto: no se reintenta, porque volvería a desbordar.
                if (razon !== "overflow")
                    Qt.callLater(comp.svc.dequeue)
                return
            }
            comp.compacting = false
            comp.warned = false
            if (comp._modo === "traspaso") {
                comp._traspasar(texto)
                return
            }
            // La contabilidad de archivos la escribe el harness y se pega tal
            // cual: es el único trozo del resumen que no puede estar mal.
            const cabecera = "**" + I18n.tr("Summary of the previous conversation")
                           + ":**\n\n" + texto
                           + (comp._fich !== ""
                              ? "\n\n**" + I18n.tr("Files touched") + "**\n```\n"
                                + comp._fich + "\n```" : "")
                           // Un resumen es una reconstrucción, no una fuente: si
                           // lo que compruebes ahora lo contradice, manda lo que
                           // compruebes. Un agente que trata su propio resumen
                           // como autoridad se pelea con la realidad.
                           + "\n\n_" + I18n.tr("This summary is a reconstruction: anything you verify now overrides it.") + "_"
            // El hilo se reconstruye entero, así que las rutas resueltas —que se
            // guardan por POSICIÓN— ya no apuntan a la tarjeta que las originó:
            // se tiran antes de repoblar. Heredar un veredicto de "no escapa" de
            // otra llamada es justo lo que no puede pasar.
            comp.tools.forgetPaths()
            comp.conv.messages.clear()
            comp.conv.append({ role: "assistant", content: cabecera,
                               modelName: comp.svc.model, at: Date.now(),
                               compactOf: Math.max(1, comp._sustituidos) })
            for (let i = 0; i < comp._keepTail.length; i++)
                comp.conv.append(comp._keepTail[i])
            comp._keepTail = []
            comp._guion = ""
            const corto = comp._corto(texto)
            comp.conv.push({ role: "info",
                             content: corto !== "" ? corto
                                : comp._ahorro > 0
                                ? I18n.tr("Context compacted (%1 chars pruned first).").arg(comp._ahorro)
                                : I18n.tr("Context compacted.") })
            comp._seguir(comp._motivo)
        }
    }

    // El documento de traspaso siembra una conversación NUEVA. La vieja se
    // archiva entera (newConversation la guarda), así que no se pierde nada: lo
    // que cambia es dónde sigue el trabajo.
    function _traspasar(texto) {
        comp._guion = ""
        const doc = "**" + I18n.tr("Handoff from the previous conversation") + ":**\n\n"
                  + texto
                  + (comp._fich !== ""
                     ? "\n\n**" + I18n.tr("Files touched") + "**\n```\n"
                       + comp._fich + "\n```" : "")
        comp.svc.newConversation()
        comp.conv.append({ role: "assistant", content: doc,
                           modelName: comp.svc.model, at: Date.now(),
                           compactOf: 1 })
        comp.conv.push({ role: "info",
                         content: I18n.tr("Handed off to a new conversation. The previous one is in the history.") })
    }

    Timer {
        id: retry
        interval: 2500
        onTriggered: if (comp.compacting) comp._send()
    }
}
