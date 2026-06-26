pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Servicio de red. Envuelve Quickshell.Networking y expone una
//  vista simple para barra/panel: estado wifi, ethernet, SSID
//  activo, intensidad de señal e icono Nerd Font correspondiente.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: net

    readonly property bool wifiEnabled: Networking.wifiEnabled

    // Dispositivo WiFi (el primero de tipo Wifi).
    readonly property var wifiDevice: {
        const devs = Networking.devices?.values ?? []
        for (let i = 0; i < devs.length; i++)
            if (devs[i].type === DeviceType.Wifi) return devs[i]
        return null
    }

    // ¿Hay ethernet conectado?
    readonly property bool ethernet: {
        const devs = Networking.devices?.values ?? []
        for (let i = 0; i < devs.length; i++)
            if (devs[i].type === DeviceType.Wired && devs[i].connected) return true
        return false
    }

    // Red WiFi conectada (Network) dentro del dispositivo WiFi.
    readonly property var activeWifi: {
        const d = wifiDevice
        if (!d) return null
        const nets = d.networks?.values ?? []
        for (let i = 0; i < nets.length; i++)
            if (nets[i].connected) return nets[i]
        return null
    }

    readonly property string ssid: activeWifi?.name ?? ""
    // signalStrength viene 0..1 → a 0..100.
    readonly property int signal: Math.round((activeWifi?.signalStrength ?? 0) * 100)
    readonly property bool online: ethernet || activeWifi !== null

    // Lista de redes WiFi visibles (para el panel).
    readonly property var networks: wifiDevice?.networks ?? null
    readonly property bool scanning: wifiDevice?.scannerEnabled ?? false

    // Activa/desactiva el escaneo de redes (lo usa el panel WiFi).
    function setScanning(on) {
        if (wifiDevice) wifiDevice.scannerEnabled = on
    }

    // Red pendiente de contraseña (la muestra WifiPasswordModal).
    property var promptNetwork: null
    function requestPassword(n) { promptNetwork = n }
    function clearPrompt()       { promptNetwork = null }

    // Icono Nerd Font según estado.
    readonly property string icon: {
        if (ethernet) return "󰈁"                 // ethernet
        if (!wifiEnabled) return "󰤮"              // wifi off
        if (!online) return "󰤯"                   // sin conexión
        if (signal >= 75) return "󰤨"
        if (signal >= 50) return "󰤥"
        if (signal >= 25) return "󰤢"
        return "󰤟"
    }

    readonly property string label: {
        if (ethernet) return "Ethernet"
        if (!wifiEnabled) return I18n.tr("WiFi off")
        if (ssid !== "") return ssid
        return I18n.tr("No connection")
    }

    function toggleWifi() { Networking.wifiEnabled = !Networking.wifiEnabled }
}
