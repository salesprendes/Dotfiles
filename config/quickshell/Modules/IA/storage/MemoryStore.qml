import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import "../TextUtils.js" as TU

// Lo que el asistente RECUERDA entre conversaciones, en dos cajones que a
// propósito no se mezclan:
//
//   · MEMORIA (idea de OpenWorker) — hechos del usuario que él aprobó guardar
//     con la herramienta 'remember'. Van con su [#id] para que el modelo pueda
//     CORREGIR o RETIRAR una nota desfasada en vez de apilar el dato nuevo al
//     lado del rancio y contradecirse más tarde.
//
//   · INSTINTOS (idea de ECC) — lecciones OPERATIVAS aprendidas trabajando en
//     ESTE equipo: "aquí systemctl pide contraseña", "el servidor web1 escucha
//     en el 2222", "grep sobre este archivo necesita -a". Cada uno lleva una
//     CONFIANZA que sube cuando el agente vuelve a toparse con lo mismo, y de
//     ahí sale el orden con el que entran al prompt.
//
// La memoria guarda hechos del usuario; el instinto guarda cómo trabajar aquí.
// Mezclarlos ensuciaría los dos.
Scope {
    id: store

    // Del harness solo hace falta una cosa: la última pregunta del usuario, que
    // es la consulta contra la que se ordena por relevancia.
    property var svc
    readonly property string _query: svc ? svc.lastUserText : ""

    // El JsonAdapter propaga sus escrituras con un tick de retraso: leer
    // mem.notes justo después de asignarlo devuelve el valor ANTERIOR. Con las
    // llamadas en paralelo, dos operaciones de memoria del mismo lote se
    // pisarían (la segunda copiaría el array viejo). Por eso la fuente de verdad
    // en memoria es la copia local en cuanto se escribe una vez; el adaptador
    // queda como persistencia.
    property var _notesLocal: null
    readonly property var notes: _notesLocal !== null ? _notesLocal : (mem.notes || [])
    function setNotes(arr) {
        _notesLocal = arr
        mem.notes = arr
    }
    function removeNote(i) {
        const n = notes.slice()
        n.splice(i, 1)
        setNotes(n)
    }

    property var _instLocal: null
    readonly property var instincts: _instLocal !== null ? _instLocal : (inst.items || [])
    function setInstincts(arr) {
        _instLocal = arr
        inst.items = arr
    }
    function removeInstinct(i) {
        const n = instincts.slice()
        n.splice(i, 1)
        setInstincts(n)
    }

    // Guardar una lección. Si ya existe una igual, no se duplica: sube su
    // confianza — que es justo la señal de que la lección es de verdad.
    function addInstinct(text) {
        const t = String(text || "").trim().slice(0, 300)
        if (t === "")
            return "Lección vacía."
        const list = instincts.slice()
        const low = t.toLowerCase()
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].text).toLowerCase() === low) {
                list[i] = { text: list[i].text,
                            confidence: Math.min(9, (list[i].confidence || 1) + 1) }
                setInstincts(list)
                return "Ya lo sabía; ahora con más confianza (" + list[i].confidence + ")."
            }
        }
        list.push({ text: t, confidence: 1 })
        setInstincts(list.slice(-40))     // tope: lo viejo cede sitio
        return "Aprendido."
    }

    // ── Lo que entra al prompt ───────────────────────────────────────────────
    readonly property string instinctBlock: {
        const all = instincts
        if (all.length === 0)
            return ""
        // Primero por confianza; a igualdad, por relevancia a lo que se acaba de
        // preguntar (el mismo criterio que la memoria).
        const texts = all.map(x => String(x.text))
        const byRel = TU.rankNotes(texts, _query)
        const order = byRel.slice().sort((a, b) =>
            ((all[b].confidence || 1) - (all[a].confidence || 1))
            || (byRel.indexOf(a) - byRel.indexOf(b)))
        let block = "\nLo que has aprendido trabajando en este equipo (entre "
                  + "paréntesis, cuántas veces se ha confirmado). Tenlo en "
                  + "cuenta antes de repetir un error ya conocido:"
        let chars = 0
        for (let k = 0; k < order.length; k++) {
            const it = all[order[k]]
            chars += String(it.text).length
            if (chars > 1200)
                break
            block += "\n- " + it.text + " (" + (it.confidence || 1) + ")"
        }
        return block
    }

    readonly property string memoryBlock: {
        const n = notes
        if (n.length === 0)
            return ""
        let block = "\nMemoria del usuario (notas que él aprobó guardar). Si "
                  + "alguna queda desfasada, corrígela con memory_update o "
                  + "retírala con memory_forget usando su número, en vez de "
                  + "guardar una nota nueva que la contradiga:"
        // Orden por RELEVANCIA a lo último que preguntó el usuario (idea de
        // OpenHarness): con el presupuesto lleno, lo que entra es lo que viene a
        // cuento, no lo que se guardó primero. Los ids [#n] siguen siendo los de
        // la lista real, para que corregir siga apuntando bien.
        const order = TU.rankNotes(n, _query)
        let chars = 0
        for (let k = 0; k < order.length; k++) {
            const i = order[k]
            chars += n[i].length
            if (chars > 2000)
                break
            block += "\n- [#" + (i + 1) + "] " + n[i]
        }
        return block
    }

    // ── Persistencia ─────────────────────────────────────────────────────────
    // Cada cajón en su archivo, dentro del módulo y fuera de git.
    FileView {
        path: store.svc ? store.svc.dataDir + "/ai-memory.json" : ""
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: mem
            property var notes: []
        }
    }

    FileView {
        path: store.svc ? store.svc.dataDir + "/ai-instincts.json" : ""
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: inst
            property var items: []      // [{text, confidence}]
        }
    }
}
