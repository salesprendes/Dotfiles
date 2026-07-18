pragma Singleton
// Ajustes del greeter (lo que se suele tocar).
import QtQuick
import Quickshell

Singleton {
    id: root

    // Fondo. En despliegue, ruta legible por el usuario 'greeter'
    // (el instalador copia el fondo de pantalla a /etc/greetd/wall.png).
    readonly property string wallpaper: "/etc/greetd/wall.png"

    // Avatares por usuario, en el estándar de AccountsService (compatible con
    // GDM y SDDM): /var/lib/AccountsService/icons/<usuario>, legible por el
    // usuario 'greeter'. Se publica desde Ajustes → Shell → Avatar → "Aplicar
    // al inicio de sesión". Si no existe, cae a la inicial.
    readonly property string avatarDir: "/var/lib/AccountsService/icons"
    function avatarFor(user) {
        return (user && user !== "") ? avatarDir + "/" + user : ""
    }

    // Sesión por defecto: el lanzador OFICIAL de Hyprland (watchdog), no
    // "Hyprland" pelado. Así heredas tu entorno y no salta el aviso
    // "iniciaste sin start-hyprland". Cambia esto si usas otro escritorio.
    readonly property string defaultSession:     "start-hyprland"
    readonly property string defaultSessionName: "Hyprland"

    // Mejoras opcionales del login.
    readonly property bool showSessionPicker: true   // lee /usr/share/wayland-sessions
    readonly property bool rememberLastUser:  true   // recuerda el último login
    readonly property bool allowReveal:       true   // botón "ojo" para ver la clave

    // Fichero de estado (debe ser escribible por el usuario 'greeter';
    // el instalador crea /var/lib/greeter con los permisos correctos).
    readonly property string statePath: "/var/lib/greeter/greetd-last.json"
}
