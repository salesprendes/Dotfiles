import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import qs.Components
import qs.Config

// Título de la ventana enfocada (wlr-foreign-toplevel).
Pill {
    id: root
    readonly property var active: ToplevelManager.activeToplevel
    visible: active !== null && (active?.title ?? "") !== ""

    Text {
        text: "󰖯"
        color: Theme.accent2
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize
    }
    Text {
        Layout.maximumWidth: Theme.dp(360)
        text: root.active?.title ?? ""
        elide: Text.ElideRight
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
