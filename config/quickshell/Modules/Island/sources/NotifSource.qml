import QtQuick
import qs.Config
import qs.Services

// Encamina las notificaciones recién llegadas hacia la isla.
//
// Sustituye a Panels/NotificationPopups.qml. La diferencia de fondo: aquella
// era una PILA —cabían cuatro a la vez, apiladas en una esquina— y la isla es
// UNA. Por eso el estado lleva cola: las que llegan mientras hay otra puesta
// esperan turno en vez de perderse, y un contador dice cuántas quedan.
//
// SE INSTANCIA UNA SOLA VEZ, no por monitor. Es la trampa evidente de este
// diseño: la ventana de la isla sí existe en cada pantalla, y si la fuente
// viviera dentro, cada aviso entraría en la cola tantas veces como monitores
// tengas. Vive en shell.qml, fuera del recorrido de pantallas.
QtObject {
    id: root

    readonly property bool enabled: Settings.islandEnabled

    readonly property Connections _notifs: Connections {
        target: NotifService
        // Con la isla apagada manda Panels/NotificationPopups.qml, que escucha
        // esta misma señal por su cuenta. Dos oyentes serían dos avisos.
        enabled: root.enabled
        function onPosted(n) {
            // El filtrado fino (DND, popups apagados, tope de cola) lo hace
            // IslandState.pushNotification: es una decisión de estado, no de
            // transporte, y así vale igual venga de donde venga.
            IslandState.pushNotification(n)
        }
        function onClearedAll() {
            IslandState.clearNotifications()
        }
    }

    // Abrir un panel descarta lo que hubiera en la isla: ya estás mirando otra
    // cosa y las notificaciones siguen estando en su centro. Misma regla que
    // seguían los popups.
    readonly property Connections _panels: Connections {
        target: Globals
        enabled: root.enabled
        function onOpenPanelChanged() {
            if (Globals.openPanel !== "")
                IslandState.clearNotifications()
        }
    }
}
