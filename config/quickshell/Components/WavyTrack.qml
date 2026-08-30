import QtQuick
import qs.Config

// Pista ondulada de Material 3 Expressive: el tramo RECORRIDO de un deslizador
// dibujado como una onda en vez de una barra recta.
//
// ── POR QUÉ SOLO EL TRAMO RECORRIDO ─────────────────────────────────────────
// En M3E la onda vive en lo que ya está hecho y lo pendiente va recto. Esa
// asimetría es lo que hace que se lea como energía —algo está pasando aquí— y
// no como un adorno repartido por todo el control.
//
// ── POR QUÉ NO ESTÁ SIEMPRE ─────────────────────────────────────────────────
// Es un Canvas, y animarlo cuesta un repintado por fotograma. La referencia de
// la que viene esto (nandoroid) mueve la fase con Date.now() de forma continua;
// en una página de Ajustes con ocho deslizadores a la vista, eso son ocho
// lienzos repintando a 60 Hz para que nadie los mire.
//
// Quien lo usa (ver Components/Slider.qml) la hace APARECER al tocar el control
// y retirarse al soltar. Gana el aspecto y el coste: en reposo la pista vuelve
// a ser una barra limpia con su degradado —una onda permanente ocupaba trece de
// los dieciséis píxeles del carril y competía con él— y no hay lienzo pintando.
Item {
    id: root

    property color color: Theme.accent
    // Grosor de la onda. Se queda por debajo del alto de la pista para que la
    // curva quepa entera con su amplitud sin recortarse arriba y abajo.
    property real lineWidth: Math.max(2, height * 0.42)
    // Cuánto sube y baja, en múltiplos del grosor.
    property real amplitude: 0.6
    // Ciclos por cada 100 px. En vez de un número fijo de ondas repartidas por
    // el ancho: si fuera fijo, al mover el deslizador la onda se estiraría y
    // encogería —el pasado se movería— en vez de desplazarse.
    property real cyclesPer100: 1.6
    // Mientras esto sea true la onda avanza.
    property bool animated: false

    property real phase: 0

    // El reloj solo corre con 'animated'. FrameAnimation y no un Timer: da el
    // tiempo real entre fotogramas, así la onda avanza a la misma velocidad
    // aunque el sistema vaya justo.
    FrameAnimation {
        running: root.animated && root.visible && root.width > 1
        onTriggered: {
            root.phase += frameTime * 6
            lienzo.requestPaint()
        }
    }

    // Fuera de la animación hay que repintar igual cuando cambia la forma o el
    // color, o la onda se quedaría dibujada con el ancho de antes.
    onWidthChanged: if (!animated) lienzo.requestPaint()
    onHeightChanged: if (!animated) lienzo.requestPaint()
    onColorChanged: if (!animated) lienzo.requestPaint()
    onAmplitudeChanged: if (!animated) lienzo.requestPaint()
    onAnimatedChanged: if (!animated) lienzo.requestPaint()

    Canvas {
        id: lienzo
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            if (width <= 1 || height <= 0)
                return

            const lw = root.lineWidth
            const amp = lw * root.amplitude
            const medio = height / 2
            // Se dibuja de medio grosor a medio grosor: con lineCap redondo,
            // el trazo se sale por los extremos justo esa mitad.
            const x0 = lw / 2
            const x1 = width - lw / 2
            if (x1 <= x0)
                return

            const w = 2 * Math.PI * root.cyclesPer100 / 100

            ctx.strokeStyle = root.color
            ctx.lineWidth = lw
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.beginPath()
            for (let x = x0; x <= x1; x += 1) {
                // La fase depende de la x ABSOLUTA, no de la fracción del
                // ancho: así la onda se queda clavada al sitio y el tramo
                // recorrido la va destapando al crecer, en vez de estirarse.
                const y = medio + amp * Math.sin(x * w + root.phase)
                if (x === x0)
                    ctx.moveTo(x, y)
                else
                    ctx.lineTo(x, y)
            }
            ctx.stroke()
        }
    }
}
