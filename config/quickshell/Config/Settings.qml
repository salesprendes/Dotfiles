pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ─────────────────────────────────────────────────────────────
//  Almacén de ajustes persistente (fuente de verdad).
//  Se guarda en ~/.config/quickshell/settings.json y los demás
//  módulos (Theme, Weather, Wallpaper, reloj…) LEEN de aquí.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: s

    readonly property string home: Quickshell.env("HOME") ?? ""

    // ── Apariencia ───────────────────────────────────────────
    property string themeName: "solitude"
    property string accentName: "theme"
    property color  accentColor: resolvedAccent
    property bool   darkMode: true      // false = variante clara de Solitude
    property bool   hyprlandAvailable: false
    property real   uiScale: 1.0
    property real   animScale: 1.0      // compatibilidad con settings.json antiguo
    property int    animationSpeed: 2   // 0 none | 1 short | 2 medium | 3 long | 4 custom
    property int    customAnimationDuration: 500
    property real   barOpacity: 0.78    // opacidad del fondo de la barra
    property real   popupOpacity: 0.85
    property real   widgetOpacity: 0.55
    property real   cornerScale: 1.0    // multiplicador del redondeo
    property real   barScale: 1.0       // multiplicador de la altura de barra
    property string fontFamily: "JetBrainsMono Nerd Font"
    property string monoFontFamily: "JetBrainsMono Nerd Font"
    property real   fontScale: 1.0
    property string panelAnimationStyle: "material" // material | fluent | dynamic
    property string panelMotionEffect: "standard" // standard | directional | depth
    property string language: "es"

    readonly property var themePresets: ({
        "solitude": {
            "label": "Solitude",
            "bg": "#101315", "bgAlt": "#161a1d", "surface": "#1e2427", "surfaceHi": "#2a3033", "overlay": "#4b4e55",
            "fg": "#cacccc", "fgDim": "#a5aeb4", "fgMuted": "#707070",
            "accent": "#798186", "accent2": "#cacccc", "cyan": "#a5aeb4", "green": "#9fa5a9", "yellow": "#c9c2b4",
            "orange": "#cbc2be", "red": "#de6145", "magenta": "#aeaeae",
            "lightBg": "#d8dbde", "lightBgAlt": "#ccd0d3", "lightSurface": "#bdc3c7", "lightSurfaceHi": "#aeb5ba",
            "lightOverlay": "#828a8f", "lightFg": "#101315", "lightFgDim": "#2b3338", "lightFgMuted": "#4c5358",
            "lightAccent": "#455055", "lightAccent2": "#586065",
            "lightCyan": "#4f636a", "lightGreen": "#56655b", "lightYellow": "#877a52", "lightOrange": "#946a52", "lightRed": "#bb4628", "lightMagenta": "#6c646a",
            "hyprInactive": "#1e1e1e", "hyprShadow": "#1a1a1a"
        },
        "tokyo": {
            "label": "Tokyo Night",
            "bg": "#1a1b26", "bgAlt": "#24283b", "surface": "#292e42", "surfaceHi": "#343b58", "overlay": "#414868",
            "fg": "#c0caf5", "fgDim": "#a9b1d6", "fgMuted": "#565f89",
            "accent": "#7aa2f7", "accent2": "#bb9af7", "cyan": "#7dcfff", "green": "#9ece6a", "yellow": "#e0af68",
            "orange": "#ff9e64", "red": "#f7768e", "magenta": "#bb9af7",
            "lightBg": "#d3d5dc", "lightBgAlt": "#c7c9d1", "lightSurface": "#bbbfd0", "lightSurfaceHi": "#aab0c8",
            "lightOverlay": "#8b91b3", "lightFg": "#3760bf", "lightFgDim": "#6172b0", "lightFgMuted": "#767ea8",
            "lightAccent": "#2e7de9", "lightAccent2": "#9854f1",
            "lightCyan": "#007197", "lightGreen": "#587539", "lightYellow": "#8c6c3e", "lightOrange": "#b15c00", "lightRed": "#f52a65", "lightMagenta": "#9854f1",
            "hyprInactive": "#565f89", "hyprShadow": "#16161e"
        },
        "kanagawa": {
            "label": "Kanagawa",
            "bg": "#1f1f28", "bgAlt": "#2a2a37", "surface": "#363646", "surfaceHi": "#54546d", "overlay": "#727169",
            "fg": "#dcd7ba", "fgDim": "#c8c093", "fgMuted": "#938aa9",
            "accent": "#7e9cd8", "accent2": "#dcd7ba", "cyan": "#7aa89f", "green": "#98bb6c", "yellow": "#e6c384",
            "orange": "#ffa066", "red": "#e46876", "magenta": "#957fb8",
            "lightBg": "#dcd6ad", "lightBgAlt": "#d0c79f", "lightSurface": "#c2b78c", "lightSurfaceHi": "#b3a878",
            "lightOverlay": "#79786f", "lightFg": "#545464", "lightFgDim": "#5e5e69", "lightFgMuted": "#76756c",
            "lightAccent": "#4d699b", "lightAccent2": "#b35b79",
            "lightCyan": "#597b75", "lightGreen": "#6f894e", "lightYellow": "#836f4e", "lightOrange": "#cc6d00", "lightRed": "#c84053", "lightMagenta": "#624c83",
            "hyprInactive": "#54546d", "hyprShadow": "#16161d"
        },
        "catppuccin": {
            "label": "Catppuccin",
            "bg": "#181824", "bgAlt": "#1e1e2e", "surface": "#313244", "surfaceHi": "#45475a", "overlay": "#6c7086",
            "fg": "#cdd6f4", "fgDim": "#bac2de", "fgMuted": "#9399b2",
            "accent": "#89b4fa", "accent2": "#cba6f7", "cyan": "#89dceb", "green": "#a6e3a1", "yellow": "#f9e2af",
            "orange": "#fab387", "red": "#f38ba8", "magenta": "#f5c2e7",
            "lightBg": "#d7dbe5", "lightBgAlt": "#cbd0db", "lightSurface": "#b9bfcc", "lightSurfaceHi": "#a8aebf",
            "lightOverlay": "#7c8095", "lightFg": "#4c4f69", "lightFgDim": "#50536c", "lightFgMuted": "#6c6f86",
            "lightAccent": "#1e66f5", "lightAccent2": "#8839ef",
            "lightCyan": "#179299", "lightGreen": "#40a02b", "lightYellow": "#df8e1d", "lightOrange": "#fe640b", "lightRed": "#d20f39", "lightMagenta": "#ea76cb",
            "hyprInactive": "#45475a", "hyprShadow": "#11111b"
        },
        "last-horizon": {
            "label": "Last Horizon",
            "bg": "#0c0b0c", "bgAlt": "#181416", "surface": "#241e21", "surfaceHi": "#332a2e", "overlay": "#584e51",
            "fg": "#fafcfb", "fgDim": "#e2dddc", "fgMuted": "#8a8588",
            "accent": "#8a8588", "accent2": "#e2dddc", "cyan": "#9aa7aa", "green": "#a5b09b", "yellow": "#d8c8a8",
            "orange": "#c99a75", "red": "#d66f5d", "magenta": "#bca8b8",
            "lightBg": "#dbd4d2", "lightBgAlt": "#cfc6c3", "lightSurface": "#c1b6b3", "lightSurfaceHi": "#b3a8a5",
            "lightOverlay": "#787276", "lightFg": "#241e21", "lightFgDim": "#4c4347", "lightFgMuted": "#645a5d",
            "lightAccent": "#595255", "lightAccent2": "#6b6467",
            "lightCyan": "#4f6669", "lightGreen": "#5f6b54", "lightYellow": "#8a7344", "lightOrange": "#a05f3a", "lightRed": "#b8462f", "lightMagenta": "#7a6470",
            "hyprInactive": "#584e51", "hyprShadow": "#161214"
        }
    })

    readonly property var themeOptions: [
        { text: "Solitude", value: "solitude" },
        { text: "Tokyo Night", value: "tokyo" },
        { text: "Kanagawa", value: "kanagawa" },
        { text: "Catppuccin", value: "catppuccin" },
        { text: "Last Horizon", value: "last-horizon" }
    ]
    // Acento "theme": en modo claro usa la variante lightAccent (más oscura,
    // para que contraste sobre fondo claro); en oscuro, el accent normal.
    readonly property color themeAccent: darkMode
        ? currentPalette.accent
        : (currentPalette.lightAccent || currentPalette.accent)

    readonly property var accentPresets: [
        { name: "theme", color: themeAccent },
        { name: "blue", color: "#7aa2f7" },
        { name: "purple", color: "#bb9af7" },
        { name: "green", color: "#9ece6a" },
        { name: "amber", color: "#e0af68" },
        { name: "red", color: "#de6145" }
    ]
    readonly property var accentSwatches: [
        { name: "theme", color: themeAccent, label: "Theme" },
        { name: "blue", color: "#7aa2f7", label: "Blue" },
        { name: "purple", color: "#bb9af7", label: "Purple" },
        { name: "green", color: "#9ece6a", label: "Green" },
        { name: "amber", color: "#e0af68", label: "Amber" },
        { name: "red", color: "#de6145", label: "Red" }
    ]
    readonly property var currentPalette: themePresets[themeName] || themePresets.solitude
    readonly property color resolvedAccent: accentFor(accentName)

    readonly property var animationDurations: [
        { "fast": 0, "normal": 0 },
        { "fast": 75, "normal": 150 },
        { "fast": 150, "normal": 300 },
        { "fast": 225, "normal": 450 }
    ]
    readonly property var popoutAnimationDurations: [0, 250, 500, 750]
    readonly property int normalizedAnimationSpeed: Math.max(0, Math.min(4, animationSpeed))
    readonly property var currentAnimationDurations: normalizedAnimationSpeed === 4
        ? ({ "fast": customAnimationDuration, "normal": customAnimationDuration })
        : animationDurations[normalizedAnimationSpeed]
    readonly property int animFastMs: currentAnimationDurations.fast
    readonly property int animNormalMs: currentAnimationDurations.normal
    readonly property int popoutAnimationMs: normalizedAnimationSpeed === 4
        ? customAnimationDuration
        : popoutAnimationDurations[normalizedAnimationSpeed]

    // ── Barra (visibilidad de widgets) ───────────────────────
    property bool   showTray: true
    property bool   showSysmon: true
    property bool   showBattery: true
    property bool   showClipboard: true
    property bool   showNotifications: true
    property bool   showPowerProfile: true
    property bool   showCaffeine: false

    // ── Reloj ────────────────────────────────────────────────
    property bool   clock24h: true
    property bool   clockShowSeconds: false
    property bool   clockShowDate: true

    // ── Clima ────────────────────────────────────────────────
    property bool   weatherEnabled: true
    property string weatherLocation: ""   // vacío = automático
    property bool   weatherMetric: true   // true = °C, false = °F
    property int    weatherRefreshMin: 30

    // ── Notificaciones ───────────────────────────────────────
    property bool   notifPopupsEnabled: true
    property int    notifTimeout: 5            // segundos
    property int    notifMaxVisible: 4
    property string notifPosition: "tr"        // tr | tl | br | bl

    // ── Fondos ───────────────────────────────────────────────
    // Transición del fondo (la dibuja Quickshell, no swww):
    // fade | zoom | slide | push | wipe.
    property string wallpaperTransition: "fade"
    property real   wallpaperTransitionDuration: 1.0
    property var    wallpaperDirs: [home + "/Pictures/Wallpapers",
                                    home + "/.config/wallpapers"]

    // ── Persistencia ─────────────────────────────────────────
    property bool _loaded: false

    readonly property var _keys: ["themeName", "accentName", "accentColor", "darkMode",
        "uiScale", "animScale", "animationSpeed", "customAnimationDuration", "barOpacity",
        "popupOpacity", "widgetOpacity",
        "cornerScale", "barScale", "fontFamily", "monoFontFamily", "fontScale",
        "panelAnimationStyle", "panelMotionEffect", "language",
        "showTray", "showSysmon", "showBattery", "showClipboard", "showNotifications", "showPowerProfile", "showCaffeine",
        "clock24h", "clockShowSeconds", "clockShowDate",
        "weatherEnabled", "weatherLocation", "weatherMetric", "weatherRefreshMin",
        "notifPopupsEnabled", "notifTimeout", "notifMaxVisible", "notifPosition",
        "wallpaperTransition", "wallpaperTransitionDuration", "wallpaperDirs"]

    // ── Saneamiento de valores cargados ─────────────────────
    //  Rangos numéricos (se recortan a [min,max]) y conjuntos de valores
    //  válidos (enums). Lo que no encaje se IGNORA y se conserva el default.
    readonly property var _numBounds: ({
        "uiScale": [0.5, 2.0], "animScale": [0.0, 3.0], "animationSpeed": [0, 4],
        "customAnimationDuration": [50, 3000], "barOpacity": [0.0, 1.0],
        "popupOpacity": [0.0, 1.0], "widgetOpacity": [0.0, 1.0], "cornerScale": [0.0, 2.0],
        "barScale": [0.5, 2.0], "fontScale": [0.5, 2.0], "weatherRefreshMin": [1, 1440],
        "notifTimeout": [1, 120], "notifMaxVisible": [1, 20],
        "wallpaperTransitionDuration": [0.1, 5.0]
    })
    readonly property var _enums: ({
        "panelAnimationStyle": ["material", "fluent", "dynamic"],
        "panelMotionEffect": ["standard", "directional", "depth"],
        "language": ["en", "es", "ca"],
        "notifPosition": ["tl", "tr", "bl", "br"],
        "wallpaperTransition": ["fade", "zoom", "slide", "push", "wipe"]
    })
    // Claves que deben ser enteros (se redondean tras recortar).
    readonly property var _intKeys: ["animationSpeed", "customAnimationDuration",
        "weatherRefreshMin", "notifTimeout", "notifMaxVisible"]

    // Devuelve un valor válido para 'k', o 'undefined' si hay que descartarlo
    // (→ se conserva el valor por defecto). Infiere el tipo esperado del default.
    function sanitize(k, val) {
        // Enums: solo valores de la lista.
        if (_enums[k] !== undefined)
            return _enums[k].indexOf(val) !== -1 ? val : undefined
        // accentColor: cadena hex de color.
        if (k === "accentColor")
            return (typeof val === "string" && /^#?[0-9a-fA-F]{3,8}$/.test(val)) ? val : undefined
        // wallpaperDirs: array de cadenas.
        if (k === "wallpaperDirs") {
            if (!Array.isArray(val)) return undefined
            return val.every(x => typeof x === "string") ? val : undefined
        }
        // Numéricos con rango: número finito recortado (y entero si procede).
        if (_numBounds[k] !== undefined) {
            if (typeof val !== "number" || !isFinite(val)) return undefined
            let v = Math.max(_numBounds[k][0], Math.min(_numBounds[k][1], val))
            if (_intKeys.indexOf(k) !== -1) v = Math.round(v)
            return v
        }
        // Resto: comprobación de tipo contra el default.
        const def = s[k]
        if (typeof def === "boolean") return (typeof val === "boolean") ? val : undefined
        if (typeof def === "number")  return (typeof val === "number" && isFinite(val)) ? val : undefined
        if (typeof def === "string")  return (typeof val === "string") ? val : undefined
        return val
    }

    function load() {
        const t = file.text()
        let ok = false
        if (t && t.trim() !== "") {
            try {
                const o = JSON.parse(t)
                for (const k of _keys) {
                    if (o[k] === undefined || o[k] === null) continue
                    const v = sanitize(k, o[k])
                    if (v !== undefined) s[k] = v
                }
                normalizeSavedSettings()
                ok = true
            } catch (e) {
                console.warn("Settings: JSON inválido, se regenera con valores por defecto.", e)
            }
        }
        _loaded = true
        // Si no había archivo válido (ausente o corrupto), créalo/recupéralo ya
        // con los valores actuales (por defecto), sin esperar a cambiar un ajuste.
        if (!ok)
            save()
    }

    function scheduleSave() {
        if (_loaded)
            saveTimer.restart()
    }

    function save() {
        if (!_loaded) return
        const o = {}
        for (const k of _keys) o[k] = s[k]
        file.setText(JSON.stringify(o, null, 2))
    }

    function reset() {
        themeName = "solitude"; accentName = "theme"; accentColor = resolvedAccent
        darkMode = true; uiScale = 1.0; animScale = 1.0; animationSpeed = 2; customAnimationDuration = 500; barOpacity = 0.78
        popupOpacity = 0.85; widgetOpacity = 0.55
        cornerScale = 1.0; barScale = 1.0; fontFamily = "JetBrainsMono Nerd Font"
        monoFontFamily = "JetBrainsMono Nerd Font"; fontScale = 1.0
        panelAnimationStyle = "material"
        panelMotionEffect = "standard"
        language = "es"
        showTray = true; showSysmon = true; showBattery = true
        showClipboard = true; showNotifications = true; showPowerProfile = true; showCaffeine = false
        clock24h = true; clockShowSeconds = false; clockShowDate = true
        weatherEnabled = true; weatherLocation = ""; weatherMetric = true; weatherRefreshMin = 30
        notifPopupsEnabled = true; notifTimeout = 5; notifMaxVisible = 4; notifPosition = "tr"
        wallpaperTransition = "fade"; wallpaperTransitionDuration = 1.0
        wallpaperDirs = [home + "/Pictures/Wallpapers", home + "/.config/wallpapers"]
    }

    function colorHex(c) {
        if (typeof c === "string")
            return c
        const r = Math.round((c.r || 0) * 255).toString(16).padStart(2, "0")
        const g = Math.round((c.g || 0) * 255).toString(16).padStart(2, "0")
        const b = Math.round((c.b || 0) * 255).toString(16).padStart(2, "0")
        return "#" + r + g + b
    }

    function stripHex(c) {
        return colorHex(c).replace("#", "")
    }

    function accentFor(name) {
        for (let i = 0; i < accentPresets.length; i++)
            if (accentPresets[i].name === name)
                return accentPresets[i].color
        return currentPalette.accent
    }

    function accentLabel(name) {
        for (let i = 0; i < accentSwatches.length; i++)
            if (accentSwatches[i].name === name)
                return accentSwatches[i].label
        return "Theme"
    }

    function hasAccentPreset(name) {
        for (let i = 0; i < accentPresets.length; i++)
            if (accentPresets[i].name === name)
                return true
        return false
    }

    function hasThemePreset(name) {
        return themePresets[name] !== undefined
    }

    function normalizeSavedSettings() {
        if (!hasThemePreset(themeName))
            themeName = "solitude"
        if (!hasAccentPreset(accentName))
            accentName = "theme"
    }

    function pickAccent(c) {
        if (typeof c === "object" && c.name !== undefined) {
            accentName = c.name
            accentColor = resolvedAccent
            return
        }

        const hex = colorHex(c).toLowerCase()
        for (let i = 0; i < accentPresets.length; i++) {
            if (colorHex(accentPresets[i].color).toLowerCase() === hex) {
                accentName = accentPresets[i].name
                accentColor = resolvedAccent
                return
            }
        }
    }

    function notifyAppearanceChanged() {
        accentColor = resolvedAccent
        scheduleSave()
        scheduleHyprSync()
    }

    function scheduleHyprSync() {
        if (_loaded && hyprlandAvailable)
            hyprSyncTimer.restart()
    }

    function hyprThemeLua() {
        const p = currentPalette
        const accent = stripHex(resolvedAccent)
        const accent2 = stripHex(p.accent2 || p.fg)
        const inactive = stripHex(p.hyprInactive || p.overlay)
        const shadow = stripHex(p.hyprShadow || p.bg)

        return [
            "-- Generated by Quickshell Settings. Edit presets in ~/.config/quickshell/Config/Settings.qml.",
            "",
            "return {",
            "    accent   = \"rgba(" + accent + "ee)\",",
            "    accent2  = \"rgba(" + accent2 + "ee)\",",
            "    inactive = \"rgba(" + inactive + "cc)\",",
            "    shadow   = \"rgba(" + shadow + "ee)\",",
            "",
            "    active_border = { colors = { \"rgba(" + accent + "ee)\", \"rgba(" + accent2 + "ee)\" }, angle = 45 },",
            "    inactive_border = \"rgba(" + inactive + "cc)\",",
            "}",
            ""
        ].join("\n")
    }

    function applyHyprlandThemeNow() {
        if (!hyprlandAvailable)
            return

        hyprThemeFile.setText(hyprThemeLua())
        if (!hyprReload.running)
            hyprReload.running = true
    }

    onThemeNameChanged: notifyAppearanceChanged()
    onAccentNameChanged: notifyAppearanceChanged()
    onAccentColorChanged: scheduleSave()
    onDarkModeChanged: notifyAppearanceChanged()
    onUiScaleChanged: scheduleSave()
    onAnimScaleChanged: scheduleSave()
    onAnimationSpeedChanged: scheduleSave()
    onCustomAnimationDurationChanged: scheduleSave()
    onBarOpacityChanged: scheduleSave()
    onPopupOpacityChanged: scheduleSave()
    onWidgetOpacityChanged: scheduleSave()
    onCornerScaleChanged: scheduleSave()
    onBarScaleChanged: scheduleSave()
    onFontFamilyChanged: scheduleSave()
    onMonoFontFamilyChanged: scheduleSave()
    onFontScaleChanged: scheduleSave()
    onPanelAnimationStyleChanged: scheduleSave()
    onPanelMotionEffectChanged: scheduleSave()
    onLanguageChanged: scheduleSave()
    onNotifPopupsEnabledChanged: scheduleSave()
    onNotifTimeoutChanged: scheduleSave()
    onNotifMaxVisibleChanged: scheduleSave()
    onNotifPositionChanged: scheduleSave()
    onShowTrayChanged: scheduleSave()
    onShowSysmonChanged: scheduleSave()
    onShowBatteryChanged: scheduleSave()
    onShowClipboardChanged: scheduleSave()
    onShowNotificationsChanged: scheduleSave()
    onShowPowerProfileChanged: scheduleSave()
    onClock24hChanged: scheduleSave()
    onClockShowSecondsChanged: scheduleSave()
    onClockShowDateChanged: scheduleSave()
    onWeatherEnabledChanged: scheduleSave()
    onWeatherLocationChanged: scheduleSave()
    onWeatherMetricChanged: scheduleSave()
    onWeatherRefreshMinChanged: scheduleSave()
    onWallpaperTransitionChanged: scheduleSave()
    onWallpaperTransitionDurationChanged: scheduleSave()
    onWallpaperDirsChanged: scheduleSave()

    Timer {
        id: saveTimer
        interval: 250
        onTriggered: s.save()
    }

    FileView {
        id: file
        path: s.home + "/.config/quickshell/settings.json"
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }

    FileView {
        id: hyprThemeFile
        path: s.home + "/.config/hypr/conf/theme.lua"
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }

    Timer {
        id: hyprSyncTimer
        interval: 250
        onTriggered: s.applyHyprlandThemeNow()
    }

    Process {
        id: hyprDetect
        command: ["sh", "-c",
            "(command -v Hyprland >/dev/null 2>&1 || command -v hyprland >/dev/null 2>&1) " +
            "&& command -v hyprctl >/dev/null 2>&1 " +
            "&& test -d \"$HOME/.config/hypr/conf\" && echo yes || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                s.hyprlandAvailable = (this.text || "").indexOf("yes") !== -1
                s.scheduleHyprSync()
            }
        }
    }

    Process {
        id: hyprReload
        command: ["sh", "-c", "test -n \"$HYPRLAND_INSTANCE_SIGNATURE\" && hyprctl reload >/dev/null 2>&1 || true"]
    }

    Component.onCompleted: {
        load()
        hyprDetect.running = true
    }
}
