import QtQuick
import QtQuick.Layouts
import qs.Config

Item {
    id: wrap

    property bool open: false
    property Component sourceComponent: null
    // Retiene el último componente para animar el cierre sin que el contenido
    // desaparezca de golpe a mitad de animación.
    property Component _shown: null
    onSourceComponentChanged: if (sourceComponent) _shown = sourceComponent

    readonly property var enterCurve: [0.05, 0.70, 0.10, 1.0, 1.0, 1.0]   // emphasizedDecel
    readonly property var exitCurve:  [0.30, 0.00, 0.80, 0.15, 1.0, 1.0]  // emphasizedAccel

    Layout.fillWidth: true
    clip: true
    Layout.preferredHeight: open ? loader.implicitHeight : 0
    visible: Layout.preferredHeight > 0.5

    Behavior on Layout.preferredHeight {
        NumberAnimation {
            duration: Theme.animNormal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: wrap.open ? wrap.enterCurve : wrap.exitCurve
        }
    }

    Loader {
        id: loader
        width: parent.width
        // Sigue cargado mientras se está recogiendo, para animar el cierre.
        active: wrap.open || wrap.Layout.preferredHeight > 0.5
        sourceComponent: wrap.open ? wrap.sourceComponent : wrap._shown
    }
}
