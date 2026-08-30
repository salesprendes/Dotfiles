import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config

// Volumen, micrófono o brillo: glifo, barra y porcentaje.
//
// La barra se rellena con un ancho animado y no con una escala, porque una
// escala deformaría también sus esquinas redondeadas.
RowLayout {
    id: root
    spacing: Theme.space10

    readonly property string kind: IslandState.levelKind
    readonly property real value: Math.max(0, Math.min(1, IslandState.levelValue))
    readonly property bool muted: IslandState.levelMuted

    readonly property string glyph: {
        if (root.kind === "brightness")
            return root.value > 0.6 ? "󰃠" : root.value > 0.25 ? "󰃟" : "󰃞"
        if (root.kind === "mic")
            return root.muted ? "󰍭" : "󰍬"
        if (root.muted || root.value <= 0.001)
            return "󰝟"
        return root.value > 0.5 ? "󰕾" : "󰖀"
    }

    readonly property color tint: root.muted ? Theme.red
                                : root.kind === "brightness" ? Theme.yellow
                                                             : Theme.accent

    ThemedText {
        text: root.glyph
        color: root.tint
        font.pixelSize: Theme.barIconSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Theme.dp(120)
        implicitHeight: Theme.dp(5)
        radius: height / 2
        color: Theme.withAlpha(Theme.overlay, 0.55)

        Rectangle {
            width: Math.round(parent.width * (root.muted ? 0 : root.value))
            height: parent.height
            radius: parent.radius
            color: root.tint
            // Rápida pero no instantánea: el nivel llega ya cambiado desde
            // Pipewire, así que esto no es "esperar", es que el ojo vea hacia
            // dónde se ha movido.
            Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }

    ThemedText {
        // Ancho fijo: sin él, la píldora entera se encoge y se estira al pasar
        // de 9 % a 100 %, y el muelle se pone a perseguir el texto.
        Layout.preferredWidth: Theme.dp(38)
        horizontalAlignment: Text.AlignRight
        text: root.muted ? I18n.tr("Muted") : Math.round(root.value * 100) + "%"
        color: Theme.fgDim
        font.pixelSize: Theme.typeBodySmall
    }
}
