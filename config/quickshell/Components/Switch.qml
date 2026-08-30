import QtQuick
import qs.Config

// Interruptor Material 3.
//
// Lo que lo distingue de un interruptor cualquiera —y la razón de copiarlo—
// es que la bolita CAMBIA DE TAMAÑO con el estado:
//
//   · apagado  → bolita pequeña, del color del borde, holgada dentro de la
//                pista. Se lee como un hueco vacío.
//   · encendido→ bolita grande y sólida que casi llena la pista, con una
//                marca de verificación dentro.
//   · pulsando → todavía más grande, mientras el dedo está encima.
//
// Eso hace dos cosas. Una, que el estado se note sin depender del color: en
// una fila con veinte interruptores distingues los encendidos por la MASA de
// la bolita aunque no distingas bien los tonos. Y dos, que el gesto tenga
// respuesta física — la bolita crece bajo el dedo y se asienta al soltar.
//
// onColor: acento de la pista encendida (BT usa accent2). offColor: pista
// apagada. offBorderColor: borde cuando está apagado.
Rectangle {
    id: sw

    property bool  checked: false
    property color onColor: Theme.accent
    property color offColor: Theme.surface
    property color offBorderColor: Theme.withAlpha(Theme.overlay, 0.4)
    signal toggled()

    activeFocusOnTab: enabled
    implicitWidth: Theme.dp(46)
    implicitHeight: Theme.dp(28)
    radius: height / 2

    color: checked ? onColor : offColor
    // El borde de la pista apagada es grueso a propósito (M3 lo pinta a 2 dp):
    // es lo que hace que el estado apagado se lea como un contorno vacío y no
    // como un botón relleno de gris.
    border.width: activeFocus ? Theme.focusWidth
                : checked ? 0 : Math.max(1, Theme.dp(2))
    border.color: activeFocus ? Theme.focusRing : offBorderColor
    Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    Keys.onReturnPressed: sw.toggled()
    Keys.onEnterPressed: sw.toggled()
    Keys.onSpacePressed: sw.toggled()
    Keys.onEscapePressed: Globals.closeAll()

    // Tamaños de la bolita, en proporciones de M3 (16 / 24 / 28 sobre una
    // pista de 32) reescaladas a la altura real de esta pista.
    readonly property real _k: height / Theme.dp(32)
    property real thumbSize: ma.pressed ? Theme.dp(28) * _k
                           : checked    ? Theme.dp(24) * _k
                                        : Theme.dp(16) * _k
    // Margen al canto de la pista: la bolita pequeña va más metida que la
    // grande, así que el recorrido del centro no es el ancho entero.
    readonly property real _offInset: Theme.dp(8) * _k
    readonly property real _onInset: Theme.dp(4) * _k
    property real thumbCenter: checked ? width - _onInset - (Theme.dp(24) * _k) / 2
                                       : _offInset + (Theme.dp(16) * _k) / 2

    Behavior on thumbSize {
        NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSpatial; easing.overshoot: 1.6 }
    }
    // OutBack suave: la bolita llega y asienta con un pelín de rebote, en vez
    // de frenar en seco. El sobreimpulso es corto para que no parezca elástica.
    Behavior on thumbCenter {
        NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSpatial; easing.overshoot: 1.2 }
    }

    // Capa de estado: el halo que aparece alrededor de la bolita al señalar o
    // pulsar. En M3 los controles no cambian de color al interactuar, se les
    // superpone una capa con una opacidad fija (ver Theme.stateHover).
    Rectangle {
        width: Theme.dp(40) * sw._k
        height: width
        radius: height / 2
        x: sw.thumbCenter - width / 2
        y: (parent.height - height) / 2
        color: sw.checked ? sw.onColor : Theme.fg
        opacity: ma.pressed ? Theme.statePressed
               : (ma.containsMouse || sw.activeFocus) ? Theme.stateHover : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    // Bolita.
    Rectangle {
        id: thumb
        width: sw.thumbSize
        height: sw.thumbSize
        radius: height / 2
        x: sw.thumbCenter - width / 2
        y: (parent.height - height) / 2
        color: sw.checked ? Theme.bg : Theme.fgDim
        Behavior on color { ColorAnimation { duration: Theme.animNormal } }

        // Marca dentro de la bolita encendida. No es adorno: dice el estado
        // sin depender del color, que es lo que necesita quien no distingue
        // el acento del gris de la pista apagada.
        ThemedText {
            anchors.centerIn: parent
            text: "󰄬"
            color: sw.onColor
            font.pixelSize: Math.round(parent.height * 0.62)
            opacity: sw.checked ? 1 : 0
            scale: sw.checked ? 1 : 0.5
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            Behavior on scale {
                NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSpatial; easing.overshoot: 2.0 }
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.margins: -Theme.space4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled()
    }
}
