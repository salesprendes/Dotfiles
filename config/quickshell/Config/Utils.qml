pragma Singleton

import QtQuick
import Quickshell

// Utilidades compartidas sin estado.
Singleton {
    // Cita un valor para interpolarlo de forma segura en `sh -c`.
    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    // Nombre legible de un nodo Pipewire, con la misma cadena de respaldos en
    // los paneles de salida y de micrófono.
    function pwDeviceName(node) {
        return node?.description || node?.nickname || node?.properties?.["node.description"]
            || node?.properties?.["media.name"] || node?.name || "—"
    }

    // Glifo de volumen según nivel (0..1) y silencio. Compartido por la barra,
    // el OSD y el panel de audio para que los umbrales no diverjan.
    function volumeGlyph(volume01, muted) {
        if (muted) return "󰝟"
        if (volume01 <= 0) return "󰖁"
        if (volume01 < 0.34) return "󰕿"
        if (volume01 < 0.67) return "󰖀"
        return "󰕾"
    }
}
