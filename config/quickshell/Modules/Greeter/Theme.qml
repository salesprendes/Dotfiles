pragma Singleton
//  ╔══════════════════════════════════════════════════════════╗
//  ║   Theme — colores 'solitude' + acento blue, con escala dp  ║
//  ╚══════════════════════════════════════════════════════════╝
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property color bg:        "#101315"
    readonly property color surface:   "#1e2427"
    readonly property color surfaceHi: "#2a3033"
    readonly property color overlay:   "#4b4e55"
    readonly property color fg:        "#cacccc"
    readonly property color fgDim:     "#a5aeb4"
    readonly property color fgMuted:   "#707070"
    readonly property color accent:    "#7aa2f7"
    readonly property color red:       "#de6145"
    readonly property string font:     "JetBrainsMono Nerd Font"

    // Densidad automática según el monitor mayor (misma curva que tu
    // Theme.qml: 1080p→1.00 · 1440p→~1.15 · 2160p→~1.45).
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
    readonly property var locale: Qt.locale("es_ES")
}
