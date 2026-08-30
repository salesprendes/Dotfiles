import QtQuick
import qs.Config
import qs.Services

// Encamina las notificaciones recién llegadas hacia la isla.
//
// Se instancia UNA SOLA VEZ desde shell.qml, fuera del recorrido de pantallas.
// La ventana de la isla sí existe en cada monitor, así que una fuente por
// ventana metería cada aviso en la cola tantas veces como monitores haya.
QtObject {
    id: root

    readonly property bool enabled: Settings.islandEnabled

    readonly property Connections _notifs: Connections {
        target: NotifService
        // Con la isla apagada escucha Panels/NotificationPopups.qml; dos
        // oyentes a la vez darían dos avisos por notificación.
        enabled: root.enabled

        // No encola con una ventana a pantalla completa delante: la isla ya se
        // esconde, pero el aviso encolado seguiría con su cuenta atrás y
        // aparecería al salir del vídeo. Queda en el centro de notificaciones.
        //
        // El filtrado fino (DND, popups apagados, tope de cola) lo hace
        // IslandState.pushNotification: es decisión de estado, no de transporte.
        function onPosted(n) {
            if (Globals.focusedHasFullscreen())
                return
            IslandState.pushNotification(n)
        }
        function onClearedAll() {
            IslandState.clearNotifications()
        }
    }

    // Abrir un panel descarta lo que hubiera en la isla: la atención ya está en
    // otro sitio y el aviso sigue guardado en su centro.
    readonly property Connections _panels: Connections {
        target: Globals
        enabled: root.enabled
        function onOpenPanelChanged() {
            if (Globals.openPanel !== "")
                IslandState.clearNotifications()
        }
    }

    // Caso espejo: entrar a pantalla completa con un aviso puesto. Sin esto la
    // isla se esconde con él dentro y reaparece al salir.
    readonly property bool enPantallaCompleta: Globals.focusedHasFullscreen()
    onEnPantallaCompletaChanged: {
        if (root.enabled && root.enPantallaCompleta)
            IslandState.clearNotifications()
    }
}
