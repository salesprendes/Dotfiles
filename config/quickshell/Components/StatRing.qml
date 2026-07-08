import QtQuick
import QtQuick.Shapes
import qs.Config

// Anillo de progreso (pista + arco) con glifo central opcional.
// Usado por el Dashboard (CPU/RAM/disco) y por los botones de energía del Centro de control.
// animated: suaviza los cambios de value; desactívalo si el progreso ya viene animado (hold)
// o el panel está oculto. glyph "" oculta el texto central; trackColor "transparent" la pista.
Item {
    id: sr
    property real value: 0
    property color tint: Theme.accent
    property string glyph: ""
    property bool animated: true
    property real ringWidth: Theme.dp(4)
    property color trackColor: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)
    implicitWidth: Theme.dp(50)
    implicitHeight: Theme.dp(50)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: sr.trackColor
            fillColor: "transparent"
            strokeWidth: sr.ringWidth
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: sr.width / 2; centerY: sr.height / 2
                radiusX: sr.width / 2 - Theme.dp(2.5); radiusY: radiusX
                startAngle: -90; sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: sr.tint
            fillColor: "transparent"
            strokeWidth: sr.ringWidth
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: sr.width / 2; centerY: sr.height / 2
                radiusX: sr.width / 2 - Theme.dp(2.5); radiusY: radiusX
                startAngle: -90
                sweepAngle: 360 * Math.max(0.02, Math.min(1, sr.value))
                // Solo anima cuando procede: las animaciones Qt corren aunque el item
                // esté oculto (SysMon actualiza cada 5 s).
                Behavior on sweepAngle { enabled: sr.animated; NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            }
        }
    }
    Text {
        visible: sr.glyph !== ""
        anchors.centerIn: parent
        text: sr.glyph
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize + 6.5
    }
}
