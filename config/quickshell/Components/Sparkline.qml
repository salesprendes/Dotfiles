import QtQuick
import qs.Config

// Gráfica de línea para una serie temporal corta (CPU, memoria, red…).
//
// Va en Canvas y no en un Shape porque una serie de sesenta puntos que se
// desplaza entera cada segundo se dibuja de una pasada con dos bucles; con
// Shape habría que reconstruir el path como objetos QML en cada tick.
Item {
    id: root

    // La serie, del más viejo al más nuevo.
    property var values: []
    // Techo del eje Y. Si es <= 0 se calcula del propio dato (ver 'techo'):
    // hace falta para la red, que no tiene un 100 % al que referirse.
    property real maxValue: 100
    property color lineColor: Theme.accent
    property real fillOpacity: 0.16
    property real lineWidth: Math.max(1, Theme.dp(2))
    // Cuántas divisiones horizontales de fondo. 0 = ninguna.
    property int gridLines: 3

    implicitHeight: Theme.dp(56)

    // Techo efectivo. Con 'maxValue' positivo manda ese —una gráfica de CPU
    // tiene que llegar al 100 aunque la máquina no pase del 30, o parecería
    // saturada—; sin él se toma el mayor de la serie con un margen del 15 %,
    // que es lo que evita que la línea vaya rozando el borde superior.
    readonly property real techo: {
        if (root.maxValue > 0)
            return root.maxValue
        let m = 0
        const v = root.values || []
        for (let i = 0; i < v.length; i++)
            if (v[i] > m)
                m = v[i]
        return m > 0 ? m * 1.15 : 1
    }

    // Solo se repinta si se está VIENDO. Sin esto, una gráfica en una pestaña
    // que no está delante seguiría repintándose con cada punto nuevo: es la
    // misma regla que ya siguen el ecualizador y el muelle de la isla.
    onValuesChanged: if (root.visible) lienzo.requestPaint()
    onVisibleChanged: if (root.visible) lienzo.requestPaint()
    onWidthChanged: if (root.visible) lienzo.requestPaint()
    onHeightChanged: if (root.visible) lienzo.requestPaint()
    onLineColorChanged: if (root.visible) lienzo.requestPaint()

    Canvas {
        id: lienzo
        anchors.fill: parent
        antialiasing: true
        // Image + Immediate: el dibujo es corto y se repite cada segundo, así
        // que interesa que salga ya en vez de pasar por el hilo de render.
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)

            const w = width, h = height
            if (w <= 0 || h <= 0)
                return

            // Rejilla de fondo. Se dibuja siempre, también con la serie vacía:
            // una caja vacía con sus divisiones se lee como "aún no hay datos",
            // y una caja del todo vacía como "esto está roto".
            if (root.gridLines > 0) {
                ctx.strokeStyle = Theme.withAlpha(Theme.overlay, 0.35)
                ctx.lineWidth = 1
                for (let g = 1; g <= root.gridLines; g++) {
                    const gy = Math.round(h * g / (root.gridLines + 1)) + 0.5
                    ctx.beginPath()
                    ctx.moveTo(0, gy)
                    ctx.lineTo(w, gy)
                    ctx.stroke()
                }
            }

            const v = root.values || []
            if (v.length < 2)
                return

            // El paso se calcula sobre la LONGITUD MÁXIMA, no sobre los puntos
            // que hay: así la gráfica se llena de izquierda a derecha al abrir
            // en vez de estirar cuatro puntos a todo lo ancho y encogerlos con
            // cada uno nuevo — que se ve como si el pasado se moviera.
            const n = Math.max(v.length, 2)
            const paso = w / (n - 1)
            const techo = root.techo

            function py(valor) {
                const c = Math.max(0, Math.min(techo, valor))
                return h - (c / techo) * h
            }

            ctx.beginPath()
            ctx.moveTo(0, py(v[0]))
            for (let i = 1; i < v.length; i++)
                ctx.lineTo(i * paso, py(v[i]))

            // Relleno bajo la curva: se cierra contra el suelo y se pinta antes
            // de la línea, para que el trazo quede limpio encima.
            ctx.save()
            ctx.lineTo((v.length - 1) * paso, h)
            ctx.lineTo(0, h)
            ctx.closePath()
            const grad = ctx.createLinearGradient(0, 0, 0, h)
            grad.addColorStop(0, Theme.withAlpha(root.lineColor, root.fillOpacity))
            grad.addColorStop(1, Theme.withAlpha(root.lineColor, 0))
            ctx.fillStyle = grad
            ctx.fill()
            ctx.restore()

            ctx.beginPath()
            ctx.moveTo(0, py(v[0]))
            for (let i = 1; i < v.length; i++)
                ctx.lineTo(i * paso, py(v[i]))
            ctx.strokeStyle = root.lineColor
            ctx.lineWidth = root.lineWidth
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.stroke()

            // Punto en el valor de ahora: en una serie que se desplaza, el
            // extremo derecho es el único que se está mirando de verdad.
            const ux = (v.length - 1) * paso
            const uy = py(v[v.length - 1])
            ctx.beginPath()
            ctx.arc(Math.min(ux, w - root.lineWidth), uy, root.lineWidth * 1.6, 0, Math.PI * 2)
            ctx.fillStyle = root.lineColor
            ctx.fill()
        }
    }
}
