import QtQuick
import Quickshell

// Densidad automática a partir del monitor de mayor resolución (lado corto
// relativo a 1080p: 1080p→~1.00 · 1440p→~1.15 · 4K→~1.45). Sin dependencias
// de Settings a propósito: el greeter corre antes de la sesión y comparte
// esta fórmula sin arrastrar la lectura de settings.json.
//
// NO es singleton adrede: Theme (singleton) lo instancia como hijo, porque
// referenciar un singleton desde otro singleton durante el arranque del motor
// se evaluaba a undefined y la escala se quedaba clavada en el mínimo.
//
// El binding se recalcula al conectar/desconectar o cambiar de modo
// (lee Quickshell.screens y width/height, que QML rastrea).
QtObject {
    readonly property real density: {
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
        return Math.max(0.85, Math.min(1.6, 1.0 + (shortSide / 1080 - 1) * 0.45))
    }
}
