import QtQuick
import qs.Config

// Slider expresivo de Material 3: pista gruesa partida en dos tramos y un agarre
// que no es un disco sino una pastilla vertical fina, más alta que la pista y
// separada de ambos tramos por un hueco.
//
// El hueco es lo que hace legible la posición: con un disco montado encima de
// una barra continua, el punto exacto queda tapado justo por la pieza que hay
// que leer. La pastilla ocupa poco a lo ancho y mucho a lo alto, así que apunta
// a un valor concreto en vez de a una zona.
//
// Al pulsar, la pastilla adelgaza en vez de crecer: mientras se arrastra hace
// falta ver dónde se cae, y una pieza más gorda tapa más. El acuse de haberla
// cogido lo da el halo de estado que aparece detrás.
//
// El punto del extremo marca dónde acaba el recorrido, para que un slider casi
// lleno no se confunda con uno lleno, y se esconde cuando el agarre lo tapa.
Item {
    id: root

    property real value: 0.0
    property color accent: Theme.accent
    property color trackColor: Theme.sliderTrack
    signal moved(real v)

    // Lógica de arrastre/teclado compartida (ver Components/SliderDrag.qml).
    SliderDrag { id: drag; control: root }

    // Para quien dibuje una lectura al lado y necesite saber si el control se
    // está moviendo ahora mismo.
    readonly property bool dragging: drag.dragging

    readonly property bool hot: ma.containsMouse || ma.pressed || root.activeFocus
    readonly property bool grabbed: ma.pressed || root.activeFocus

    // La pista engorda al tocarla. No van como 'readonly' porque un Behavior no
    // puede animar una propiedad de solo lectura; siguen siendo bindings, solo
    // que admiten que la animación los mueva.
    property int trackH: root.hot ? Theme.dp(16) : Theme.dp(12)
    property int handleW: root.grabbed ? Theme.dp(3) : Theme.dp(4)
    property int handleH: root.grabbed ? Theme.dp(28) : Theme.dp(22)
    readonly property int gap: Theme.dp(5)

    // 'slotW' es el grosor nominal del agarre y es constante. Toda la geometría
    // —recorrido, tramos, mapeo del puntero— se calcula con él y nunca con
    // 'handleW', que adelgaza al pulsar y además animado: con el recorrido
    // dependiendo de él, al agarrar el slider el recorrido se alargaría de forma
    // continua durante la animación, el agarre se desplazaría solo bajo el dedo y
    // el mapeo dividiría entre un número que cambia por fotograma.
    readonly property real slotW: Theme.dp(4)
    readonly property real travel: Math.max(1, width - slotW)
    // Centro del agarre, que es el punto que señala el valor. El rectángulo se
    // cuelga de él, así que al adelgazar encoge simétricamente en vez de
    // desplazarse.
    readonly property real handleCenter: slotW / 2 + drag.shownValue * travel

    activeFocusOnTab: enabled
    implicitHeight: Theme.dp(28)

    // Teclado: con Mayúsculas el paso baja al 1 % para afinar, Re Pág y Av Pág
    // dan saltos del 10 % e Inicio y Fin van a los extremos.
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

    Behavior on trackH { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
    Behavior on handleW { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
    Behavior on handleH { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }

    // Degradado dentro del mismo tono, del acento aclarado al acento. Con dos
    // acentos distintos, una paleta dinámica puede dejarlos en lados opuestos del
    // círculo cromático y la pista se convierte en un arcoíris que no dice nada.
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
        // Al arrastrar sigue al dedo 1:1; fuera del arrastre el salto se suaviza.
        Behavior on width { enabled: !drag.dragging; NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }

        // Va encima del degradado y no en su lugar: el degradado da la
        // profundidad y la onda pone el movimiento. Sustituirlo dejaba una línea
        // suelta flotando sobre el hueco de la pista.
        // La onda aparece al tocar y se retira al soltar, en vez de estar siempre
        // puesta: en reposo la pista vuelve a ser una barra limpia con su
        // degradado, y no hay lienzo repintando mientras no pasa nada. Una onda
        // permanente ocuparía casi todo el carril y competiría con el degradado.
        //
        // "Algo pasa" es: se está arrastrando, hay puntero encima, o el valor ha
        // cambiado solo hace poco.
        WavyTrack {
            id: onda
            anchors.fill: parent
            readonly property bool activa: drag.dragging || root.hot || externo.running

            // Con las animaciones desactivadas no aparece: una onda quieta es
            // una raya con bultos, y no es lo que se está pidiendo.
            visible: Theme.animNormal > 0 && opacity > 0.01
                     && parent.width > root.trackH * 2
            opacity: onda.activa ? 1 : 0
            // Crece al entrar en vez de aparecer ya ondulada: la onda se levanta
            // de la barra.
            amplitude: onda.activa ? 0.6 : 0.05
            // Sigue moviéndose mientras se ve, también durante el desvanecido:
            // parándose antes, se congelaría a media retirada.
            animated: onda.opacity > 0.01

            color: Theme.withAlpha(Qt.lighter(root.accent, 1.35), 0.9)
            lineWidth: Math.max(2, root.trackH * 0.30)

            Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
            Behavior on amplitude { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSpatial } }
        }
    }

    // ¿Ha cambiado el valor por su cuenta hace poco? Distingue "se está mirando
    // esto" de "esto está pasando ahora mismo", como el volumen que sube desde
    // una tecla. Mientras dure, la onda se mueve aunque no haya puntero encima.
    Timer {
        id: externo
        interval: 900
    }
    onValueChanged: if (!drag.dragging) externo.restart()

    // Tramo pendiente
    Rectangle {
        id: restTrack
        y: (root.height - height) / 2
        x: Math.min(root.width, root.handleCenter + root.slotW / 2 + root.gap)
        width: Math.max(0, root.width - x)
        height: root.trackH
        radius: height / 2
        color: root.trackColor
        visible: width > 0.5
        Behavior on x { enabled: !drag.dragging; NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }

        // Fin del recorrido. Se apaga cuando el agarre está a punto de pisarlo,
        // para que no parezca que quedan dos piezas sueltas.
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

    // Aparece detrás del agarre al cogerlo o al enfocarlo con el teclado. Es el
    // acuse de "lo tienes", y evita engordar el agarre para decirlo, que taparía
    // justo lo que se está mirando.
    Rectangle {
        y: (root.height - height) / 2
        x: root.handleCenter - width / 2
        implicitWidth: Theme.dp(26)
        implicitHeight: Theme.dp(26)
        radius: width / 2
        color: Theme.withAlpha(root.accent, root.activeFocus ? 0.26 : 0.18)
        opacity: root.grabbed ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        Behavior on x { enabled: !drag.dragging; NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
    }

    // Agarre
    Rectangle {
        id: handle
        // Colgado del centro: al adelgazar encoge hacia dentro, sin moverse.
        x: root.handleCenter - width / 2
        y: (root.height - height) / 2
        width: root.handleW
        height: root.handleH
        radius: width / 2
        color: root.accent
        Behavior on x { enabled: !drag.dragging; NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        // La zona sensible desborda el dibujo por arriba y por abajo hasta el
        // mínimo cómodo para apuntar sin precisión. Por los lados el desborde
        // permite además llevar el valor a los extremos sin clavar el puntero en
        // el píxel final.
        anchors.margins: -Theme.space6
        hoverEnabled: true
        // La página de Ajustes es un Flickable: sin esto, en cuanto el arrastre
        // se desvía un poco en vertical el Flickable roba el gesto y el slider se
        // suelta solo a media corrección.
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        // Puntero → valor. Se descuenta medio hueco nominal, no medio agarre
        // real, para que el recorrido coincida exactamente con el del dibujo y no
        // haya desfase al soltar.
        function ratio(mx) {
            return (mapToItem(root, mx, 0).x - root.slotW / 2) / root.travel
        }

        onPressed: (m) => { root.forceActiveFocus(); drag.press(ratio(m.x)) }
        onPositionChanged: (m) => { if (pressed) drag.update(ratio(m.x)) }
        onReleased: drag.release()
        onCanceled: drag.release()

        // Rueda solo con el control enfocado, o sea después de haberlo pulsado.
        // Un slider que responde a la rueda con solo pasar por encima es una
        // trampa dentro de una página que se desplaza: bajar por Ajustes cruzaría
        // los sliders cambiándoles el valor. Sin foco el evento se rechaza y el
        // desplazamiento llega a la página.
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
