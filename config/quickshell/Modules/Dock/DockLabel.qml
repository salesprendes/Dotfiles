import QtQuick
import qs.Components
import qs.Config

// El nombre de la app, sobre su icono.
//
// Existe porque la vista previa no llega a todo: tarda medio segundo a
// propósito —es un globo con miniaturas, aparecer al roce sería insufrible— y
// se puede desactivar entera desde Ajustes. Una app FIJADA que no está abierta
// se queda entonces sin ninguna forma de decir cómo se llama, que es justo
// cuando hace falta: un icono que no reconoces es siempre uno que no has
// abierto todavía.
//
// Se retira en cuanto la vista previa se abre; esa ya lleva el nombre en su
// primera línea y dos globos a la vez sobre el mismo icono sobran.
Item {
    id: root

    property string texto: ""

    // Lo que asoma de la punta por debajo de la pastilla (ver 'punta' abajo).
    readonly property int puntaAlto: Theme.dp(5)
    // Un nombre largo no puede cruzar media pantalla; a partir de aquí, elide.
    readonly property int anchoMax: Theme.dp(260)

    implicitWidth: Math.min(root.anchoMax, etiqueta.implicitWidth + Theme.space12 * 2)
    implicitHeight: pastilla.height + root.puntaAlto

    // Entra subiendo desde el icono y con fundido: aparecer de golpe a mitad de
    // camino del cursor se lee como un parpadeo, no como una respuesta.
    opacity: 0
    transform: Translate { id: entrada; y: Theme.dp(5) }
    Component.onCompleted: aparecer.start()
    ParallelAnimation {
        id: aparecer
        NumberAnimation {
            target: root; property: "opacity"; to: 1
            duration: Theme.animFast; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: entrada; property: "y"; to: 0
            duration: Theme.animNormal
            easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel
        }
    }

    // La pastilla, la sombra y la luz del canto salen de DockSurface, que es lo
    // que comparten las cuatro superficies del dock. Aquí solo se ajusta lo que
    // de verdad es distinto: una sombra algo más corta —esto flota un dedo por
    // encima del dock, no un palmo— y un corte de luz más abajo, porque en una
    // pastilla de 30 px el 0,45 de una de 73 px cae ya fuera del arco.
    DockSurface {
        id: pastilla
        width: root.width
        height: etiqueta.implicitHeight + Theme.space6 * 2
        // Pastilla completa, como el propio dock: es una etiqueta, no una tarjeta.
        radius: height / 2
        // El mismo filete translúcido que el dock, y no el de los globos opacos:
        // esto es la misma pieza de cristal, más pequeña.
        border.color: Theme.withAlpha(Theme.overlay, 0.35)
        corteLuz: 0.5
        sombraBlur: Theme.dp(14)

        // La punta que señala al icono. Es lo que convierte un rectángulo que
        // flota cerca en una etiqueta que habla de ESE icono, y con varios iconos
        // seguidos es la diferencia entre saber de cuál habla y suponerlo.
        //
        // Va con z negativo, que es lo que la deja DEBAJO del fondo de la
        // pastilla: así la pastilla le tapa la mitad de arriba y el filete que
        // la cruzaría por dentro. Con z negativo también queda por detrás de la
        // sombra, que es hermana suya y se declara antes.
        Rectangle {
            id: punta
            z: -1
            width: Theme.dp(10)
            height: width
            rotation: 45
            antialiasing: true
            color: pastilla.color
            border.width: pastilla.border.width
            border.color: pastilla.border.color
            x: Math.round((pastilla.width - width) / 2)
            y: pastilla.height - Math.round(height / 2)
        }

        ThemedText {
            id: etiqueta
            anchors.centerIn: parent
            // Acotado al ancho real: 'implicitWidth' es el natural y no depende
            // de este, así que no hay bucle.
            width: Math.min(implicitWidth, pastilla.width - Theme.space12 * 2)
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            text: root.texto
            color: Theme.fg
            font.pixelSize: Theme.fontSize
            font.weight: Font.DemiBold
        }
    }
}
