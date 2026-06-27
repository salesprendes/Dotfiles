pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
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

    // ── Conexión PRIORITARIA (ruta por defecto) ──────────────
    //  La prioridad real la decide la tabla de rutas del kernel: la ruta por
    //  defecto de menor 'metric' gana. Se lee /proc/net/route con FileView
    //  (QML PURO, CERO subprocesos) y la interfaz resultante se mapea a su tipo
    //  con Quickshell.Networking. Así, si hay cable pero el sistema enruta por
    //  wifi (o al revés), el icono refleja lo REAL, no solo "hay cable".
    //  Valores: "ethernet" | "wifi" | "none" | "" (sin resolver → respaldo).
    property string primaryType: ""

    // ¿Es ethernet la conexión activa/prioritaria? Mientras no se haya resuelto
    // la ruta (primaryType ""), cae al estado físico (hay cable conectado).
    readonly property bool primaryEthernet: primaryType === "ethernet"
                                          || (primaryType === "" && ethernet)

    // Recalcula releyendo /proc/net/route (con pequeño debounce: la tabla de
    // rutas tarda un instante en asentarse tras un cambio de conexión).
    function refreshPrimary() { primaryDebounce.restart() }
    onEthernetChanged:   refreshPrimary()
    onActiveWifiChanged: refreshPrimary()
    onWifiEnabledChanged: refreshPrimary()
    Component.onCompleted: refreshPrimary()

    Timer {
        id: primaryDebounce
        interval: 300
        onTriggered: routeFile.reload()
    }

    // Tabla de rutas del kernel (archivo virtual; se relee con reload()).
    FileView {
        id: routeFile
        path: "/proc/net/route"
        blockLoading: true
        printErrors: false
        watchChanges: false
        onLoaded: net.computePrimary()
    }

    // Parsea /proc/net/route → tipo de la conexión prioritaria. Columnas:
    // Iface Destination Gateway Flags RefCnt Use Metric ... La ruta por defecto
    // tiene Destination "00000000"; gana la de menor Metric (decimal).
    function computePrimary() {
        const txt = routeFile.text()
        if (!txt || txt.trim() === "") {              // ilegible → respaldo físico
            net.primaryType = ""
            return
        }
        // Un solo recorrido: la ruta por defecto de menor 'metric'.
        const best = txt.split("\n").slice(1).reduce((acc, line) => {
            const f = line.trim().split(/\s+/)
            const m = (f.length >= 7 && f[1] === "00000000") ? parseInt(f[6], 10) : NaN
            return (!isNaN(m) && m < acc.metric) ? ({ iface: f[0], metric: m }) : acc
        }, ({ iface: "", metric: Infinity }))

        net.primaryType = best.iface === "" ? "none" : net.ifaceType(best.iface)
    }

    // Tipo de una interfaz ("wifi"|"ethernet"|"none"): vía Quickshell.Networking
    // o, si no casa con ningún device, por el nombre (wl* = wifi).
    function ifaceType(iface) {
        const dev = (Networking.devices?.values ?? []).find(d => d.name === iface)
        if (dev)
            return dev.type === DeviceType.Wifi  ? "wifi"
                 : dev.type === DeviceType.Wired ? "ethernet"
                 : "none"
        return iface.indexOf("wl") === 0 ? "wifi" : "ethernet"
    }

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

    // Ajustes IP de la conexión activa (los muestra IpSettingsModal).
    // El modal resuelve por nmcli la conexión activa (wifi o ethernet),
    // lee su configuración IPv4 y la aplica en NetworkManager.
    property bool ipConfigOpen: false
    function openIpConfig()  { ipConfigOpen = true }
    function closeIpConfig() { ipConfigOpen = false }

    // Icono Nerd Font según estado.
    readonly property string icon: {
        if (primaryEthernet) return "󰈁"           // ethernet (ruta prioritaria)
        if (!wifiEnabled) return "󰤮"              // wifi off
        if (!online) return "󰤯"                   // sin conexión
        if (signal >= 75) return "󰤨"
        if (signal >= 50) return "󰤥"
        if (signal >= 25) return "󰤢"
        return "󰤟"
    }

    readonly property string label: {
        if (primaryEthernet) return "Ethernet"
        if (!wifiEnabled) return I18n.tr("WiFi off")
        if (ssid !== "") return ssid
        return I18n.tr("No connection")
    }

    function toggleWifi() { Networking.wifiEnabled = !Networking.wifiEnabled }
}
