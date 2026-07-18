pragma Singleton

import QtQuick
import Quickshell

// Estado global compartido. Un único panel abierto a la vez.
Singleton {
    id: g

    // "", "control", "notif", "sysmon", "launcher", "clipboard", "dashboard", "capture"
    property string openPanel: ""

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

    function toggle(p)            { openPanel = (openPanel === p) ? "" : p }
    function toggleControlCenter() { toggle("control") }
    function toggleNotifCenter()   { toggle("notif") }
    function toggleSysMon()        { toggle("sysmon") }
    function toggleLauncher()      { toggle("launcher") }
    function toggleClipboard()     { toggle("clipboard") }
    function toggleDashboard()     { toggle("dashboard") }
    function toggleScreenCapture()  { toggle("capture") }
    // Si está cerrada, ábrela. Si ya está abierta, deja que la propia ventana
    // decida: cerrarla (si está en este workspace) o traerla al actual.
    signal settingsResummon()
    function toggleSettings() {
        if (settingsOpen) settingsResummon()
        else settingsOpen = true
    }
    // Cierra solo los popups (la ventana de Ajustes es independiente).
    function closeAll()            { openPanel = "" }

    // Acciones de sesión/energía compartidas (lanzador y centro de control).
    // La pausa del bloqueo deja que el popout se cierre y SUELTE el teclado
    // exclusivo antes de que hyprlock tome el foco (si no, la pantalla de
    // contraseña aparece con el panel aún encima → se "bugea").
    function runPowerAction(action) {
        closeAll()
        if (action === "lock")
            Quickshell.execDetached(["sh", "-c", "sleep 0.25; command -v hyprlock >/dev/null && hyprlock || loginctl lock-session"])
        else if (action === "suspend")
            Quickshell.execDetached(["systemctl", "suspend"])
        else if (action === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"])
        else if (action === "poweroff")
            Quickshell.execDetached(["systemctl", "poweroff"])
    }
}
