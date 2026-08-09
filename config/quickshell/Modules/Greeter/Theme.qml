pragma Singleton
// Paleta fija del greeter (modo oscuro), con escala dp. El greeter corre
// antes de la sesión y no lee settings.json, así que los colores van fijos
// aquí, independientes de los presets de Config/Settings.qml.
import QtQuick
import Quickshell
import qs.Config as Shared

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

    // Densidad automática compartida con el tema principal (Config/Scale.qml,
    // sin dependencias de Settings: seguro de importar antes de la sesión).
    readonly property Shared.Scale _densitySource: Shared.Scale {}
    readonly property real scale: _densitySource.density
    function dp(v) { return Math.round(v * scale) }
    function sp(v) { return Math.max(9, Math.round(v * scale)) }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
}
