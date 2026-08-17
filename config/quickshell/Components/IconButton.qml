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
    Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

    // Crece un punto al pasar el ratón y se hunde al pulsar.
    //
    // EL REBOTE NO PUEDE IR EN LA PULSACIÓN, y ahí estaba el "achafado": la
    // curva OutBack se PASA del destino antes de asentarse, que es justo lo
    // que la hace agradable al crecer… y lo que la arruina al encoger, porque
    // pasarse hacia abajo de 0,92 es bajar a ~0,85 y el botón se ve aplastado
    // durante un instante. Encima iba con la duración larga, así que el
    // aplastamiento se veía entero.
    //
    // Un clic quiere lo contrario que un hover: acuse INMEDIATO y sin adorno.
    // Así que la curva depende de hacia dónde va — al pulsar, corta y sin
    // rebote; al soltar y al pasar el ratón, la de siempre.
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

    Text {
        anchors.centerIn: parent
        text: btn.icon
        color: btn.hovered ? btn.hoverIconColor : btn.iconColor
        font.family: Theme.fontFamily
        font.pixelSize: btn.iconPixelSize
        // El glifo funde a la vez que el fondo.
        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
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
