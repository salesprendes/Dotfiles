pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Config

// Estado global compartido: un único panel abierto a la vez.
Singleton {
    id: g

    // Registro único de los paneles conmutables. 'widget' es el id del widget
    // de la barra que abre el panel, y hace que el salto con flechas siga el
    // orden configurado en la barra en vez de uno fijado aquí. 'island' es el
    // destino de la isla que sustituye al panel cuando la isla está encendida.
    readonly property var panels: [
        { name: "launcher",  widget: "launcher" },
        { name: "control",   widget: "connectivity" },
        { name: "notif",     widget: "notifications", island: "notifs" },
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

    // Panel abierto, o "" si no hay ninguno. Los valores válidos son los 'name'
    // del registro.
    property string openPanel: ""

    // Monitor con foco en el momento de abrir. shell.qml construye el panel
    // solo en esta pantalla, así que los demás monitores no instancian copias
    // invisibles con sus timers. Se captura en open() antes de tocar openPanel,
    // y se conserva al cerrar para que la animación termine donde empezó. Sin
    // Hyprland queda "" y entonces instancian todas las pantallas.
    property string openedOnMonitor: ""

    // Ajustes es una ventana real de Hyprland, no un popout: tiene estado
    // propio y no compite con 'openPanel' ni se cierra al abrir uno.
    property bool settingsOpen: false

    // El monitor de sistema como aplicación, con las mismas reglas que Ajustes.
    // Convive con el popout de la barra (openPanel === "sysmon"), que es el
    // vistazo rápido; esto es la ventana en la que sentarse a mirar.
    property bool sysMonAppOpen: false
    signal sysMonAppResummon()

    // Abre la aplicación, o deja que la ventana decida si ya existe: cerrarse
    // si está en este workspace, o traerse al actual.
    function toggleSysMonApp() {
        if (sysMonAppOpen) sysMonAppResummon()
        else sysMonAppOpen = true
    }

    readonly property bool controlCenterOpen: openPanel === "control"
    readonly property bool notifCenterOpen:   openPanel === "notif"
    readonly property bool sysMonOpen:         openPanel === "sysmon"
    readonly property bool launcherOpen:       openPanel === "launcher"
    readonly property bool clipboardOpen:      openPanel === "clipboard"
    readonly property bool dashboardOpen:      openPanel === "dashboard"
    readonly property bool screenCaptureOpen:  openPanel === "capture"
    readonly property bool aiOpen:             openPanel === "ai"
    readonly property bool emojiOpen:          openPanel === "emoji"
    // readonly como sus nueve hermanas, y es obligatorio: en QML asignar a una
    // propiedad con binding lo destruye para siempre, así que un
    // 'spotlightOpen = false' dejaría la propiedad congelada y openPanel
    // clavado en "spotlight". Spotlight se cierra con closeAll().
    readonly property bool spotlightOpen: openPanel === "spotlight"

    // Nombre del monitor con foco, o "" sin Hyprland.
    function focusedMonitorName() {
        return Hyprland.focusedMonitor?.name ?? ""
    }

    // ¿Hay una ventana a pantalla completa en esta pantalla que obligue al
    // shell a apartarse?
    //
    // La barra y el dock desaparecen solos porque viven en la capa Top y
    // Hyprland dibuja la ventana completa por encima de ella. La isla está en
    // Overlay —lo necesita para ponerse delante de los popouts— y ahí nada la
    // tapa, así que tiene que apartarse a mano.
    //
    // Se pregunta por pantalla: un vídeo en un monitor no borra el reloj del
    // otro. Sin Hyprland devuelve false, que es la respuesta segura: quedarse
    // puesto se ve y se corrige, desaparecer sin motivo parece una caída.
    function hiddenByFullscreen(screen) {
        if (!Settings.hideOnFullscreen || !screen)
            return false
        return Hyprland.monitorFor(screen)?.activeWorkspace?.hasFullscreen === true
    }

    // La misma regla para quien no tiene una pantalla concreta que mirar, como
    // la fuente de notificaciones de la isla, que se instancia una sola vez
    // fuera del recorrido de monitores. Mira el monitor enfocado, así que con
    // dos pantallas también calla en la que no está a pantalla completa.
    function focusedHasFullscreen() {
        if (!Settings.hideOnFullscreen)
            return false
        return Hyprland.focusedMonitor?.activeWorkspace?.hasFullscreen === true
    }

    // Destino de isla que sustituye a este panel, o "" si es un panel de
    // verdad. Sale del registro para que todas las entradas —open, toggle,
    // switchOrder, switchPanel— apliquen la misma condición. Con la isla
    // apagada nunca hay sustitución.
    function islandDestinationFor(p) {
        if (!Settings.islandEnabled)
            return ""
        for (const e of g.panels)
            if (e.name === p)
                return e.island ?? ""
        return ""
    }

    // Abre un panel, o su hoja de isla si la tiene, manteniendo el invariante:
    //
    //     openPanel !== ""   ⇒   IslandState.destination === ""
    //
    // Los dos a la vez dejan la isla invisible (se esconde con cualquier panel
    // abierto) y, al cerrar el panel, aparece sola una hoja modal que no ha
    // abierto nadie y que además se queda con el teclado. Por eso cada rama
    // limpia la otra antes de asignar.
    function open(p) {
        const dest = g.islandDestinationFor(p)
        if (dest !== "") {
            openPanel = ""
            IslandState.openDestination(dest)
            return
        }
        IslandState.closeDestination()
        openedOnMonitor = g.focusedMonitorName()
        openPanel = p
    }

    // Alterna un panel. Si su destino de isla está tapado por otro panel no
    // alterna sino que abre: cerrar una hoja que no se está viendo se sentiría
    // como que el gesto no hace nada.
    function toggle(p) {
        const dest = g.islandDestinationFor(p)
        if (dest !== "") {
            if (g.openPanel !== "") {
                g.open(p)
                return
            }
            IslandState.toggleDestination(dest)
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
    signal settingsResummon()

    // Abre Ajustes, o deja que la ventana decida si ya existe: cerrarse si está
    // en este workspace, o traerse al actual.
    function toggleSettings() {
        if (settingsOpen) settingsResummon()
        else settingsOpen = true
    }

    // Destino pendiente dentro de Ajustes. Se deja anotado en vez de llamar a
    // la ventana porque puede no existir todavía: se construye perezosamente
    // la primera vez que se abre.
    property string settingsPendingCat: ""
    property string settingsPendingQuery: ""

    // Abre Ajustes directamente en una categoría y con una búsqueda puesta,
    // para que un resultado del buscador lleve al ajuste y no solo a la ventana.
    function openSettingsAt(cat, query) {
        g.settingsPendingCat = cat ?? ""
        g.settingsPendingQuery = query ?? ""
        if (g.settingsOpen)
            g.settingsResummon()
        else
            g.settingsOpen = true
    }

    // Cierra los popups y la hoja de la isla; Ajustes es independiente y no se
    // toca. Incluye la hoja porque es lo que espera `qs ipc call panel close` y
    // lo que hace falta antes de bloquear la pantalla. Usa closeDestination y
    // no collapse para que un aviso a la vista se vaya cuando le toque y no
    // porque se haya cerrado un panel ajeno.
    function closeAll() {
        openPanel = ""
        IslandState.closeDestination()
    }

    // Recorrido de las flechas con un panel abierto: el orden en que los
    // widgets aparecen en la barra, de izquierda a derecha. Los paneles sin
    // widget quedan fuera porque no tienen sitio en ese recorrido.
    readonly property var switchOrder: {
        const out = []
        for (const sec of BarCatalog.sections)
            for (const e of BarCatalog.entriesOf(Settings.barLayout, sec))
                for (const p of g.panels)
                    if (p.widget !== "" && p.widget === e.id && out.indexOf(p.name) === -1)
                        out.push(p.name)
        return out
    }

    // Posición lógica dentro del recorrido. No basta 'openPanel': con la isla
    // encendida, "notif" abre una hoja y deja openPanel vacío, y entonces
    // indexOf("") daría -1 y las flechas dejarían de responder.
    readonly property string ringPosition: {
        if (g.openPanel !== "")
            return g.openPanel
        if (IslandState.destination !== "")
            for (const e of g.panels)
                if (e.island === IslandState.destination)
                    return e.name
        return ""
    }

    // Salta al panel vecino del recorrido. Es circular a propósito: un extremo
    // sin salida obliga a recordar en qué punta se está.
    function switchPanel(direction) {
        const order = g.switchOrder
        if (order.length < 2)
            return false
        const at = order.indexOf(g.ringPosition)
        if (at === -1)
            return false
        const next = (at + direction + order.length) % order.length
        g.open(order[next])
        return true
    }

    // Pantalla con foco, para ventanas modales únicas que no deben duplicarse
    // por monitor compitiendo por el teclado exclusivo. Sin Hyprland cae a la
    // primera pantalla.
    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name ?? ""
        const list = Quickshell.screens
        for (let i = 0; i < list.length; i++)
            if (list[i].name === name)
                return list[i]
        return list.length > 0 ? list[0] : null
    }

    // Sanea los dos estados imposibles que deja cambiar el interruptor de la
    // isla con algo abierto: openPanel === "notif" con la isla encendida la
    // dejaría invisible sin que nada la vuelva a mostrar, y un destino puesto
    // con la isla apagada reaparecería expandido al volver a encenderla.
    Connections {
        target: Settings
        function onIslandEnabledChanged() {
            if (g.openPanel === "notif")
                g.openPanel = ""
            IslandState.closeDestination()
        }
    }
}
