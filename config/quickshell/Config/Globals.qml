pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Config

// Estado global compartido. Un único panel abierto a la vez.
Singleton {
    id: g

    // ── Registro de paneles ──────────────────────────────────────────────────
    // La lista de paneles conmutables vive AQUÍ y no repartida entre shell.qml
    // (las ranuras), el IpcHandler (una función por panel) y cada widget de la
    // barra. Antes había que tocar los tres sitios para añadir uno, y el IPC
    // era una lista fija de funciones: añadir un panel obligaba a editar QML y
    // a regenerar los atajos de Hyprland.
    //
    // 'widget' es el id del widget de la barra que abre este panel, si lo hay.
    // Sirve para que el salto con flechas siga el ORDEN QUE SE VE en la barra
    // en vez de un orden inventado aquí — y como la barra ahora es
    // configurable, ese orden es el que el usuario haya puesto.
    readonly property var panels: [
        { name: "launcher",  widget: "launcher" },
        { name: "control",   widget: "connectivity" },
        { name: "notif",     widget: "notifications" },
        { name: "sysmon",    widget: "sysmon" },
        { name: "clipboard", widget: "clipboard" },
        { name: "dashboard", widget: "clock" },
        { name: "ai",        widget: "ai" },
        { name: "emoji",     widget: "" },
        { name: "spotlight", widget: "" },
        { name: "capture",   widget: "" }
    ]

    function isPanel(name) {
        for (const p of panels)
            if (p.name === name)
                return true
        return false
    }

    // "", "control", "notif", "sysmon", "launcher", "clipboard", "dashboard",
    // "capture", "ai"
    property string openPanel: ""

    // Monitor con foco al abrir el panel. Se captura aquí (en open(), ANTES de
    // tocar openPanel, para que las ranuras de shell.qml nunca se evalúen con
    // el monitor viejo) y no en cada Popout: shell.qml solo construye el panel
    // en esta pantalla, así los otros monitores no instancian copias
    // invisibles con sus timers. Se conserva al cerrar para que la animación
    // de cierre termine en el mismo monitor. Sin Hyprland queda "" y todas
    // las pantallas instancian (fallback).
    property string openedOnMonitor: ""

    // La ventana de Ajustes es independiente (es una ventana real de
    // Hyprland): tiene su propio estado y NO se cierra al abrir popups.
    property bool settingsOpen: false

    // El monitor de sistema como APLICACIÓN. Igual que Ajustes: ventana real de
    // Hyprland, con su estado propio, que no se cierra al abrir un popup ni
    // compite con 'openPanel'.
    //
    // Convive con el popout de la barra (openPanel === "sysmon"), que sigue
    // siendo lo de siempre: un vistazo rápido sin salir de lo que estabas
    // haciendo. La aplicación es lo otro — sentarse a mirar.
    property bool sysMonAppOpen: false
    signal sysMonAppResummon()
    function toggleSysMonApp() {
        if (sysMonAppOpen) sysMonAppResummon()
        else sysMonAppOpen = true
    }

    // No molestar (silencia popups).
    property bool dnd: false

    readonly property bool controlCenterOpen: openPanel === "control"
    readonly property bool notifCenterOpen:   openPanel === "notif"
    readonly property bool sysMonOpen:         openPanel === "sysmon"
    readonly property bool launcherOpen:       openPanel === "launcher"
    readonly property bool clipboardOpen:      openPanel === "clipboard"
    readonly property bool dashboardOpen:      openPanel === "dashboard"
    readonly property bool screenCaptureOpen:  openPanel === "capture"
    readonly property bool aiOpen:             openPanel === "ai"
    readonly property bool emojiOpen:          openPanel === "emoji"
    // Spotlight es panel como los demás (uno solo abierto a la vez), pero con
    // su propio conmutador legible porque se usa desde muchos sitios.
    //
    // ── POR QUÉ ES readonly, COMO SUS NUEVE HERMANAS ────────────────────────
    // Era la única declarada SIN readonly, con un onSpotlightOpenChanged que
    // la reescribía a openPanel en los dos sentidos. La idea era dejar que
    // quien quisiera cerrar Spotlight escribiera 'spotlightOpen = false' en
    // vez de llamar a closeAll(), y funcionaba... exactamente una vez.
    //
    // En QML, ASIGNAR A UNA PROPIEDAD CON BINDING DESTRUYE EL BINDING. Para
    // siempre, sin aviso. Así que en cuanto Spotlight se cerraba a sí mismo:
    //
    //   · spotlightOpen se quedaba en false fijo, sin volver a mirar openPanel
    //   · shell.qml, que construye el panel con 'active: spotlightOpen', no lo
    //     volvía a construir NUNCA
    //   · y openPanel se quedaba clavado en "spotlight", porque el único que
    //     lo limpiaba era el propio panel que ya no existía — con el dock y la
    //     isla escondidos el resto de la sesión, que se esconden con cualquier
    //     panel abierto
    //
    // No daba ningún error: simplemente dejaba de funcionar. Ahora es readonly
    // como las demás, y Spotlight se cierra con closeAll() como todos los
    // otros paneles del shell.
    readonly property bool spotlightOpen: openPanel === "spotlight"

    // Nombre del monitor con foco, o "" sin Hyprland. Se expone porque hay más
    // de un sitio que necesita saber "¿en cuál de las pantallas está mirando?"
    // — los paneles, y ahora también las hojas de la isla.
    function focusedMonitorName() {
        return Hyprland.focusedMonitor?.name ?? ""
    }

    // Con la isla encendida, las notificaciones viven EN ELLA y el centro
    // clásico no debe salir además: son la misma lista dos veces, y como la
    // isla se esconde mientras hay un panel abierto, abrir el centro la hacía
    // desaparecer justo al ir a mirar los avisos.
    //
    // ── POR QUÉ LA BIFURCACIÓN ESTÁ EN open() Y toggle() ────────────────────
    // Estuvo en toggleNotifCenter(), y ahí se colaba por debajo. La campana de
    // la barra sí pasa por ahí, pero `qs ipc call panel open notif` —y todo
    // atajo de teclado escrito así— entra por open() a secas y ponía
    // openPanel = "notif" con la isla encendida. El resultado no da ningún
    // error: la isla se esconde (se esconde con cualquier panel abierto), el
    // centro clásico no se construye (está condicionado a la isla apagada) y
    // no aparece NADA — con la isla desaparecida hasta que abras y cierres
    // otra cosa. Es el mismo estado colgado que ya arreglamos en el
    // interruptor de Ajustes, entrando por otra puerta.
    function _esNotifDeIsla(p) {
        return p === "notif" && Settings.islandEnabled
    }

    function open(p) {
        if (g._esNotifDeIsla(p)) {
            IslandState.openDestination("notifs")
            return
        }
        // Abrir un panel CIERRA la hoja de la isla. No es cosmético: la isla se
        // esconde entera mientras haya un panel abierto, así que sin esto quedan
        // dos cosas abiertas a la vez y una de ellas no se ve. Al cerrar el
        // panel reaparecía la hoja que abriste hace diez minutos, sola, como si
        // el shell tuviera memoria de algo que ya habías dejado atrás.
        //
        // Y desde que la hoja pide teclado (ver IslandWindow) es algo más que
        // raro: la isla invisible volvería a quedarse con las teclas.
        IslandState.closeDestination()
        openedOnMonitor = g.focusedMonitorName()
        openPanel = p
    }
    function toggle(p) {
        if (g._esNotifDeIsla(p)) {
            IslandState.toggleDestination("notifs")
            return
        }
        if (openPanel === p) openPanel = ""
        else open(p)
    }
    function toggleControlCenter() { toggle("control") }
    function toggleNotifCenter()   { toggle("notif") }
    function toggleSysMon()        { toggle("sysmon") }
    function toggleLauncher()      { toggle("launcher") }
    function toggleClipboard()     { toggle("clipboard") }
    function toggleDashboard()     { toggle("dashboard") }
    function toggleAi()            { toggle("ai") }
    function toggleEmoji()         { toggle("emoji") }
    function toggleSpotlight()     { toggle("spotlight") }
    // Si está cerrada, ábrela. Si ya está abierta, deja que la propia ventana
    // decida: cerrarla (si está en este workspace) o traerla al actual.
    signal settingsResummon()
    function toggleSettings() {
        if (settingsOpen) settingsResummon()
        else settingsOpen = true
    }

    // Abrir Ajustes DIRECTAMENTE en un sitio concreto, que es lo que hace falta
    // cuando el resultado de una búsqueda es un ajuste: llevarte a la ventana y
    // que te toque buscarlo otra vez a mano no es haberlo encontrado.
    //
    // Se deja anotado y la ventana lo recoge: puede que aún no exista (se
    // construye perezosamente al abrirse por primera vez), así que no hay a
    // quién llamarle en ese momento.
    property string settingsPendingCat: ""
    property string settingsPendingQuery: ""

    function openSettingsAt(cat, query) {
        g.settingsPendingCat = cat ?? ""
        g.settingsPendingQuery = query ?? ""
        if (g.settingsOpen)
            g.settingsResummon()
        else
            g.settingsOpen = true
    }
    // Cierra solo los popups (la ventana de Ajustes es independiente).
    // "Cierra lo que haya" incluye la hoja de la isla: es lo que espera quien
    // llama a `qs ipc call panel close`, y sobre todo lo que hace falta antes de
    // bloquear la pantalla (ver Config/PowerActions.run) — una hoja abierta
    // debajo del bloqueo no la ve nadie, pero sigue ahí al volver.
    //
    // closeDestination y no collapse: un aviso que está a la vista se va cuando
    // le toca, no porque hayas cerrado un panel que no tenía nada que ver.
    function closeAll() {
        openPanel = ""
        IslandState.closeDestination()
    }

    // ── Salto entre paneles con las flechas ──────────────────────────────────
    // Con un panel abierto, ←/→ pasan al panel del widget vecino de la barra.
    // Es el gesto de una barra de pestañas: una vez dentro, no hay que cerrar,
    // apuntar con el ratón a otra píldora y volver a abrir.
    //
    // El recorrido lo marca el layout de la barra (izquierda → centro →
    // derecha), así que salta exactamente entre lo que se ve y en el orden en
    // que se ve. Los paneles sin widget (la captura de pantalla) quedan fuera:
    // no tienen sitio en ese recorrido.
    readonly property var switchOrder: {
        const out = []
        for (const sec of BarCatalog.sections)
            for (const e of BarCatalog.entriesOf(Settings.barLayout, sec))
                for (const p of g.panels)
                    if (p.widget !== "" && p.widget === e.id && out.indexOf(p.name) === -1)
                        out.push(p.name)
        return out
    }

    function switchPanel(direction) {
        const order = g.switchOrder
        if (order.length < 2)
            return false
        const at = order.indexOf(g.openPanel)
        if (at === -1)
            return false
        // Circular a propósito: llegar al extremo y no poder seguir obliga a
        // recordar en qué punta estás.
        const next = (at + direction + order.length) % order.length
        g.open(order[next])
        return true
    }

    // Pantalla con foco, para ventanas únicas (modales) que deben aparecer una
    // sola vez y en el monitor activo — no una copia por monitor compitiendo
    // por el teclado exclusivo. Sin Hyprland cae a la primera pantalla.
    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name ?? ""
        const list = Quickshell.screens
        for (let i = 0; i < list.length; i++)
            if (list[i].name === name)
                return list[i]
        return list.length > 0 ? list[0] : null
    }

    // ── Cambiar el interruptor de la isla con algo abierto ───────────────────
    // Sin esto el shell se queda en un estado imposible, y de los que no dan
    // ningún error:
    //
    //   · ENCENDERLA con el centro clásico abierto: el centro deja de
    //     construirse, pero 'openPanel' se queda en "notif" — y la isla se
    //     esconde mientras haya un panel abierto. Isla invisible hasta que
    //     abras y cierres cualquier otra cosa.
    //   · APAGARLA con la hoja de la isla abierta: el destino se queda puesto
    //     en una isla que ya no existe, y al volver a encenderla aparecería
    //     expandida sin que nadie la haya tocado.
    //
    // Se sanean los dos lados en el mismo sitio porque es un solo cambio de
    // interruptor el que puede dejar cualquiera de los dos colgando.
    Connections {
        target: Settings
        function onIslandEnabledChanged() {
            if (g.openPanel === "notif")
                g.openPanel = ""
            IslandState.closeDestination()
        }
    }
}
