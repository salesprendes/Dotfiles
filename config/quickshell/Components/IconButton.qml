import QtQuick
import qs.Config

// Botón redondo con glifo (Nerd Font) y resaltado al pasar el ratón.
// Color base/hover del fondo y del icono personalizables.
Rectangle {
    id: btn

    property string icon: ""
    property real   diameter: Theme.controlM
    property int    iconPixelSize: Theme.iconSize
    property color  baseColor: Theme.surface
    property color  hoverColor: Theme.accent
    property color  iconColor: Theme.fgDim
    property color  hoverIconColor: Theme.bg
    readonly property bool hovered: ma.containsMouse || activeFocus

    signal clicked()

    activeFocusOnTab: enabled
    implicitWidth: diameter
    implicitHeight: diameter
    radius: height / 2
    // Si el fondo base es transparente, funde hacia el hover con alfa 0:
    // "transparent" es negro con alfa 0 y el fundido pasaba por una sombra oscura.
    color: hovered ? (ma.pressed ? Qt.darker(hoverColor, 1.12) : hoverColor)
         : (baseColor.a === 0 ? Qt.rgba(hoverColor.r, hoverColor.g, hoverColor.b, 0) : baseColor)
    border.width: activeFocus ? Theme.focusWidth : 0
    border.color: Theme.focusRing
    Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }

    // Crece un punto al pasar el ratón y se hunde al pulsar.
    //
    // La curva depende de hacia dónde va. El rebote no puede ir en la pulsación:
    // OutBack se pasa del destino antes de asentarse, que es lo que la hace
    // agradable al crecer y lo que la arruina al encoger, porque pasarse hacia
    // abajo deja el botón visiblemente aplastado. Un clic quiere lo contrario que
    // un hover: acuse inmediato y sin adorno.
    scale: ma.pressed ? 0.96 : (hovered ? 1.05 : 1.0)
    Behavior on scale {
        NumberAnimation {
            duration: ma.pressed ? Theme.animFast : Theme.animNormal
            easing.type: ma.pressed ? Easing.OutCubic : Easing.OutBack
            easing.overshoot: 1.7
        }
    }

    Keys.onReturnPressed: btn.clicked()
    Keys.onEnterPressed: btn.clicked()
    Keys.onSpacePressed: btn.clicked()
    Keys.onEscapePressed: Globals.closeAll()

    ThemedText {
        anchors.centerIn: parent
        text: btn.icon
        color: btn.hovered ? btn.hoverIconColor : btn.iconColor
        font.pixelSize: btn.iconPixelSize
        // El glifo funde a la vez que el fondo.
        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
    }

    // Repetición al mantener pulsado (opcional): dispara al instante al
    // pulsar, espera un margen y luego repite mientras se mantenga. Pensado
    // para navegación (p. ej. avanzar meses en el calendario).
    property bool autoRepeat: false
    Timer { id: repeatDelay; interval: 350; onTriggered: repeatTimer.start() }
    Timer { id: repeatTimer; interval: 140; repeat: true; onTriggered: btn.clicked() }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: if (btn.autoRepeat) { btn.clicked(); repeatDelay.start() }
        onReleased: { repeatDelay.stop(); repeatTimer.stop() }
        onCanceled: { repeatDelay.stop(); repeatTimer.stop() }
        // Con autoRepeat el disparo va en onPressed (respuesta inmediata);
        // sin él, el clic normal al soltar.
        onClicked: if (!btn.autoRepeat) btn.clicked()
    }
}
