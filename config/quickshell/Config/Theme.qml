pragma Singleton

import QtQuick
import Quickshell
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Tema "Solitude": paleta global, radios, espaciado y escala visual.
//  Singleton global: usa Theme.<prop> desde cualquier componente.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: theme

    //  Conmutado por Settings.darkMode desde el Centro de control.
    //  Todo lo demás deriva de estos colores para cambiar en bloque.
    readonly property bool isDark: Settings.darkMode

    readonly property var palette: Settings.currentPalette

    // ── Paleta base ──────────────────────────────────────────
    readonly property color bg:        isDark ? palette.bg        : palette.lightBg
    readonly property color bgAlt:     isDark ? palette.bgAlt     : palette.lightBgAlt
    readonly property color surface:   isDark ? palette.surface   : palette.lightSurface
    readonly property color surfaceHi: isDark ? palette.surfaceHi : palette.lightSurfaceHi
    readonly property color overlay:   isDark ? palette.overlay   : palette.lightOverlay

    readonly property color fg:        isDark ? palette.fg        : palette.lightFg
    readonly property color fgDim:     isDark ? palette.fgDim     : palette.lightFgDim
    readonly property color fgMuted:   isDark ? palette.fgMuted   : palette.lightFgMuted

    // ── Acentos ──────────────────────────────────────────────
    readonly property color accent:    Settings.resolvedAccent
    // En modo claro usa la variante oscura del acento secundario (si existe)
    // para que iconos como el de Bluetooth contrasten sobre fondo claro.
    readonly property color accent2:   isDark ? palette.accent2
                                              : (palette.lightAccent2 || palette.accent2)
    // Colores semánticos: en modo claro usan su variante oscura (lightX) para
    // contrastar sobre fondo claro; en oscuro, el valor normal de la paleta.
    readonly property color cyan:      isDark ? palette.cyan    : (palette.lightCyan    || palette.cyan)
    readonly property color green:     isDark ? palette.green   : (palette.lightGreen   || palette.green)
    readonly property color yellow:    isDark ? palette.yellow  : (palette.lightYellow  || palette.yellow)
    readonly property color orange:    isDark ? palette.orange  : (palette.lightOrange  || palette.orange)
    readonly property color red:       isDark ? palette.red     : (palette.lightRed     || palette.red)
    readonly property color magenta:   isDark ? palette.magenta : (palette.lightMagenta || palette.magenta)

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    readonly property color barBg:      withAlpha(bg, Settings.barOpacity)
    readonly property color popupBg:    withAlpha(bg, Settings.popupOpacity)
    // Superficie anidada dentro de un popup (chips/filas sobre la tarjeta).
    readonly property color popupSurface: withAlpha(surface, Math.min(1, Settings.popupOpacity + 0.05))
    readonly property color pillBg:     withAlpha(surface, Settings.widgetOpacity)

    //  densityScale se deriva AUTOMÁTICAMENTE de la resolución del
    //  monitor mayor conectado (lado corto/vertical relativo a 1080p).
    //  uiScale y fontScale del usuario MULTIPLICAN encima (1.0 = neutro):
    //     escala_final = densityScale × uiScale
    //  Curva (lado corto):  1080p→~1.00 · 1440p→~1.15 · 2160p(4K)→~1.45
    property real uiScale: Settings.uiScale
    readonly property real densityScale: autoDensity()
    readonly property real scale: clamp(uiScale * densityScale, 0.7, 1.9)

    // Densidad automática a partir del monitor de mayor resolución.
    // El binding se recalcula al conectar/desconectar o cambiar de modo
    // (lee Quickshell.screens y width/height, que QML rastrea).
    function autoDensity() {
        const list = Quickshell.screens
        let best = null
        for (let i = 0; i < list.length; i++) {
            const sc = list[i]
            if (!sc)
                continue
            if (!best || (sc.width * sc.height) > (best.width * best.height))
                best = sc
        }
        if (!best)
            return 1.0
        const shortSide = Math.min(best.width || 1920, best.height || 1080)
        return clamp(1.0 + (shortSide / 1080 - 1) * 0.45, 0.85, 1.6)
    }

    function dp(value) {
        return Math.round(value * scale)
    }

    function sp(value) {
        return Math.max(9, Math.round(value * scale * fontScale))
    }

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value))
    }

    // Densidad de UNA pantalla concreta × uiScale (misma curva que el
    // auto global). Hoy el escalado es global; esto queda disponible por
    // si se quiere escalado per-pantalla real en el futuro.
    function screenScale(screen) {
        if (!screen)
            return scale
        const shortSide = Math.min(screen.width || 1920, screen.height || 1080)
        const density = clamp(1.0 + (shortSide / 1080 - 1) * 0.45, 0.85, 1.6)
        return clamp(uiScale * density, 0.7, 1.9)
    }

    function panelWidth(screen, desired, minValue, maxRatio) {
        const sw = screen ? screen.width : 1920
        const margin = barMargin * 2
        const maxByRatio = Math.round(sw * (maxRatio || 0.92))
        return Math.max(dp(minValue || 300), Math.min(dp(desired), maxByRatio, sw - margin))
    }

    // ── Geometría / espaciado (tokens derivados) ─────────────
    readonly property int hairline: 1
    readonly property int space2: dp(2)
    readonly property int space4: dp(4)
    readonly property int space6: dp(6)
    readonly property int space8: dp(8)
    readonly property int space10: dp(10)
    readonly property int space12: dp(12)
    readonly property int space14: dp(14)
    readonly property int space16: dp(16)
    readonly property int space18: dp(18)

    readonly property int controlXS: dp(22)
    readonly property int controlS: dp(26)
    readonly property int controlM: dp(30)
    readonly property int controlL: dp(38)
    readonly property int rowS: dp(34)
    readonly property int rowM: dp(38)
    readonly property int rowL: dp(48)
    readonly property int tileM: dp(54)
    readonly property int tileL: dp(64)

    readonly property int   barHeight:   dp(Math.round(38 * Settings.barScale))
    readonly property int   barMargin:   dp(8)       // separación del borde
    // Factor de redondeo amplificado: por debajo del 100% es lineal
    // (de casi-cuadrado a normal); por encima crece x2.2 para que subir
    // hasta el 160% se note claramente más redondeado (≈ doble de radio).
    readonly property real  cornerFactor: Settings.cornerScale <= 1.0
                                           ? Settings.cornerScale
                                           : 1.0 + (Settings.cornerScale - 1.0) * 2.2
    readonly property int   barRadius:   dp(Math.round(10 * cornerFactor))
    readonly property int   pillRadius:  dp(Math.round(8 * cornerFactor))
    readonly property int   gap:         space8       // entre grupos
    readonly property int   pad:         space10      // padding interno pill
    readonly property int   spacing:     space6       // entre items dentro de pill

    // ── Tipografía ───────────────────────────────────────────
    readonly property string fontFamily: Settings.fontFamily
    readonly property string monoFontFamily: Settings.monoFontFamily
    readonly property real   fontScale: Settings.fontScale
    readonly property int    fontSize:    sp(13)
    readonly property int    iconSize:    sp(15)

    readonly property int   animFast:   Settings.animFastMs
    readonly property int   animNormal: Settings.animNormalMs
}
