pragma Singleton

import QtQuick
import Quickshell
import qs.Config

// Catálogo de widgets de la barra: solo metadatos. La implementación de cada
// uno vive en Bar/BarWidgetLoader.qml, que es quien mapea id → Component.
//
// La separación permite que el editor de Ajustes liste qué widgets existen sin
// instanciar una barra: un singleton que instanciara componentes arrastraría
// Hyprland, PipeWire, MPRIS y el resto de servicios solo por abrir una página.
//
// El layout vive en Settings.barLayout con esta forma:
//
//     { "left": [ {"id":"launcher"}, … ], "center": [ … ], "right": [ … ] }
//
// Cada entrada es un objeto y no un id suelto, para que un widget pueda llevar
// sus propios ajustes en línea el día que haga falta. Hoy solo se usa 'id'.
//
// La presencia en el layout es la única fuente de verdad sobre si un widget se
// ve.
Singleton {
    id: cat

    readonly property var sections: ["left", "center", "right"]

    // 'needs' declara una dependencia del sistema que comprueba el editor;
    // Config no importa qs.Services para no acoplar la capa de configuración a
    // la de servicios. El widget ya se auto-oculta si su servicio no está, así
    // que esto solo evita ofrecer algo que nunca se verá.
    //
    // 'multiple' permite varias instancias del mismo id.
    readonly property var widgets: [
        { id: "launcher",     glyph: "󰣇",  section: "left",   needs: "", multiple: false },
        { id: "workspaces",   glyph: "󰧨",  section: "left",   needs: "", multiple: false },
        { id: "activeWindow", glyph: "󰖯",  section: "left",   needs: "", multiple: false },

        { id: "media",        glyph: "󰝚",  section: "center", needs: "", multiple: false },
        { id: "weather",      glyph: "󰖐",  section: "center", needs: "", multiple: false },
        { id: "clock",        glyph: "󰥔",  section: "center", needs: "", multiple: false },

        { id: "tray",         glyph: "󰒓",  section: "right",  needs: "", multiple: false },
        { id: "sysmon",       glyph: "󰍛",  section: "right",  needs: "", multiple: false },
        { id: "keyboard",     glyph: "󰌌",  section: "right",  needs: "", multiple: false },
        { id: "updates",      glyph: "󰚰",  section: "right",  needs: "", multiple: false },
        { id: "connectivity", glyph: "󰖩",  section: "right",  needs: "", multiple: false },
        { id: "nightlight",   glyph: "󰖔",  section: "right",  needs: "", multiple: false },
        { id: "power",        glyph: "󰠠",  section: "right",  needs: "power",   multiple: false },
        { id: "caffeine",     glyph: "󰅶",  section: "right",  needs: "", multiple: false },
        { id: "ai",           glyph: "󱙺",  section: "right",  needs: "", multiple: false },
        { id: "battery",      glyph: "󰁽",  section: "right",  needs: "battery", multiple: false },
        { id: "clipboard",    glyph: "󰅍",  section: "right",  needs: "", multiple: false },
        { id: "emoji",        glyph: "󰞅",  section: "right",  needs: "", multiple: false },
        { id: "notifications",glyph: "󰂚",  section: "right",  needs: "", multiple: false },

        { id: "spacer",       glyph: "󰇜",  section: "right",  needs: "", multiple: true }
    ]

    // Nombre visible, aparte de 'widgets' porque pasa por I18n y se resuelve en
    // el idioma actual: dentro de aquel mapa se evaluaría una sola vez y cambiar
    // de idioma dejaría el editor en el anterior hasta reiniciar.
    function nameFor(id) {
        switch (id) {
        case "launcher":      return I18n.tr("Launcher")
        case "workspaces":    return I18n.tr("Workspaces")
        case "activeWindow":  return I18n.tr("Active window")
        case "media":         return I18n.tr("Media player")
        case "weather":       return I18n.tr("Weather")
        case "clock":         return I18n.tr("Clock")
        case "tray":          return I18n.tr("System tray")
        case "sysmon":        return I18n.tr("Resource monitor")
        case "keyboard":      return I18n.tr("Keyboard layout")
        case "updates":       return I18n.tr("System updates")
        case "connectivity":  return I18n.tr("Network and sound")
        case "nightlight":    return I18n.tr("Night light")
        case "power":         return I18n.tr("Power profile")
        case "caffeine":      return I18n.tr("Caffeine")
        case "ai":            return I18n.tr("AI assistant")
        case "battery":       return I18n.tr("Battery")
        case "clipboard":     return I18n.tr("Clipboard")
        case "emoji":         return I18n.tr("Emoji")
        case "notifications": return I18n.tr("Notifications")
        case "spacer":        return I18n.tr("Spacer")
        }
        return id
    }

    function metaFor(id) {
        for (let i = 0; i < widgets.length; i++)
            if (widgets[i].id === id)
                return widgets[i]
        return null
    }

    function knows(id) {
        return metaFor(id) !== null
    }

    function glyphFor(id) {
        const m = metaFor(id)
        return m ? m.glyph : "󰘿"
    }

    // Disposición de fábrica. Solo entra lo que se ve de serie: el clima, la
    // cafeína, el separador y los widgets nuevos vienen apagados y se añaden
    // desde Ajustes, para no estrenarle a nadie una píldora que no ha pedido.
    function defaultLayout() {
        return {
            left:   [{ id: "launcher" }, { id: "workspaces" }, { id: "activeWindow" }],
            center: [{ id: "media" }, { id: "clock" }],
            right:  [{ id: "tray" }, { id: "sysmon" }, { id: "connectivity" },
                     { id: "power" }, { id: "ai" }, { id: "battery" },
                     { id: "clipboard" }, { id: "notifications" }]
        }
    }


    function entriesOf(layout, section) {
        if (!layout || typeof layout !== "object")
            return []
        const list = layout[section]
        return Array.isArray(list) ? list : []
    }

    // ¿Está este widget puesto en alguna sección? Lo usan los servicios que solo
    // deben sondear si su widget está a la vista.
    function has(layout, id) {
        for (const sec of sections)
            for (const e of entriesOf(layout, sec))
                if (e && e.id === id)
                    return true
        return false
    }

    // Posición de una entrada por su id, o null si no está puesta. Con
    // 'multiple' devuelve la primera: el editor trabaja por índice y no por id,
    // precisamente para poder distinguir dos separadores.
    function locate(layout, id) {
        for (const sec of sections) {
            const list = entriesOf(layout, sec)
            for (let i = 0; i < list.length; i++)
                if (list[i] && list[i].id === id)
                    return { section: sec, index: i }
        }
        return null
    }

    // Todas devuelven un layout nuevo en vez de mutar el recibido. Settings lo
    // guarda en una 'property var', y mutar el objeto in situ no emite el
    // cambio, así que la barra no se enteraría y no se guardaría nada.

    function clone(layout) {
        const out = {}
        for (const sec of sections)
            out[sec] = entriesOf(layout, sec).map(e => Object.assign({}, e))
        return out
    }

    // Descarta ids desconocidos y duplicados de widgets de instancia única, y
    // garantiza las tres secciones. Es lo que protege de un settings.json
    // editado a mano o venido de una versión con otros widgets.
    function sanitize(layout) {
        const out = { left: [], center: [], right: [] }
        const seen = {}
        for (const sec of sections) {
            for (const e of entriesOf(layout, sec)) {
                if (!e || typeof e !== "object")
                    continue
                const id = String(e.id || "")
                const meta = metaFor(id)
                if (!meta)
                    continue
                if (!meta.multiple) {
                    if (seen[id])
                        continue
                    seen[id] = true
                }
                out[sec].push(Object.assign({}, e))
            }
        }
        return out
    }

    // Mueve una entrada entre posiciones. toIndex se interpreta sobre la lista
    // ya sin la entrada movida, que es lo que hace que arrastrar un widget
    // dentro de su sección caiga donde se ve el hueco.
    function move(layout, fromSection, fromIndex, toSection, toIndex) {
        const next = clone(layout)
        const from = next[fromSection]
        if (!from || fromIndex < 0 || fromIndex >= from.length)
            return next
        const entry = from.splice(fromIndex, 1)[0]
        const to = next[toSection]
        const at = Math.max(0, Math.min(to.length, toIndex))
        to.splice(at, 0, entry)
        return next
    }

    function removeAt(layout, section, index) {
        const next = clone(layout)
        const list = next[section]
        if (list && index >= 0 && index < list.length)
            list.splice(index, 1)
        return next
    }

    // Añade al final de la sección indicada (o la de fábrica del widget).
    function add(layout, id, section) {
        const meta = metaFor(id)
        if (!meta)
            return clone(layout)
        const next = clone(layout)
        if (!meta.multiple && has(next, id))
            return next
        const sec = sections.indexOf(section) !== -1 ? section : meta.section
        next[sec].push({ id: id })
        return next
    }
}
