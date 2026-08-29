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

    function open(p) {
        openedOnMonitor = Hyprland.focusedMonitor?.name ?? ""
        openPanel = p
    }
    function toggle(p)            { if (openPanel === p) openPanel = ""; else open(p) }
    function toggleControlCenter() { toggle("control") }
    function toggleNotifCenter()   { toggle("notif") }
    function toggleSysMon()        { toggle("sysmon") }
    function toggleLauncher()      { toggle("launcher") }
    function toggleClipboard()     { toggle("clipboard") }
    function toggleDashboard()     { toggle("dashboard") }
    function toggleAi()            { toggle("ai") }
    function toggleEmoji()         { toggle("emoji") }
    // Si está cerrada, ábrela. Si ya está abierta, deja que la propia ventana
    // decida: cerrarla (si está en este workspace) o traerla al actual.
    signal settingsResummon()
    function toggleSettings() {
        if (settingsOpen) settingsResummon()
        else settingsOpen = true
    }
    // Cierra solo los popups (la ventana de Ajustes es independiente).
    function closeAll()            { openPanel = "" }

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

    // Acciones de sesión/energía compartidas (lanzador y centro de control).
    //
    // El bloqueo ya no sale a hyprlock: lo sirve el propio shell con
    // WlSessionLock (ver Services/Lock.qml), así que comparte tema, paleta e
    // idioma con todo lo demás. Y desaparece la pausa de 0,25 s que hacía
    // falta antes para que el popout soltara el teclado exclusivo a tiempo:
    // ahora el bloqueo es una capa del mismo proceso y Wayland le da el foco
    // en exclusiva por protocolo.
    //
    // Se pide por SEÑAL y no llamando a Services.Lock: Config es la capa de
    // abajo y no debe importar qs.Services (Services ya importa qs.Config; el
    // par cruzado es una dependencia circular entre directorios del módulo).
    // El servicio se suscribe; shell.qml lo mantiene vivo.
    signal lockRequested()

    function runPowerAction(action) {
        closeAll()
        if (action === "lock")
            g.lockRequested()
        else if (action === "suspend")
            Quickshell.execDetached(["systemctl", "suspend"])
        else if (action === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"])
        else if (action === "poweroff")
            Quickshell.execDetached(["systemctl", "poweroff"])
    }
}
