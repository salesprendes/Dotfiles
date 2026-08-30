import QtQuick
import qs.Config

// Glifo de icono de la barra: fuente y tamaño unificados para todos los widgets.
// 'sizeDelta' permite ajustes puntuales.
//
// Los glifos de una Nerd Font vienen de una docena de colecciones distintas y cada
// una tiene su propia idea de cuánto aire dejar a los lados, así que la tinta casi
// nunca está en el centro de su caja de avance. Dentro de una píldora centrada eso
// se ve, sobre todo en las de un solo icono y en una fila de píldoras seguidas.
//
// Aquí se mide la caja de tinta real y se compensa la diferencia con relleno a un
// lado. No se toca la vertical a propósito: todos los glifos comparten la línea
// base, y corregirla por glifo los descuadraría entre sí.
//
// El cálculo depende solo de TextMetrics, una medición aparte y no del propio
// Text, así que no hay realimentación: el relleno no depende del ancho que
// produce.
ThemedText {
    id: glyph

    property int sizeDelta: 0
    property bool animateColor: false
    // Se puede apagar donde el glifo va pegado a un texto y lo que importa es
    // el espaciado tipográfico, no el eje de la píldora.
    property bool opticalCenter: true

    color: Theme.fgDim
    font.pixelSize: Theme.barIconSize + sizeDelta

    TextMetrics {
        id: metrics
        font: glyph.font
        text: glyph.text
    }

    // Cuánto hay que empujar la tinta para que su centro coincida con el de la
    // caja. Positivo = hay que moverla a la derecha.
    readonly property real _shift: {
        if (!glyph.opticalCenter || glyph.text === "")
            return 0
        const ink = metrics.tightBoundingRect
        if (!ink || ink.width <= 0)
            return 0
        const box = metrics.advanceWidth
        if (!(box > 0))
            return 0
        const delta = box / 2 - (ink.x + ink.width / 2)
        // Se ignoran las correcciones minúsculas: por debajo de medio píxel no
        // se ve nada y solo sirven para que el ancho de la píldora cambie al
        // cambiar de icono (el del reproductor alterna play/pausa).
        return Math.abs(delta) < 0.5 ? 0 : delta
    }

    leftPadding: Math.max(0, Math.round(glyph._shift))
    rightPadding: Math.max(0, Math.round(-glyph._shift))

    Behavior on color {
        enabled: glyph.animateColor
        ColorAnimation { duration: Theme.animFast }
    }
}
