import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config

// Aplicación enfocada: resuelve el appId del toplevel contra su entrada
// .desktop para mostrar icono y nombre estables, no el título del documento.
Pill {
    id: root

    spacing: Theme.space4

    // No se llama 'active': Pill ya define una 'active' booleana para el punto
    // de acento, y una propiedad que tapa la de su tipo base es una trampa
    // silenciosa — además de que aquí no cabría, porque es de solo lectura.
    readonly property var toplevel: ToplevelManager.activeToplevel
    readonly property string appId: toplevel?.appId ?? ""
    readonly property var desktopEntry: appId !== "" ? DesktopEntries.heuristicLookup(appId) : null

    readonly property string iconSource: {
        const entryIcon = desktopEntry?.icon ?? ""
        const icon = entryIcon !== "" ? entryIcon : appId
        return icon !== "" ? Quickshell.iconPath(icon, true) : ""
    }

    readonly property string appName: {
        const name = desktopEntry?.name ?? ""
        if (name !== "") return name
        if (appId !== "") {
            const shortId = appId.split(".").pop().replace(/[-_]+/g, " ")
            return shortId.charAt(0).toUpperCase() + shortId.slice(1)
        }
        return toplevel?.title ?? ""
    }

    shown: toplevel !== null && appName !== ""

    Image {
        readonly property int displaySize: Math.min(Theme.barIconSize, root.implicitHeight - Theme.space8)

        Layout.preferredWidth: displaySize
        Layout.preferredHeight: displaySize
        source: root.iconSource
        sourceSize.width: displaySize
        sourceSize.height: displaySize
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: source !== ""
    }

    // Respaldo para aplicaciones sin icono instalable en el tema actual.
    BarGlyph {
        visible: root.iconSource === ""
        text: "󰎯"
        color: Theme.accent2
    }

    BarLabel {
        Layout.maximumWidth: Theme.dp(220)
        text: root.appName
        elide: Text.ElideRight
        color: Theme.fgDim
    }
}
