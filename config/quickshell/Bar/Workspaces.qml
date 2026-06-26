import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Components
import qs.Config

// Indicador de workspaces de Hyprland: el activo se ensancha y se
// ilumina. Click = saltar a ese workspace.
Pill {
    id: root
    property var screen

    function focusWorkspace(workspace) {
        const id = workspace && workspace.id !== undefined ? workspace.id : 1
        // Este Hyprland corre en modo Lua: dispatch() se interpreta como
        // hl.dispatch(...), así que "workspace N" daría error de sintaxis.
        // Hay que usar la API Lua del framework (hl.dsp.focus).
        if (Hyprland.usingLua) {
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })")
        } else {
            Hyprland.dispatch("workspace " + id)
        }
    }

    Repeater {
        model: Hyprland.workspaces

        delegate: Rectangle {
            id: ws
            required property var modelData

            // Muestra solo los workspaces de ESTA pantalla (en multi-monitor
            // cada barra enseñaba los de todos los monitores).
            readonly property bool onThisScreen: !modelData?.monitor
                || !root.screen
                || modelData.monitor.name === root.screen.name

            readonly property bool active: modelData ? modelData.active : false
            readonly property bool occupied: modelData && modelData.lastIpcObject ? modelData.lastIpcObject.windows > 0 : false

            visible: onThisScreen
            implicitWidth: !onThisScreen ? 0 : active ? Theme.controlS : Theme.space12
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
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusWorkspace(ws.modelData)
            }
        }
    }
}
