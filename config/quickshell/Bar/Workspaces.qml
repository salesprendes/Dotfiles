import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Components
import qs.Config

// Workspaces de Hyprland: el activo se ensancha, se ilumina y muestra su
// número. Click en un punto salta a ese workspace; la rueda sobre la píldora
// recorre los workspaces de esta pantalla en orden.
Pill {
    id: root
    property var screen
    interactive: true
    hoverCursor: true

    // Workspaces de ESTA pantalla, ordenados por id. Lo comparten el Repeater
    // y el recorrido con la rueda; filtrar en el origen evita crear delegates
    // ocultos de los demás monitores.
    readonly property var wsList: Hyprland.workspaces.values
        .filter(w => !w.monitor || !root.screen || w.monitor.name === root.screen.name)
        .sort((a, b) => a.id - b.id)

    function focusWorkspace(workspace) {
        const id = workspace && workspace.id !== undefined ? workspace.id : 1
        // En modo Lua, dispatch() se interpreta como hl.dispatch(...), así
        // que "workspace N" petaría con error de sintaxis. Hay que usar la
        // API Lua (hl.dsp.focus).
        if (Hyprland.usingLua) {
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })")
        } else {
            Hyprland.dispatch("workspace " + id)
        }
    }

    // Salta al workspace numérico vecino (dir = ±1). Va por número y no por la
    // lista de existentes (Hyprland solo lista los que están en uso; enfocar
    // un número que no existe lo crea). Techo: el workspace OCUPADO más alto
    // de esta pantalla + 1 — se puede abrir un único workspace vacío por
    // delante, pero sin ventanas más arriba la rueda no sigue subiendo. El
    // suelo es siempre el 1.
    function step(dir) {
        const cur = wsList.find(w => w.active)
        const base = cur ? cur.id : (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1)
        let maxOccupied = 0
        for (let i = 0; i < wsList.length; i++) {
            const w = wsList[i]
            const windows = w.lastIpcObject ? (w.lastIpcObject.windows || 0) : 0
            if (windows > 0 && w.id > maxOccupied)
                maxOccupied = w.id
        }
        const ceiling = Math.max(1, maxOccupied + 1)
        const target = Math.max(1, Math.min(ceiling, base + dir))
        if (target !== base)
            focusWorkspace({ id: target })
    }

    onScrolled: (dy) => step(dy > 0 ? -1 : 1)

    Repeater {
        model: ScriptModel { values: root.wsList }

        delegate: Rectangle {
            id: ws
            required property var modelData

            readonly property bool active: modelData ? modelData.active : false
            readonly property bool occupied: modelData && modelData.lastIpcObject ? modelData.lastIpcObject.windows > 0 : false

            implicitWidth: active ? Theme.dp(30) : Theme.dp(13)
            implicitHeight: Theme.dp(13)
            radius: height / 2
            // Crece un pelo bajo el ratón y nace con un pop al crearse.
            scale: wsMa.containsMouse && !active ? 1.25 : 1
            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            Component.onCompleted: { scale = 0.4; scale = Qt.binding(() =>
                wsMa.containsMouse && !ws.active ? 1.25 : 1) }

            color: active ? Theme.accent
                 : wsMa.containsMouse ? Theme.withAlpha(Theme.accent, 0.45)
                 : occupied ? Theme.overlay
                 : Theme.surface

            Behavior on implicitWidth {
                NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            Text {
                anchors.centerIn: parent
                visible: ws.active
                text: ws.modelData ? ws.modelData.id : ""
                color: Theme.bg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(11)
                font.bold: true
            }

            MouseArea {
                id: wsMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusWorkspace(ws.modelData)
            }
        }
    }
}
