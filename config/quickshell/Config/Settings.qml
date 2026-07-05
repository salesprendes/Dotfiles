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

    // Opacidades PROPIAS del tema Liquid Glass, independientes de las de arriba
    // para no pisar las de otros temas al cambiar. Translúcidas pero legibles:
    // con el blur del compositor detrás, ~0.45 se lee como cristal esmerilado
    // nítido (antes 0.36/0.18/0.14 quedaban demasiado transparentes).
    property real   glassBarOpacity: 0.45
    property real   glassPopupOpacity: 0.45
    property real   glassWidgetOpacity: 0.35

    // Opacidad "efectiva" según el tema activo. Tanto Theme como los sliders de
    // Ajustes usan ESTAS: así el mismo control edita/refleja la opacidad del
    // tema en uso (glass o no) sin mezclar valores entre temas.
    readonly property bool _isGlass: themeName === "liquid-glass"
    readonly property real effBarOpacity:    _isGlass ? glassBarOpacity    : barOpacity
    readonly property real effPopupOpacity:  _isGlass ? glassPopupOpacity  : popupOpacity
    readonly property real effWidgetOpacity: _isGlass ? glassWidgetOpacity : widgetOpacity
    function setBarOpacity(v)    { if (_isGlass) glassBarOpacity = v;    else barOpacity = v }
    function setPopupOpacity(v)  { if (_isGlass) glassPopupOpacity = v;  else popupOpacity = v }
    function setWidgetOpacity(v) { if (_isGlass) glassWidgetOpacity = v; else widgetOpacity = v }
    property real   cornerScale: 1.0    // multiplicador del redondeo
    property real   barScale: 1.0       // multiplicador de la altura de barra
    property string fontFamily: "JetBrainsMono Nerd Font"
    property string monoFontFamily: "JetBrainsMono Nerd Font"
    property real   fontScale: 1.0
    // ── Render de fuentes (fontconfig) — editables; se vuelcan a fonts.conf ──
    property bool   fontAntialias: true
    property bool   fontHinting: true
    property string fontHintstyle: "hintslight"   // hintnone | hintslight | hintmedium | hintfull
    property string fontRgba: "rgb"               // none | rgb | bgr | vrgb | vbgr
    property string fontLcdfilter: "lcddefault"   // none | lcddefault | lcdlight | lcdlegacy
    property bool   fontEmbeddedbitmap: false
    property string panelAnimationStyle: "material" // material | fluent | dynamic
    property string panelMotionEffect: "standard" // standard | directional | depth
    property string language: "es"

    // ── Terminal ─────────────────────────────────────────────
    //  La PALETA de color la genera el servicio Terminal a partir del tema
    //  (no editable aquí). Estos son los parámetros NO-color personalizables.
    property string terminalApp: "kitty"        // kitty | alacritty | foot | …
    property string terminalFont: ""            // "" = usar fontFamily
    property real   terminalFontSize: 11.5
    property real   terminalOpacity: 0.80
    property int    terminalPadding: 12
    property string terminalCursorShape: "beam" // beam | block | underline
    property bool   terminalCursorBlink: true
    property int    terminalLineHeight: 2       // px extra entre líneas
    property string terminalTabStyle: "powerline" // powerline | separator | fade | hidden
    property bool   terminalLigatures: true

    readonly property var themePresets: ({
        "solitude": {
            "label": "Solitude",
            "bg": "#101315", "bgAlt": "#161a1d", "surface": "#1e2427", "surfaceHi": "#2a3033", "overlay": "#4b4e55",
            "fg": "#cacccc", "fgDim": "#a5aeb4", "fgMuted": "#707070",
            "accent": "#798186", "accent2": "#cacccc", "cyan": "#a5aeb4", "green": "#9fa5a9", "yellow": "#c9c2b4",
            "orange": "#cbc2be", "red": "#de6145", "magenta": "#aeaeae",
            "lightBg": "#cccfd2", "lightBgAlt": "#c0c4c8", "lightSurface": "#b3b9be", "lightSurfaceHi": "#a5acb2",
            "lightOverlay": "#778086", "lightFg": "#101315", "lightFgDim": "#2b3338", "lightFgMuted": "#4c5358",
            "lightAccent": "#375259", "lightAccent2": "#48545a",
            "lightCyan": "#4f636a", "lightGreen": "#56655b", "lightYellow": "#877a52", "lightOrange": "#946a52", "lightRed": "#bb4628", "lightMagenta": "#6c646a",
            "hyprInactive": "#1e1e1e", "hyprShadow": "#1a1a1a"
        },
        "tokyo": {
            "label": "Tokyo Night",
            "bg": "#1a1b26", "bgAlt": "#24283b", "surface": "#292e42", "surfaceHi": "#343b58", "overlay": "#414868",
            "fg": "#c0caf5", "fgDim": "#a9b1d6", "fgMuted": "#565f89",
            "accent": "#7aa2f7", "accent2": "#bb9af7", "cyan": "#7dcfff", "green": "#9ece6a", "yellow": "#e0af68",
            "orange": "#ff9e64", "red": "#f7768e", "magenta": "#bb9af7",
            "lightBg": "#c8cbd4", "lightBgAlt": "#bcbfc9", "lightSurface": "#aeb3c4", "lightSurfaceHi": "#9ea5bd",
            "lightOverlay": "#7e85a6", "lightFg": "#3760bf", "lightFgDim": "#6172b0", "lightFgMuted": "#767ea8",
            "lightAccent": "#2668d1", "lightAccent2": "#8641e0",
            "lightCyan": "#007197", "lightGreen": "#587539", "lightYellow": "#8c6c3e", "lightOrange": "#b15c00", "lightRed": "#f52a65", "lightMagenta": "#9854f1",
            "hyprInactive": "#565f89", "hyprShadow": "#16161e"
        },
        "kanagawa": {
            "label": "Kanagawa",
            "bg": "#1f1f28", "bgAlt": "#2a2a37", "surface": "#363646", "surfaceHi": "#54546d", "overlay": "#727169",
            "fg": "#dcd7ba", "fgDim": "#c8c093", "fgMuted": "#938aa9",
            "accent": "#7e9cd8", "accent2": "#dcd7ba", "cyan": "#7aa89f", "green": "#98bb6c", "yellow": "#e6c384",
            "orange": "#ffa066", "red": "#e46876", "magenta": "#957fb8",
            "lightBg": "#d0ca9f", "lightBgAlt": "#c4bb90", "lightSurface": "#b6ab80", "lightSurfaceHi": "#a89d6d",
            "lightOverlay": "#6f6e64", "lightFg": "#545464", "lightFgDim": "#5e5e69", "lightFgMuted": "#76756c",
            "lightAccent": "#3d5b8f", "lightAccent2": "#a24a68",
            "lightCyan": "#597b75", "lightGreen": "#6f894e", "lightYellow": "#836f4e", "lightOrange": "#cc6d00", "lightRed": "#c84053", "lightMagenta": "#624c83",
            "hyprInactive": "#54546d", "hyprShadow": "#16161d"
        },
        "catppuccin": {
            "label": "Catppuccin",
            "bg": "#181824", "bgAlt": "#1e1e2e", "surface": "#313244", "surfaceHi": "#45475a", "overlay": "#6c7086",
            "fg": "#cdd6f4", "fgDim": "#bac2de", "fgMuted": "#9399b2",
            "accent": "#89b4fa", "accent2": "#cba6f7", "cyan": "#89dceb", "green": "#a6e3a1", "yellow": "#f9e2af",
            "orange": "#fab387", "red": "#f38ba8", "magenta": "#f5c2e7",
            "lightBg": "#cbcfdb", "lightBgAlt": "#bfc4d1", "lightSurface": "#adb3c2", "lightSurfaceHi": "#9ba2b5",
            "lightOverlay": "#71748b", "lightFg": "#4c4f69", "lightFgDim": "#50536c", "lightFgMuted": "#6c6f86",
            "lightAccent": "#1a5ae0", "lightAccent2": "#7a2fe0",
            "lightCyan": "#179299", "lightGreen": "#40a02b", "lightYellow": "#df8e1d", "lightOrange": "#fe640b", "lightRed": "#d20f39", "lightMagenta": "#ea76cb",
            "hyprInactive": "#45475a", "hyprShadow": "#11111b"
        },
        // Cristal líquido estilo macOS. Es ADAPTATIVO: en modo oscuro da un
        // cristal ahumado (fondo frío casi negro, texto claro) y en claro un
        // cristal luminoso (casi blanco translúcido, texto oscuro). La
        // translucidez REAL la aplica Theme (alphas de 'glass'); aquí solo van
        // los colores base. 'overlay' se deja BRILLANTE a propósito: los bordes
        // (withAlpha(overlay, …)) se convierten así en el filo de luz esmerilado.
        // Acentos = colores de sistema de macOS. El blur del compositor lo activa
        // shell.qml (hl.layer_rule) mientras este tema esté seleccionado.
        "liquid-glass": {
            "label": "Liquid Glass",
            // Tonos neutros: bg = surfaceContainer (#1e2023), surface =
            // surfaceContainerHigh (#292b2f), overlay = 'outline' (borde de luz
            // sutil). Los alphas de translucidez viven en
            // Theme (0.36/0.18/0.14). Acentos = colores de sistema de macOS.
            "bg": "#1e2023", "bgAlt": "#16181a", "surface": "#292b2f", "surfaceHi": "#34373b", "overlay": "#8b9198",
            "fg": "#e3e3e7", "fgDim": "#c3c6cc", "fgMuted": "#8b9198",
            "accent": "#0a84ff", "accent2": "#64d2ff", "cyan": "#64d2ff", "green": "#30d158", "yellow": "#ffd60a",
            "orange": "#ff9f0a", "red": "#ff453a", "magenta": "#bf5af2",
            "lightBg": "#eceef3", "lightBgAlt": "#e3e5ec", "lightSurface": "#dadde6", "lightSurfaceHi": "#cccfdb",
            "lightOverlay": "#b9bec9", "lightFg": "#1a1c1f", "lightFgDim": "#282c33", "lightFgMuted": "#33373e",
            "lightAccent": "#007aff", "lightAccent2": "#0a84ff",
            "lightCyan": "#0071a4", "lightGreen": "#248a3d", "lightYellow": "#a1670a", "lightOrange": "#c93400", "lightRed": "#d70015", "lightMagenta": "#a63ec0",
            "hyprInactive": "#3a3f47", "hyprShadow": "#000000"
        }
    })

    readonly property var themeOptions: [
        { text: "Solitude", value: "solitude" },
        { text: "Tokyo Night", value: "tokyo" },
        { text: "Kanagawa", value: "kanagawa" },
        { text: "Catppuccin", value: "catppuccin" },
        { text: "Liquid Glass", value: "liquid-glass" }
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
    property var    mutedNotificationApps: []

    // ── Fondos ───────────────────────────────────────────────
    // Transición visual que aplica Background/Backdrop.qml al cambiar de fondo:
    // fade | zoom | slide | push | wipe.
    property string wallpaperTransition: "fade"
    property real   wallpaperTransitionDuration: 1.0
    // Carpetas de fondos. La de imágenes se resuelve con `xdg-user-dir PICTURES`
    // (localizada, p. ej. ~/Imágenes) al arrancar; no se persiste ni se edita.
    property var    wallpaperDirs: [home + "/.config/wallpapers"]
    property string wallpaperCurrent: ""  // último fondo aplicado (ruta absoluta)

    // ── Captura de pantalla / grabación ──────────────────────
    //  Sub-objeto con TODOS los ajustes del servicio ScreenCapture, unificados
    //  aquí para tener una única fuente de verdad (settings.json). El servicio
    //  los sanea con sus propios rangos/enums al aplicarlos; aquí solo validamos
    //  que sea un objeto JSON para no corromper el archivo.
    property var screenCapture: ({})

    // ── Persistencia ─────────────────────────────────────────
    property bool _loaded: false

    readonly property var _keys: ["themeName", "accentName", "accentColor", "darkMode",
        "uiScale", "animScale", "animationSpeed", "customAnimationDuration", "barOpacity",
        "popupOpacity", "widgetOpacity", "glassBarOpacity", "glassPopupOpacity", "glassWidgetOpacity",
        "cornerScale", "barScale", "fontFamily", "monoFontFamily", "fontScale",
        "fontAntialias", "fontHinting", "fontHintstyle", "fontRgba", "fontLcdfilter", "fontEmbeddedbitmap",
        "panelAnimationStyle", "panelMotionEffect", "language",
        "showTray", "showSysmon", "showBattery", "showClipboard", "showNotifications", "showPowerProfile", "showCaffeine",
        "clock24h", "clockShowSeconds", "clockShowDate",
        "weatherEnabled", "weatherLocation", "weatherMetric", "weatherRefreshMin",
        "notifPopupsEnabled", "notifTimeout", "notifMaxVisible", "notifPosition", "mutedNotificationApps",
        "wallpaperTransition", "wallpaperTransitionDuration", "wallpaperCurrent",
        "terminalApp", "terminalFont", "terminalFontSize", "terminalOpacity", "terminalPadding",
        "terminalCursorShape", "terminalCursorBlink", "terminalLineHeight", "terminalTabStyle", "terminalLigatures",
        "screenCapture"]

    // ── Saneamiento de valores cargados ─────────────────────
    //  Rangos numéricos (se recortan a [min,max]) y conjuntos de valores
    //  válidos (enums). Lo que no encaje se IGNORA y se conserva el default.
    readonly property var _numBounds: ({
        "uiScale": [0.5, 2.0], "animScale": [0.0, 3.0], "animationSpeed": [0, 4],
        "customAnimationDuration": [50, 3000], "barOpacity": [0.0, 1.0],
        "popupOpacity": [0.0, 1.0], "widgetOpacity": [0.0, 1.0],
        "glassBarOpacity": [0.0, 1.0], "glassPopupOpacity": [0.0, 1.0], "glassWidgetOpacity": [0.0, 1.0],
        "cornerScale": [0.0, 2.0],
        "barScale": [0.5, 2.0], "fontScale": [0.5, 2.0], "weatherRefreshMin": [1, 1440],
        "notifTimeout": [1, 120], "notifMaxVisible": [1, 20],
        "wallpaperTransitionDuration": [0.1, 5.0]
    })
    readonly property var _enums: ({
        "panelAnimationStyle": ["material", "fluent", "dynamic"],
        "panelMotionEffect": ["standard", "directional", "depth"],
        "language": ["en", "es", "ca"],
        "notifPosition": ["tl", "tr", "bl", "br"],
        "wallpaperTransition": ["fade", "zoom", "slide", "push", "wipe"],
        "fontHintstyle": ["hintnone", "hintslight", "hintmedium", "hintfull"],
        "fontRgba": ["none", "rgb", "bgr", "vrgb", "vbgr"],
        "fontLcdfilter": ["none", "lcddefault", "lcdlight", "lcdlegacy"]
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
        if (k === "mutedNotificationApps") {
            if (!Array.isArray(val)) return undefined
            return val.every(x => typeof x === "string") ? val : undefined
        }
        // screenCapture: objeto JSON (el saneo fino lo hace el servicio).
        if (k === "screenCapture")
            return (val && typeof val === "object" && !Array.isArray(val)) ? val : undefined
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
        glassBarOpacity = 0.45; glassPopupOpacity = 0.45; glassWidgetOpacity = 0.35
        cornerScale = 1.0; barScale = 1.0; fontFamily = "JetBrainsMono Nerd Font"
        monoFontFamily = "JetBrainsMono Nerd Font"; fontScale = 1.0
        fontAntialias = true; fontHinting = true; fontHintstyle = "hintslight"
        fontRgba = "rgb"; fontLcdfilter = "lcddefault"; fontEmbeddedbitmap = false
        panelAnimationStyle = "material"
        panelMotionEffect = "standard"
        language = "es"
        showTray = true; showSysmon = true; showBattery = true
        showClipboard = true; showNotifications = true; showPowerProfile = true; showCaffeine = false
        clock24h = true; clockShowSeconds = false; clockShowDate = true
        weatherEnabled = true; weatherLocation = ""; weatherMetric = true; weatherRefreshMin = 30
        notifPopupsEnabled = true; notifTimeout = 5; notifMaxVisible = 4; notifPosition = "tr"; mutedNotificationApps = []
        wallpaperTransition = "fade"; wallpaperTransitionDuration = 1.0
        wallpaperCurrent = ""
        terminalApp = "kitty"; terminalFont = ""; terminalFontSize = 11.5; terminalOpacity = 0.80
        terminalPadding = 12; terminalCursorShape = "beam"; terminalCursorBlink = true
        terminalLineHeight = 2; terminalTabStyle = "powerline"; terminalLigatures = true
        screenCapture = ({})
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

    // "#rrggbb" (+ alfa 0..1) → "rgba(r, g, b, a)" para CSS de GTK.
    function rgbaCss(c, a) {
        const h = stripHex(c)
        const r = parseInt(h.substring(0, 2), 16)
        const g = parseInt(h.substring(2, 4), 16)
        const b = parseInt(h.substring(4, 6), 16)
        return "rgba(" + r + ", " + g + ", " + b + ", " + a.toFixed(2) + ")"
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
        scheduleGtkSync()
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

    // ── Tematizado de apps GTK4/libadwaita (Nautilus, etc.) ──────────
    //  Redefine los colores con nombre de libadwaita en ~/.config/gtk-4.0/
    //  gtk.css según el tema activo y el modo claro/oscuro; el interruptor
    //  real claro↔oscuro lo da gsettings color-scheme. Reescribe en cada
    //  cambio de tema/acento/darkMode (igual que la sync de Hyprland).
    function gtkColorCss(forGtk3) {
        const p = currentPalette
        const accent = colorHex(resolvedAccent)
        let c
        if (darkMode) {
            // Fondo casi-negro del propio tema ("negro adaptado").
            c = { accentBg: accent, accentFg: p.bg,
                  winBg: p.bg, winFg: p.fg, viewBg: p.bgAlt, viewFg: p.fg,
                  headBg: p.bg, headFg: p.fg, sideBg: p.bg, sideFg: p.fgDim,
                  cardBg: p.surface, popBg: p.surface, popFg: p.fg, dlgBg: p.bgAlt,
                  border: p.overlay }
        } else {
            // 'view' (listas/entradas de Nautilus, campos de texto): antes se
            // aclaraba un punto sobre el fondo y "deslumbraba" en claro. Ahora se
            // iguala al color de la barra (headerbar = lightBgAlt), más apagado,
            // para un blanco que no brilla de más.
            c = { accentBg: (p.lightAccent || accent), accentFg: "#ffffff",
                  winBg: p.lightBg, winFg: p.lightFg, viewBg: p.lightBgAlt, viewFg: p.lightFg,
                  headBg: p.lightBgAlt, headFg: p.lightFg, sideBg: p.lightBg, sideFg: (p.lightFgDim || p.lightFg),
                  cardBg: p.lightSurface, popBg: p.lightSurface, popFg: p.lightFg, dlgBg: p.lightBg,
                  border: (p.lightOverlay || p.lightSurface) }
        }
        // Transparencias: SOLO en Liquid Glass, y de forma MÍNIMA — únicamente el
        // fondo de la VENTANA (deslizador de panel) y del HEADERBAR (deslizador de
        // barra) reciben alfa. Las zonas de contenido (vista/listas/entradas),
        // sidebars, tarjetas, popovers y diálogos quedan OPACAS para no perder
        // legibilidad. Textos, acento y bordes también opacos. Fuera de Glass,
        // A() devuelve el hex tal cual (comportamiento anterior).
        const glass = _isGlass
        function A(hex, a) { return glass ? rgbaCss(hex, a) : hex }
        const aWin = effPopupOpacity, aBar = effBarOpacity
        // Colores con nombre de libadwaita (GTK4 / Nautilus).
        let out = [
            "/* Generado por Quickshell Settings — no editar a mano.",
            "   Colores del tema adaptados a GTK según modo claro/oscuro. */",
            "@define-color accent_color "       + c.accentBg + ";",
            "@define-color accent_bg_color "    + c.accentBg + ";",
            "@define-color accent_fg_color "    + c.accentFg + ";",
            "@define-color window_bg_color "    + A(c.winBg, aWin) + ";",
            "@define-color window_fg_color "    + c.winFg + ";",
            "@define-color view_bg_color "      + c.viewBg + ";",
            "@define-color view_fg_color "      + c.viewFg + ";",
            "@define-color headerbar_bg_color " + A(c.headBg, aBar) + ";",
            "@define-color headerbar_fg_color " + c.headFg + ";",
            // backdrop = color cuando la ventana NO está enfocada (si no se
            // define, libadwaita usa un gris por defecto que no pega).
            "@define-color headerbar_backdrop_color " + A(c.headBg, aBar) + ";",
            // Sidebar TOTALMENTE transparente (alfa 0): así hereda el fondo
            // translúcido de la ventana en lugar de apilar su propio tinte
            // encima (que la dejaría más opaca). libadwaita usa estos colores
            // con nombre para pintar el panel lateral, así que basta con esto.
            "@define-color sidebar_bg_color "   + A(c.sideBg, 0) + ";",
            "@define-color sidebar_fg_color "   + c.sideFg + ";",
            "@define-color sidebar_backdrop_color " + A(c.sideBg, 0) + ";",
            "@define-color secondary_sidebar_bg_color " + A(c.sideBg, 0) + ";",
            "@define-color secondary_sidebar_backdrop_color " + A(c.sideBg, 0) + ";",
            "@define-color card_bg_color "      + c.cardBg + ";",
            "@define-color popover_bg_color "   + c.popBg + ";",
            "@define-color popover_fg_color "   + c.popFg + ";",
            "@define-color dialog_bg_color "    + c.dlgBg + ";"
        ]
        // NOTA: no añadimos reglas CSS explícitas (window/headerbar/sidebar).
        // libadwaita 1.9 ya pinta cada zona UNA sola vez a partir de estos
        // @define-color (vía sus variables --window-bg-color, --sidebar-bg-color,
        // etc.). Forzarlas a mano pintaba una capa extra sobre la sidebar y la
        // dejaba con un tono distinto al del contenido. Con solo los colores con
        // nombre —y la sidebar a alfa 0 para que muestre el mismo fondo de la
        // ventana— todo el cristal queda uniforme.
        // GTK3 (Nemo y apps GTK3): añade los nombres heredados del tema, para
        // que también se adapten sin depender solo de libadwaita.
        //
        // IMPORTANTE: aquí NO se aplica alfa. Chromium/Brave (y otras apps GTK3)
        // leen estos theme_*_color para pintar su marco y PESTAÑAS, y no hacen
        // cristal: un color translúcido les rompe el render. El efecto glass se
        // queda solo en GTK4/libadwaita (Nautilus). Por eso los fondos van
        // opacos (c.winBg tal cual, no A(...)).
        if (forGtk3) {
            out = out.concat([
                "@define-color theme_bg_color "           + c.winBg + ";",
                "@define-color theme_fg_color "           + c.winFg + ";",
                "@define-color theme_base_color "         + c.viewBg + ";",
                "@define-color theme_text_color "         + c.viewFg + ";",
                "@define-color theme_selected_bg_color "  + c.accentBg + ";",
                "@define-color theme_selected_fg_color "  + c.accentFg + ";",
                "@define-color theme_unfocused_bg_color " + c.winBg + ";",
                "@define-color theme_unfocused_fg_color " + c.winFg + ";",
                "@define-color insensitive_bg_color "     + c.winBg + ";",
                "@define-color menu_bg_color "            + c.popBg + ";",
                "@define-color menu_fg_color "            + c.popFg + ";",
                "@define-color borders "                  + c.border + ";"
            ])
        }
        return out.join("\n") + "\n"
    }

    // refresh=true → tras escribir el CSS, reinicia Nautilus reabriendo su
    // carpeta (GTK4/libadwaita no recarga CSS en caliente). En el arranque
    // se llama con false para no reiniciar nada.
    property bool _gtkPendingRefresh: false
    function applyGtkTheme(refresh) {
        // El refresco se dispara en gtk4CssFile.onSaved, así que la marca se pone
        // ANTES de escribir. Los CSS se vuelcan con FileView (sin shell).
        _gtkPendingRefresh = (refresh === true)
        gtk4CssFile.setText(gtkColorCss(false))
        gtk3CssFile.setText(gtkColorCss(true))
        // Process solo para lo que no es un archivo: asegurar carpetas (por si
        // no existen) y conmutar el modo claro/oscuro de las apps GTK.
        const g4 = home + "/.config/gtk-4.0"
        const g3 = home + "/.config/gtk-3.0"
        const mode = darkMode ? "prefer-dark" : "prefer-light"
        gtkApply.command = ["sh", "-c",
            "mkdir -p '" + g4 + "' '" + g3 + "' ; "
            + "gsettings set org.gnome.desktop.interface color-scheme '" + mode + "' || true"]
        if (!gtkApply.running)
            gtkApply.running = true
    }

    function scheduleGtkSync() {
        if (_loaded)
            gtkSyncTimer.restart()
    }

    // ── fontconfig (~/.config/fontconfig/fonts.conf) ────────────────
    //  Gestionado desde la Tipografía: combina la fuente elegida (fontFamily /
    //  monoFontFamily) como familia preferida + los ajustes de render
    //  (subpíxel RGB, hinting). Afecta a Brave, Discord, GTK, Qt…
    function xmlEsc(t) {
        return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    function fontsConfXml() {
        const sans = xmlEsc(fontFamily || "Noto Sans")
        const mono = xmlEsc(monoFontFamily || fontFamily || "Noto Sans Mono")
        return [
            '<?xml version="1.0"?>',
            '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">',
            '<!-- Generado por Quickshell Settings (Tipografía) — no editar a mano. -->',
            '<fontconfig>',
            '  <!-- Familia preferida = la elegida en Tipografía (con respaldos). -->',
            '  <alias><family>sans-serif</family><prefer><family>' + sans + '</family><family>Noto Sans</family></prefer></alias>',
            '  <alias><family>monospace</family><prefer><family>' + mono + '</family><family>Noto Sans Mono</family></prefer></alias>',
            '  <!-- Render: subpíxel RGB + hinting slight, sin bitmaps embebidos. -->',
            '  <match target="font">',
            '    <edit name="antialias"      mode="assign"><bool>' + (fontAntialias ? "true" : "false") + '</bool></edit>',
            '    <edit name="hinting"        mode="assign"><bool>' + (fontHinting ? "true" : "false") + '</bool></edit>',
            '    <edit name="hintstyle"      mode="assign"><const>' + fontHintstyle + '</const></edit>',
            '    <edit name="rgba"           mode="assign"><const>' + fontRgba + '</const></edit>',
            '    <edit name="lcdfilter"      mode="assign"><const>' + fontLcdfilter + '</const></edit>',
            '    <edit name="embeddedbitmap" mode="assign"><bool>' + (fontEmbeddedbitmap ? "true" : "false") + '</bool></edit>',
            '  </match>',
            '</fontconfig>',
            ''
        ].join("\n")
    }
    // Traduce los ajustes de render del panel Tipografía a las claves de
    // gsettings que leen las apps GTK (GTK4/libadwaita las toma de aquí, no de
    // fontconfig). Así el subpíxel/hinting elegido SÍ llega a GTK. No tocamos
    // font-name: la fuente de UI de GTK se deja como esté (p. ej. Adwaita Sans).
    function gtkFontRenderCmds() {
        // antialiasing: sin AA → none; con AA y orden subpíxel → rgba; si no → grayscale.
        const aa = !fontAntialias ? "none" : (fontRgba !== "none" ? "rgba" : "grayscale")
        // hinting: apagado → none; si no, mapea el hintstyle de fontconfig.
        const hintMap = { "hintnone": "none", "hintslight": "slight",
                          "hintmedium": "medium", "hintfull": "full" }
        const hint = !fontHinting ? "none" : (hintMap[fontHintstyle] || "slight")
        // orden subpíxel: solo valores válidos de gsettings; 'none' → rgb (neutro).
        const order = (fontRgba === "bgr" || fontRgba === "vrgb" || fontRgba === "vbgr")
                        ? fontRgba : "rgb"
        const g = "gsettings set org.gnome.desktop.interface "
        return g + "font-antialiasing '" + aa + "'; "
             + g + "font-hinting '" + hint + "'; "
             + g + "font-rgba-order '" + order + "'"
    }
    function applyFontsConf() {
        fontsConfFile.setText(fontsConfXml())
        // Process solo para asegurar la carpeta y aplicar el render en gsettings.
        const dir = home + "/.config/fontconfig"
        fontsApply.command = ["sh", "-c",
            "mkdir -p '" + dir + "' ; " + gtkFontRenderCmds() + " || true"]
        if (!fontsApply.running)
            fontsApply.running = true
    }
    function scheduleFontSync() {
        if (_loaded)
            fontSyncTimer.restart()
    }

    onThemeNameChanged: notifyAppearanceChanged()
    onAccentNameChanged: notifyAppearanceChanged()
    onAccentColorChanged: scheduleSave()
    onDarkModeChanged: notifyAppearanceChanged()
    onUiScaleChanged: scheduleSave()
    onAnimScaleChanged: scheduleSave()
    onAnimationSpeedChanged: scheduleSave()
    onCustomAnimationDurationChanged: scheduleSave()
    onBarOpacityChanged: { scheduleSave(); scheduleGtkSync() }
    onPopupOpacityChanged: { scheduleSave(); scheduleGtkSync() }
    onWidgetOpacityChanged: { scheduleSave(); scheduleGtkSync() }
    onGlassBarOpacityChanged: { scheduleSave(); scheduleGtkSync() }
    onGlassPopupOpacityChanged: { scheduleSave(); scheduleGtkSync() }
    onGlassWidgetOpacityChanged: { scheduleSave(); scheduleGtkSync() }
    onCornerScaleChanged: scheduleSave()
    onBarScaleChanged: scheduleSave()
    onFontFamilyChanged: { scheduleSave(); scheduleFontSync() }
    onMonoFontFamilyChanged: { scheduleSave(); scheduleFontSync() }
    onFontScaleChanged: scheduleSave()
    onFontAntialiasChanged: { scheduleSave(); scheduleFontSync() }
    onFontHintingChanged: { scheduleSave(); scheduleFontSync() }
    onFontHintstyleChanged: { scheduleSave(); scheduleFontSync() }
    onFontRgbaChanged: { scheduleSave(); scheduleFontSync() }
    onFontLcdfilterChanged: { scheduleSave(); scheduleFontSync() }
    onFontEmbeddedbitmapChanged: { scheduleSave(); scheduleFontSync() }
    onPanelAnimationStyleChanged: scheduleSave()
    onPanelMotionEffectChanged: scheduleSave()
    onLanguageChanged: scheduleSave()
    onNotifPopupsEnabledChanged: scheduleSave()
    onNotifTimeoutChanged: scheduleSave()
    onNotifMaxVisibleChanged: scheduleSave()
    onNotifPositionChanged: scheduleSave()
    onMutedNotificationAppsChanged: scheduleSave()
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
    onWallpaperCurrentChanged: scheduleSave()
    onTerminalAppChanged: scheduleSave()
    onTerminalFontChanged: scheduleSave()
    onTerminalFontSizeChanged: scheduleSave()
    onTerminalOpacityChanged: scheduleSave()
    onTerminalPaddingChanged: scheduleSave()
    onTerminalCursorShapeChanged: scheduleSave()
    onTerminalCursorBlinkChanged: scheduleSave()
    onTerminalLineHeightChanged: scheduleSave()
    onTerminalTabStyleChanged: scheduleSave()
    onTerminalLigaturesChanged: scheduleSave()
    onScreenCaptureChanged: scheduleSave()

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

    // gtk.css (GTK4/libadwaita y GTK3) + fonts.conf: se escriben con FileView
    // (setText vuelca el string directo al archivo; sin base64 ni paso por
    // shell, que era el único motivo del antiguo _b64/printf|base64 -d).
    FileView {
        id: gtk4CssFile
        path: s.home + "/.config/gtk-4.0/gtk.css"
        atomicWrites: true
        printErrors: false
    }
    // Al guardar el CSS de GTK4 tras un cambio del usuario, refresca las apps GTK
    // abiertas (reinicio de Nautilus). Nautilus lee GTK4, así que basta este.
    Connections {
        target: gtk4CssFile
        function onSaved() {
            if (s._gtkPendingRefresh) {
                s._gtkPendingRefresh = false
                if (!nautilusRefresh.running)
                    nautilusRefresh.running = true
            }
        }
    }
    FileView {
        id: gtk3CssFile
        path: s.home + "/.config/gtk-3.0/gtk.css"
        atomicWrites: true
        printErrors: false
    }
    FileView {
        id: fontsConfFile
        path: s.home + "/.config/fontconfig/fonts.conf"
        atomicWrites: true
        printErrors: false
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

    Timer {
        id: gtkSyncTimer
        interval: 400
        onTriggered: s.applyGtkTheme(true)
    }

    // Solo asegura carpetas y conmuta el modo claro/oscuro (gsettings). La
    // escritura de los CSS y el refresco de Nautilus van por los FileView.
    Process {
        id: gtkApply
    }

    // Reinicia Nautilus reabriendo la(s) misma(s) carpeta(s): detecta sus
    // ventanas por la clase en Hyprland y resuelve la carpeta desde el título
    // (cae a la carpeta personal si no la puede resolver). En Python para
    // evitar problemas de escapado en shell.
    Process {
        id: nautilusRefresh
        command: ["python3", "-c", [
            "import json,os,subprocess,time",
            "home=os.path.expanduser('~')",
            "try:",
            "    data=json.loads(subprocess.check_output(['hyprctl','clients','-j']))",
            "except Exception:",
            "    raise SystemExit",
            "def resolve(t):",
            "    if not t or t in ('Home','Inicio','Carpeta personal','Personal'): return home",
            "    p=os.path.join(home,t)",
            "    return p if os.path.isdir(p) else home",
            "folders=[]",
            "for c in data:",
            "    if 'nautilus' in (c.get('class') or '').lower():",
            "        f=resolve(c.get('title') or '')",
            "        if f not in folders: folders.append(f)",
            "if not folders: raise SystemExit",
            "subprocess.run(['nautilus','-q'])",
            "time.sleep(0.5)",
            "for f in folders: subprocess.Popen(['nautilus',f],start_new_session=True)"
        ].join("\n")]
    }

    Timer {
        id: fontSyncTimer
        interval: 250
        onTriggered: s.applyFontsConf()
    }

    Process {
        id: fontsApply
    }

    // Resuelve la carpeta de imágenes XDG (localizada) y compone wallpaperDirs:
    // <imágenes>/Wallpapers + ~/.config/wallpapers.
    Process {
        id: xdgPicturesProc
        command: ["xdg-user-dir", "PICTURES"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = (text || "").trim()
                if (p)
                    s.wallpaperDirs = [p + "/Wallpapers", s.home + "/.config/wallpapers"]
            }
        }
    }

    Component.onCompleted: {
        load()
        hyprDetect.running = true
        xdgPicturesProc.running = true   // resuelve la carpeta de imágenes XDG
        applyGtkTheme(false)   // genera gtk.css y fija color-scheme (sin reiniciar apps)
        applyFontsConf()       // genera ~/.config/fontconfig/fonts.conf (render + fuente)
    }
}

