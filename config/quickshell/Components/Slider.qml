import QtQuick
import qs.Config

// Slider al estilo del Material 3 "expresivo": pista gruesa partida en dos
// tramos y un agarre que NO es un disco, sino una pastilla vertical fina y
// más alta que la pista, separada de ambos tramos por un hueco.
//
// Por qué así y no el disco de siempre:
//
//  · El hueco a los lados del agarre es lo que hace legible la posición. Con
//    un disco montado ENCIMA de una barra continua, el punto exacto queda
//    tapado justo por la pieza que hay que leer; partiendo la pista, el valor
//    se lee en el corte y el agarre solo lo señala.
//  · La pastilla vertical ocupa poco a lo ancho (4 px) y mucho a lo alto, así
//    que apunta a un valor concreto en vez de a una zona de 16 px. En una
//    escala de 0 a 100 esa diferencia son varios puntos.
//  · Al pulsar, la pastilla ADELGAZA en vez de crecer. Es al revés de lo que
//    pide el instinto, pero es lo correcto: mientras arrastras necesitas ver
//    dónde caes, y una pieza más gorda tapa más. El acuse de que la has
//    cogido lo da el halo de estado que aparece detrás.
//
// El punto del extremo derecho ("stop indicator") marca dónde acaba el
// recorrido, para que un slider casi lleno no se confunda con uno lleno. Se
// esconde cuando el agarre llega a taparlo.
Item {
    id: root

    property real value: 0.0
    property color accent: Theme.accent
    property color trackColor: Theme.sliderTrack
    signal moved(real v)

    // Lógica de arrastre/teclado compartida (ver Components/SliderDrag.qml).
    SliderDrag { id: drag; control: root }

    // Para quien dibuje una lectura al lado y necesite saber si el usuario
    // está moviendo el control ahora mismo (ver Components/SliderRow.qml).
    readonly property bool dragging: drag.dragging

    readonly property bool hot: ma.containsMouse || ma.pressed || root.activeFocus
    readonly property bool grabbed: ma.pressed || root.activeFocus

    // La pista engorda al tocarla: el control se ofrece cuando lo apuntas.
    // No van como 'readonly': un Behavior no puede animar una propiedad de
    // solo lectura (Qt lo rechaza en tiempo de carga). Siguen siendo bindings,
    // que es lo que importa; simplemente admiten que la animación los mueva.
    property int trackH: root.hot ? Theme.dp(16) : Theme.dp(12)
    property int handleW: root.grabbed ? Theme.dp(3) : Theme.dp(4)
    property int handleH: root.grabbed ? Theme.dp(28) : Theme.dp(22)
    readonly property int gap: Theme.dp(5)

    // ── Geometría del recorrido ──────────────────────────────────────────────
    // 'slotW' es el grosor NOMINAL del agarre y es constante. Toda la
    // geometría (recorrido, tramos, mapeo del puntero) se calcula con él, y
    // NUNCA con 'handleW'.
    //
    // Por qué importa: handleW adelgaza al pulsar, y además lo hace animado.
    // Si el recorrido dependiera de él, en el instante de agarrar el slider
    // el recorrido se alargaba 1 px de forma continua durante toda la
    // animación — así que la posición del agarre se desplazaba sola bajo el
    // dedo, y el mapeo puntero→valor iba dividiendo entre un número que
    // cambiaba fotograma a fotograma. Se notaba como un microdeslizamiento al
    // empezar a arrastrar, justo en el momento en que más precisión quieres.
    //
    // Con slotW fijo, pulsar solo cambia el DIBUJO del agarre: el punto que
    // marca no se mueve ni un píxel.
    readonly property real slotW: Theme.dp(4)
    readonly property real travel: Math.max(1, width - slotW)
    // Centro del agarre, que es el punto que de verdad señala el valor. El
    // rectángulo se cuelga de él (x = centro − su propio grosor / 2), así que
    // al adelgazar encoge simétricamente en vez de desplazarse.
    readonly property real handleCenter: slotW / 2 + drag.shownValue * travel

    activeFocusOnTab: enabled
    implicitHeight: Theme.dp(28)

    // Teclado. Con Mayúsculas el paso baja al 1% para afinar; Re Pág/Av Pág
    // dan saltos del 10% e Inicio/Fin van a los extremos.
    function _step(event) {
        return (event.modifiers & Qt.ShiftModifier) ? 0.01 : 0.05
    }
    Keys.onLeftPressed: (e) => drag.nudge(-1, root._step(e))
    Keys.onDownPressed: (e) => drag.nudge(-1, root._step(e))
    Keys.onRightPressed: (e) => drag.nudge(1, root._step(e))
    Keys.onUpPressed: (e) => drag.nudge(1, root._step(e))
    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Home) { drag.jumpTo(0); e.accepted = true }
        else if (e.key === Qt.Key_End) { drag.jumpTo(1); e.accepted = true }
        else if (e.key === Qt.Key_PageDown) { drag.nudge(-1, 0.10); e.accepted = true }
        else if (e.key === Qt.Key_PageUp) { drag.nudge(1, 0.10); e.accepted = true }
    }
    Keys.onEscapePressed: Globals.closeAll()

    Behavior on trackH { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    Behavior on handleW { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    Behavior on handleH { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

    // ── Tramo recorrido ──────────────────────────────────────────────────────
    // Degradado dentro del MISMO tono: del acento aclarado al acento. Iba de
    // accent2 a accent, y con una paleta dinámica accent2 puede caer en el
    // lado opuesto del círculo cromático — con el fondo de escritorio actual
    // la pista pasaba de ámbar a morado, un arcoíris que no dice nada. Una
    // sola familia de color da la misma profundidad sin inventarse un
    // segundo significado.
    Rectangle {
        id: activeTrack
        y: (root.height - height) / 2
        x: 0
        width: Math.max(0, root.handleCenter - root.slotW / 2 - root.gap)
        height: root.trackH
        radius: height / 2
        visible: width > 0.5
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.lighter(root.accent, 1.22) }
            GradientStop { position: 1.0; color: root.accent }
        }
        // Al arrastrar sigue al dedo 1:1; fuera del arrastre (teclado, cambio
        // externo) el salto se suaviza.
        Behavior on width { enabled: !drag.dragging; NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    }

    // ── Tramo pendiente ──────────────────────────────────────────────────────
    Rectangle {
        id: restTrack
        y: (root.height - height) / 2
        x: Math.min(root.width, root.handleCenter + root.slotW / 2 + root.gap)
        width: Math.max(0, root.width - x)
        height: root.trackH
        radius: height / 2
        color: root.trackColor
        visible: width > 0.5
        Behavior on x { enabled: !drag.dragging; NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

        // Fin del recorrido. Se apaga cuando el agarre está a punto de
        // pisarlo, para que no parezca que quedan dos piezas sueltas.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Theme.dp(6)
            implicitWidth: Theme.dp(4)
            implicitHeight: Theme.dp(4)
            radius: width / 2
            color: Theme.withAlpha(Theme.fg, Theme.isDark ? 0.34 : 0.30)
            opacity: restTrack.width > Theme.dp(18) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        }
    }

    // ── Halo de estado ───────────────────────────────────────────────────────
    // Aparece detrás del agarre al cogerlo o al enfocarlo con el teclado. Es
    // el acuse de "lo tienes", y evita tener que engordar el agarre para
    // decirlo (que taparía justo lo que estás mirando).
    Rectangle {
        y: (root.height - height) / 2
        x: root.handleCenter - width / 2
        implicitWidth: Theme.dp(26)
        implicitHeight: Theme.dp(26)
        radius: width / 2
        color: Theme.withAlpha(root.accent, root.activeFocus ? 0.26 : 0.18)
        opacity: root.grabbed ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        Behavior on x { enabled: !drag.dragging; NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    }

    // ── Agarre ───────────────────────────────────────────────────────────────
    Rectangle {
        id: handle
        // Colgado del centro: al adelgazar encoge hacia dentro, sin moverse.
        x: root.handleCenter - width / 2
        y: (root.height - height) / 2
        width: root.handleW
        height: root.handleH
        radius: width / 2
        color: root.accent
        Behavior on x { enabled: !drag.dragging; NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        // La zona sensible desborda el dibujo por arriba y por abajo: el
        // control mide 28 px de alto pero el blanco real pasa de 40, que es
        // el mínimo cómodo para apuntar sin precisión. Por los lados el
        // desborde permite además llevar el valor a 0 o a 100 sin tener que
        // clavar el puntero en el píxel del extremo.
        anchors.margins: -Theme.space6
        hoverEnabled: true
        // Imprescindible: la página de Ajustes es un Flickable y, sin esto,
        // en cuanto el arrastre se desviaba un poco en vertical el Flickable
        // robaba el gesto y el slider se soltaba solo a media corrección.
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        // Puntero → valor. Se descuenta medio hueco NOMINAL (no medio agarre
        // real, que adelgaza al pulsar) para que el recorrido de aquí sea
        // exactamente el mismo que el del dibujo: donde sueltas es donde se
        // queda la pastilla, sin desfase de medio píxel.
        function ratio(mx) {
            return (mapToItem(root, mx, 0).x - root.slotW / 2) / root.travel
        }

        onPressed: (m) => { root.forceActiveFocus(); drag.press(ratio(m.x)) }
        onPositionChanged: (m) => { if (pressed) drag.update(ratio(m.x)) }
        onReleased: drag.release()
        onCanceled: drag.release()

        // Rueda SOLO con el control enfocado (es decir, después de haberlo
        // pulsado). Un slider que responde a la rueda con solo pasar por
        // encima es una trampa dentro de una página que se desplaza: al bajar
        // por Ajustes, el puntero cruza los sliders y les cambia el valor sin
        // que te enteres. Sin foco el evento se rechaza y el desplazamiento
        // llega a la página, que es lo que esperas.
        onWheel: (w) => {
            if (!root.activeFocus) {
                w.accepted = false
                return
            }
            const d = w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x
            if (d !== 0)
                drag.nudge(d > 0 ? 1 : -1,
                           (w.modifiers & Qt.ShiftModifier) ? 0.01 : 0.05)
            w.accepted = true
        }
    }
}
