import QtQuick
import Quickshell

// Densidad automática a partir del monitor de mayor resolución (lado corto
// relativo a 1080p: 1080p→~1.00 · 1440p→~1.15 · 4K→~1.45). Sin dependencias de
// Settings a propósito: el greeter corre antes de la sesión y comparte esta
// fórmula sin arrastrar la lectura de settings.json.
//
// No es singleton adrede: Theme lo instancia como hijo, porque referenciar un
// singleton desde otro durante el arranque del motor se evalúa a undefined y la
// escala se queda clavada en el mínimo.
//
// El binding se recalcula al conectar, desconectar o cambiar de modo, porque lee
// Quickshell.screens y width/height, que QML rastrea.
QtObject {
    id: scale

    // Lados cortos de todas las pantallas, en píxeles lógicos: si el compositor
    // ya escala un 4K a 2, Quickshell reporta 1920 y aquí no hay que volver a
    // escalar nada.
    readonly property var shortSides: {
        const out = []
        const list = Quickshell.screens
        for (let i = 0; i < list.length; i++) {
            const sc = list[i]
            if (sc)
                out.push(Math.min(sc.width || 1920, sc.height || 1080))
        }
        return out
    }

    readonly property real density: {
        const sides = scale.shortSides
        if (sides.length === 0)
            return 1.0
        let best = 0
        for (let i = 0; i < sides.length; i++)
            if (sides[i] > best)
                best = sides[i]
        return Math.max(0.85, Math.min(1.6, 1.0 + (best / 1080 - 1) * 0.45))
    }

    // La escala es global, una sola para todo el shell. Con monitores de
    // resoluciones lógicas distintas se calcula con el más grande y se aplica
    // también al pequeño, que queda con la interfaz sobredimensionada. No es
    // catastrófico —los anchos de panel se recortan contra el ancho de pantalla—
    // pero se nota. La solución por monitor exige que Theme deje de ser un
    // singleton, y eso son las mil llamadas a Theme.dp() del shell.
    //
    // Lo indicado es que el compositor escale, y entonces esta cuenta da 1.0 para
    // las dos pantallas. Por eso Ajustes avisa cuando detecta la mezcla.
    //
    // 15 %: por debajo la diferencia no se ve y avisar sería ruido.
    readonly property bool mixed: {
        const sides = scale.shortSides
        if (sides.length < 2)
            return false
        let min = sides[0], max = sides[0]
        for (let i = 1; i < sides.length; i++) {
            if (sides[i] < min) min = sides[i]
            if (sides[i] > max) max = sides[i]
        }
        return min > 0 && (max / min) > 1.15
    }
}
