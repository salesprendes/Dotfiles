pragma Singleton

import QtQuick
import Quickshell

// Utilidades compartidas sin estado.
Singleton {
    // Cita un valor para interpolarlo de forma segura en `sh -c`.
    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }
}
