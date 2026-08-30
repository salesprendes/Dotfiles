pragma Singleton

import QtQuick
import Quickshell
import qs.Config
import qs.Services
import "Search.js" as Search

// De dónde salen los resultados de Spotlight. Cada fuente convierte lo suyo a
// la MISMA forma de elemento, y a partir de ahí el motor (Search.js) las trata
// a todas igual — que es lo que permite que una búsqueda mezcle una app, un
// emoji y un ajuste sin que ninguna sepa de las otras.
//
//   { id, name, subtitle, keywords, type, glyph, icon, run }
//
// 'run' es la función que se ejecuta al elegirlo. Va en el propio elemento y no
// en un switch por tipo: así añadir una fuente es escribir una función que
// devuelve elementos, y no tocar además el sitio donde se decide qué hacer con
// cada uno.
//
// PEREZA A PROPÓSITO. Solo se construyen las listas que la consulta puede
// necesitar. El catálogo de emojis son 2.500 objetos y el índice de ajustes hay
// que montarlo página a página: hacerlo en cada pulsación de tecla, para una
// consulta que empieza por "fir", sería tirar el trabajo entero.
Singleton {
    id: root

    function label(type) {
        switch (type) {
        case "calc":      return I18n.tr("Result")
        case "app":       return I18n.tr("Applications")
        case "setting":   return I18n.tr("Settings")
        case "clipboard": return I18n.tr("Clipboard")
        case "emoji":     return I18n.tr("Emoji")
        case "command":   return I18n.tr("Command")
        case "file":      return I18n.tr("Files")
        case "action":    return I18n.tr("Actions")
        }
        return type
    }

    // ── Aplicaciones ─────────────────────────────────────────────────────────
    // Junto con sus ACCIONES: una entrada .desktop puede declarar cosas como
    // «Nueva ventana privada» o «Nuevo documento», y hasta ahora el único modo
    // de llegar a ellas era abrir la app y buscarlas por dentro.
    //
    // Van en la misma lista y no en un menú aparte (que es como lo resuelve la
    // referencia) porque son pocas —aquí las declara menos del 10 % de las
    // apps, una o dos cada una— así que no ensucian nada, y a cambio se llega
    // a ellas escribiendo, que es de lo que va esto.
    function apps() {
        const out = []
        const list = AppCatalog.entries
        for (let i = 0; i < list.length; i++) {
            const e = list[i].entry
            if (!e)
                continue
            const kw = Array.isArray(e.keywords) ? e.keywords
                     : (typeof e.keywords === "string" && e.keywords !== "" ? [e.keywords] : [])
            out.push({
                id: "app:" + (e.id ?? e.name),
                name: e.name ?? "",
                subtitle: e.genericName || e.comment || "",
                keywords: kw,
                type: "app",
                icon: e.icon ?? "",
                entry: e,
                // La entrada .desktop se ejecuta sola: es lo mismo que hace
                // Panels/AppLauncher.qml, así que las dos vías lanzan igual.
                run: function () { e.execute() }
            })

            const acts = e.actions ?? []
            for (let j = 0; j < acts.length; j++) {
                const a = acts[j]
                if (!a || !a.name)
                    continue
                out.push({
                    id: "appact:" + (e.id ?? e.name) + ":" + a.name,
                    name: a.name,
                    subtitle: e.name ?? "",
                    // El nombre de la app va en una palabra clave JUNTO al de
                    // la acción, y ese detalle es el que hace que funcione
                    // "firefox privada": la búsqueda por varias palabras exige
                    // que todos los trozos casen dentro del MISMO campo, y el
                    // nombre de la app está en el subtítulo, no en el nombre.
                    keywords: [(e.name ?? "") + " " + a.name],
                    type: "action",
                    icon: a.icon || e.icon || "",
                    run: function () { a.execute() }
                })
            }
        }
        return out
    }

    // ── Acciones de sesión ───────────────────────────────────────────────────
    // Bloquear, suspender, reiniciar y apagar. El modelo ya existe y lo
    // comparten el centro de control y el lanzador (ver Config/PowerActions),
    // así que aquí solo se traduce a elementos: una etiqueta que cambie de
    // sitio no puede quedarse a medias entre dos listas.
    function actions() {
        const out = []
        const list = PowerActions.model
        for (let i = 0; i < list.length; i++) {
            const a = list[i]
            out.push({
                id: "power:" + a.action,
                name: a.label,
                subtitle: I18n.tr("Session"),
                type: "action",
                glyph: a.ic,
                run: function () { Globals.runPowerAction(a.action) }
            })
        }
        return out
    }

    // ── Emojis ───────────────────────────────────────────────────────────────
    function emojis() {
        Emoji.load()
        const out = []
        const list = Emoji.all
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            out.push({
                id: "emoji:" + e.c,
                name: e.n,
                subtitle: e.g,
                type: "emoji",
                glyph: e.c,
                run: function () { Emoji.copy(e.c) }
            })
        }
        return out
    }

    // ── Ajustes ──────────────────────────────────────────────────────────────
    // El índice ya existe y se construye solo recorriendo las páginas (ver
    // Config/SettingsSearchIndex.qml). Aquí solo se traduce a elementos.
    function settings() {
        const out = []
        const list = SettingsSearchIndex.entries ?? []
        for (let i = 0; i < list.length; i++) {
            const s = list[i]
            out.push({
                id: "setting:" + s.cat + ":" + s.skey,
                name: s.label,
                subtitle: s.desc,
                // Los alias van de palabra clave y no metidos en el nombre: así
                // "matugen" encuentra el ajuste sin ensuciar lo que se lee en
                // la lista, y puntúa por debajo del nombre, que es lo justo.
                keywords: s.alias ? [s.alias] : [],
                type: "setting",
                glyph: "󰒓",
                run: function () { Globals.openSettingsAt(s.cat, s.label) }
            })
        }
        return out
    }

    // ── Portapapeles ─────────────────────────────────────────────────────────
    function clipboard() {
        Clipboard.refresh()
        const out = []
        const list = Clipboard.entries
        for (let i = 0; i < list.length; i++) {
            const c = list[i]
            out.push({
                id: "clip:" + c.raw,
                name: c.preview,
                subtitle: "",
                type: "clipboard",
                glyph: "󰅍",
                run: function () { Clipboard.copy(c) }
            })
        }
        return out
    }

    // ── Archivos ─────────────────────────────────────────────────────────────
    // La lista la trae Services/FileSearch, que ya ha hecho el trabajo lento
    // fuera. Aquí solo se le da forma de elemento.
    //
    // OJO CON EL ORDEN: estos elementos vienen de una búsqueda que YA ha
    // filtrado por el mismo texto, así que volver a puntuarlos contra la
    // consulta no descarta nada — solo decide cuál va primero, y para eso el
    // nombre del archivo es el campo que importa. Por eso la ruta va de
    // subtítulo y no de nombre: si no, "informe" puntuaría igual de alto un
    // archivo dentro de ~/informes que uno llamado informe.pdf.
    function files() {
        const out = []
        const list = FileSearch.results
        for (let i = 0; i < list.length; i++) {
            const ruta = list[i]
            const corte = ruta.lastIndexOf("/")
            const nombre = corte >= 0 ? ruta.slice(corte + 1) : ruta
            const carpeta = corte >= 0 ? ruta.slice(0, corte) : ""
            out.push({
                id: "file:" + ruta,
                name: nombre,
                subtitle: carpeta,
                type: "file",
                glyph: "󰈔",
                run: function () { Quickshell.execDetached(["xdg-open", ruta]) }
            })
        }
        return out
    }

    // ── Calculadora ──────────────────────────────────────────────────────────
    // No es una lista que se filtra: o la consulta es una cuenta o no lo es.
    function calc(text) {
        const value = Search.calc(text)
        if (value === null)
            return []
        const shown = Search.formatNumber(value)
        return [{
            id: "calc:" + text,
            name: shown,
            subtitle: text + " =",
            type: "calc",
            glyph: "󰃬",
            // Copiar el resultado es lo único razonable: sacar la calculadora
            // para volver a teclear el número a mano no tiene sentido.
            run: function () { Emoji.copy(shown) }
        }]
    }

    // ── Comando ──────────────────────────────────────────────────────────────
    // Solo con el prefijo ">": ofrecer "ejecutar esto en un terminal" para
    // cualquier cosa que se teclee es una forma rápida de que algún día se
    // ejecute algo que solo era una búsqueda.
    function command(text) {
        if (text === "")
            return []
        return [{
            id: "cmd:" + text,
            name: text,
            subtitle: I18n.tr("Run in the terminal"),
            type: "command",
            glyph: "󰆍",
            run: function () {
                const term = Settings.terminalApp !== "" ? Settings.terminalApp : "kitty"
                Quickshell.execDetached([term, "-e", "sh", "-c",
                    text + "; printf '\\n[Enter] '; read _"])
            }
        }]
    }

    // ── Reunir según el modo ─────────────────────────────────────────────────
    // Sin prefijo se buscan las fuentes "de todos los días". Los emojis y el
    // portapapeles quedan fuera de la búsqueda general a propósito: son 2.500 y
    // N entradas de texto libre que ensuciarían cualquier consulta corta. Se
    // llega a ellos con ":" y "@", que es un carácter de más y mucho menos ruido.
    function gather(mode, text) {
        if (mode === "calc")
            return root.calc(text)
        if (mode === "command")
            return root.command(text)
        if (mode === "emoji")
            return root.emojis()
        if (mode === "clipboard")
            return root.clipboard()
        if (mode === "setting")
            return root.settings()
        if (mode === "file")
            return root.files()

        // Modo general. La calculadora NO entra aquí: depende del texto y esto
        // se cachea por modo, así que la resuelve Spotlight.qml aparte.
        let out = root.apps()
        // Los ajustes solo cuando el índice ya está construido, para no forzar
        // su montaje en la primera pulsación.
        if (SettingsSearchIndex.built)
            out = out.concat(root.settings())
        // Las de sesión son cuatro y siempre valen: apagar el equipo desde el
        // buscador es de lo que más se usa una vez que existe.
        return out.concat(root.actions())
    }
}
