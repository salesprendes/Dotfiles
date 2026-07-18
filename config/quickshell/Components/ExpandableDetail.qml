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

    // Escalar único 0→1 (ver Theme.qml): la altura hace de barrido de
    // recorte y la opacidad se deriva del mismo valor, así entran/salen
    // coordinados en vez de solo cortarse en seco.
    property real reveal: wrap.open ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: Theme.animNormal
            easing.type: wrap.open ? Theme.enterEasing : Theme.exitEasing
        }
    }

    Layout.fillWidth: true
    clip: true
    Layout.preferredHeight: loader.implicitHeight * reveal
    visible: Layout.preferredHeight > 0.5

    Loader {
        id: loader
        width: parent.width
        // Sigue cargado mientras se está recogiendo, para animar el cierre.
        active: wrap.open || wrap.Layout.preferredHeight > 0.5
        sourceComponent: wrap.open ? wrap.sourceComponent : wrap._shown
        opacity: Theme.revealOpacity(wrap.reveal)
    }
}
