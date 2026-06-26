pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Servicio de perfiles de energía. Envuelve el singleton nativo
//  PowerProfiles (Quickshell.Services.UPower), que escribe a
//  power-profiles-daemon por D-Bus. Expone perfil actual, icono,
//  nombre traducido y funciones para fijar/ciclar perfil, de modo
//  que la UI solo necesita importar qs.Services.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: power

    // ¿Está instalado power-profiles-daemon? Si no, la UI (pill de la barra y
    // tile/selector del Centro de control) se oculta por completo. El singleton
    // nativo PowerProfiles no expone disponibilidad, así que la detectamos con
    // rutas estables del paquete (mismo patrón que Brightness.available).
    property bool available: false

    Process {
        running: true
        command: ["sh", "-c",
            "(test -e /usr/share/dbus-1/system-services/net.hadess.PowerProfiles.service " +
            "|| test -e /usr/lib/systemd/system/power-profiles-daemon.service " +
            "|| command -v powerprofilesctl >/dev/null) && echo yes || true"]
        stdout: StdioCollector {
            onStreamFinished: power.available = (this.text || "").indexOf("yes") !== -1
        }
    }

    // Perfil activo (enum: PowerSaver=0, Balanced=1, Performance=2).
    readonly property int profile: PowerProfiles.profile
    // Performance solo está disponible en cierto hardware.
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile

    readonly property bool isSaver: profile === PowerProfile.PowerSaver
    readonly property bool isBalanced: profile === PowerProfile.Balanced
    readonly property bool isPerformance: profile === PowerProfile.Performance

    function iconFor(p) {
        if (p === PowerProfile.PowerSaver) return "󰌪"        // hoja (ahorro)
        if (p === PowerProfile.Performance) return "󰓅"       // velocímetro
        return "󰾅"                                            // medidor (equilibrado)
    }
    function labelFor(p) {
        if (p === PowerProfile.PowerSaver) return I18n.tr("Power saver")
        if (p === PowerProfile.Performance) return I18n.tr("Performance")
        return I18n.tr("Balanced")
    }
    function colorFor(p) {
        if (p === PowerProfile.PowerSaver) return Theme.green
        if (p === PowerProfile.Performance) return Theme.cyan
        return Theme.accent
    }

    readonly property string icon: iconFor(profile)
    readonly property string name: labelFor(profile)
    readonly property color color: colorFor(profile)

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
        PowerProfiles.profile = p
    }

    // Avanza al siguiente perfil disponible (orden Saver→Balanced→Performance→loop).
    function cycle() {
        const list = profiles
        let idx = 0
        for (let i = 0; i < list.length; i++)
            if (list[i].value === profile) { idx = i; break }
        set(list[(idx + 1) % list.length].value)
    }
}
