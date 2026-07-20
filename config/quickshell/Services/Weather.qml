pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Clima con Open-Meteo (JSON gratuito, sin API key): estado actual +
// pronóstico diario. En modo automático, ipinfo.io da ciudad y coordenadas;
// con ciudad fija (query), el geocodificador de Open-Meteo resuelve las
// coordenadas una vez y quedan cacheadas hasta cambiar la ciudad.
Singleton {
    id: root

    // Configurable desde Settings.
    property string query: Settings.weatherLocation   // vacío = autodetección
    property bool   enabled: Settings.weatherEnabled
    readonly property string unit: Settings.weatherMetric ? "celsius" : "fahrenheit"

    // Re-consulta al cambiar ciudad o unidad, agrupando cambios seguidos. La
    // ciudad fija invalida además sus coordenadas cacheadas.
    onQueryChanged: { fixedLoc = ""; fixedName = ""; if (enabled) refreshLater.restart() }
    onUnitChanged:  if (enabled) refreshLater.restart()
    // Cambiar los días de pronóstico o activar el viento cambia la petición.
    property int forecastDays: Settings.weatherForecastDays
    property bool wantWind: Settings.weatherShowWind
    property bool wantRain: Settings.weatherShowRain
    property bool wantSun: Settings.weatherShowSun
    property bool showInBar: Settings.weatherShowInBar
    onForecastDaysChanged: if (enabled) refreshLater.restart()
    onWantWindChanged: if (enabled) refreshLater.restart()
    onWantRainChanged: if (enabled) refreshLater.restart()
    onWantSunChanged: if (enabled) refreshLater.restart()
    // Activar la píldora de la barra pide datos al momento si toca.
    onShowInBarChanged: if (enabled && showInBar) refreshIfStale(refreshInterval)
    onEnabledChanged: if (enabled) refreshLater.restart()

    property string location: ""
    property string temp: ""
    property string condition: ""
    property string feels: ""
    property string humidity: ""
    property string windSpeed: ""
    property string sunrise: ""
    property string sunset: ""
    // Pronóstico diario: [{ label, glyph, max, min }] (hasta 5 días).
    property var    forecast: []
    property bool   ready: false
    property bool _pendingRefresh: false
    // Marca de tiempo del último dato bueno, para no repetir consultas
    // recientes al reabrir el panel.
    property real _lastFetch: 0

    // Geolocalización automática cacheada (ipinfo.io, "lat,lon"). Se pide UNA
    // vez y el tick de 30 min reutiliza las coordenadas. Se invalida al
    // reanudar de suspensión o al reconectar la red.
    property string geoCity: ""
    property string geoLoc: ""
    // Coordenadas de la ciudad fija (geocodificador), cacheadas por query.
    property string fixedLoc: ""
    property string fixedName: ""
    property bool _retried: false

    property int refreshInterval: Settings.weatherRefreshMin * 60 * 1000

    // Grupos de códigos WMO → glifo y texto: los códigos concretos se
    // condensan en ocho estados legibles.
    readonly property var _bucketGlyphs: ["󰖙", "󰖕", "󰖐", "󰖑", "󰖗", "󰖗", "󰖘", "󰖓"]
    readonly property var _bucketNames: ["Clear sky", "Partly cloudy", "Overcast", "Fog",
                                         "Drizzle", "Rain", "Snow", "Storm"]
    function _bucket(code) {
        if (code === 0) return 0
        if (code === 1 || code === 2) return 1
        if (code === 3) return 2
        if (code === 45 || code === 48) return 3
        if (code >= 51 && code <= 57) return 4
        if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return 5
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return 6
        if (code >= 95) return 7
        return 1
    }

    property int _currentCode: 1
    readonly property string icon: _bucketGlyphs[_bucket(_currentCode)]

    // Temperatura con signo y unidad, como espera la interfaz ("+21°C").
    function _fmtTemp(v) {
        const r = Math.round(v)
        return (r > 0 ? "+" : "") + r + "°" + (Settings.weatherMetric ? "C" : "F")
    }

    // Consulta solo si el dato es más viejo que maxAgeMs: reabrir el panel
    // con datos frescos no vuelve a llamar a la API.
    function refreshIfStale(maxAgeMs) {
        if (Date.now() - _lastFetch > maxAgeMs)
            refresh()
    }

    function refresh() {
        if (!enabled)
            return
        if (forecastProc.running || geoProc.running || geocodeProc.running) {
            _pendingRefresh = true
            return
        }
        _pendingRefresh = false
        if (query.trim() !== "") {
            if (fixedLoc !== "") forecastProc.running = true
            else geocodeProc.running = true
        } else {
            if (geoLoc !== "") forecastProc.running = true
            else geoProc.running = true
        }
    }

    // Un único reintento corto tras un fallo: en un arranque con red lenta
    // no hay que esperar 30 min al siguiente tick.
    function _fetchFailed() {
        if (_retried)
            return
        _retried = true
        retryTimer.restart()
    }

    // Restaura la última respuesta persistida (si coincide unidad y ciudad):
    // el panel pinta al instante tras un arranque o recarga, y solo se
    // consulta la API si el dato caducó. La condición y los glifos se
    // recalculan del código WMO guardado (por si cambió el idioma).
    function _restoreCache() {
        const c = Settings.weatherCache
        if (!c || c.t === undefined || c.unit !== unit || c.query !== query.trim()
            || c.days !== forecastDays || c.wind !== wantWind
            || c.rain !== wantRain || c.sun !== wantSun) {
            if (showInBar && enabled)
                refreshLater.restart()
            return
        }
        geoLoc = c.geoLoc || ""
        geoCity = c.geoCity || ""
        fixedLoc = c.fixedLoc || ""
        fixedName = c.fixedName || ""
        _currentCode = c.code ?? 1
        temp = c.temp || ""
        feels = c.feels || ""
        humidity = c.humidity || ""
        windSpeed = c.windSpeed || ""
        sunrise = c.sunrise || ""
        sunset = c.sunset || ""
        condition = I18n.tr(_bucketNames[_bucket(_currentCode)])
        location = c.location || ""
        forecast = c.forecast || []
        _lastFetch = c.t
        ready = temp !== ""
        if (showInBar)
            refreshIfStale(refreshInterval)
    }
    Component.onCompleted: if (Settings._loaded) _restoreCache()
    Connections {
        target: Settings
        function on_LoadedChanged() { root._restoreCache() }
    }

    // Sin consulta al arrancar ni sondeo de fondo: la primera apertura del
    // panel dispara refreshIfStale() y el tick solo corre mientras se ve.
    Timer {
        interval: root.refreshInterval
        running: root.enabled && (Globals.dashboardOpen || root.showInBar)
        repeat: true
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

    // Tras el resume, los datos pueden llevar horas obsoletos y la ubicación
    // puede haber cambiado: se invalida la geolocalización y se re-consulta.
    Connections {
        target: Resume
        function onResumed() {
            root.geoLoc = ""
            root.geoCity = ""
            root._lastFetch = 0
            if (root.enabled && Globals.dashboardOpen)
                root.refresh()
        }
    }

    // Al reconectar la red: si aún no hay datos o falta la geolocalización
    // (arranque con red lenta), re-consulta en cuanto haya conexión.
    Connections {
        target: Net
        function onOnlineChanged() {
            if (Net.online && root.enabled && (!root.ready || (root.query.trim() === "" && root.geoLoc === "")))
                refreshLater.restart()
        }
    }

    // Modo automático sin caché: una petición a ipinfo.io/json ("loc" ya viene
    // como "lat,lon", directamente utilizable por Open-Meteo).
    Process {
        id: geoProc
        command: ["curl", "-sf", "--compressed", "--max-time", "6", "https://ipinfo.io/json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const info = JSON.parse(this.text)
                    if (info && typeof info.loc === "string" && info.loc !== "") {
                        root.geoLoc = info.loc
                        root.geoCity = (info.city && info.city !== "") ? info.city : info.loc
                    }
                } catch (e) { /* sin red: el reintento corto volverá a probar */ }
                if (root.geoLoc !== "")
                    forecastProc.running = true
                else
                    root._fetchFailed()
            }
        }
    }

    // Ciudad fija → coordenadas, con el geocodificador gratuito de Open-Meteo.
    Process {
        id: geocodeProc
        command: ["curl", "-sf", "--compressed", "--max-time", "8",
            "https://geocoding-api.open-meteo.com/v1/search?count=1&format=json&language="
            + I18n.language + "&name=" + encodeURIComponent(root.query.trim())]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(this.text)
                    const hit = res?.results?.[0]
                    if (hit && hit.latitude !== undefined) {
                        root.fixedLoc = hit.latitude + "," + hit.longitude
                        root.fixedName = hit.name || root.query.trim()
                    }
                } catch (e) { /* respuesta no válida */ }
                if (root.fixedLoc !== "")
                    forecastProc.running = true
                else
                    root._fetchFailed()
            }
        }
    }

    // Estado actual + 5 días en una sola petición.
    readonly property string _coords: query.trim() !== "" ? fixedLoc : geoLoc
    readonly property string _forecastUrl: {
        const ll = _coords.split(",")
        return "https://api.open-meteo.com/v1/forecast?latitude=" + (ll[0] || "0")
             + "&longitude=" + (ll[1] || "0")
             + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code"
             + (wantWind ? ",wind_speed_10m" : "")
             + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
             + (wantRain ? ",precipitation_probability_max" : "")
             + (wantSun ? ",sunrise,sunset" : "")
             + "&forecast_days=" + forecastDays + "&timezone=auto&temperature_unit=" + unit
             + (Settings.weatherMetric ? "" : "&wind_speed_unit=mph")
    }

    Process {
        id: forecastProc
        command: ["curl", "-sf", "--compressed", "--max-time", "8", root._forecastUrl]
        onRunningChanged: {
            if (!running && root._pendingRefresh)
                root.refresh()
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(this.text)
                    const cur = r.current
                    if (!cur || cur.temperature_2m === undefined) {
                        root._fetchFailed()
                        return
                    }
                    root._currentCode = cur.weather_code ?? 1
                    root.temp      = root._fmtTemp(cur.temperature_2m)
                    root.feels     = root._fmtTemp(cur.apparent_temperature)
                    root.humidity  = Math.round(cur.relative_humidity_2m) + "%"
                    root.windSpeed = cur.wind_speed_10m !== undefined
                        ? Math.round(cur.wind_speed_10m) + (Settings.weatherMetric ? " km/h" : " mph") : ""
                    root.condition = I18n.tr(root._bucketNames[root._bucket(root._currentCode)])
                    root.location  = root.query.trim() !== "" ? root.fixedName : root.geoCity

                    const days = []
                    const d = r.daily
                    root.sunrise = d?.sunrise?.[0] !== undefined ? d.sunrise[0].split("T")[1] : ""
                    root.sunset  = d?.sunset?.[0]  !== undefined ? d.sunset[0].split("T")[1]  : ""
                    const n = Math.min(forecastDays, d?.time?.length ?? 0)
                    for (let i = 0; i < n; i++) {
                        const parts = d.time[i].split("-")
                        const date = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]))
                        days.push({
                            label: date.toLocaleDateString(I18n.locale(), "ddd"),
                            glyph: root._bucketGlyphs[root._bucket(d.weather_code[i])],
                            max: Math.round(d.temperature_2m_max[i]),
                            min: Math.round(d.temperature_2m_min[i]),
                            rain: d.precipitation_probability_max !== undefined
                                  ? Math.round(d.precipitation_probability_max[i]) : -1
                        })
                    }
                    root.forecast = days
                    root.ready = true
                    root._retried = false
                    root._lastFetch = Date.now()
                    Settings.weatherCache = {
                        t: root._lastFetch, unit: root.unit, query: root.query.trim(),
                        days: root.forecastDays, wind: root.wantWind, windSpeed: root.windSpeed,
                        rain: root.wantRain, sun: root.wantSun,
                        sunrise: root.sunrise, sunset: root.sunset,
                        geoLoc: root.geoLoc, geoCity: root.geoCity,
                        fixedLoc: root.fixedLoc, fixedName: root.fixedName,
                        code: root._currentCode, temp: root.temp, feels: root.feels,
                        humidity: root.humidity, location: root.location, forecast: days
                    }
                } catch (e) {
                    root._fetchFailed()
                }
            }
        }
    }
}
