import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Components
import qs.Config

// Workspaces de Hyprland: el activo se ensancha y se ilumina.
// Click salta a ese workspace.
Pill {
    id: root
    property var screen
    hoverCursor: true

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

    Repeater {
        // Filtra en el origen: solo los workspaces de esta pantalla, para no
        // crear delegates ocultos de los demás monitores. ScriptModel
        // re-evalúa al cambiar Hyprland.workspaces o el monitor de uno.
        model: ScriptModel {
            values: Hyprland.workspaces.values.filter(w =>
                !w.monitor || !root.screen || w.monitor.name === root.screen.name)
        }

        delegate: Rectangle {
            id: ws
            required property var modelData

            readonly property bool active: modelData ? modelData.active : false
            readonly property bool occupied: modelData && modelData.lastIpcObject ? modelData.lastIpcObject.windows > 0 : false

            implicitWidth: active ? Theme.controlS : Theme.space12
            implicitHeight: Theme.space12
            radius: height / 2

            color: active ? Theme.accent
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
                font.pixelSize: Theme.sp(10)
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusWorkspace(ws.modelData)
            }
        }
    }
}
