pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Almacén de ajustes persistente y fuente de verdad. Se guarda en
// ~/.config/quickshell/settings.json; los demás módulos leen de aquí.
Singleton {
    id: s

    readonly property string home: Quickshell.env("HOME") ?? ""

    // Apariencia
    property string themeName: "dynamic"
    property string accentName: "theme"
    property color  accentColor: resolvedAccent
    property bool   darkMode: true      // false = variante clara de Solitude
    // ¿Hyprland es el compositor activo ahora mismo? Se mira la variable de
    // entorno que pone al arrancar, no 'which': eso solo diría si el paquete
    // está instalado.
    readonly property bool hyprlandAvailable: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "") !== ""
    // Interruptor maestro de plantillas: pausa el sistema entero sin tocar qué
    // apps tenía marcadas cada una, así que al reactivar vuelve a lo que había.
    property bool   templatesOn: true
    // Tematizado GTK (ver Ajustes → Plantillas y Templates/gtk/).
    property bool   gtkThemingEnabled: true
    // Tematizado Hyprland (ver Ajustes → Plantillas y applyHyprlandThemeNow).
    property bool   hyprlandThemingEnabled: true
    // Bloq Núm encendido: se aplica al arrancar el shell y al conmutarlo, vía
    // la opción numlock_by_default de Hyprland (API Lua).
    property bool   numlockOn: false
    // Resto de plantillas: mapa id → activada, todas apagadas por defecto. GTK
    // y Hyprland quedan aparte, arriba, con su propio interruptor.
    property var    templatesEnabled: ({})
    // Proveedor activo del asistente y, por proveedor, el modelo y su
    // credencial. Las claves se guardan en claro como el resto de ajustes: es
    // un archivo local del usuario.
    property string aiProvider: "gemini"
    property string aiModelGemini: "gemini-2.5-flash"
    property string aiModelOpenrouter: "qwen/qwen3-30b-a3b:free"
    property string aiModelOllama: "qwen3"
    property string aiKeyGemini: ""
    property string aiKeyOpenrouter: ""
    property string aiOllamaUrl: "http://127.0.0.1:11434"
    // Proveedor "Servidor": cualquier servidor compatible con la API de OpenAI,
    // pensado ante todo para uno remoto. La URL es la base /v1 —se normaliza y
    // admite host a secas— y la clave es opcional.
    property string aiCustomUrl: ""
    property string aiModelCustom: ""
    property string aiKeyCustom: ""
    // Cabecera HTTP extra para servidores tras una pasarela ("Nombre: valor").
    property string aiCustomHeader: ""
    // Aceptar certificados TLS no verificables (servidor propio con certificado
    // autofirmado). Solo afecta a Servidor y Ollama.
    property bool   aiInsecureTls: false
    // Panel ancho: más sitio para leer código y respuestas largas.
    property bool   aiWide: false
    // Estilo de respuesta: "normal" | "concise" | "teacher" | "reviewer".
    property string aiPersona: "normal"
    // Modo del asistente: "chat" (solo conversación) o "agent" (herramientas
    // con aprobación). Planificar no es un modo: lo decide el agente al leer el
    // encargo, proponiendo con propose_plan cuando la tarea lo merece.
    property string aiMode: "chat"
    // Instrucciones extra del usuario, añadidas al prompt de sistema.
    property string aiCustomPrompt: ""
    // Heredado: hoy la aprobación la decide aiApproval y este valor solo sirve
    // para migrar.
    property bool   aiAutoRead: false
    // Cuánta correa lleva el agente, en un solo control. La aprobación de cada
    // herramienta sale de su clase de riesgo, así que no hay que decidir lo
    // mismo cuarenta veces:
    //   "careful"  pregunta siempre, incluso para leer
    //   "normal"   lee y consulta sola; escribir y ejecutar preguntan
    //   "auto"     actúa sin preguntar (menos ask_user, que es una pausa)
    property string aiApproval: "normal"
    // Registro de auditoría en data/ai-audit.jsonl: qué ejecutó el agente y por
    // qué se le dejó. Sobrevive a /limpiar y a cambiar de conversación, cosa que
    // el historial del chat no puede hacer porque se compacta y se borra.
    property bool aiAudit: true
    // Supervisor: un segundo modelo mirando al agente.
    //   "off"    nadie mira
    //   "risky"  solo lo que puede hacer daño (riesgo 2+, comandos destructivos,
    //            enlaces que salen de la carpeta personal)
    //   "all"    todas las llamadas — solo con un modelo rápido
    // Cuesta una llamada extra por cada cosa supervisada.
    property string aiSupervisor: "risky"
    // Qué modelo supervisa; vacío = el mismo que el agente. Lo interesante es
    // uno pequeño y rápido del mismo servidor: vigilar es más fácil que
    // trabajar, y así el segundo par de ojos casi no cuesta.
    property string aiSupervisorModel: ""
    // Excepciones por herramienta, por encima del modo: mapa nombre → "ask"
    // (pedir aprobación) | "auto" (sin preguntar) | "off" (el modelo ni la ve).
    // Vacío = manda el modo.
    property var    aiToolPolicies: ({})
    // Habilidades: mapa nombre → false para apagar una. Lo que no esté en el
    // mapa cuenta como encendida, porque instalar la carpeta ya es quererla.
    property var    aiSkills: ({})
    // Servidores MCP (transporte stdio): lista de {name, command}. Cada uno es
    // un proceso hijo que publica herramientas; el modelo las ve como
    // mcp__<name>__<tool> y pasan por la misma tarjeta de aprobación que las
    // nativas.
    property var    aiMcpServers: []
    // A quién se le pregunta: "searxng" (propio o local detectado), "brave" o
    // "tavily". Si el elegido falla se prueban los demás configurados.
    //
    // Hay que elegir algo porque las instancias públicas de SearXNG ya no
    // sirven format=json a un cliente sin navegador, y los buscadores generales
    // responden con un captcha.
    property string aiSearchBackend: "searxng"
    // URL de un SearXNG con la API JSON activa (formats: [json] en su
    // settings.yml). Vacío = solo se prueban las instancias locales.
    property string aiSearchUrl: ""
    // Clave del buscador elegido. Respaldo en claro: la de verdad vive en el
    // llavero del sistema, igual que las de los proveedores de modelos.
    property string aiKeySearch: ""
    // Servidores remotos de confianza (lista blanca para SSH/SFTP/hosting):
    // lista de {name, host, user, port}. El modelo solo puede conectarse a los
    // registrados aquí, por su nombre. Las contraseñas van al llavero y, sin
    // llavero, al mapa de abajo.
    property var    aiSshHosts: []
    // Respaldo en claro de las contraseñas SSH, solo cuando no hay llavero o
    // falló; con llavero funcional este mapa se queda vacío.
    property var    aiSshPasswords: ({})
    // Temperatura del modelo (parámetro universal del contrato).
    property real   aiTemperature: 0.7
    // Ventana de contexto del modelo, en tokens; 0 = automático (32k con
    // servidor propio, 128k en la nube). De aquí salen el recorte del historial,
    // el tope de cada resultado de herramienta y el medidor.
    property int    aiContextTokens: 0
    // Interruptor suave de razonamiento: "auto" no toca nada y "think"/
    // "no_think" se añaden al mensaje del usuario. Un servidor que no lo
    // entienda lo ignora.
    property string aiThink: "auto"
    // Los tres ajustes siguientes solo hacen algo si el modelo está reconocido
    // en ModelProfile.js; con cualquier otro son inertes.
    //
    // Esfuerzo de razonamiento: "auto" deja que el harness lo reparta por tarea,
    // o se fija a mano en low | medium | xhigh.
    property string aiEffort: "auto"
    // Usar los parámetros de muestreo que recomiendan los autores del modelo:
    // con la temperatura equivocada, el mismo modelo pasa de resolver la tarea a
    // irse por las ramas.
    property bool   aiModelTuning: true
    // Reenviar al modelo su propio razonamiento de turnos anteriores, en los que
    // saben aprovecharlo: es lo que le permite retomar una tarea larga donde la
    // dejó en vez de volver a razonarla entera.
    property bool   aiKeepThinking: true
    // Compactación del contexto: "manual" (solo /compactar) | "warn" (avisa
    // al llenarse) | "auto" (se compacta solo al llenarse).
    property string aiAutoCompact: "warn"
    // Turnos recientes (pregunta+respuesta) que sobreviven a la compactación.
    property int    aiCompactKeep: 1

    property real   uiScale: 1.0
    // Zoom automático: deriva la densidad de la resolución del monitor (ver
    // Config/Scale.qml). Apagado, manda solo uiScale.
    property bool   autoDensity: true
    property int    animationSpeed: 2   // 0 none | 1 short | 2 medium | 3 long | 4 custom
    property int    customAnimationDuration: 500
    property real   barOpacity: 0.78    // opacidad del fondo de la barra
    property real   popupOpacity: 0.85
    property real   widgetOpacity: 0.55

    // Opacidad efectiva. Los nombres eff*/set* los usan Theme y los sliders de
    // Ajustes.
    readonly property real effBarOpacity:    barOpacity
    readonly property real effPopupOpacity:  popupOpacity
    readonly property real effWidgetOpacity: widgetOpacity
    function setBarOpacity(v)    { barOpacity = v }
    function setPopupOpacity(v)  { popupOpacity = v }
    function setWidgetOpacity(v) { widgetOpacity = v }
    property real   cornerScale: 1.0    // multiplicador del redondeo
    property real   barScale: 1.0       // multiplicador de la altura de barra
    // Disposición de la barra: borde de pantalla donde vive y si va flotante
    // (separada con margen y esquinas) o pegada a sangre de borde a borde.
    property string barPosition: "top"  // top | bottom
    property bool   barFloating: true
    // Velo que oscurece el escritorio mientras hay un panel abierto (0 = no).
    property real   panelBackdropDim: 0.0
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

    // Terminal: aquí van los parámetros no-color. La paleta la genera el
    // servicio Terminal a partir del tema.
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
        // Paletas de temas conocidos. Los tonos intermedios
        // (bgAlt/surfaceHi/fgMuted) y el naranja se derivan, porque no existen
        // en las originales. Los colores semánticos salen de la paleta ANSI de
        // terminal de cada una, corregidos para garantizar contraste WCAG sobre
        // el fondo de cada modo.
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
        { text: "Dinámico", value: "dynamic" },
        { text: "Ayu", value: "ayu" },
        { text: "Catppuccin", value: "catppuccin" },
        { text: "Dracula", value: "dracula" },
        { text: "Eldritch", value: "eldritch" },
        { text: "Gruvbox", value: "gruvbox" },
        { text: "Kanagawa", value: "kanagawa" },
        { text: "Nord", value: "nord" },
        { text: "Rosé Pine", value: "rose-pine" },
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
    // Con el tema "dynamic" la paleta viene del extractor del fondo. Mientras no
    // haya una calculada, o ante un nombre inválido, se pinta con el preset base.
    readonly property var currentPalette:
        themeName === "dynamic" && dynamicPalette.bg !== undefined ? dynamicPalette
        : themePresets[themeName] || themePresets["tokyo-night"]
    readonly property color resolvedAccent: accentFor(accentName)

    // Base de las tres velocidades: 100 / 200 / 400 ms, moduladas por un
    // multiplicador continuo en vez de tres valores sueltos por paso. El paso
    // "Medium" es speed = 1.0, sin modular.
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
    // Los paneles recorren mucha distancia —se despliega la tarjeta entera— y
    // con la duración normal el barrido no llega a verse. Base propia de 360 ms
    // modulada por la misma velocidad global; en modo custom manda la duración
    // elegida tal cual.
    readonly property int animBasePopout: 360
    readonly property int popoutAnimationMs: normalizedAnimationSpeed === 4
        ? customAnimationDuration
        : (_speedFactor === 0 ? 0 : Math.round(animBasePopout / _speedFactor))

    // Cafeína: inhibe la inactividad, así que no se suspende ni se bloquea.
    // Vive aquí y no en Globals para sobrevivir a los reinicios del shell. El
    // proceso inhibidor lo levanta shell.qml leyendo este estado.
    property bool   caffeine: false

    // "No molestar": silencia los avisos y sobrevive a los reinicios, como
    // 'caffeine'. El precio de que persista es que se puede olvidar encendido,
    // y lo paga el icono de la campana de la barra, que se ve tachado mientras
    // lo esté.
    //
    // Vive en Settings y no en Globals para que IslandState pueda consultarlo
    // antes de encolar un aviso sin importar el singleton de los paneles, que no
    // pinta nada en esto y cerraría un ciclo entre los dos.
    property bool   dnd: false

    // La píldora del centro de la barra que se transforma según lo que pasa y se
    // abre en hoja al pulsarla. Con ella encendida la sección central de la barra
    // no se dibuja, pero no se borra del layout: apagándola vuelve como estaba.
    property bool   keepAwakeOnMedia: true
    property bool   islandEnabled: true
    property bool   islandShowWeather: true
    // Apartarse cuando una ventana ocupa la pantalla entera. Afecta a lo que vive
    // en la capa Overlay y no es urgente: la isla y, con la isla apagada, los
    // avisos clásicos que la sustituyen. Se quedan a propósito el OSD de volumen
    // —se sube mientras se ve el vídeo— y la píldora de grabación.
    property bool   hideOnFullscreen: true

    // Dos formas de dock: "pill" es una pastilla flotante y centrada, del ancho
    // de su contenido, y "hotseat" una barra ancha pegada al borde. Cambian solo
    // en geometría: la fila, el botón, la vista previa y el menú son los mismos.
    property bool   dockEnabled: true
    property string dockStyle: "pill"            // pill | hotseat
    // Ids de .desktop, en el orden elegido arrastrando. Lo sanea DockCatalog.
    property var    dockPinned: []
    property bool   dockShowRunning: true
    // "smart" enseña el dock solo con el escritorio vacío (el del monitor,
    // no el de la sesión); "always" lo esconde salvo al rozar el borde;
    // "never" lo deja fijo.
    property string dockAutoHide: "smart"        // smart | always | never
    // Zona exclusiva. Solo tiene efecto con dockAutoHide "never": reservar un
    // hueco para algo que está escondido dejaría una franja vacía permanente.
    property bool   dockReserveSpace: false
    // Nombres de conector ("DP-1"). Vacío = todos los monitores.
    property var    dockOnlyMonitors: []
    // 32 y no 48: con iconos mayores la pastilla queda apretada y se lee como una
    // barra de herramientas en vez de como un dock.
    property int    dockIconSize: 32
    property int    dockSpacing: 8
    property int    dockPadding: 8
    property real   dockOpacity: 0.78
    // -1 = lo decide el estilo. Una sola clave para las dos formas, para que
    // cambiar de estilo no arrastre un radio pensado para el otro.
    property int    dockRadius: -1
    property real   dockMagnify: 1.12            // 1.0 = sin lupa
    // "auto" es rayita con una ventana y puntos con varias, que es lo que más
    // información da por píxel; el resto son formas fijas.
    property string dockRunningIndicator: "auto" // auto | line | dots | count | none
    // "mono" mete cada icono en un círculo de acento y lo tiñe del mismo color:
    // queda coherente, y el precio es perder el color de marca de cada app, así
    // que con muchas fijadas hay que distinguirlas por la silueta. "color" deja
    // los iconos como son.
    property string dockIconStyle: "mono"        // mono | color
    property bool   dockShadow: true
    property bool   dockShowLauncher: true
    property bool   dockShowSpotlight: true
    property bool   dockNotifBadges: true
    property bool   dockPreviews: true

    // Emojis usados últimamente, los más recientes primero: casi todo el uso real
    // son las mismas veinte caras.
    property var emojiRecent: []

    // "shell" usa la pantalla de bloqueo propia (Services/Lock.qml), con el mismo
    // tema, paleta e idioma que el resto; "hyprlock" delega en hyprlock. Si el
    // servicio PAM elegido no existe, el shell cae a hyprlock por su cuenta aunque
    // aquí ponga "shell".
    property string lockBackend: "shell"
    // Servicio de /etc/pam.d/ con el que autenticar. Vacío = automático
    // (hyprlock si está, si no login).
    property string lockPamService: ""

    // Qué enseña la pantalla de bloqueo además del campo de contraseña. Cada
    // bloque se apaga por separado: es lo que ve quien pase por delante de la
    // mesa, y no todo el mundo quiere que ahí salga qué está escuchando.
    property bool   lockShowMedia: true          // reproductor y sus controles
    property bool   lockShowWeather: true        // ciudad y temperatura
    property bool   lockShowStatus: true         // red y batería
    property bool   lockShowSessionButtons: true // suspender, reiniciar, apagar
    // Desenfoque del fondo, 0 = nítido. Es un multiplicador sobre el radio máximo
    // y no píxeles, así que se ve igual en 1080p que en 4K.
    property real   lockBlur: 0.75
    // Oscurecido del fondo por encima del desenfoque.
    property real   lockDim: 0.45

    // Qué widgets se ven, en qué sección y en qué orden:
    //   { "left": [{"id":"launcher"}, …], "center": [...], "right": [...] }
    // El catálogo de ids vive en Config/BarCatalog.qml, y la migración v2
    // convierte los booleanos de visibilidad que había antes.
    property var    barLayout: BarCatalog.defaultLayout()

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

    // Notificaciones
    property bool   notifPopupsEnabled: true
    // Duración en pantalla por urgencia: un aviso de urgencia baja no debe durar
    // lo mismo que uno crítico. notifTimeout es la urgencia normal y conserva el
    // nombre para no invalidar los settings.json ya guardados.
    property int    notifTimeoutLow: 4          // segundos
    property int    notifTimeout: 5             // segundos (urgencia normal)
    // 0 = no expira: se queda hasta descartarlo, como espera la especificación de
    // freedesktop para lo crítico.
    property int    notifTimeoutCritical: 0     // segundos (0 = nunca)
    property int    notifMaxVisible: 4
    // Esquina de los popups clásicos. Solo se usa con la isla apagada: la isla
    // vive donde vive la barra y no tiene esquina que elegir.
    property string notifPosition: "tr"        // tr | tl | br | bl
    // Barra de cuenta atrás en el popup: enseña cuánto le queda antes de irse.
    property bool   notifShowProgress: true
    // Modo compacto: solo el título, sin el cuerpo del mensaje.
    property bool   notifCompact: false
    property var    mutedNotificationApps: []

    // Avisos de batería. Los umbrales son configurables porque un porcentaje fijo
    // son horas con una batería grande y minutos con una gastada.
    property bool   batteryNotifyLow: true
    property int    batteryLowThreshold: 15      // %
    property bool   batteryNotifyCritical: true
    property int    batteryCriticalThreshold: 5  // %

    // El aviso flotante de volumen.
    property bool   osdEnabled: true
    // Como notifPosition: solo manda con la isla apagada.
    property string osdPosition: "bottom"      // top | bottom
    property real   osdTimeout: 1.6            // segundos en pantalla

    // Transición que aplica Background/Backdrop.qml al cambiar de fondo:
    // fade | zoom | slide | push | wipe.
    property string wallpaperTransition: "fade"
    property real   wallpaperTransitionDuration: 1.0
    // Carpetas de fondos. La de imágenes se resuelve con `xdg-user-dir
    // PICTURES` al arrancar; no se persiste ni se edita.
    property var    wallpaperDirs: [home + "/.config/wallpapers"]
    property string wallpaperCurrent: ""  // último fondo aplicado (ruta absoluta)
    // Rotación automática: minutos entre cambios (0 = apagada) y orden aleatorio
    // o secuencial. La ejecuta Services/Wallpaper.qml.
    property int    wallpaperAutoMin: 0
    property bool   wallpaperRandom: true
    // Encaje cuando la proporción de la imagen no coincide con la pantalla:
    // crop recorta lo que sobra, fit deja franjas y stretch deforma.
    property string wallpaperFillMode: "crop"   // crop | fit | stretch

    // Paleta dinámica calculada desde el fondo activo por el extractor de la
    // barra. Se persiste para que un arranque nuevo pinte con ella al instante
    // sin esperar al análisis de imagen.
    property var dynamicPalette: ({})

    // Última respuesta buena del clima con su marca de tiempo: al arrancar, el
    // panel pinta desde aquí y solo consulta la API si el dato ya caducó.
    property var weatherCache: ({})

    // Avatar del usuario: ruta absoluta a una imagen, o vacío para la inicial en
    // un círculo tonal.
    property string avatarPath: ""

    // Captura de pantalla / grabación
    // Ajustes del servicio ScreenCapture. Él los sanea con sus rangos y enums al
    // aplicarlos; aquí solo se valida que sea un objeto JSON.
    property var screenCapture: ({})

    // Persistencia
    property bool _loaded: false

    // Claves persistidas: las de _defaults más accentColor, que no tiene default
    // estático porque se deriva de accentName.
    readonly property var _keys: Object.keys(_defaults).concat(["accentColor"])

    // Valores por defecto de todas las claves persistidas: la única lista que
    // hay que mantener, porque _keys se deriva de aquí y el guardado automático
    // se conecta recorriéndola. Al añadir un ajuste hay que añadirlo también
    // aquí. accentColor no aparece: su default es resolvedAccent y reset() lo
    // recalcula al final.
    readonly property var _defaults: ({
        "themeName": "dynamic", "accentName": "theme", "darkMode": true,
        "aiProvider": "gemini", "aiModelGemini": "gemini-2.5-flash",
        "aiModelOpenrouter": "qwen/qwen3-30b-a3b:free", "aiModelOllama": "qwen3",
        "aiKeyGemini": "", "aiKeyOpenrouter": "", "aiOllamaUrl": "http://127.0.0.1:11434",
        "aiCustomUrl": "", "aiModelCustom": "", "aiKeyCustom": "",
        "aiCustomHeader": "", "aiInsecureTls": false, "aiWide": false,
        "aiPersona": "normal", "aiMode": "chat", "aiCustomPrompt": "", "aiAutoRead": false,
        "aiApproval": "normal", "aiAudit": true,
        "aiSupervisor": "risky", "aiSupervisorModel": "",
        "aiToolPolicies": {}, "aiSkills": {}, "aiMcpServers": [],
        "aiSearchBackend": "searxng", "aiSearchUrl": "", "aiKeySearch": "",
        "aiSshHosts": [], "aiSshPasswords": {}, "aiTemperature": 0.7, "aiContextTokens": 0,
        "aiAutoCompact": "warn", "aiCompactKeep": 1, "aiThink": "auto",
        "aiEffort": "auto", "aiModelTuning": true, "aiKeepThinking": true,
        "uiScale": 1.0, "autoDensity": true, "animationSpeed": 2, "customAnimationDuration": 500, "barOpacity": 0.78,
        "popupOpacity": 0.85, "widgetOpacity": 0.55,
        "cornerScale": 1.0, "barScale": 1.0,
        "barPosition": "top", "barFloating": true, "panelBackdropDim": 0.0,
        "fontFamily": "JetBrainsMono Nerd Font", "monoFontFamily": "JetBrainsMono Nerd Font", "fontScale": 1.0,
        "fontAntialias": true, "fontHinting": true, "fontHintstyle": "hintslight",
        "fontRgba": "rgb", "fontLcdfilter": "lcddefault", "fontEmbeddedbitmap": false,
        "language": "es",
        "barLayout": BarCatalog.defaultLayout(),
        "lockBackend": "shell", "lockPamService": "",
        "lockShowMedia": true, "lockShowWeather": true, "lockShowStatus": true,
        "lockShowSessionButtons": true, "lockBlur": 0.75, "lockDim": 0.45,
        "keepAwakeOnMedia": true,
        "islandEnabled": true, "islandShowWeather": true, "hideOnFullscreen": true,
        "dockEnabled": true, "dockStyle": "pill", "dockPinned": [],
        "dockShowRunning": true, "dockAutoHide": "smart", "dockReserveSpace": false,
        "dockOnlyMonitors": [], "dockIconSize": 32, "dockSpacing": 8,
        "dockPadding": 8, "dockOpacity": 0.78, "dockRadius": -1,
        "dockMagnify": 1.12, "dockRunningIndicator": "auto",
        "dockNotifBadges": true, "dockPreviews": true,
        "dockIconStyle": "mono", "dockShadow": true,
        "dockShowLauncher": true, "dockShowSpotlight": true,
        "notifPosition": "tr", "osdPosition": "bottom",
        "emojiRecent": [],
        "caffeine": false, "dnd": false,
        "templatesOn": true, "gtkThemingEnabled": true, "hyprlandThemingEnabled": true, "templatesEnabled": ({}),
        "numlockOn": false,
        "clock24h": true, "clockShowSeconds": false, "clockShowDate": true,
        "weatherEnabled": true, "weatherLocation": "", "weatherMetric": true, "weatherRefreshMin": 30,
        "weatherShowForecast": true, "weatherForecastDays": 5, "weatherShowDetails": true, "weatherShowWind": false,
        "weatherShowRain": false, "weatherShowSun": false,
        "notifPopupsEnabled": true, "notifTimeout": 5, "notifTimeoutLow": 4, "notifTimeoutCritical": 0,
        "notifMaxVisible": 4,
        "notifShowProgress": true, "notifCompact": false,
        "mutedNotificationApps": [],
        "batteryNotifyLow": true, "batteryLowThreshold": 15,
        "batteryNotifyCritical": true, "batteryCriticalThreshold": 5,
        "osdEnabled": true, "osdTimeout": 1.6,
        "wallpaperTransition": "fade", "wallpaperTransitionDuration": 1.0, "wallpaperCurrent": "", "avatarPath": "",
        "wallpaperAutoMin": 0, "wallpaperRandom": true, "wallpaperFillMode": "crop",
        "dynamicPalette": ({}), "weatherCache": ({}),
        "terminalApp": "kitty", "terminalFont": "", "terminalFontSize": 11.5, "terminalOpacity": 0.80,
        "terminalPadding": 12, "terminalCursorShape": "beam", "terminalCursorBlink": true,
        "terminalLineHeight": 2, "terminalTabStyle": "powerline", "terminalLigatures": true,
        "screenCapture": {}
    })

    // Saneamiento de lo cargado: rangos numéricos que se recortan a [min,max] y
    // conjuntos válidos. Lo que no encaje se ignora y conserva su default.
    readonly property var _numBounds: ({
        "uiScale": [0.5, 2.0], "animationSpeed": [0, 4],
        "customAnimationDuration": [50, 3000], "barOpacity": [0.0, 1.0],
        "popupOpacity": [0.0, 1.0], "widgetOpacity": [0.0, 1.0],
        "cornerScale": [0.0, 2.0],
        "barScale": [0.5, 2.0], "fontScale": [0.5, 2.0], "weatherRefreshMin": [1, 1440], "weatherForecastDays": [3, 7],
        "notifTimeout": [1, 120], "notifTimeoutLow": [1, 120], "notifTimeoutCritical": [0, 120],
        "notifMaxVisible": [1, 20],
        "batteryLowThreshold": [5, 50], "batteryCriticalThreshold": [1, 30],
        "osdTimeout": [0.5, 6.0],
        "wallpaperTransitionDuration": [0.1, 5.0],
        "panelBackdropDim": [0.0, 0.7], "wallpaperAutoMin": [0, 1440],
        "lockBlur": [0.0, 1.0], "lockDim": [0.0, 0.9],
        "dockIconSize": [24, 96], "dockSpacing": [0, 32], "dockPadding": [0, 32],
        "dockOpacity": [0.0, 1.0], "dockRadius": [-1, 40], "dockMagnify": [1.0, 1.6]
    })
    readonly property var _enums: ({
        "language": ["en", "es", "ca"],
        "notifPosition": ["tl", "tr", "bl", "br"],
        "osdPosition": ["top", "bottom"],
        "lockBackend": ["shell", "hyprlock"],
        "barPosition": ["top", "bottom"],
        "wallpaperTransition": ["fade", "zoom", "slide", "push", "wipe"],
        "wallpaperFillMode": ["crop", "fit", "stretch"],
        "fontHintstyle": ["hintnone", "hintslight", "hintmedium", "hintfull"],
        "fontRgba": ["none", "rgb", "bgr", "vrgb", "vbgr"],
        "fontLcdfilter": ["none", "lcddefault", "lcdlight", "lcdlegacy"],
        "dockStyle": ["pill", "hotseat"],
        "dockAutoHide": ["smart", "always", "never"],
        "dockRunningIndicator": ["auto", "line", "dots", "count", "none"],
        "dockIconStyle": ["mono", "color"]
    })
    // Claves que deben ser enteros (se redondean tras recortar).
    readonly property var _intKeys: ["animationSpeed", "customAnimationDuration",
        "weatherRefreshMin", "weatherForecastDays", "notifTimeout", "notifMaxVisible",
        "wallpaperAutoMin",
        "dockIconSize", "dockSpacing", "dockPadding", "dockRadius"]

    // Devuelve un valor válido para 'k', o undefined si hay que descartarlo y
    // conservar el default. Infiere el tipo esperado del propio default.
    function sanitize(k, val) {
        // Enums: solo valores de la lista.
        if (_enums[k] !== undefined)
            return _enums[k].indexOf(val) !== -1 ? val : undefined
        // accentColor: cadena hex de color.
        if (k === "accentColor")
            return (typeof val === "string" && /^#?[0-9a-fA-F]{3,8}$/.test(val)) ? val : undefined
        if (k === "emojiRecent") {
            if (!Array.isArray(val)) return undefined
            return val.filter(x => typeof x === "string" && x !== "").slice(0, 40)
        }
        if (k === "mutedNotificationApps") {
            if (!Array.isArray(val)) return undefined
            return val.every(x => typeof x === "string") ? val : undefined
        }
        // La disposición de la barra la sanea su catálogo: descarta ids que ya
        // no existen y duplicados de widgets de instancia única, y garantiza las
        // tres secciones. Es lo que protege de un settings.json editado a mano o
        // traído de una versión con otros widgets.
        if (k === "barLayout") {
            if (!val || typeof val !== "object" || Array.isArray(val)) return undefined
            return BarCatalog.sanitize(val)
        }
        // Las fijadas del dock, con el mismo reparto: normaliza claves, quita
        // duplicados y basura, y corta en el tope.
        if (k === "dockPinned")
            return Array.isArray(val) ? DockCatalog.sanitize(val) : undefined
        // Nombres de conector de monitor. No se puede validar que existan —un
        // monitor desenchufado sigue siendo una elección válida—, así que solo se
        // comprueba que sean cadenas con algo dentro.
        if (k === "dockOnlyMonitors") {
            if (!Array.isArray(val)) return undefined
            return val.filter(x => typeof x === "string" && x !== "")
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

    // settings.json lleva "_version". Sin él, cambiar la FORMA de un ajuste
    // rompe en silencio las configuraciones guardadas: load() lee clave a clave,
    // ignora lo que no reconoce y el save() del final borra el rastro del valor
    // viejo. Con versión y migraciones, un cambio de forma se declara una vez y
    // lo antiguo se convierte al cargar.
    readonly property int schemaVersion: 3

    // Cada entrada transforma el objeto JSON crudo —antes del saneado por
    // clave— desde la versión anterior hasta 'to'. Se aplican en orden, así que
    // un archivo de v0 pasa por todas, y mutan el objeto que reciben.
    readonly property var _migrations: [
        {
            to: 2,
            // Los booleanos de visibilidad de la barra pasan a ser presencia en
            // barLayout. Se respeta lo que estuviera apagado; el orden es el de
            // fábrica, porque en v1 no había orden que preservar.
            apply: function (o) {
                if (o.barLayout !== undefined)
                    return                       // ya migrado a mano
                const on = function (key, byDefault) {
                    return typeof o[key] === "boolean" ? o[key] : byDefault
                }
                const layout = BarCatalog.defaultLayout()
                const drop = []
                if (!on("showTray", true))          drop.push("tray")
                if (!on("showSysmon", true))        drop.push("sysmon")
                if (!on("showBattery", true))       drop.push("battery")
                if (!on("showClipboard", true))     drop.push("clipboard")
                if (!on("showNotifications", true)) drop.push("notifications")
                if (!on("showPowerProfile", true))  drop.push("power")
                if (!on("showAi", true))            drop.push("ai")
                for (const sec of BarCatalog.sections)
                    layout[sec] = layout[sec].filter(e => drop.indexOf(e.id) === -1)
                // Estos dos vienen apagados de fábrica y no están en el layout
                // por defecto: se añaden solo si estaban encendidos.
                if (on("showCaffeine", false))
                    layout.right.splice(Math.max(0, layout.right.length - 3), 0,
                                        { id: "caffeine" })
                if (on("weatherShowInBar", false))
                    layout.center.splice(Math.min(1, layout.center.length), 0,
                                         { id: "weather" })
                o.barLayout = layout
            }
        },
        {
            to: 3,
            // Entrada inerte. Se conserva para no dejar un hueco en la
            // numeración ni dejar a quien ya migró en una versión inexistente.
            apply: function (o) {}
        }
    ]

    // Lleva el objeto crudo a la versión actual y devuelve la versión de la que
    // venía, para poder avisar de lo que se ha hecho.
    function migrate(o) {
        // Sin marca de versión es un archivo anterior al versionado.
        let from = (typeof o._version === "number" && isFinite(o._version))
                 ? Math.floor(o._version) : 1
        if (from >= schemaVersion)
            return from
        for (const m of _migrations) {
            if (m.to <= from)
                continue
            try {
                m.apply(o)
            } catch (e) {
                console.warn("Settings: falló la migración a v" + m.to + ":", e)
            }
            from = m.to
        }
        console.log("Settings: configuración migrada a v" + schemaVersion)
        return from
    }

    // El dock viene encendido y, con autoocultar inteligente, se ve justo cuando
    // no hay ninguna ventana abierta. Con 'dockPinned' vacío eso sería estrenarlo
    // mirando una pastilla vacía, así que la primera vez se siembra.
    //
    // Se siembra con lo que de verdad esté instalado, comprobado contra
    // DesktopEntries: una lista fija de ids serían iconos rotos en cualquier
    // máquina ajena. Y la marca de "ya sembrado" es que la clave exista en el
    // archivo, no un booleano aparte, para que quien vacíe la lista a propósito
    // no se la encuentre repoblada al arrancar.
    property bool _dockNeedsSeed: true

    readonly property var _dockSeedRoles: [
        ["firefox", "zen", "librewolf", "chromium", "google-chrome", "brave-browser"],
        ["org.gnome.Nautilus", "org.kde.dolphin", "thunar", "nemo", "pcmanfm"],
        ["code", "codium", "org.gnome.TextEditor", "org.kde.kate", "nvim"]
    ]

    function _dockEntryExists(id) {
        if (!id || id === "")
            return false
        return DesktopEntries.heuristicLookup(id) !== null
    }

    function _sembrarDock() {
        if (!_dockNeedsSeed || !_loaded)
            return
        // DesktopEntries se puebla de forma asíncrona: sin entradas todavía, la
        // siembra daría una lista vacía y gastaría su única oportunidad.
        if ((DesktopEntries.applications?.values ?? []).length === 0)
            return
        _dockNeedsSeed = false

        const semilla = []
        if (_dockEntryExists(terminalApp))
            semilla.push(terminalApp)
        for (const rol of _dockSeedRoles)
            for (const id of rol)
                if (_dockEntryExists(id)) {
                    semilla.push(id)
                    break
                }
        dockPinned = DockCatalog.sanitize(semilla)
        save()
    }

    // DesktopEntries se puebla en ráfagas. Sin rebote, la siembra se dispararía
    // con la primera entrada que llegue y gastaría su única oportunidad sobre una
    // lista a medio hacer.
    readonly property Timer _dockSeedDebounce: Timer {
        interval: 400
        onTriggered: s._sembrarDock()
    }

    readonly property Connections _dockSeedWatch: Connections {
        target: DesktopEntries
        function onApplicationsChanged() { s._dockSeedDebounce.restart() }
    }

    function load() {
        const t = file.text()
        if (t && t.trim() !== "") {
            try {
                const o = JSON.parse(t)
                // Un archivo más nuevo que este shell se carga igual —el saneado
                // por clave protege de valores raros— pero el save() del final lo
                // reescribiría con la forma vieja, perdiendo lo que aquí no se
                // entiende. Se guarda una copia antes de tocarlo.
                if (typeof o._version === "number" && o._version > schemaVersion) {
                    console.warn("Settings: el archivo es de v" + o._version
                                 + " y este shell entiende hasta v" + schemaVersion
                                 + ". Se guarda copia en settings.json.bak")
                    Quickshell.execDetached(["cp", "--", file.path, file.path + ".bak"])
                }
                migrate(o)
                // Si el archivo ya trae 'dockPinned', su lista manda aunque esté
                // vacía. Ver _sembrarDock().
                if (o.dockPinned !== undefined)
                    _dockNeedsSeed = false
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
        // La opción de Hyprland no persiste entre sesiones, así que se re-aplica
        // en cada arranque. Solo si se ha pedido: con el ajuste apagado no se
        // toca nada, por si lo gestiona la config de Hyprland.
        if (numlockOn)
            applyNumlock()
        // Si DesktopEntries ya está poblado, siembra en cuanto se estabilice; si
        // no, lo hará el Connections de arriba.
        _dockSeedDebounce.restart()
        // Reescribe siempre tras cargar. normalizeSavedSettings() corrige en
        // memoria lo que ya no existe, pero corre con _loaded todavía en false y
        // su scheduleSave() se descarta, así que el archivo se quedaría con el
        // valor muerto y con claves de ajustes eliminados. Guardar aquí lo deja
        // saneado, y también cubre que no hubiera archivo válido.
        save()
    }

    function scheduleSave() {
        if (_loaded)
            saveTimer.restart()
    }

    function save() {
        if (!_loaded) return
        const o = {}
        // Primera clave del archivo a propósito: quien lo abra a mano ve de qué
        // versión es sin bucear.
        o._version = schemaVersion
        for (const k of _keys) o[k] = s[k]
        // accentColor es un QColor: serializado tal cual sería un objeto que
        // sanitize() rechaza al cargar, así que se persiste como "#rrggbb".
        o.accentColor = colorHex(accentColor)
        file.setText(JSON.stringify(o, null, 2))
    }

    // Restaura cada clave persistida a su valor de declaración. Arrays y objetos
    // se copian para no compartir la referencia del mapa de defaults, y
    // accentColor se recalcula aparte porque se deriva de accentName.
    function reset() {
        for (const k in _defaults) {
            const v = _defaults[k]
            s[k] = Array.isArray(v) ? v.slice()
                 : (v !== null && typeof v === "object") ? Object.assign({}, v)
                 : v
        }
        accentColor = resolvedAccent
        // Aparte del bucle: la copia de arriba es superficial y compartiría los
        // arrays de secciones con el mapa de defaults, de modo que mutarlos in
        // situ corrompería los valores de fábrica para toda la sesión.
        barLayout = BarCatalog.defaultLayout()
    }

    // Claves que difieren de su default sin que nadie las haya tocado, porque se
    // autorrellenan al arrancar: screenCapture con sus propios valores,
    // wallpaperCurrent con el fondo elegido o asignado, y weatherCache y
    // dynamicPalette como cachés de runtime. Compararlas siempre daría
    // "modificado" y dejaría el botón Restablecer visible en permanencia. reset()
    // sí las restaura si de verdad se pulsa.
    readonly property var _volatileKeys: ({ "screenCapture": true, "wallpaperCurrent": true,
                                            "weatherCache": true, "dynamicPalette": true })

    // ¿Difiere esta clave de su valor por defecto? Lo usa el filtro "solo
    // modificados". accentColor queda fuera porque no está en _defaults.
    function isModified(key) {
        if (_volatileKeys[key])
            return false
        const def = _defaults[key]
        if (def === undefined)
            return false
        const cur = s[key]
        // Arrays y objetos: comparación estructural, porque por referencia daría
        // siempre "modificado".
        if (def !== null && typeof def === "object")
            return JSON.stringify(cur) !== JSON.stringify(def)
        // Los reales llevan coma flotante: un == exacto marcaría como modificado
        // un valor que ha ido y vuelto por un slider.
        if (typeof def === "number" && typeof cur === "number")
            return Math.abs(cur - def) > 1e-6
        return cur !== def
    }

    // ¿Hay algo que restablecer? Gatea el botón de Ajustes, que no tiene sentido
    // si no cambiaría nada.
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

    // La matemática de color (OKLab y derivación de la paleta) vive en
    // Config/DynamicPalette.qml, porque el greeter necesita la misma fórmula y no
    // puede depender de este singleton. Aquí solo se cachea el resultado.

    // La matemática de color (OKLab + derivación de la paleta) vive en
    // Config/DynamicPalette.qml: el greeter necesita la MISMA fórmula y no
    // puede depender de este singleton. Aquí solo se cachea el resultado.
    readonly property DynamicPalette _paletteMath: DynamicPalette {}

    // Recibe los píxeles RGBA de una miniatura del fondo y guarda la paleta que
    // sale de ellos.
    function computeDynamicPalette(data) {
        setDynamicPalette(_paletteMath.fromPixels(data))
    }

    function setDynamicPalette(p) {
        dynamicPalette = p
        scheduleSave()
    }

    function hasThemePreset(name) {
        return name === "dynamic" || themePresets[name] !== undefined
    }

    // Corrige un tema o acento guardado que ya no exista, volviendo al valor por
    // defecto en vez de dejar la app con una paleta inválida.
    function normalizeSavedSettings() {
        if (!hasThemePreset(themeName))
            themeName = "dynamic"
        if (!hasAccentPreset(accentName))
            accentName = "theme"
        // Si los valores del proveedor "Servidor" siguen siendo los de ejemplo,
        // se vacían para que el campo pida la URL en vez de heredar un servidor
        // local inexistente.
        if (aiCustomUrl === "http://127.0.0.1:8080/v1")
            aiCustomUrl = ""
        if (aiModelCustom === "local")
            aiModelCustom = ""
        // El modo "plan" ya no existe: pasa a "agent", donde el agente propone
        // el plan por su cuenta.
        if (aiMode === "plan")
            aiMode = "agent"
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

    // Tabla Lua con los colores del tema, para que el hyprland.lua del usuario
    // haga require() de este archivo y los aplique con hl.config(). Incluye los
    // colores de grupo de ventanas además de los bordes normales, con accent2
    // como secundario del grupo activo y rojo fijo para el estado bloqueado.
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
            "    -- Interruptor de la plantilla: conf/animations.lua aplica las",
            "    -- animaciones personalizadas solo si esto es true; en false",
            "    -- Hyprland se queda con sus animaciones por defecto.",
            "    animations = " + ((templatesOn && hyprlandThemingEnabled) ? "true" : "false") + ",",
            "",
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

    // Vuelca hyprThemeLua() en theme.lua y recarga Hyprland. No hace nada si
    // Hyprland no está corriendo, el maestro de plantillas está en pausa o esta
    // plantilla está desactivada.
    function applyHyprlandThemeNow() {
        if (!hyprlandAvailable || !templatesOn || !hyprlandThemingEnabled)
            return
        hyprThemeFile.setText(hyprThemeLua())
        if (!hyprReload.running)
            hyprReload.running = true
    }

    // Al apagar la plantilla, o el maestro, no basta con dejar de sincronizar: se
    // escribe theme.lua una última vez con animations=false y se recarga, para
    // que las animaciones se quiten al momento. Los colores conservan su último
    // valor, porque volver a los de fábrica a mitad de sesión sería más brusco.
    function hyprTemplateOffSync() {
        if (!_loaded || !hyprlandAvailable)
            return
        hyprThemeFile.setText(hyprThemeLua())
        if (!hyprReload.running)
            hyprReload.running = true
    }

    // Blanco o casi-negro según la claridad del color, para los roles sin
    // convención previa en el shell. Usa la claridad percibida (OKLab) y no la
    // luminancia Rec.709, que pondera tanto el verde que pone texto negro sobre
    // verdes y cianes medios donde el blanco se lee mejor.
    function readableOn(hex) {
        hex = String(hex).replace("#", "")
        const r = parseInt(hex.substring(0, 2), 16) / 255
        const g = parseInt(hex.substring(2, 4), 16) / 255
        const b = parseInt(hex.substring(4, 6), 16) / 255
        return _paletteMath.rgbToOklab(r, g, b).L > 0.62 ? "#1a1a1a" : "#ffffff"
    }

    // Mezcla lineal de dos colores hex (t=0 → a, t=1 → b), para derivar los
    // niveles que la paleta no tiene explícitos.
    function mix(hexA, hexB, t) {
        const a = String(hexA).replace("#", ""), b = String(hexB).replace("#", "")
        const ar = parseInt(a.substring(0, 2), 16), ag = parseInt(a.substring(2, 4), 16), ab = parseInt(a.substring(4, 6), 16)
        const br = parseInt(b.substring(0, 2), 16), bg = parseInt(b.substring(2, 4), 16), bb = parseInt(b.substring(4, 6), 16)
        const r = Math.round(ar + (br - ar) * t), g = Math.round(ag + (bg - ag) * t), bl = Math.round(ab + (bb - ab) * t)
        const h = (n) => n.toString(16).padStart(2, "0")
        return "#" + h(r) + h(g) + h(bl)
    }

    // Aproximación de los roles de Material 3 a partir de la paleta del shell,
    // que tiene bastantes menos campos. No es un motor HCT: es una derivación
    // razonable para que las plantillas de cada app tengan de dónde sacar cada
    // rol sin reescribirlas.
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
        // 'view' se iguala al color de la barra, más apagado, para un blanco que
        // no deslumbre en modo claro.
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

    // Motor de plantillas mínimo: sustituye {{clave}} por tokens[clave] y deja
    // intacto lo que no tenga correspondencia, para que una errata se vea en vez
    // de borrarse en silencio.
    function renderTemplate(text, tokens) {
        return String(text).replace(/\{\{(\w+)\}\}/g, function (whole, key) {
            return tokens[key] !== undefined ? tokens[key] : whole
        })
    }

    // Asegura que gtk.css importe quickshell.css sin pisar nada de lo que ya
    // hubiera: si el import está, no toca el archivo; si no, lo añade al final o
    // crea el archivo. 'view' es el FileView del gtk.css real del usuario.
    function ensureGtkImport(view) {
        const content = view.text() || ""
        if (content.indexOf("@import") !== -1 && content.indexOf("quickshell.css") !== -1)
            return
        const importLine = "@import url(\"quickshell.css\");"
        const trimmed = content.replace(/\s+$/, "")
        view.setText(trimmed.length > 0 ? (trimmed + "\n\n" + importLine + "\n") : (importLine + "\n"))
    }

    property bool _gtkPendingRefresh: false
    // Tematiza apps GTK3/GTK4/libadwaita: renderiza las plantillas de
    // Templates/gtk/ e inyecta el @import en gtk.css sin pisar lo que hubiera.
    //
    // El refresco reinicia Nautilus reabriendo su carpeta, porque GTK4 no recarga
    // CSS en caliente; se dispara en gtk4CssFile.onSaved, así que la marca se
    // pone antes de escribir, y en el arranque se llama con false para no
    // reiniciar nada. El modo claro/oscuro se sincroniza aparte vía gsettings.
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

    // fontconfig: combina la fuente elegida como familia preferida con los
    // ajustes de render (subpíxel RGB, hinting). Afecta a las apps GTK y Qt.
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
    // Traduce los ajustes de render a las claves de gsettings que leen las apps
    // GTK, que las toman de ahí y no de fontconfig. No se toca font-name: la
    // fuente de UI de GTK se deja como esté.
    function gtkFontRenderCmds() {
        // antialiasing: sin AA → none; con AA y orden subpíxel → rgba; si no,
        // grayscale.
        const aa = !fontAntialias ? "none" : (fontRgba !== "none" ? "rgba" : "grayscale")
        // hinting: apagado → none; si no, mapea el hintstyle de fontconfig.
        const hintMap = { "hintnone": "none", "hintslight": "slight",
                          "hintmedium": "medium", "hintfull": "full" }
        const hint = !fontHinting ? "none" : (hintMap[fontHintstyle] || "slight")
        // orden subpíxel: solo valores válidos de gsettings; 'none' → rgb.
        const order = (fontRgba === "bgr" || fontRgba === "vrgb" || fontRgba === "vbgr")
                        ? fontRgba : "rgb"
        const g = "gsettings set org.gnome.desktop.interface "
        return g + "font-antialiasing '" + aa + "'; "
             + g + "font-hinting '" + hint + "'; "
             + g + "font-rgba-order '" + order + "'"
    }
    function applyFontsConf() {
        fontsConfFile.setText(fontsConfXml())
        // Asegura la carpeta y aplica el render en gsettings.
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

    // Guardado automático: Component.onCompleted conecta la señal <clave>Changed
    // de todas las claves persistidas a este despachador, en vez de un handler
    // por clave que hubiera que mantener a mano. El caso por defecto es guardar;
    // aquí solo se enumeran las claves con efectos adicionales.
    //
    // Las opacidades no disparan scheduleGtkSync porque solo afectan al shell:
    // reescribirían gtk.css idéntico y reiniciarían Nautilus sin efecto visible.
    function applyNumlock() {
        Quickshell.execDetached(["hyprctl", "eval",
            'hl.config({ input = { numlock_by_default = '
            + (numlockOn ? "true" : "false") + ' } })'])
    }

    function _settingChanged(k) {
        switch (k) {
        case "themeName":
        case "accentName":
        case "darkMode":
            notifyAppearanceChanged()   // incluye scheduleSave()
            return
        case "fontFamily":
        case "monoFontFamily":
        case "fontAntialias":
        case "fontHinting":
        case "fontHintstyle":
        case "fontRgba":
        case "fontLcdfilter":
        case "fontEmbeddedbitmap":
            scheduleSave(); scheduleFontSync()
            return
        case "numlockOn":
            scheduleSave()
            applyNumlock()
            return
        case "templatesOn":
            scheduleSave()
            if (templatesOn) { scheduleGtkSync(); scheduleHyprSync() } else hyprTemplateOffSync()
            return
        case "gtkThemingEnabled":
            scheduleSave()
            if (gtkThemingEnabled) scheduleGtkSync()
            return
        case "hyprlandThemingEnabled":
            scheduleSave()
            if (hyprlandThemingEnabled) scheduleHyprSync(); else hyprTemplateOffSync()
            return
        default:
            scheduleSave()
        }
    }

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

    // Plantillas GTK: se leen en cada aplicación y no solo al arrancar, para que
    // un cambio a mano en el archivo se note sin reiniciar el shell. Lectura
    // síncrona como el resto de plantillas: son pocos KB.
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

    // Salida ya renderizada de las plantillas. Vive en un archivo propio y no en
    // gtk.css, que es del usuario y solo recibe el @import.
    FileView {
        id: gtk4CssFile
        path: s.home + "/.config/gtk-4.0/quickshell.css"
        atomicWrites: true
        printErrors: false
    }
    // gtk.css real del usuario: solo se le añade el @import si falta.
    // watchChanges recarga __text si se toca a mano fuera del shell.
    FileView {
        id: gtk4RealCssFile
        path: s.home + "/.config/gtk-4.0/gtk.css"
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }
    // Al guardar el CSS de GTK4 refresca las apps GTK abiertas. Nautilus lee
    // GTK4, así que basta con este.
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

    // Crea la carpeta de destino de theme.lua una vez al arrancar, si Hyprland
    // está activo: FileView no crea directorios y el primer setText() fallaría en
    // silencio. La escritura espera a que termine, no va en paralelo.
    //
    // Se escribe con la plantilla en ambos estados: si está apagada y theme.lua
    // no existe, el respaldo de conf/animations.lua aplicaría las animaciones
    // igualmente, y la escritura con animations=false mantiene la regla.
    Process {
        id: hyprConfDirMkdir
        command: ["mkdir", "-p", s.home + "/.config/hypr/conf"]
        onExited: (code, status) => {
            if (s.templatesOn && s.hyprlandThemingEnabled)
                s.applyHyprlandThemeNow()
            else
                s.hyprTemplateOffSync()
        }
    }

    // Ráfaga de re-aplicaciones de Bloq Núm tras el arranque. El apply de load()
    // pierde la carrera contra el hyprctl reload de la plantilla, y el listener
    // de configreloaded puede caer antes de que conecte el socket de eventos.
    // Cuatro disparos idempotentes cubren la ventana y luego se callan.
    property int _numlockShots: 0
    Timer {
        interval: 3000
        repeat: true
        running: s._loaded && s.numlockOn && s._numlockShots < 4
        onTriggered: {
            s._numlockShots++
            s.applyNumlock()
        }
    }

    Process {
        id: hyprReload
        command: ["hyprctl", "reload"]
        // La recarga relee la config Lua y pisa las opciones puestas en caliente,
        // así que lo que dependa de ellas se re-aplica al terminar. En el arranque
        // el listener de 'configreloaded' aún no existe, pero este onExited sí.
        onExited: if (s.numlockOn) s.applyNumlock()
    }

    Timer {
        id: gtkSyncTimer
        interval: 400
        onTriggered: s.applyGtkTheme(true)
    }

    // Sincroniza modo claro/oscuro y tema base GTK3 por gsettings. El @import en
    // gtk.css y la escritura de los CSS van por los FileView de arriba.
    Process {
        id: gtkAppearanceSync
    }

    // Reinicia Nautilus reabriendo las mismas carpetas: detecta sus ventanas por
    // la clase en Hyprland y resuelve la carpeta desde el título, cayendo a la
    // carpeta personal si no puede. En Python para evitar problemas de escapado.
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

    // Carpetas XDG del usuario, localizadas y resueltas una sola vez para todo el
    // shell: aquí componen wallpaperDirs y Services/ScreenCapture.qml las consume
    // por binding.
    property string xdgPicturesDir: home + "/Pictures"
    property string xdgVideosDir: home + "/Videos"
    // Las usa el selector de imágenes para su lista de sitios.
    property string xdgDownloadDir: home + "/Downloads"
    property string xdgDesktopDir: home + "/Desktop"
    Process {
        id: xdgPicturesProc
        command: ["sh", "-c",
            "printf 'pictures='; xdg-user-dir PICTURES 2>/dev/null || echo \"$HOME/Pictures\"; " +
            "printf 'videos='; xdg-user-dir VIDEOS 2>/dev/null || echo \"$HOME/Videos\"; " +
            "printf 'download='; xdg-user-dir DOWNLOAD 2>/dev/null || echo \"$HOME/Downloads\"; " +
            "printf 'desktop='; xdg-user-dir DESKTOP 2>/dev/null || echo \"$HOME/Desktop\""]
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
                    else if (k === "download" && v !== "") s.xdgDownloadDir = v
                    else if (k === "desktop" && v !== "") s.xdgDesktopDir = v
                }
                s.wallpaperDirs = [s.xdgPicturesDir + "/Wallpapers", s.home + "/.config/wallpapers"]
            }
        }
    }

    Component.onCompleted: {
        // Conecta el guardado automático antes de load(): durante la carga,
        // scheduleSave y los scheduleSync se descartan porque _loaded es false.
        for (const k of _keys)
            s[k + "Changed"].connect(() => s._settingChanged(k))
        load()
        if (hyprlandAvailable)
            hyprConfDirMkdir.running = true
        xdgPicturesProc.running = true   // resuelve la carpeta de imágenes XDG
        applyGtkTheme(false)   // genera quickshell.css y fija color-scheme (sin reiniciar apps)
        applyFontsConf()       // genera ~/.config/fontconfig/fonts.conf (render + fuente)
    }
}

