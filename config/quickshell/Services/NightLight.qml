pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Luz nocturna vía hyprsunset, que es un demonio: el comando falla si no está
// levantado, así que se levanta bajo demanda la primera vez que se pide un
// cambio y se consulta el estado real al arrancar, para que el widget no mienta
// si ya estaba puesto desde la configuración de Hyprland.
//
// El estado no se guarda en settings.json a propósito: la fuente de verdad es el
// propio hyprsunset, que sobrevive a un reinicio del shell. Guardarlo aquí daría
// dos verdades que se contradicen en cuanto alguien use el comando desde fuera.
Singleton {
    id: root

    // Temperaturas en kelvin. 6500 K es "sin filtro"; por debajo, la pantalla se
    // vuelve ámbar.
    property int nightTemperature: 4000
    readonly property int dayTemperature: 6500

    readonly property bool available: Deps.has("hyprsunset")

    // null mientras no se ha podido leer el estado: el widget se muestra apagado
    // pero no afirma nada.
    property var temperature: null
    property bool stateLoaded: false

    readonly property bool enabled: stateLoaded
                                    && typeof temperature === "number"
                                    && temperature < dayTemperature

    // Un cambio pedido mientras el anterior sigue en marcha no se pierde ni
    // encadena procesos: se anota el último y se aplica al terminar.
    property bool _hasPending: false
    property int _pending: 0

    function refresh() {
        if (!available) {
            root.stateLoaded = true
            return
        }
        if (!statusProbe.running)
            statusProbe.running = true
    }

    function apply(temp) {
        if (!available)
            return
        root.temperature = temp
        root.stateLoaded = true
        if (applyProc.running) {
            root._pending = temp
            root._hasPending = true
            return
        }
        _run(temp)
    }

    function set(on) { apply(on ? nightTemperature : dayTemperature) }
    function toggle() { set(!enabled) }

    function _run(temp) {
        // Levanta el demonio si hace falta y luego le habla. El `sleep` da
        // tiempo a que abra su socket de control: sin él, el primer comando tras
        // arrancarlo falla por no encontrarlo.
        applyProc.command = ["sh", "-c",
            "pgrep -x hyprsunset >/dev/null || { setsid hyprsunset >/dev/null 2>&1 & sleep 1; }; "
            + "hyprctl hyprsunset temperature " + Math.round(temp)]
        applyProc.running = true
    }

    Process {
        id: statusProbe
        command: ["hyprctl", "hyprsunset", "temperature"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                // Sale como un número suelto; cualquier otra cosa, como el
                // error de "no such command", se descarta.
                const n = parseInt(String(this.text || "").trim(), 10)
                root.temperature = isFinite(n) && n > 0 ? n : null
                root.stateLoaded = true
            }
        }
        onExited: (code) => {
            if (code !== 0) {
                root.temperature = null
                root.stateLoaded = true
            }
        }
    }

    Process {
        id: applyProc
        onExited: {
            if (root._hasPending) {
                root._hasPending = false
                root._run(root._pending)
                return
            }
            // Relee el valor real: si el demonio rechazó la temperatura, el
            // widget no debe quedarse afirmando un estado que no existe.
            root.refresh()
        }
    }

    // Deps tarda un instante en resolver: sin esperarlo, 'available' sería false
    // al arrancar y nunca se consultaría el estado.
    Connections {
        target: Deps
        function onLoaded() { root.refresh() }
    }

    // Tras suspender, hyprsunset puede haberse muerto con la sesión gráfica.
    // Solo el primer pulso: una sola consulta basta y, si falla, no hay nada que
    // reintentar porque el demonio no está.
    Connections {
        target: Resume
        function onResumed() {
            if (Resume.recoveryPulse === 1)
                root.refresh()
        }
    }
}
