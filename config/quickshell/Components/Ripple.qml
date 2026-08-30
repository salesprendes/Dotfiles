import QtQuick
import qs.Config

// Onda de pulsación de Material: nace en el punto donde pinchas, se expande
// hasta cubrir el control y se apaga. Es el gesto que dice "te he oído" sin
// esperar a que la acción termine, y lo que hace que un panel se sienta
// táctil en vez de estático.
//
// La onda NO se recorta con una máscara: se recorta sola por geometría. Es una
// pastilla (radio = su propio alto / 2) centrada verticalmente que crece hasta
// coincidir con el control. Como su redondeo es siempre el máximo posible para
// su alto, y su alto nunca supera el del control, la forma queda SIEMPRE dentro
// de cualquier contenedor redondeado — sin OpacityMask (Qt5Compat no está
// instalado en este equipo) y sin capas de composición, que costarían GPU en
// cada pestaña de la nav.
Item {
    id: root

    anchors.fill: parent
    property color color: Theme.withAlpha(Theme.fg, Theme.isDark ? 0.16 : 0.13)

    function press(px, py) {
        wave.originX = px
        anim.restart()
    }

    Rectangle {
        id: wave

        property real originX: 0
        // 0 → 1: lo animado. De aquí salen alto, ancho y posición.
        property real progress: 0
        // Lo que le falta por llegar al borde más lejano: así la onda tarda lo
        // mismo en cubrir el control se pinche donde se pinche.
        readonly property real spread: Math.max(originX, root.width - originX)

        height: root.height * progress
        y: (root.height - height) / 2
        x: Math.max(0, originX - spread * progress)
        width: Math.min(root.width, originX + spread * progress) - x
        radius: height / 2
        color: root.color
        opacity: 0
    }

    ParallelAnimation {
        id: anim
        NumberAnimation {
            target: wave; property: "progress"
            from: 0; to: 1
            duration: Theme.animSlow; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel
        }
        // Entra deprisa y se va despacio: al revés se percibe como un
        // parpadeo, no como un material que responde.
        SequentialAnimation {
            NumberAnimation {
                target: wave; property: "opacity"
                from: 0; to: 1; duration: Theme.animFast
            }
            NumberAnimation {
                target: wave; property: "opacity"
                to: 0; duration: Theme.animSlow
            }
        }
    }
}
