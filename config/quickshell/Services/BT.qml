pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Config

// Bluetooth: envuelve Quickshell.Bluetooth y expone estado del adaptador y
// dispositivos conectados.
Singleton {
    id: bt

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property bool discovering: adapter?.discovering ?? false

    // Todos los dispositivos conocidos.
    readonly property var devices: Bluetooth.devices

    // Dispositivos actualmente conectados.
    readonly property var connected: {
        const all = Bluetooth.devices?.values ?? []
        return all.filter(d => d.connected)
    }
    readonly property int connectedCount: connected.length

    readonly property string icon: {
        if (!available || !enabled) return "󰂲"   // bt off
        if (connectedCount > 0) return "󰂱"        // conectado
        return "󰂯"                                 // on, sin conexión
    }

    readonly property string label: {
        if (!available) return I18n.tr("No Bluetooth")
        if (!enabled) return I18n.tr("Bluetooth off")
        if (connectedCount === 1) return connected[0].name
        if (connectedCount > 1) return I18n.tr("%1 devices").arg(connectedCount)
        return I18n.tr("Bluetooth on")
    }

    function toggle() {
        if (adapter) adapter.enabled = !adapter.enabled
    }

    // Recuperación tras suspensión. Quickshell.Bluetooth no expone un re-sync
    // manual, así que no podemos reconstruir su modelo desde fuera. El fallo
    // real es que el adaptador despierte apagado o con soft-block de rfkill
    // (BlueZ no siempre lo restaura). Al reactivarlo, BlueZ emite
    // PropertiesChanged y reconecta los dispositivos de confianza: señales que
    // Quickshell sí capta, así que su modelo se re-sincroniza solo. Corre en
    // cada pulso de recuperación (reintento a ~0.7/3.2/7.7 s, por si el
    // controlador tarda en volver). Idempotente: si ya está encendido no hace
    // nada; si el BT estaba apagado antes de dormir, se respeta.
    property bool _wasOn: false
    Connections {
        target: Resume
        function onAboutToSleep() { bt._wasOn = bt.enabled }
        function onResumed() {
            if (bt._wasOn)
                Quickshell.execDetached(["sh", "-c",
                    "rfkill unblock bluetooth 2>/dev/null; bluetoothctl power on 2>/dev/null"])
        }
    }
}
