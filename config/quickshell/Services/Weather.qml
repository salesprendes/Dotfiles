pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Clima (wttr.in, sin API key). Refresca cada 30 min. En modo automático,
// ipinfo.io da ciudad + coordenadas (más preciso que la IP cruda de wttr) y el
// clima se pide por esas coordenadas. query fuerza una ciudad manual (desde
// ajustes); vacío = automático.
Singleton {
    id: root

    // Configurable desde Settings.
    property string query: Settings.weatherLocation   // vacío = autodetección
    property bool   enabled: Settings.weatherEnabled
    readonly property string unit: Settings.weatherMetric ? "m" : "u"   // wttr: m=°C, u=°F

    // Re-consulta al cambiar ciudad o unidad, agrupando cambios seguidos.
    onQueryChanged: if (enabled) refreshLater.restart()
    onUnitChanged:  if (enabled) refreshLater.restart()
    onEnabledChanged: if (enabled) refreshLater.restart()

    property string location: ""
    property string temp: ""
    property string condition: ""
    property string feels: ""
    property string humidity: ""
    property bool   ready: false
    property bool _pendingRefresh: false

    // Geolocalización cacheada (ipinfo.io). Se pide UNA vez y el tick de
    // 30 min reutiliza las coordenadas (solo re-consulta wttr.in). Se
    // invalida al reanudar de suspensión o al reconectar la red.
    property string geoCity: ""
    property string geoLoc: ""
    property bool _retried: false

    property int refreshInterval: Settings.weatherRefreshMin * 60 * 1000

    // Glifo (Nerd Font) según el texto de la condición.
    readonly property string icon: {
        const c = condition.toLowerCase()
        if (c.includes("thunder") || c.includes("storm")) return "󰖓"
        if (c.includes("snow") || c.includes("sleet") || c.includes("ice") || c.includes("blizzard")) return "󰖘"
        if (c.includes("rain") || c.includes("drizzle") || c.includes("shower")) return "󰖗"
        if (c.includes("fog") || c.includes("mist") || c.includes("haze")) return "󰖑"
        if (c.includes("overcast")) return "󰖐"
        if (c.includes("cloud") || c.includes("partly")) return "󰖕"
        if (c.includes("clear") || c.includes("sunny")) return "󰖙"
        return "󰖕"
    }

    function refresh() {
        if (!enabled)
            return
        if (proc.running || geoProc.running) {
            _pendingRefresh = true
            return
        }
        _pendingRefresh = false
        // Modo automático sin geolocalización cacheada: primero ipinfo.io
        // (una sola petición /json), después wttr.in con las coordenadas.
        if (query.trim() === "" && geoLoc === "")
            geoProc.running = true
        else
            proc.running = true
    }

    // Un único reintento corto tras un fallo: en un arranque con red lenta
    // no hay que esperar 30 min al siguiente tick.
    function _fetchFailed() {
        if (_retried)
            return
        _retried = true
        retryTimer.restart()
    }

    Component.onCompleted: refresh()
    Timer {
        interval: root.refreshInterval; running: root.enabled; repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshLater
        interval: 400
        onTriggered: root.refresh()
    }

    Timer {
        id: retryTimer
        interval: 60 * 1000
        onTriggered: root.refresh()
    }

    // Tras el resume, los datos pueden llevar horas obsoletos (el temporizador de
    // 30 min no corre mientras se duerme) y la ubicación puede haber cambiado:
    // se invalida la geolocalización cacheada y se re-consulta al despertar.
    Connections {
        target: Resume
        function onResumed() {
            root.geoLoc = ""
            root.geoCity = ""
            if (root.enabled)
                root.refresh()
        }
    }

    // Al reconectar la red: si aún no hay datos o falta la geolocalización
    // (arranque con red lenta), re-consulta en cuanto haya conexión.
    Connections {
        target: Net
        function onOnlineChanged() {
            if (Net.online && root.enabled && (!root.ready || root.geoLoc === ""))
                refreshLater.restart()
        }
    }

    // Paso 1 (solo modo automático, sin caché): una petición a ipinfo.io/json
    // y el JSON se parsea aquí.
    Process {
        id: geoProc
        command: ["sh", "-c", "curl -sf --max-time 6 https://ipinfo.io/json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const info = JSON.parse(this.text)
                    if (info && typeof info.loc === "string" && info.loc !== "") {
                        root.geoLoc = info.loc
                        root.geoCity = (info.city && info.city !== "") ? info.city : info.loc
                    }
                } catch (e) { /* sin red o respuesta no-JSON: proc usa el fallback por IP */ }
                proc.running = true
            }
        }
    }

    // Paso 2: clima por coordenadas cacheadas; la ciudad ya la conocemos,
    // así que no se pide %l. Fallback (ipinfo caído): wttr.in por IP.
    readonly property string cachedCmd:
        'curl -sf --max-time 8 "https://wttr.in/'
      + encodeURIComponent(geoLoc) + '?format=%t|%C|%f|%h&' + unit + '"'

    readonly property string autoFallbackCmd:
        'curl -sf --max-time 8 "https://wttr.in/?format=%l|%t|%C|%f|%h&' + unit + '"'

    // Comando con ciudad fija (cuando query está definido).
    readonly property string fixedCmd:
        'curl -s --max-time 8 "https://wttr.in/'
      + encodeURIComponent(query.trim()) + '?format=%l|%t|%C|%f|%h&' + unit + '"'

    Process {
        id: proc
        command: ["sh", "-c", root.query.trim() !== "" ? root.fixedCmd
                            : root.geoLoc !== ""       ? root.cachedCmd
                                                       : root.autoFallbackCmd]
        onRunningChanged: {
            if (!running && root._pendingRefresh)
                root.refresh()
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t === "" || t.toLowerCase().includes("unknown location")) {
                    root._fetchFailed()
                    return
                }
                const parts = t.split("|")
                let loc = "", data = null
                if (parts.length >= 5 && parts[0].trim() !== "") {
                    loc = parts[0].trim()
                    data = parts.slice(1)
                } else if (parts.length === 4 && root.geoCity !== "") {
                    loc = root.geoCity
                    data = parts
                }
                if (data) {
                    root.location  = loc
                    root.temp      = data[0].trim()
                    root.condition = data[1].trim()
                    root.feels     = data[2].trim()
                    root.humidity  = data[3].trim()
                    root.ready = true
                    root._retried = false
                } else {
                    root._fetchFailed()
                }
            }
        }
    }
}
