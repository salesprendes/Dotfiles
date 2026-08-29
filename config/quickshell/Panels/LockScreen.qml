import QtQuick
import Quickshell.Wayland
import qs.Config
import qs.Services

// Pantalla de bloqueo: la superficie de ext-session-lock, una por monitor.
//
// Aquí solo está el enganche con Wayland. El contenido vive en
// Panels/LockContent.qml —un Item normal, para poder probarlo sin bloquear la
// sesión— y la lógica (PAM, estado, respaldo a hyprlock) en Services/Lock.qml.
//
// Se instancia UNA vez desde shell.qml, no por monitor: WlSessionLock crea su
// propia superficie en cada pantalla a partir de este componente, y además
// cubre las que se conecten con la sesión ya bloqueada — enchufar un monitor
// externo con el portátil bloqueado no deja un escritorio a la vista.
WlSessionLock {
    id: sessionLock

    locked: Lock.locked

    WlSessionLockSurface {
        id: surface

        color: Theme.bg

        LockContent {
            anchors.fill: parent
            screen: surface.screen
            active: Lock.locked
        }
    }
}
