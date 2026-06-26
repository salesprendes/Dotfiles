pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Servicio Bluetooth. Envuelve Quickshell.Bluetooth y expone
//  estado del adaptador y dispositivos conectados.
// ─────────────────────────────────────────────────────────────
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
}
