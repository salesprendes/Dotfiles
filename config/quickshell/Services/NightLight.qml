pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Luz nocturna (temperatura de color) vía hyprsunset.
//
// hyprsunset es un demonio: `hyprctl hyprsunset temperature <K>` le habla, pero
// si no está levantado el comando falla. Aquí se levanta bajo demanda la
// primera vez que se pide un cambio, y se consulta el estado real al arrancar
// para que el widget no mienta si el usuario ya lo tenía puesto desde su
// configuración de Hyprland.
//
// El estado NO se guarda en settings.json a propósito: la fuente de verdad es
// el propio hyprsunset, que sobrevive a un reinicio del shell. Guardarlo aquí
// crearía dos verdades que se contradicen en cuanto alguien use el comando
// desde fuera (un atajo de teclado, un script).
Singleton {
    id: root

    // Temperaturas en kelvin. 6500 K es "sin filtro" (luz de día estándar);
    // por debajo, la pantalla se vuelve ámbar.
    property int nightTemperature: 4000
    readonly property int dayTemperature: 6500

    readonly property bool available: Deps.has("hyprsunset")

    // null mientras no se ha podido leer el estado: el widget se muestra
    // apagado pero no afirma nada.
    property var temperature: null
    property bool stateLoaded: false

    readonly property bool enabled: stateLoaded
                                    && typeof temperature === "number"
                                    && temperature < dayTemperature

    // Un cambio pedido mientras el anterior sigue en marcha no se pierde ni
    // encadena procesos: se anota el último y se aplica al terminar. Pulsar el
    // toggle cinco veces seguidas deja UNA aplicación pendiente, no cinco.
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
        // Levanta el demonio si hace falta y luego le habla. El `sleep 1` da
        // tiempo a que abra su socket de control: sin él, el primer
        // `hyprctl hyprsunset` tras arrancarlo falla por no encontrarlo.
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
                // Sale como un número suelto. Cualquier otra cosa (el error de
                // "no such command" cuando el demonio no está) se descarta.
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
            // Relee el valor de verdad: si el demonio rechazó la temperatura
            // (fuera de rango, por ejemplo) el widget no debe quedarse
            // afirmando un estado que la pantalla no tiene.
            root.refresh()
        }
    }

    // Deps tarda un instante en resolver 'which'; sin esperar a que termine,
    // available sería false al arrancar y nunca se consultaría el estado.
    Connections {
        target: Deps
        function onLoaded() { root.refresh() }
    }

    // Tras suspender, hyprsunset puede haberse muerto con la sesión gráfica.
    // Solo el primer pulso: Resume reemite varias veces por si el hardware
    // tarda, y aquí una sola consulta basta (y si falla, no hay nada que
    // reintentar: el demonio no está y punto).
    Connections {
        target: Resume
        function onResumed() {
            if (Resume.recoveryPulse === 1)
                root.refresh()
        }
    }
}
