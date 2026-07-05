pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Servicio de pantallas. LEE los monitores de forma reactiva desde
//  Quickshell.Hyprland (sin subprocess) y los APLICA con
//  `hyprctl eval 'hl.monitor{…}'`. Aplicar es lo único que necesita
//  proceso (Quickshell solo expone dispatchers). Se usa `eval` + la
//  API Lua porque `hyprctl keyword` NO funciona con el parser Lua de
//  Hyprland. El cambio es en caliente; persistirlo es opcional.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property var monitors: Hyprland.monitors?.values ?? []

    function refresh() { Hyprland.refreshMonitors() }

    // Tras el resume, los monitores pueden re-enumerarse (DPMS/hotplug): re-lee
    // el estado live desde Hyprland para que la UI de Pantallas quede al día.
    Connections {
        target: Resume
        function onResumed() { root.refresh() }
    }

    // Último 'spec' aplicado por monitor (para persistir lo aplicado, no el
    // estado live —que se actualiza con retardo tras el `eval`).
    property var _desired: ({})

    // Tabla Lua de un monitor: { output=…, mode=…, position=…, scale=… }.
    function _luaTable(spec) {
        if (!spec.enabled)
            return '{ output = "' + spec.name + '", disabled = true }'
        return '{ output = "' + spec.name + '"'
             + ', mode = "' + spec.res + '@' + spec.refresh + '"'
             + ', position = "' + Math.round(spec.x) + 'x' + Math.round(spec.y) + '"'
             + ', scale = ' + spec.scale
             + ((spec.transform && spec.transform !== 0) ? ', transform = ' + spec.transform : '')
             + ' }'
    }

    // Spec normalizado desde el estado live de un monitor.
    function _specOf(i) {
        return ({ name: i.name, res: i.width + "x" + i.height,
                  refresh: Number(i.refresh).toFixed(2), scale: i.scale,
                  transform: i.transform, x: i.x, y: i.y, enabled: !i.disabled })
    }

    // ── Persistencia ─────────────────────────────────────────
    //  Escribe todos los monitores en ~/.config/hypr/conf/monitors.lua para
    //  que sobreviva a reinicios. Usa lo APLICADO (_desired) y, para los no
    //  editados, su estado actual. Lo llama apply() automáticamente.
    function persistAll() {
        let body = "-- ── Monitores ──────────────────────────────────────────\n"
                 + "-- Generado por Quickshell (Ajustes → Pantallas).\n\n"
        root.monitors.forEach(m => {
            const i = root.info(m)
            const spec = root._desired[i.name] ?? root._specOf(i)
            body += "hl.monitor(" + root._luaTable(spec) + ")\n"
        })
        monitorsFile.setText(body)
    }

    FileView {
        id: monitorsFile
        path: root.home + "/.config/hypr/conf/monitors.lua"
        printErrors: false
        atomicWrites: true
    }

    // Info normalizada de un monitor (props directas + lastIpcObject).
    function info(mon) {
        const j = mon?.lastIpcObject ?? ({})
        return ({
            name: mon?.name ?? (j.name ?? ""),
            description: j.description ?? "",
            width: mon?.width ?? (j.width ?? 0),
            height: mon?.height ?? (j.height ?? 0),
            refresh: j.refreshRate ?? 0,
            x: mon?.x ?? (j.x ?? 0),
            y: mon?.y ?? (j.y ?? 0),
            scale: mon?.scale ?? (j.scale ?? 1),
            transform: j.transform ?? 0,
            disabled: j.disabled ?? false
        })
    }

    // Modos disponibles deduplicados: [{label, value, res, refresh}].
    function modesFor(mon) {
        const raw = (mon?.lastIpcObject?.availableModes) ?? []
        const seen = ({})
        return raw.reduce((out, s) => {
            if (!seen[s]) {
                seen[s] = true
                const at = s.split("@")                 // "2560x1440@59.95Hz"
                out.push(({ text: s.replace("Hz", " Hz"), value: s,
                            res: at[0], refresh: (at[1] || "").replace("Hz", "") }))
            }
            return out
        }, [])
    }

    // Aplica config a un monitor (en caliente) vía `hyprctl eval` Y la persiste
    // en monitors.lua, todo de una. spec: { name, res, refresh, scale,
    // transform, x, y, enabled }.
    function apply(spec) {
        const d = Object.assign({}, root._desired)
        d[spec.name] = spec
        root._desired = d
        applyProc.command = ["hyprctl", "eval", "hl.monitor(" + root._luaTable(spec) + ")"]
        applyProc.running = true
        root.persistAll()
    }

    Process {
        id: applyProc
        onExited: (code, status) => root.refresh()
    }
}
