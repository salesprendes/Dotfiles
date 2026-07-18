pragma Singleton
// Paleta 'salesprendes' (modo oscuro), con escala dp. El greeter corre antes
// de la sesión y no lee settings.json, así que los colores van fijos aquí:
// se mantienen a mano en sintonía con themePresets.salesprendes de
// Config/Settings.qml.
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property color bg:        "#070722"
    readonly property color surface:   "#11112d"
    readonly property color surfaceHi: "#15153b"
    readonly property color overlay:   "#21215f"
    readonly property color fg:        "#f3edf7"
    readonly property color fgDim:     "#7c80b4"
    readonly property color fgMuted:   "#535681"
    readonly property color accent:    "#fff59b"
    readonly property color red:       "#fd4663"
    readonly property string font:     "JetBrainsMono Nerd Font"

    // Densidad automática según el monitor mayor
    // (1080p→1.00 · 1440p→~1.15 · 2160p→~1.45).
    readonly property real scale: {
        const list = Quickshell.screens
        let best = null
        for (let i = 0; i < list.length; i++) {
            const sc = list[i]
            if (!sc) continue
            if (!best || (sc.width * sc.height) > (best.width * best.height))
                best = sc
        }
        if (!best) return 1.0
        const shortSide = Math.min(best.width || 1920, best.height || 1080)
        return Math.max(0.85, Math.min(1.6, 1.0 + (shortSide / 1080 - 1) * 0.45))
    }
    function dp(v) { return Math.round(v * scale) }
    function sp(v) { return Math.max(9, Math.round(v * scale)) }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
}
