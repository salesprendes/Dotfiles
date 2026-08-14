import QtQuick

// Lógica de arrastre y teclado compartida por Slider (fino) y el FatSlider
// del Centro de control: al arrastrar, el relleno sigue al puntero con un
// valor local (dragValue) sin esperar el "eco" del backend (PipeWire /
// brillo), que llega con retardo; al soltar se vuelve al valor real ya
// asentado. nudge() da pasos de teclado del 5%.
QtObject {
    id: d

    // El control dueño: debe exponer 'value' (real 0..1) y la señal moved(real).
    required property var control

    property bool dragging: false
    property real dragValue: 0
    readonly property real shownValue: dragging ? dragValue : control.value

    // Paso de teclado/rueda. 'step' es opcional (5% por defecto) para que
    // quien quiera afinar pueda pedir un paso más fino sin duplicar la
    // lógica de recorte; los usos antiguos con un solo argumento siguen igual.
    function nudge(delta, step) {
        const s = (step === undefined) ? 0.05 : step
        control.moved(Math.max(0, Math.min(1, control.value + delta * s)))
    }

    // Salto directo a un valor absoluto (Inicio / Fin).
    function jumpTo(v01) {
        control.moved(Math.max(0, Math.min(1, v01)))
    }

    function update(v01) {
        const v = Math.max(0, Math.min(1, v01))
        dragValue = v
        control.moved(v)
    }

    function press(v01) { dragging = true; update(v01) }
    function release() { dragging = false }
}
