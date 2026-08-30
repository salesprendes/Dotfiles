pragma Singleton
// Paleta del greeter (modo oscuro), con escala dp. El greeter corre antes de
// la sesión, como usuario 'greeter', y NO puede leer settings.json (el HOME
// del usuario es 0700), así que no hereda el tema elegido en Ajustes. Lo que
// sí puede leer es su propio fondo (/etc/greetd/wall.png), y de ahí deriva la
// paleta con la MISMA fórmula que el tema "dynamic" de la sesión
// (Config/DynamicPalette.qml). Así el login entona con el escritorio sin
// depender de nada del usuario.
import QtQuick
import Quickshell
import qs.Config as Shared

Singleton {
    id: root

    // ── Curvas de movimiento de Material 3 ───────────────────────────────────
    // LAS MISMAS que Config/Theme.qml, y repetidas a propósito: el greeter
    // corre ANTES de la sesión y tiene su propio Theme justamente para no
    // arrastrar Settings ni el resto del shell. Importar el otro por seis
    // constantes traería toda esa dependencia a la pantalla de inicio.
    //
    // Si se tocan allí, hay que tocarlas aquí. Son seis números que no van a
    // cambiar —son el estándar de Material 3— así que el coste de la copia es
    // menor que el de acoplar el greeter al shell.
    readonly property var curveEmphasized:      [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
    readonly property var curveEmphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var curveEmphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
    readonly property var curveStandard:        [0.2, 0, 0, 1, 1, 1]
    readonly property var curveSpatial:         [0.38, 1.21, 0.22, 1.00, 1, 1]
    readonly property var curveEffects:         [0.34, 0.80, 0.34, 1.00, 1, 1]

    // La paleta la calcula GreeterSurface, no este singleton: un Canvas
    // necesita una escena para pintar y aquí dentro nunca lo haría. Llega por
    // applyFromPixels con los píxeles de una miniatura del fondo.
    readonly property Shared.DynamicPalette _paletteMath: Shared.DynamicPalette {}
    property var dynamicPalette: ({})
    function applyFromPixels(data) {
        dynamicPalette = _paletteMath.fromPixels(data)
    }

    // Respaldo mientras el extractor aún no ha calculado nada (primer frame),
    // o si el fondo no existe / no se puede leer: el greeter nunca sale sin
    // color, solo sin personalizar.
    readonly property var fallbackPalette: ({
        bg:      "#070722", surface: "#11112d", surfaceHi: "#15153b",
        overlay: "#21215f", fg:      "#f3edf7", fgDim:     "#7c80b4",
        fgMuted: "#535681", accent:  "#fff59b", red:       "#fd4663"
    })
    readonly property var palette: dynamicPalette.bg !== undefined ? dynamicPalette
                                                                   : fallbackPalette

    readonly property color bg:        palette.bg
    readonly property color surface:   palette.surface
    readonly property color surfaceHi: palette.surfaceHi
    readonly property color overlay:   palette.overlay
    readonly property color fg:        palette.fg
    readonly property color fgDim:     palette.fgDim
    readonly property color fgMuted:   palette.fgMuted
    readonly property color accent:    palette.accent
    readonly property color red:       palette.red
    // Mismos nombres que el Theme de la sesión (Config/Theme.qml) a propósito:
    // es lo que permite que un componente de Components/ funcione igual aquí y
    // allí, y por tanto que el greeter reutilice en vez de duplicar.
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    // El greeter va siempre en oscuro: no lee settings.json, así que no hay
    // modo claro que seguir. Se expone porque los componentes compartidos
    // preguntan por él.
    readonly property bool isDark: true

    // Densidad automática compartida con el tema principal (Config/Scale.qml,
    // sin dependencias de Settings: seguro de importar antes de la sesión).
    readonly property Shared.Scale _densitySource: Shared.Scale {}
    readonly property real scale: _densitySource.density
    function dp(v) { return Math.round(v * scale) }
    function sp(v) { return Math.max(9, Math.round(v * scale)) }
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
}
