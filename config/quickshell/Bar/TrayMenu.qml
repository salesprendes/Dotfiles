import QtQuick
import Quickshell
import qs.Config

// Popup con el menú contextual de un item del tray, con el estilo del tema.
// Se ancla bajo el icono y se cierra al hacer click fuera (grabFocus).
PopupWindow {
    id: menu

    property var menuHandle: null
    required property var anchorItem

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: Theme.space6

    color: "transparent"
    visible: false
    grabFocus: true

    readonly property int pad: Theme.space6
    readonly property int minW: Theme.dp(170)
    readonly property int maxW: Theme.dp(380)

    implicitWidth: Math.max(minW, Math.min(maxW, rootLevel.implicitWidth + pad * 2))
    implicitHeight: rootLevel.implicitHeight + pad * 2

    function open() { menu.visible = true }
    function close() { menu.visible = false }

    // Al cerrar, vuelve al nivel raíz del menú.
    onVisibleChanged: if (!visible) rootLevel.reset()

    Rectangle {
        anchors.fill: parent
        radius: Theme.barRadius
        color: Theme.popupBg
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.5)
        antialiasing: true

        MenuLevel {
            id: rootLevel
            x: menu.pad
            y: menu.pad
            width: parent.width - menu.pad * 2
            menuHandle: menu.menuHandle
            onRequestClose: menu.close()
        }
    }
}
