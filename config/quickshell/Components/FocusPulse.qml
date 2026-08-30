import QtQuick

// Da el foco de teclado a un campo, insistiendo hasta que lo coge.
//
// ── EL PROBLEMA, QUE ES DE CARRERA ──────────────────────────────────────────
// Un `forceActiveFocus()` en cuanto se abre un panel se pierde: la superficie
// se ha construido, pero el compositor todavía no le ha entregado el foco de
// teclado, así que la petición cae sobre una ventana que aún no puede tenerlo.
// No avisa: simplemente no pasa nada, y el usuario tiene que hacer clic en el
// campo antes de escribir.
//
// El shell lo esquivaba con un `Timer { interval: 60 }` de una sola pulsación,
// copiado en seis paneles. Funciona casi siempre, y "casi" es el problema: con
// el sistema cargado, 60 ms no bastan y el fallo reaparece — sin dejar rastro,
// porque no hay error, solo un campo que no responde.
//
// Aquí se insiste hasta que agarra, con tope para no dejar un temporizador
// corriendo para siempre si algo va mal. En cuanto el objetivo tiene el foco,
// el temporizador se apaga solo (su 'running' lo mira).
//
// USO:
//     FocusPulse { id: foco; target: searchField.input }
//     onShownChanged: if (shown) foco.start()
Item {
    id: root

    // El item que debe acabar con el foco.
    property Item target: null
    // Mientras esto sea false no se intenta nada. Sirve para atarlo a la
    // visibilidad del panel y que deje de insistir al cerrarse.
    property bool active: false

    property int interval: 40
    // 60 intentos × 40 ms = 2,4 s. Pasado eso, o el panel ya no está o hay algo
    // más roto que un foco, y seguir intentándolo es ruido.
    property int maxAttempts: 60
    property int attempts: 0

    visible: false

    function start() {
        root.attempts = 0
        root.active = true
    }

    function stop() {
        root.active = false
    }

    readonly property bool _needed: root.active && root.target !== null
                                    && !root.target.activeFocus
                                    && root.attempts < root.maxAttempts

    Timer {
        interval: root.interval
        repeat: true
        running: root._needed
        // Al primero no se espera: el caso normal es que el foco ya se pueda
        // tomar, y hacerle esperar 40 ms a todo el mundo por el caso raro es
        // pagar el peaje al revés.
        triggeredOnStart: true
        onTriggered: {
            root.attempts++
            if (root.target)
                root.target.forceActiveFocus()
        }
    }
}
