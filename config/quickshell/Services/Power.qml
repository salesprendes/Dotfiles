pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Config

// Perfiles de energía. Envuelve el singleton nativo PowerProfiles
// (Quickshell.Services.UPower), que escribe a power-profiles-daemon por D-Bus.
// Expone perfil actual, icono, nombre traducido y funciones para fijar/ciclar,
// así la UI solo necesita importar qs.Services.
Singleton {
    id: power

    // ¿Está instalado power-profiles-daemon? Si no, la UI (pill de la barra y
    // tile/selector del Centro de control) se oculta por completo. El singleton
    // nativo PowerProfiles no expone disponibilidad, así que la detectamos por
    // el CLI que acompaña al daemon (powerprofilesctl, también con tuned-ppd),
    // vía Deps: binding reactivo, sin proceso de detección propio.
    readonly property bool available: Deps.has("powerprofilesctl")

    // Perfil activo. Se mantiene como var para no forzar conversiones del enum
    // de QuickShell a int, que pueden romper el estado visual.
    readonly property var profile: PowerProfiles.profile
    // Performance solo está disponible en cierto hardware.
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile

    property string currentProfileKey: keyFor(profile)
    onProfileChanged: currentProfileKey = keyFor(profile)

    readonly property bool isSaver: currentProfileKey === "power-saver"
    readonly property bool isBalanced: currentProfileKey === "balanced"
    readonly property bool isPerformance: currentProfileKey === "performance"

    function keyFor(p) {
        if (p === PowerProfile.PowerSaver || Number(p) === Number(PowerProfile.PowerSaver))
            return "power-saver"
        if (p === PowerProfile.Performance || Number(p) === Number(PowerProfile.Performance))
            return "performance"

        const text = String(p).toLowerCase()
        if (text.indexOf("saver") !== -1 || text.indexOf("power-saver") !== -1)
            return "power-saver"
        if (text.indexOf("performance") !== -1)
            return "performance"
        return "balanced"
    }

    function matches(p) {
        return keyFor(p) === currentProfileKey
    }

    function iconFor(p) {
        const key = keyFor(p)
        if (key === "power-saver") return "󰌪"                // hoja (ahorro)
        if (key === "performance") return "󰓅"                // velocímetro
        return "󰾅"                                            // medidor (equilibrado)
    }
    function labelFor(p) {
        const key = keyFor(p)
        if (key === "power-saver") return I18n.tr("Power saver")
        if (key === "performance") return I18n.tr("Performance")
        return I18n.tr("Balanced")
    }
    function colorFor(p) {
        return Theme.accent
    }

    readonly property string icon: iconFor(currentProfileKey)
    readonly property string name: labelFor(currentProfileKey)
    readonly property color color: colorFor(currentProfileKey)

    // Lista para el selector. PowerSaver/Balanced siempre; Performance
    // solo si el hardware lo soporta.
    readonly property var profiles: {
        const arr = [
            { value: PowerProfile.PowerSaver,  icon: iconFor(PowerProfile.PowerSaver),  label: labelFor(PowerProfile.PowerSaver),  color: colorFor(PowerProfile.PowerSaver) },
            { value: PowerProfile.Balanced,    icon: iconFor(PowerProfile.Balanced),    label: labelFor(PowerProfile.Balanced),    color: colorFor(PowerProfile.Balanced) }
        ]
        if (hasPerformance)
            arr.push({ value: PowerProfile.Performance, icon: iconFor(PowerProfile.Performance), label: labelFor(PowerProfile.Performance), color: colorFor(PowerProfile.Performance) })
        return arr
    }

    function set(p) {
        currentProfileKey = keyFor(p)
        PowerProfiles.profile = p
    }

    // Avanza al siguiente perfil disponible (orden Saver→Balanced→Performance→loop).
    function cycle() {
        const list = profiles
        let idx = 0
        for (let i = 0; i < list.length; i++)
            if (matches(list[i].value)) { idx = i; break }
        set(list[(idx + 1) % list.length].value)
    }
}
