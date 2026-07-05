pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Servicio de clima (wttr.in, sin API key). Refresca cada 30 min.
//  Detección automática de ciudad: ipinfo.io da la ciudad +
//  coordenadas (más preciso que la IP cruda de wttr) y el clima se
//  pide por esas coordenadas. `query` permite forzar una ciudad
//  manualmente (configurable desde ajustes); vacío = automático.
// ─────────────────────────────────────────────────────────────
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
        if (proc.running) {
            _pendingRefresh = true
            return
        }
        _pendingRefresh = false
        proc.running = true
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

    // Tras el resume, los datos pueden llevar horas obsoletos (el temporizador de
    // 30 min no corre mientras se duerme): re-consulta al despertar.
    Connections {
        target: Resume
        function onResumed() { if (root.enabled) root.refresh() }
    }

    // Comando automático: ciudad + coordenadas de ipinfo.io y clima
    // por coordenadas. Si ipinfo falla, recurre a wttr.in por IP.
    readonly property string autoCmd:
        'LOC=$(curl -s --max-time 6 https://ipinfo.io/loc); '
      + 'CITY=$(curl -s --max-time 6 https://ipinfo.io/city); '
      + 'if [ -n "$LOC" ]; then printf "%s|" "${CITY:-$LOC}"; '
      + 'curl -s --max-time 8 "https://wttr.in/${LOC}?format=%t|%C|%f|%h&' + unit + '"; '
      + 'else curl -s --max-time 8 "https://wttr.in/?format=%l|%t|%C|%f|%h&' + unit + '"; fi'

    // Comando con ciudad fija (cuando `query` está definido).
    readonly property string fixedCmd:
        'curl -s --max-time 8 "https://wttr.in/'
      + encodeURIComponent(query.trim()) + '?format=%l|%t|%C|%f|%h&' + unit + '"'

    Process {
        id: proc
        command: ["sh", "-c", root.query.trim() !== "" ? root.fixedCmd : root.autoCmd]
        onRunningChanged: {
            if (!running && root._pendingRefresh)
                root.refresh()
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|")
                if (parts.length >= 5 && parts[0].trim() !== ""
                        && !text.toLowerCase().includes("unknown location")) {
                    root.location  = parts[0].trim()
                    root.temp      = parts[1].trim()
                    root.condition = parts[2].trim()
                    root.feels     = parts[3].trim()
                    root.humidity  = parts[4].trim()
                    root.ready = true
                }
            }
        }
    }
}
