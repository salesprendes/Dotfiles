pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Almacén de ajustes persistente (fuente de verdad). Se guarda en
// ~/.config/quickshell/settings.json; los demás módulos (Theme, Weather,
// Wallpaper, reloj) leen de aquí.
Singleton {
    id: s

    readonly property string home: Quickshell.env("HOME") ?? ""

    // Apariencia
    property string themeName: "salesprendes"
    property string accentName: "theme"
    property color  accentColor: resolvedAccent
    property bool   darkMode: true      // false = variante clara de Solitude
    // ¿Hyprland es el compositor ACTIVO ahora mismo? Vía la variable de
    // entorno que pone al arrancar (no 'which': eso solo diría si el
    // paquete está instalado, no si es el que corre).
    readonly property bool hyprlandAvailable: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "") !== ""
    // Interruptor maestro de Ajustes → Plantillas: pausa TODO el sistema de
    // plantillas (GTK/Hyprland incluidos) sin tocar qué apps tenía marcadas
    // cada uno — 'gtkThemingEnabled'/'hyprlandThemingEnabled'/
    // 'templatesEnabled' de abajo no se tocan al pausar, así que al
    // reactivar vuelve exactamente a lo que ya estaba.
    property bool   templatesOn: true
    // Tematizado GTK (ver Ajustes → Plantillas y Templates/gtk/).
    property bool   gtkThemingEnabled: true
    // Tematizado Hyprland (ver Ajustes → Plantillas y applyHyprlandThemeNow).
    property bool   hyprlandThemingEnabled: true
    // Resto de plantillas (ver Ajustes → Plantillas y Config/AppTemplates.qml):
    // mapa id → activada/no, todas apagadas por defecto (cada plantilla se
    // activa a mano). GTK/Hyprland quedan aparte, arriba: ya tenían su
    // propio interruptor antes de que existiera este mecanismo.
    property var    templatesEnabled: ({})
    property real   uiScale: 1.0
    property int    animationSpeed: 2   // 0 none | 1 short | 2 medium | 3 long | 4 custom
    property int    customAnimationDuration: 500
    property real   barOpacity: 0.78    // opacidad del fondo de la barra
    property real   popupOpacity: 0.85
    property real   widgetOpacity: 0.55

    // Opacidad efectiva. Se conservan los nombres eff*/set* (los usan Theme y
    // los sliders de Ajustes) aunque ya no haya un tema con opacidades propias.
    readonly property real effBarOpacity:    barOpacity
    readonly property real effPopupOpacity:  popupOpacity
    readonly property real effWidgetOpacity: widgetOpacity
    function setBarOpacity(v)    { barOpacity = v }
    function setPopupOpacity(v)  { popupOpacity = v }
    function setWidgetOpacity(v) { widgetOpacity = v }
    property real   cornerScale: 1.0    // multiplicador del redondeo
    property real   barScale: 1.0       // multiplicador de la altura de barra
    property string fontFamily: "JetBrainsMono Nerd Font"
    property string monoFontFamily: "JetBrainsMono Nerd Font"
    property real   fontScale: 1.0
    // Render de fuentes (fontconfig): editables, se vuelcan a fonts.conf
    property bool   fontAntialias: true
    property bool   fontHinting: true
    property string fontHintstyle: "hintslight"   // hintnone | hintslight | hintmedium | hintfull
    property string fontRgba: "rgb"               // none | rgb | bgr | vrgb | vbgr
    property string fontLcdfilter: "lcddefault"   // none | lcddefault | lcdlight | lcdlegacy
    property bool   fontEmbeddedbitmap: false
    property string language: "es"

    // Terminal. La paleta de color la genera el servicio Terminal a partir
    // del tema (no editable aquí); aquí van los parámetros no-color.
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
        // Paletas de temas/editores conocidos, más una propia
        // (salesprendes). Los tonos intermedios (bgAlt/surfaceHi/fgMuted) y
        // el naranja no existen en las paletas originales: se derivan. Los
        // colores semanticos salen de la paleta ANSI de terminal de cada
        // una, corregidos para garantizar contraste WCAG sobre el fondo de
        // cada modo (algunos acentos claros son ilegibles sobre fondo claro
        // en el original: alli se usan como relleno, aqui van encima).
        "ayu": {
            "label": "Ayu",
            "bg": "#0b0e14", "bgAlt": "#14181f", "surface": "#1e222a", "surfaceHi": "#2e323b", "overlay": "#565b66",
            "fg": "#d1d1c7", "fgDim": "#8e959e", "fgMuted": "#60666e",
            "accent": "#e6b450", "accent2": "#aad94c", "cyan": "#95e6cb", "green": "#d5ff80", "yellow": "#ffd173",
            "orange": "#f9b076", "red": "#f28779", "magenta": "#dfbfff",
            "lightBg": "#f8f9fa", "lightBgAlt": "#eef0f2", "lightSurface": "#e4e6e9", "lightSurfaceHi": "#cbced3",
            "lightOverlay": "#8a9199", "lightFg": "#42474c", "lightFgDim": "#6d747b", "lightFgMuted": "#979da2",
            "lightAccent": "#f26400", "lightAccent2": "#769e00",
            "lightCyan": "#3ca07f", "lightGreen": "#5aa237", "lightYellow": "#c78014", "lightOrange": "#e66f28", "lightRed": "#e96667", "lightMagenta": "#9e75c7",
            "hyprInactive": "#1e222a", "hyprShadow": "#000000"
        },
        "catppuccin": {
            "label": "Catppuccin",
            "bg": "#1e1e2e", "bgAlt": "#282839", "surface": "#313244", "surfaceHi": "#393a4e", "overlay": "#4c4f69",
            "fg": "#cdd6f4", "fgDim": "#a3b4eb", "fgMuted": "#7480a9",
            "accent": "#cba6f7", "accent2": "#fab387", "cyan": "#6bd7ca", "green": "#89d88b", "yellow": "#ebd391",
            "orange": "#efaa95", "red": "#f37799", "magenta": "#f2aede",
            "lightBg": "#eff1f5", "lightBgAlt": "#dee0e8", "lightSurface": "#ccd0da", "lightSurfaceHi": "#c1c6d6",
            "lightOverlay": "#a5adcb", "lightFg": "#4c4f69", "lightFgDim": "#6a6d82", "lightFgMuted": "#9396a6",
            "lightAccent": "#8839ef", "lightAccent2": "#f05901",
            "lightCyan": "#42978b", "lightGreen": "#61983b", "lightYellow": "#af8129", "lightOrange": "#d56e3c", "lightRed": "#e16163", "lightMagenta": "#e450bd",
            "hyprInactive": "#313244", "hyprShadow": "#11111b"
        },
        "dracula": {
            "label": "Dracula",
            "bg": "#282a36", "bgAlt": "#363848", "surface": "#44475a", "surfaceHi": "#4a4d62", "overlay": "#5a5e77",
            "fg": "#f8f8f2", "fgDim": "#d6d8e0", "fgMuted": "#999ba4",
            "accent": "#bd93f9", "accent2": "#ff79c6", "cyan": "#a4ffff", "green": "#69ff94", "yellow": "#ffffa5",
            "orange": "#ffbe8c", "red": "#ff6e6e", "magenta": "#ff92df",
            "lightBg": "#f8f8f2", "lightBgAlt": "#efefee", "lightSurface": "#e6e6ea", "lightSurfaceHi": "#dedee4",
            "lightOverlay": "#cacad3", "lightFg": "#282a36", "lightFgDim": "#44475a", "lightFgMuted": "#83858f",
            "lightAccent": "#8332f4", "lightAccent2": "#ff1399",
            "lightCyan": "#039cbd", "lightGreen": "#05a72e", "lightYellow": "#8a9607", "lightOrange": "#e36f0c", "lightRed": "#ff4e4e", "lightMagenta": "#ff3dac",
            "hyprInactive": "#44475a", "hyprShadow": "#282a36"
        },
        "eldritch": {
            "label": "Eldritch",
            "bg": "#212337", "bgAlt": "#25283d", "surface": "#292e42", "surfaceHi": "#2e344b", "overlay": "#3b4261",
            "fg": "#ebfafa", "fgDim": "#abb4da", "fgMuted": "#7b81a1",
            "accent": "#37f499", "accent2": "#04d1f9", "cyan": "#66e4fd", "green": "#69f8b3", "yellow": "#f1fc79",
            "orange": "#f1bb77", "red": "#f16c75", "magenta": "#fd92ce",
            "lightBg": "#ffffff", "lightBgAlt": "#f8fafc", "lightSurface": "#f2f4f8", "lightSurfaceHi": "#e0e3e9",
            "lightOverlay": "#b0b6c3", "lightFg": "#171928", "lightFgDim": "#3b4261", "lightFgMuted": "#808498",
            "lightAccent": "#09aa5d", "lightAccent2": "#03a1c0",
            "lightCyan": "#1a6c8c", "lightGreen": "#1a7f4c", "lightYellow": "#9e8c13", "lightOrange": "#ab5916", "lightRed": "#ba1a1a", "lightMagenta": "#8c2a6c",
            "hyprInactive": "#292e42", "hyprShadow": "#414868"
        },
        "gruvbox": {
            "label": "Gruvbox",
            "bg": "#282828", "bgAlt": "#32302f", "surface": "#3c3836", "surfaceHi": "#443f3d", "overlay": "#57514e",
            "fg": "#fbf1c7", "fgDim": "#ebdbb2", "fgMuted": "#a79c82",
            "accent": "#b8bb26", "accent2": "#fabd2f", "cyan": "#8ec07c", "green": "#b8bb26", "yellow": "#fabd2f",
            "orange": "#fa8931", "red": "#fb4934", "magenta": "#d3869b",
            "lightBg": "#fbf1c7", "lightBgAlt": "#f3e6bc", "lightSurface": "#ebdbb2", "lightSurfaceHi": "#decea9",
            "lightOverlay": "#bdae93", "lightFg": "#3c3836", "lightFgDim": "#786c61", "lightFgMuted": "#a1947c",
            "lightAccent": "#908f19", "lightAccent2": "#b5811c",
            "lightCyan": "#629664", "lightGreen": "#908f19", "lightYellow": "#b5811c", "lightOrange": "#d2641f", "lightRed": "#cc241d", "lightMagenta": "#b16286",
            "hyprInactive": "#3c3836", "hyprShadow": "#282828"
        },
        "kanagawa": {
            "label": "Kanagawa",
            "bg": "#1f1f28", "bgAlt": "#242430", "surface": "#2a2a37", "surfaceHi": "#2d2d3b", "overlay": "#363646",
            "fg": "#c8c093", "fgDim": "#7d8989", "fgMuted": "#5b6266",
            "accent": "#76946a", "accent2": "#c0a36e", "cyan": "#7aa89f", "green": "#98bb6c", "yellow": "#e6c384",
            "orange": "#e77b59", "red": "#e82424", "magenta": "#938aa9",
            "lightBg": "#f2ecbc", "lightBgAlt": "#ece4b6", "lightSurface": "#e5ddb0", "lightSurfaceHi": "#dfd6aa",
            "lightOverlay": "#cfc49c", "lightFg": "#4c4c5a", "lightFgDim": "#6b6a62", "lightFgMuted": "#959274",
            "lightAccent": "#6f894e", "lightAccent2": "#77713f",
            "lightCyan": "#597b75", "lightGreen": "#6f894e", "lightYellow": "#77713f", "lightOrange": "#9b5b48", "lightRed": "#c84053", "lightMagenta": "#b35b79",
            "hyprInactive": "#2a2a37", "hyprShadow": "#1f1f28"
        },
        "nord": {
            "label": "Nord",
            "bg": "#2e3440", "bgAlt": "#343b49", "surface": "#3b4252", "surfaceHi": "#41495a", "overlay": "#505a70",
            "fg": "#eceff4", "fgDim": "#d8dee9", "fgMuted": "#9ca3ae",
            "accent": "#8fbcbb", "accent2": "#88c0d0", "cyan": "#8fbcbb", "green": "#a3be8c", "yellow": "#ebcb8b",
            "orange": "#d79b7c", "red": "#bf616a", "magenta": "#b48ead",
            "lightBg": "#eceff4", "lightBgAlt": "#e9ecf2", "lightSurface": "#e5e9f0", "lightSurfaceHi": "#dce1eb",
            "lightOverlay": "#c5cedd", "lightFg": "#2e3440", "lightFgDim": "#4c566a", "lightFgMuted": "#848c9a",
            "lightAccent": "#5e81ac", "lightAccent2": "#4394ab",
            "lightCyan": "#4c92a6", "lightGreen": "#739159", "lightYellow": "#a7843f", "lightOrange": "#bb7956", "lightRed": "#bf616a", "lightMagenta": "#a77b9f",
            "hyprInactive": "#3b4252", "hyprShadow": "#2e3440"
        },
        "rose-pine": {
            "label": "Rosé Pine",
            "bg": "#191724", "bgAlt": "#201d2f", "surface": "#26233a", "surfaceHi": "#2d2a41", "overlay": "#403d52",
            "fg": "#e0def4", "fgDim": "#908caa", "fgMuted": "#66637b",
            "accent": "#ebbcba", "accent2": "#9ccfd8", "cyan": "#86e6ee", "green": "#31748f", "yellow": "#f6c177",
            "orange": "#f19c83", "red": "#eb6f92", "magenta": "#c4a7e7",
            "lightBg": "#fffaf3", "lightBgAlt": "#f8f2ea", "lightSurface": "#f2e9e1", "lightSurfaceHi": "#ede5df",
            "lightOverlay": "#dfdad9", "lightFg": "#575279", "lightFgDim": "#736f8e", "lightFgMuted": "#9f9aad",
            "lightAccent": "#d47874", "lightAccent2": "#56949f",
            "lightCyan": "#34a0a9", "lightGreen": "#286983", "lightYellow": "#cd7f15", "lightOrange": "#cf7c4a", "lightRed": "#b4637a", "lightMagenta": "#907aa9",
            "hyprInactive": "#26233a", "hyprShadow": "#191724"
        },
        "salesprendes": {
            "label": "Salesprendes",
            "bg": "#070722", "bgAlt": "#0c0c28", "surface": "#11112d", "surfaceHi": "#15153b", "overlay": "#21215f",
            "fg": "#f3edf7", "fgDim": "#7c80b4", "fgMuted": "#535681",
            "accent": "#fff59b", "accent2": "#a9aefe", "cyan": "#9bfece", "green": "#9bfe9b", "yellow": "#fff59b",
            "orange": "#fea682", "red": "#fd4663", "magenta": "#fe9be5",
            "lightBg": "#e6e8fa", "lightBgAlt": "#ebecfc", "lightSurface": "#eff0ff", "lightSurfaceHi": "#d0d3fe",
            "lightOverlay": "#8288fc", "lightFg": "#0e0e43", "lightFgDim": "#4b55c8", "lightFgMuted": "#8188d9",
            "lightAccent": "#5d65f5", "lightAccent2": "#797fd1",
            "lightCyan": "#0e0e43", "lightGreen": "#0a9b0a", "lightYellow": "#9b830a", "lightOrange": "#d8620d", "lightRed": "#fd3050", "lightMagenta": "#f124be",
            "hyprInactive": "#11112d", "hyprShadow": "#070722"
        },
        "tokyo-night": {
            "label": "Tokyo-Night",
            "bg": "#1a1b26", "bgAlt": "#1f2230", "surface": "#24283b", "surfaceHi": "#292e43", "overlay": "#353d57",
            "fg": "#c0caf5", "fgDim": "#9aa5ce", "fgMuted": "#6d7593",
            "accent": "#7aa2f7", "accent2": "#bb9af7", "cyan": "#7dcfff", "green": "#9ece6a", "yellow": "#e0af68",
            "orange": "#ea9579", "red": "#f7768e", "magenta": "#bb9af7",
            "lightBg": "#e1e2e7", "lightBgAlt": "#d8dce5", "lightSurface": "#d0d5e3", "lightSurfaceHi": "#c8ccd7",
            "lightOverlay": "#b4b5b9", "lightFg": "#28458a", "lightFgDim": "#5061a0", "lightFgMuted": "#7c89ba",
            "lightAccent": "#2e7de9", "lightAccent2": "#9854f1",
            "lightCyan": "#007197", "lightGreen": "#587539", "lightYellow": "#8c6c3e", "lightOrange": "#bb4e50", "lightRed": "#f52a65", "lightMagenta": "#9854f1",
            "hyprInactive": "#24283b", "hyprShadow": "#15161e"
        }
    })

    readonly property var themeOptions: [
        { text: "Dinámico (fondo)", value: "dynamic" },
        { text: "Ayu", value: "ayu" },
        { text: "Catppuccin", value: "catppuccin" },
        { text: "Dracula", value: "dracula" },
        { text: "Eldritch", value: "eldritch" },
        { text: "Gruvbox", value: "gruvbox" },
        { text: "Kanagawa", value: "kanagawa" },
        { text: "Nord", value: "nord" },
        { text: "Rosé Pine", value: "rose-pine" },
        { text: "Salesprendes", value: "salesprendes" },
        { text: "Tokyo-Night", value: "tokyo-night" }
    ]
    // Acento "theme": en modo claro usa la variante lightAccent (más oscura,
    // para que contraste sobre fondo claro); en oscuro, el accent normal.
    readonly property color themeAccent: darkMode
        ? currentPalette.accent
        : (currentPalette.lightAccent || currentPalette.accent)

    // Lista canónica de acentos {name, color, label}. Es la única fuente:
    // de aquí leen accentFor/accentLabel/hasAccentPreset/pickAccent y el
    // selector de la página de Tema (ThemePage usa este nombre desde fuera).
    readonly property var accentSwatches: [
        { name: "theme", color: themeAccent, label: "Theme" },
        { name: "blue", color: "#7aa2f7", label: "Blue" },
        { name: "purple", color: "#bb9af7", label: "Purple" },
        { name: "green", color: "#9ece6a", label: "Green" },
        { name: "amber", color: "#e0af68", label: "Amber" },
        { name: "red", color: "#de6145", label: "Red" }
    ]
    // Con el tema "dynamic", la paleta viene del extractor del fondo (si ya
    // hay una calculada); mientras no la haya, se pinta con el preset base.
    readonly property var currentPalette:
        themeName === "dynamic" && dynamicPalette.bg !== undefined ? dynamicPalette
        : themePresets[themeName] || themePresets.salesprendes
    readonly property color resolvedAccent: accentFor(accentName)

    // Base de las tres velocidades: 100 / 200 / 400 ms, moduladas por un
    // multiplicador continuo (duracion / speed) en vez de tres valores
    // sueltos por paso. El paso "Medium" es speed = 1.0, sin modular.
    readonly property int animBaseFast: 100
    readonly property int animBaseNormal: 200
    readonly property int animBaseSlow: 400
    readonly property var animationSpeedFactors: [0, 1.5, 1.0, 0.6]   // duracion / factor
    readonly property int normalizedAnimationSpeed: Math.max(0, Math.min(4, animationSpeed))
    readonly property real _speedFactor: animationSpeedFactors[normalizedAnimationSpeed] || 0

    readonly property int animFastMs: normalizedAnimationSpeed === 4
        ? Math.round(customAnimationDuration / 2)
        : (_speedFactor === 0 ? 0 : Math.round(animBaseFast / _speedFactor))
    readonly property int animNormalMs: normalizedAnimationSpeed === 4
        ? customAnimationDuration
        : (_speedFactor === 0 ? 0 : Math.round(animBaseNormal / _speedFactor))
    readonly property int animSlowMs: normalizedAnimationSpeed === 4
        ? customAnimationDuration * 2
        : (_speedFactor === 0 ? 0 : Math.round(animBaseSlow / _speedFactor))
    // Los paneles usan la duracion "normal": todo abre y cierra en 200 ms.
    readonly property int popoutAnimationMs: animNormalMs

    // Cafeína: inhibe la inactividad (no se suspende ni bloquea). Vive aquí, y
    // no en Globals, para que sobreviva a los reinicios del shell: si lo dejaste
    // puesto, sigue puesto. El proceso inhibidor lo levanta shell.qml leyendo
    // este estado.
    property bool   caffeine: false

    // Barra (visibilidad de widgets)
    property bool   showTray: true
    property bool   showSysmon: true
    property bool   showBattery: true
    property bool   showClipboard: true
    property bool   showNotifications: true
    property bool   showPowerProfile: true
    property bool   showCaffeine: false

    // Reloj
    property bool   clock24h: true
    property bool   clockShowSeconds: false
    property bool   clockShowDate: true

    // Clima
    property bool   weatherEnabled: true
    property string weatherLocation: ""   // vacío = automático
    property bool   weatherMetric: true   // true = °C, false = °F
    property int    weatherRefreshMin: 30
    property bool   weatherShowForecast: true
    property int    weatherForecastDays: 5
    property bool   weatherShowDetails: true   // sensación térmica y humedad
    property bool   weatherShowWind: false
    property bool   weatherShowRain: false     // % de lluvia en el pronóstico
    property bool   weatherShowSun: false      // amanecer y atardecer
    property bool   weatherShowInBar: false    // píldora de clima en la barra

    // Notificaciones
    property bool   notifPopupsEnabled: true
    property int    notifTimeout: 5            // segundos
    property int    notifMaxVisible: 4
    property string notifPosition: "tr"        // tr | tl | br | bl
    property var    mutedNotificationApps: []

    // Fondos
    // Transición visual que aplica Background/Backdrop.qml al cambiar de fondo:
    // fade | zoom | slide | push | wipe.
    property string wallpaperTransition: "fade"
    property real   wallpaperTransitionDuration: 1.0
    // Carpetas de fondos. La de imágenes se resuelve con `xdg-user-dir PICTURES`
    // (localizada, p. ej. ~/Imágenes) al arrancar; no se persiste ni se edita.
    property var    wallpaperDirs: [home + "/.config/wallpapers"]
    property string wallpaperCurrent: ""  // último fondo aplicado (ruta absoluta)

    // Paleta dinámica generada desde el fondo de pantalla activo (tema base
    // "dynamic"). La calcula el extractor de la barra (ver Bar.qml) y se
    // persiste para que un arranque nuevo pinte con ella al instante, sin
    // esperar al análisis de imagen.
    property var dynamicPalette: ({})

    // Última respuesta buena del clima (con su marca de tiempo): al arrancar
    // o recargar, el panel pinta al instante desde aquí y solo consulta la
    // API si el dato ya caducó.
    property var weatherCache: ({})

    // Avatar del usuario: ruta absoluta a una imagen (vacío = inicial en
    // círculo tonal). Se muestra recortado en círculo en el perfil de Ajustes,
    // en "Acerca de" y, si se copia al greeter, en la pantalla de bloqueo.
    property string avatarPath: ""

    // Captura de pantalla / grabación
    // Sub-objeto con todos los ajustes del servicio ScreenCapture, unificados
    // aquí para tener una única fuente de verdad (settings.json). El servicio
    // los sanea con sus rangos/enums al aplicarlos; aquí solo validamos que sea
    // un objeto JSON para no corromper el archivo.
    property var screenCapture: ({})

    // Persistencia
    property bool _loaded: false

    readonly property var _keys: ["themeName", "accentName", "accentColor", "darkMode",
        "uiScale", "animationSpeed", "customAnimationDuration", "barOpacity",
        "popupOpacity", "widgetOpacity",
        "cornerScale", "barScale", "fontFamily", "monoFontFamily", "fontScale",
        "fontAntialias", "fontHinting", "fontHintstyle", "fontRgba", "fontLcdfilter", "fontEmbeddedbitmap",
        "language",
        "caffeine",
        "templatesOn", "gtkThemingEnabled", "hyprlandThemingEnabled", "templatesEnabled",
        "showTray", "showSysmon", "showBattery", "showClipboard", "showNotifications", "showPowerProfile", "showCaffeine",
        "clock24h", "clockShowSeconds", "clockShowDate",
        "weatherEnabled", "weatherLocation", "weatherMetric", "weatherRefreshMin",
        "weatherShowForecast", "weatherForecastDays", "weatherShowDetails", "weatherShowWind",
        "weatherShowRain", "weatherShowSun", "weatherShowInBar",
        "notifPopupsEnabled", "notifTimeout", "notifMaxVisible", "notifPosition", "mutedNotificationApps",
        "wallpaperTransition", "wallpaperTransitionDuration", "wallpaperCurrent", "avatarPath",
        "dynamicPalette", "weatherCache",
        "terminalApp", "terminalFont", "terminalFontSize", "terminalOpacity", "terminalPadding",
        "terminalCursorShape", "terminalCursorBlink", "terminalLineHeight", "terminalTabStyle", "terminalLigatures",
        "screenCapture"]

    // Valores por defecto de todas las claves persistidas (_keys).
    // Copiados de las declaraciones de arriba (no capturados en runtime: tras
    // load() las propiedades ya tienen los valores del JSON). reset() itera
    // este mapa; al añadir un ajuste, añádelo a la declaración, a _keys y aquí.
    // accentColor no aparece: su default es resolvedAccent y reset() lo
    // recalcula al final.
    readonly property var _defaults: ({
        "themeName": "salesprendes", "accentName": "theme", "darkMode": true,
        "uiScale": 1.0, "animationSpeed": 2, "customAnimationDuration": 500, "barOpacity": 0.78,
        "popupOpacity": 0.85, "widgetOpacity": 0.55,
        "cornerScale": 1.0, "barScale": 1.0,
        "fontFamily": "JetBrainsMono Nerd Font", "monoFontFamily": "JetBrainsMono Nerd Font", "fontScale": 1.0,
        "fontAntialias": true, "fontHinting": true, "fontHintstyle": "hintslight",
        "fontRgba": "rgb", "fontLcdfilter": "lcddefault", "fontEmbeddedbitmap": false,
        "language": "es",
        "showTray": true, "showSysmon": true, "showBattery": true, "showClipboard": true,
        "caffeine": false,
        "templatesOn": true, "gtkThemingEnabled": true, "hyprlandThemingEnabled": true, "templatesEnabled": ({}),
        "showNotifications": true, "showPowerProfile": true, "showCaffeine": false,
        "clock24h": true, "clockShowSeconds": false, "clockShowDate": true,
        "weatherEnabled": true, "weatherLocation": "", "weatherMetric": true, "weatherRefreshMin": 30,
        "weatherShowForecast": true, "weatherForecastDays": 5, "weatherShowDetails": true, "weatherShowWind": false,
        "weatherShowRain": false, "weatherShowSun": false, "weatherShowInBar": false,
        "notifPopupsEnabled": true, "notifTimeout": 5, "notifMaxVisible": 4, "notifPosition": "tr",
        "mutedNotificationApps": [],
        "wallpaperTransition": "fade", "wallpaperTransitionDuration": 1.0, "wallpaperCurrent": "", "avatarPath": "",
        "dynamicPalette": ({}), "weatherCache": ({}),
        "terminalApp": "kitty", "terminalFont": "", "terminalFontSize": 11.5, "terminalOpacity": 0.80,
        "terminalPadding": 12, "terminalCursorShape": "beam", "terminalCursorBlink": true,
        "terminalLineHeight": 2, "terminalTabStyle": "powerline", "terminalLigatures": true,
        "screenCapture": {}
    })

    // Saneamiento de valores cargados
    // Rangos numéricos (se recortan a [min,max]) y conjuntos válidos (enums).
    // Lo que no encaje se ignora y se conserva el default.
    readonly property var _numBounds: ({
        "uiScale": [0.5, 2.0], "animationSpeed": [0, 4],
        "customAnimationDuration": [50, 3000], "barOpacity": [0.0, 1.0],
        "popupOpacity": [0.0, 1.0], "widgetOpacity": [0.0, 1.0],
        "cornerScale": [0.0, 2.0],
        "barScale": [0.5, 2.0], "fontScale": [0.5, 2.0], "weatherRefreshMin": [1, 1440], "weatherForecastDays": [3, 7],
        "notifTimeout": [1, 120], "notifMaxVisible": [1, 20],
        "wallpaperTransitionDuration": [0.1, 5.0]
    })
    readonly property var _enums: ({
        "language": ["en", "es", "ca"],
        "notifPosition": ["tl", "tr", "bl", "br"],
        "wallpaperTransition": ["fade", "zoom", "slide", "push", "wipe"],
        "fontHintstyle": ["hintnone", "hintslight", "hintmedium", "hintfull"],
        "fontRgba": ["none", "rgb", "bgr", "vrgb", "vbgr"],
        "fontLcdfilter": ["none", "lcddefault", "lcdlight", "lcdlegacy"]
    })
    // Claves que deben ser enteros (se redondean tras recortar).
    readonly property var _intKeys: ["animationSpeed", "customAnimationDuration",
        "weatherRefreshMin", "weatherForecastDays", "notifTimeout", "notifMaxVisible"]

    // Devuelve un valor válido para 'k', o 'undefined' si hay que descartarlo
    // (se conserva el valor por defecto). Infiere el tipo esperado del default.
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
        // Objetos JSON anidados (el saneo fino lo hace su consumidor).
        if (k === "screenCapture" || k === "dynamicPalette" || k === "weatherCache")
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
        if (t && t.trim() !== "") {
            try {
                const o = JSON.parse(t)
                for (const k of _keys) {
                    if (o[k] === undefined || o[k] === null) continue
                    const v = sanitize(k, o[k])
                    if (v !== undefined) s[k] = v
                }
                normalizeSavedSettings()
            } catch (e) {
                console.warn("Settings: JSON inválido, se regenera con valores por defecto.", e)
            }
        }
        _loaded = true
        // Reescribe siempre tras cargar. normalizeSavedSettings() corrige en
        // memoria lo que ya no existe (un tema retirado, p.ej.), pero corre con
        // _loaded aún en false, así que su scheduleSave() se descarta y el
        // archivo se quedaba con el valor muerto y con claves de ajustes ya
        // eliminados. Al guardar aquí, el archivo queda saneado (save() escribe
        // solo las claves de _keys) sin esperar a que se toque un ajuste.
        // También cubre el caso de que no hubiera archivo válido (ausente o
        // corrupto): queda creado con los valores por defecto.
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
        // accentColor es un QColor: serializado tal cual sería un objeto que
        // sanitize() rechaza al cargar. Se persiste como "#rrggbb".
        o.accentColor = colorHex(accentColor)
        file.setText(JSON.stringify(o, null, 2))
    }

    // Restaura cada clave persistida a su valor de declaración (_defaults).
    // Arrays/objetos se copian para no compartir la referencia del mapa (si
    // algo los mutara in situ, corrompería los defaults); accentColor se
    // recalcula aparte porque no vive en _defaults (se deriva de accentName).
    function reset() {
        for (const k in _defaults) {
            const v = _defaults[k]
            s[k] = Array.isArray(v) ? v.slice()
                 : (v !== null && typeof v === "object") ? Object.assign({}, v)
                 : v
        }
        accentColor = resolvedAccent
    }

    // Claves que casi siempre difieren de su "valor por defecto" recién
    // arrancado sin que el usuario haya tocado nada: screenCapture se
    // autorrellena con sus propios valores la primera vez que se lee
    // (ver ScreenCapture.applyFromSettings, así el JSON queda editable a
    // mano), y wallpaperCurrent parte vacío pero siempre acaba con un fondo
    // puesto (elegido o auto-asignado). Comparar cualquiera de las dos
    // contra su default literal siempre da "modificado", así que no cuentan
    // para "solo modificados" / mostrar "Restablecer" — pero 'reset()' sí
    // las restaura (vía _defaults) si de verdad se pulsa el botón.
    readonly property var _volatileKeys: ({ "screenCapture": true, "wallpaperCurrent": true })

    // ¿Difiere esta clave de su valor por defecto? Lo usa el filtro "solo
    // modificados" de la ventana de Ajustes. accentColor queda fuera a
    // propósito: no está en _defaults (se deriva de accentName).
    function isModified(key) {
        if (_volatileKeys[key])
            return false
        const def = _defaults[key]
        if (def === undefined)
            return false
        const cur = s[key]
        // Arrays y objetos (mutedNotificationApps, screenCapture): comparación
        // estructural; comparar por referencia daría siempre "modificado".
        if (def !== null && typeof def === "object")
            return JSON.stringify(cur) !== JSON.stringify(def)
        // Los reales llevan coma flotante (uiScale, opacidades…): un == exacto
        // marcaría como modificado un 0.78 que ha ido y vuelto por un slider.
        if (typeof def === "number" && typeof cur === "number")
            return Math.abs(cur - def) > 1e-6
        return cur !== def
    }

    // ¿Hay algo que restablecer? Gatea el botón "Restablecer" de Ajustes:
    // no tiene sentido mostrarlo si no cambiaría nada.
    readonly property bool anyModified: {
        for (let i = 0; i < _keys.length; i++)
            if (isModified(_keys[i]))
                return true
        return false
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
        for (let i = 0; i < accentSwatches.length; i++)
            if (accentSwatches[i].name === name)
                return accentSwatches[i].color
        return currentPalette.accent
    }

    function accentLabel(name) {
        for (let i = 0; i < accentSwatches.length; i++)
            if (accentSwatches[i].name === name)
                return accentSwatches[i].label
        return "Theme"
    }

    function hasAccentPreset(name) {
        for (let i = 0; i < accentSwatches.length; i++)
            if (accentSwatches[i].name === name)
                return true
        return false
    }

    // ── Paleta dinámica ──────────────────────────────────────────────────────

    // HSL (h 0-360, s/l 0-1) → "#rrggbb".
    function _hslHex(h, sat, l) {
        h = ((h % 360) + 360) % 360
        const c = (1 - Math.abs(2 * l - 1)) * sat
        const x = c * (1 - Math.abs((h / 60) % 2 - 1))
        const m = l - c / 2
        let r = 0, g = 0, b = 0
        if (h < 60)       { r = c; g = x }
        else if (h < 120) { r = x; g = c }
        else if (h < 180) { g = c; b = x }
        else if (h < 240) { g = x; b = c }
        else if (h < 300) { r = x; b = c }
        else              { r = c; b = x }
        const hx = (n) => Math.max(0, Math.min(255, Math.round((n + m) * 255)))
            .toString(16).padStart(2, "0")
        return "#" + hx(r) + hx(g) + hx(b)
    }

    // Recibe los píxeles RGBA de una miniatura del fondo, vota el tono
    // dominante (ponderando saturación y luz media) y publica la paleta.
    function computeDynamicPalette(data) {
        const buckets = new Array(36).fill(0)
        let voted = 0
        for (let i = 0; i + 3 < data.length; i += 4) {
            const r = data[i] / 255, g = data[i + 1] / 255, b = data[i + 2] / 255
            const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn
            if (d < 0.05)
                continue
            const l = (mx + mn) / 2
            const sat = d / (1 - Math.abs(2 * l - 1))
            let h
            if (mx === r) h = ((g - b) / d) % 6
            else if (mx === g) h = (b - r) / d + 2
            else h = (r - g) / d + 4
            h = h * 60; if (h < 0) h += 360
            const w = sat * (1 - Math.abs(l - 0.5))
            buckets[Math.floor(h / 10) % 36] += w
            voted += w
        }
        let best = 0
        for (let i = 1; i < 36; i++)
            if (buckets[i] > buckets[best]) best = i
        // Imagen casi monocroma: paleta sobria en vez de inventar color.
        const sat = voted > 8 ? 0.55 : voted > 2 ? 0.4 : 0.22
        setDynamicPalette(_paletteFromSeed(best * 10 + 5, sat))
    }

    // Deriva del tono semilla la paleta completa (oscura + variantes claras).
    // Los colores semánticos conservan su matiz reconocible pero se acercan
    // un 15% al tono base para que armonicen con el fondo.
    function _paletteFromSeed(hue, sat) {
        const H = (x) => ((x % 360) + 360) % 360
        const harm = (h) => H(h + (((hue - h + 540) % 360) - 180) * 0.15)
        const c = _hslHex
        return {
            label: "Dinámico",
            bg: c(hue, sat * 0.45, 0.08), bgAlt: c(hue, sat * 0.45, 0.10),
            surface: c(hue, sat * 0.4, 0.13), surfaceHi: c(hue, sat * 0.4, 0.17),
            overlay: c(hue, sat * 0.35, 0.28),
            fg: c(hue, sat * 0.25, 0.93), fgDim: c(hue, sat * 0.2, 0.72), fgMuted: c(hue, sat * 0.15, 0.52),
            accent: c(hue, Math.min(0.8, sat + 0.15), 0.72),
            accent2: c(H(hue + 40), Math.min(0.7, sat + 0.05), 0.68),
            cyan: c(harm(190), 0.5, 0.68), green: c(harm(140), 0.45, 0.66),
            yellow: c(harm(55), 0.6, 0.68), orange: c(harm(28), 0.6, 0.66),
            red: c(harm(2), 0.6, 0.64), magenta: c(harm(310), 0.5, 0.7),
            lightBg: c(hue, sat * 0.35, 0.94), lightBgAlt: c(hue, sat * 0.35, 0.92),
            lightSurface: c(hue, sat * 0.3, 0.89), lightSurfaceHi: c(hue, sat * 0.3, 0.85),
            lightOverlay: c(hue, sat * 0.3, 0.72),
            lightFg: c(hue, sat * 0.5, 0.15), lightFgDim: c(hue, sat * 0.35, 0.32),
            lightFgMuted: c(hue, sat * 0.25, 0.48),
            lightAccent: c(hue, Math.min(0.75, sat + 0.1), 0.42),
            lightAccent2: c(H(hue + 40), 0.5, 0.4),
            lightCyan: c(harm(190), 0.55, 0.34), lightGreen: c(harm(140), 0.5, 0.32),
            lightYellow: c(harm(55), 0.6, 0.34), lightOrange: c(harm(28), 0.6, 0.36),
            lightRed: c(harm(2), 0.6, 0.4), lightMagenta: c(harm(310), 0.5, 0.38),
            hyprInactive: c(hue, sat * 0.4, 0.13), hyprShadow: c(hue, sat * 0.45, 0.06)
        }
    }

    function setDynamicPalette(p) {
        dynamicPalette = p
        scheduleSave()
    }

    function hasThemePreset(name) {
        return name === "dynamic" || themePresets[name] !== undefined
    }

    // Corrige un tema/acento guardado que ya no exista (renombrado o
    // quitado de themePresets/accentSwatches), volviendo al valor por
    // defecto en vez de dejar la app con una paleta inválida.
    function normalizeSavedSettings() {
        if (!hasThemePreset(themeName))
            themeName = "salesprendes"
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
        for (let i = 0; i < accentSwatches.length; i++) {
            if (colorHex(accentSwatches[i].color).toLowerCase() === hex) {
                accentName = accentSwatches[i].name
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
        if (_loaded && hyprlandAvailable && templatesOn && hyprlandThemingEnabled)
            hyprSyncTimer.restart()
    }

    // Tabla Lua con los colores del tema, para que el hyprland.lua del
    // usuario haga require() de este archivo y los aplique con hl.config().
    // Además de accent/accent2/inactive/shadow (bordes de ventana normales,
    // ya existían), añade los colores de GRUPO de ventanas (border_active/
    // inactive/locked_active/locked_inactive + su groupbar), que Hyprland
    // usa al agrupar pestañas — antes se quedaban en el valor por defecto de
    // Hyprland, sin seguir el tema. accent2 hace de color secundario del
    // grupo activo, y rojo fijo para el estado bloqueado.
    function hyprThemeLua() {
        const p = currentPalette
        const accent = stripHex(resolvedAccent)
        const accent2 = stripHex(p.accent2 || p.fg)
        const inactive = stripHex(p.hyprInactive || p.overlay)
        const shadow = stripHex(p.hyprShadow || p.bg)
        const locked = stripHex(p.red)

        return [
            "-- Generated by Quickshell Settings. Edit presets in ~/.config/quickshell/Config/Settings.qml.",
            "",
            "return {",
            "    accent   = \"rgba(" + accent + "ee)\",",
            "    accent2  = \"rgba(" + accent2 + "ee)\",",
            "    inactive = \"rgba(" + inactive + "cc)\",",
            "    shadow   = \"rgba(" + shadow + "ee)\",",
            "    locked   = \"rgba(" + locked + "ee)\",",
            "",
            "    active_border = { colors = { \"rgba(" + accent + "ee)\", \"rgba(" + accent2 + "ee)\" }, angle = 45 },",
            "    inactive_border = \"rgba(" + inactive + "cc)\",",
            "",
            "    group_active_border = \"rgba(" + accent2 + "ee)\",",
            "    group_inactive_border = \"rgba(" + inactive + "cc)\",",
            "    group_locked_active_border = \"rgba(" + locked + "ee)\",",
            "    group_locked_inactive_border = \"rgba(" + inactive + "cc)\",",
            "",
            "    groupbar_active = \"rgba(" + accent2 + "ee)\",",
            "    groupbar_inactive = \"rgba(" + inactive + "cc)\",",
            "    groupbar_locked_active = \"rgba(" + locked + "ee)\",",
            "    groupbar_locked_inactive = \"rgba(" + inactive + "cc)\",",
            "}",
            ""
        ].join("\n")
    }

    // Vuelca hyprThemeLua() en theme.lua y recarga Hyprland — no hace nada
    // si Hyprland no está corriendo, el maestro de plantillas está en pausa,
    // o esta plantilla está desactivada.
    function applyHyprlandThemeNow() {
        if (!hyprlandAvailable || !templatesOn || !hyprlandThemingEnabled)
            return
        hyprThemeFile.setText(hyprThemeLua())
        if (!hyprReload.running)
            hyprReload.running = true
    }

    // Blanco o casi-negro según la luminancia del color, para roles sin
    // convención previa en el shell (destructive/error/warning/success): el
    // acento y la paleta ya tienen su fg pensado a mano, pero red/yellow/green
    // sueltos no. Fórmula de luminancia relativa estándar (coeficientes
    // Rec. 709).
    function readableOn(hex) {
        hex = String(hex).replace("#", "")
        const r = parseInt(hex.substring(0, 2), 16) / 255
        const g = parseInt(hex.substring(2, 4), 16) / 255
        const b = parseInt(hex.substring(4, 6), 16) / 255
        const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return lum > 0.5 ? "#1a1a1a" : "#ffffff"
    }

    // Mezcla lineal de dos colores hex (t=0 → a, t=1 → b). Para derivar los
    // niveles que la paleta no tiene explícitos (contenedores, variantes).
    function mix(hexA, hexB, t) {
        const a = String(hexA).replace("#", ""), b = String(hexB).replace("#", "")
        const ar = parseInt(a.substring(0, 2), 16), ag = parseInt(a.substring(2, 4), 16), ab = parseInt(a.substring(4, 6), 16)
        const br = parseInt(b.substring(0, 2), 16), bg = parseInt(b.substring(2, 4), 16), bb = parseInt(b.substring(4, 6), 16)
        const r = Math.round(ar + (br - ar) * t), g = Math.round(ag + (bg - ag) * t), bl = Math.round(ab + (bb - ab) * t)
        const h = (n) => n.toString(16).padStart(2, "0")
        return "#" + h(r) + h(g) + h(bl)
    }

    // Tokens "Material-ish" para las plantillas de apps (Templates/<app>/):
    // aproximan los ~35 roles de Material 3 (primary/surface/outline/...
    // con variantes on*/*Container) a partir de nuestra paleta, que solo
    // tiene ~15 campos. No es un motor HCT real: es una derivación
    // razonable (mismo espíritu que gtkTokens/readableOn) para que las
    // plantillas de cada app tengan de dónde sacar cada rol sin reescribirlas.
    function materialTokens() {
        const p = currentPalette
        const pick = (dk, lt) => darkMode ? dk : (lt || dk)
        const bg = pick(p.bg, p.lightBg)
        const surface = pick(p.surface, p.lightSurface)
        const surfaceHi = pick(p.surfaceHi, p.lightSurfaceHi)
        const overlay = pick(p.overlay, p.lightOverlay)
        const fg = pick(p.fg, p.lightFg)
        const fgDim = pick(p.fgDim, p.lightFgDim)
        const fgMuted = pick(p.fgMuted, p.lightFgMuted)
        const accent = colorHex(resolvedAccent)
        const accent2 = pick(p.accent2, p.lightAccent2 || p.accent2)
        const cyan = pick(p.cyan, p.lightCyan || p.cyan)
        const green = pick(p.green, p.lightGreen || p.green)
        const yellow = pick(p.yellow, p.lightYellow || p.yellow)
        const red = pick(p.red, p.lightRed || p.red)
        const magenta = pick(p.magenta, p.lightMagenta || p.magenta)
        const shadow = p.hyprShadow || "#000000"
        const white = "#ffffff"

        return {
            background: bg, onBackground: fg,
            surface: surface, onSurface: fg,
            surfaceVariant: surfaceHi, onSurfaceVariant: fgDim,
            surfaceContainerLowest: mix(surface, bg, 0.35),
            surfaceContainerLow: mix(surface, bg, 0.15),
            surfaceContainer: surface,
            surfaceContainerHigh: mix(surface, surfaceHi, 0.5),
            surfaceContainerHighest: surfaceHi,
            primary: accent, onPrimary: readableOn(accent),
            primaryContainer: surfaceHi, onPrimaryContainer: fg,
            secondary: accent2, onSecondary: readableOn(accent2),
            secondaryContainer: mix(accent2, surface, 0.75), onSecondaryContainer: fg,
            tertiary: cyan, onTertiary: readableOn(cyan),
            tertiaryContainer: mix(cyan, surface, 0.75), onTertiaryContainer: fg,
            error: red, onError: readableOn(red),
            errorContainer: mix(red, surface, 0.75), onErrorContainer: fg,
            outline: overlay, outlineVariant: mix(overlay, surface, 0.5),
            inverseSurface: fg, hover: surfaceHi, shadow: shadow,
            terminalBackground: bg, terminalForeground: fg,
            terminalBackgroundDarken01: mix(bg, "#000000", 0.1),
            terminalBackgroundDarken005: mix(bg, "#000000", 0.05),
            terminalCursor: accent, terminalCursorText: readableOn(accent),
            terminalSelectionBg: overlay, terminalSelectionFg: fg,
            terminalNormalBlack: bg, terminalNormalRed: red, terminalNormalGreen: green,
            terminalNormalYellow: yellow, terminalNormalBlue: accent2, terminalNormalMagenta: magenta,
            terminalNormalCyan: cyan, terminalNormalWhite: fgDim,
            terminalBrightBlack: fgMuted, terminalBrightRed: mix(red, white, 0.18),
            terminalBrightGreen: mix(green, white, 0.18), terminalBrightYellow: mix(yellow, white, 0.18),
            terminalBrightBlue: mix(accent2, white, 0.18), terminalBrightMagenta: mix(magenta, white, 0.18),
            terminalBrightCyan: mix(cyan, white, 0.18), terminalBrightWhite: fg
        }
    }

    // Añade automáticamente, por cada token hex de materialTokens(), las
    // variantes que algunas plantillas necesitan: '<token>Stripped' (sin #,
    // para formatos "0xRRGGBB") y '<token>Rgb' (r,g,b decimal, para KDE).
    function expandTokenVariants(tokens) {
        const out = Object.assign({}, tokens)
        for (const k in tokens) {
            const hex = String(tokens[k]).replace("#", "")
            out[k + "Stripped"] = hex
            const r = parseInt(hex.substring(0, 2), 16)
            const g = parseInt(hex.substring(2, 4), 16)
            const b = parseInt(hex.substring(4, 6), 16)
            out[k + "Rgb"] = r + "," + g + "," + b
        }
        return out
    }

    // Mapa de tokens que consumen Templates/gtk/gtk3.css y gtk4.css.
    function gtkTokens() {
        const p = currentPalette
        const accent = colorHex(resolvedAccent)
        const warning = darkMode ? p.yellow : (p.lightYellow || p.yellow)
        const success = darkMode ? p.green  : (p.lightGreen  || p.green)
        const destructive = darkMode ? p.red : (p.lightRed || p.red)

        if (darkMode) {
            return {
                accent: accent, accent_fg: p.bg,
                destructive: destructive, destructive_fg: readableOn(destructive),
                error: destructive, error_fg: readableOn(destructive),
                warning: warning, warning_bg: warning, warning_fg: readableOn(warning),
                success: success, success_bg: success, success_fg: readableOn(success),
                window_bg: p.bg, window_fg: p.fg,
                view_bg: p.bgAlt, view_fg: p.fg,
                headerbar_bg: p.bg, headerbar_fg: p.fg,
                popover_bg: p.surface, popover_fg: p.fg,
                card_bg: p.surface, card_fg: p.fg,
                dialog_bg: p.bgAlt, dialog_fg: p.fg,
                overview_bg: p.surface, overview_fg: p.fg,
                sidebar_bg: p.bg, sidebar_fg: p.fgDim,
                secondary_sidebar_bg: p.bg, secondary_sidebar_fg: p.fgDim,
                legacy_border: p.overlay
            }
        }
        // 'view' (listas/entradas de Nautilus, campos de texto): se iguala al
        // color de la barra (headerbar = lightBgAlt), más apagado, para un
        // blanco que no deslumbra en modo claro.
        return {
            accent: (p.lightAccent || accent), accent_fg: "#ffffff",
            destructive: destructive, destructive_fg: readableOn(destructive),
            error: destructive, error_fg: readableOn(destructive),
            warning: warning, warning_bg: warning, warning_fg: readableOn(warning),
            success: success, success_bg: success, success_fg: readableOn(success),
            window_bg: p.lightBg, window_fg: p.lightFg,
            view_bg: p.lightBgAlt, view_fg: p.lightFg,
            headerbar_bg: p.lightBgAlt, headerbar_fg: p.lightFg,
            popover_bg: p.lightSurface, popover_fg: p.lightFg,
            card_bg: p.lightSurface, card_fg: p.lightFg,
            dialog_bg: p.lightBg, dialog_fg: p.lightFg,
            overview_bg: p.lightSurface, overview_fg: p.lightFg,
            sidebar_bg: p.lightBg, sidebar_fg: (p.lightFgDim || p.lightFg),
            secondary_sidebar_bg: p.lightBg, secondary_sidebar_fg: (p.lightFgDim || p.lightFg),
            legacy_border: (p.lightOverlay || p.lightSurface)
        }
    }

    // Motor de plantillas mínimo: sustituye {{clave}} por tokens[clave]. Deja
    // intacto cualquier {{...}} sin correspondencia (para detectar erratas
    // a simple vista en vez de borrarlas en silencio).
    function renderTemplate(text, tokens) {
        return String(text).replace(/\{\{(\w+)\}\}/g, function (whole, key) {
            return tokens[key] !== undefined ? tokens[key] : whole
        })
    }

    // Asegura que gtk.css importe quickshell.css, sin pisar nada que ya
    // hubiera ahí: si el import ya está, no toca el archivo; si no, lo añade
    // al final (o crea el archivo si no existía). 'view' es el FileView que
    // apunta al gtk.css real del usuario.
    function ensureGtkImport(view) {
        const content = view.text() || ""
        if (content.indexOf("@import") !== -1 && content.indexOf("quickshell.css") !== -1)
            return
        const importLine = "@import url(\"quickshell.css\");"
        const trimmed = content.replace(/\s+$/, "")
        view.setText(trimmed.length > 0 ? (trimmed + "\n\n" + importLine + "\n") : (importLine + "\n"))
    }

    property bool _gtkPendingRefresh: false
    // Tematiza apps GTK3/GTK4/libadwaita (Nautilus, GNOME apps…): renderiza
    // las plantillas de Templates/gtk/ e inyecta el @import en gtk.css SIN
    // pisar lo que ya hubiera ahí (ensureGtkImport, FileView puro). El
    // refresco (refresh=true) se dispara en gtk4CssFile.onSaved, así que la
    // marca se pone antes de escribir — reinicia Nautilus reabriendo su
    // carpeta, porque GTK4/libadwaita no recarga CSS en caliente; en el
    // arranque se llama con false para no reiniciar nada. El modo
    // claro/oscuro se sincroniza aparte vía gsettings, directo (un binario
    // con sus argumentos, no un script). El tema base GTK3 (adw-gtk3) no se
    // toca: queda a mano del usuario, vía nwg-look.
    function applyGtkTheme(refresh) {
        if (!templatesOn || !gtkThemingEnabled)
            return
        _gtkPendingRefresh = (refresh === true)
        const tokens = gtkTokens()
        gtk4CssFile.setText(renderTemplate(gtk4Template.text(), tokens))
        gtk3CssFile.setText(renderTemplate(gtk3Template.text(), tokens))
        ensureGtkImport(gtk4RealCssFile)
        ensureGtkImport(gtk3RealCssFile)
        const mode = darkMode ? "dark" : "light"
        gtkAppearanceSync.command = ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-" + mode]
        if (!gtkAppearanceSync.running)
            gtkAppearanceSync.running = true
    }

    function scheduleGtkSync() {
        if (_loaded)
            gtkSyncTimer.restart()
    }

    // fontconfig (~/.config/fontconfig/fonts.conf)
    // Gestionado desde Tipografía: combina la fuente elegida (fontFamily /
    // monoFontFamily) como familia preferida + los ajustes de render (subpíxel
    // RGB, hinting). Afecta a Brave, Discord, GTK, Qt.
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
    // fontconfig). Así el subpíxel/hinting elegido sí llega a GTK. No tocamos
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
    onAnimationSpeedChanged: scheduleSave()
    onCustomAnimationDurationChanged: scheduleSave()
    // Las opacidades solo afectan al shell (el CSS de GTK va siempre opaco),
    // así que no disparan scheduleGtkSync: reescribiría gtk.css idéntico y
    // reiniciaría Nautilus sin efecto visible.
    onBarOpacityChanged: scheduleSave()
    onPopupOpacityChanged: scheduleSave()
    onWidgetOpacityChanged: scheduleSave()
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
    onCaffeineChanged: scheduleSave()
    onShowCaffeineChanged: scheduleSave()
    onTemplatesOnChanged: { scheduleSave(); if (templatesOn) { scheduleGtkSync(); scheduleHyprSync() } }
    onGtkThemingEnabledChanged: { scheduleSave(); if (gtkThemingEnabled) scheduleGtkSync() }
    onHyprlandThemingEnabledChanged: { scheduleSave(); if (hyprlandThemingEnabled) scheduleHyprSync() }
    onTemplatesEnabledChanged: scheduleSave()
    onClock24hChanged: scheduleSave()
    onClockShowSecondsChanged: scheduleSave()
    onClockShowDateChanged: scheduleSave()
    onWeatherEnabledChanged: scheduleSave()
    onWeatherLocationChanged: scheduleSave()
    onWeatherMetricChanged: scheduleSave()
    onWeatherRefreshMinChanged: scheduleSave()
    onWeatherShowForecastChanged: scheduleSave()
    onWeatherForecastDaysChanged: scheduleSave()
    onWeatherShowDetailsChanged: scheduleSave()
    onWeatherShowWindChanged: scheduleSave()
    onWeatherShowRainChanged: scheduleSave()
    onWeatherShowSunChanged: scheduleSave()
    onWeatherShowInBarChanged: scheduleSave()
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
    onWeatherCacheChanged: scheduleSave()

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

    // Solo se escribe (setText en applyHyprlandThemeNow); su contenido nunca
    // se lee, así que no necesita carga síncrona (blockLoading) al arrancar.
    FileView {
        id: hyprThemeFile
        path: s.home + "/.config/hypr/conf/theme.lua"
        printErrors: false
        atomicWrites: true
    }

    // Plantillas GTK (Templates/gtk/): se LEEN en cada aplicación, no solo al
    // arrancar, para que un cambio a mano en el archivo se note sin reiniciar
    // el shell. blockLoading: lectura síncrona, como el resto de plantillas
    // de este archivo (son pocos KB).
    FileView {
        id: gtk4Template
        path: s.home + "/.config/quickshell/Templates/gtk/gtk4.css"
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: gtk3Template
        path: s.home + "/.config/quickshell/Templates/gtk/gtk3.css"
        blockLoading: true
        printErrors: false
    }

    // Salida YA renderizada de las plantillas de arriba. Vive en un archivo
    // PROPIO (quickshell.css), no en gtk.css: gtk.css es del usuario y
    // ensureGtkImport() solo le asegura un @import a este, sin pisar nada
    // más que hubiera ahí.
    FileView {
        id: gtk4CssFile
        path: s.home + "/.config/gtk-4.0/quickshell.css"
        atomicWrites: true
        printErrors: false
    }
    // gtk.css real del usuario: solo se le añade el @import si falta
    // (ensureGtkImport). watchChanges (activo por defecto) recarga __text
    // solo si lo tocas a mano fuera del shell.
    FileView {
        id: gtk4RealCssFile
        path: s.home + "/.config/gtk-4.0/gtk.css"
        blockLoading: true
        printErrors: false
        atomicWrites: true
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
        path: s.home + "/.config/gtk-3.0/quickshell.css"
        atomicWrites: true
        printErrors: false
    }
    FileView {
        id: gtk3RealCssFile
        path: s.home + "/.config/gtk-3.0/gtk.css"
        blockLoading: true
        printErrors: false
        atomicWrites: true
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

    // Crea la carpeta de destino de theme.lua una sola vez al arrancar (si
    // Hyprland está activo): FileView no crea directorios por sí solo, y
    // sin esto el primer setText() a hyprThemeFile fallaría en silencio si
    // el usuario nunca ha tenido nada en conf/. applyHyprlandThemeNow()
    // espera a que termine (onExited), no se dispara en paralelo.
    Process {
        id: hyprConfDirMkdir
        command: ["mkdir", "-p", s.home + "/.config/hypr/conf"]
        onExited: (code, status) => s.applyHyprlandThemeNow()
    }

    Process {
        id: hyprReload
        command: ["hyprctl", "reload"]
    }

    Timer {
        id: gtkSyncTimer
        interval: 400
        onTriggered: s.applyGtkTheme(true)
    }

    // Sincroniza modo claro/oscuro + tema base GTK3 por gsettings/dconf
    // (comando armado en applyGtkTheme). El @import en gtk.css y la escritura
    // de los CSS (quickshell.css) van por los FileView de arriba, sin shell.
    Process {
        id: gtkAppearanceSync
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

    // Carpetas XDG del usuario (localizadas), resueltas UNA vez para todo el
    // shell: aquí componen wallpaperDirs (<imágenes>/Wallpapers +
    // ~/.config/wallpapers) y Services/ScreenCapture.qml las consume por
    // binding para capturas/grabaciones (antes cada uno lanzaba su proceso).
    property string xdgPicturesDir: home + "/Pictures"
    property string xdgVideosDir: home + "/Videos"
    Process {
        id: xdgPicturesProc
        command: ["sh", "-c",
            "printf 'pictures='; xdg-user-dir PICTURES 2>/dev/null || echo \"$HOME/Pictures\"; " +
            "printf 'videos='; xdg-user-dir VIDEOS 2>/dev/null || echo \"$HOME/Videos\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (text || "").trim().split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const p = lines[i].indexOf("=")
                    if (p <= 0) continue
                    const k = lines[i].substring(0, p)
                    const v = lines[i].substring(p + 1).trim()
                    if (k === "pictures" && v !== "") s.xdgPicturesDir = v
                    else if (k === "videos" && v !== "") s.xdgVideosDir = v
                }
                s.wallpaperDirs = [s.xdgPicturesDir + "/Wallpapers", s.home + "/.config/wallpapers"]
            }
        }
    }

    Component.onCompleted: {
        load()
        if (hyprlandAvailable)
            hyprConfDirMkdir.running = true
        xdgPicturesProc.running = true   // resuelve la carpeta de imágenes XDG
        applyGtkTheme(false)   // genera quickshell.css y fija color-scheme (sin reiniciar apps)
        applyFontsConf()       // genera ~/.config/fontconfig/fonts.conf (render + fuente)
    }
}

