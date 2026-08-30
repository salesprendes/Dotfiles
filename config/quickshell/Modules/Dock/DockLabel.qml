import QtQuick
import QtQuick.Effects
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

    // La punta que señala al icono. Es lo que convierte un rectángulo que
    // flota cerca en una etiqueta que habla de ESE icono, y con varios iconos
    // seguidos es la diferencia entre saber de cuál habla y suponerlo.
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

    // La misma sombra que el dock, para que los dos floten a la misma altura.
    RectangularShadow {
        anchors.fill: pastilla
        visible: Settings.dockShadow
        radius: pastilla.radius
        blur: Theme.dp(14)
        spread: Theme.dp(1)
        offset: Qt.vector2d(0, Theme.dp(2))
        color: Theme.withAlpha("#000000", Theme.isDark ? 0.45 : 0.22)
        cached: true
    }

    // Va ANTES de la pastilla en el árbol para que su mitad de arriba —y el
    // filete que la cruzaría por dentro— queden tapados por ella.
    Rectangle {
        id: punta
        width: Theme.dp(10)
        height: width
        rotation: 45
        antialiasing: true
        color: pastilla.color
        border.width: pastilla.border.width
        border.color: pastilla.border.color
        x: Math.round((root.width - width) / 2)
        y: root.height - root.puntaAlto - Math.round(height / 2)
    }

    Rectangle {
        id: pastilla
        width: root.width
        height: etiqueta.implicitHeight + Theme.space6 * 2
        // Pastilla completa, como el propio dock: es una etiqueta, no una tarjeta.
        radius: height / 2
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.withAlpha(Theme.overlay, 0.35)
        antialiasing: true

        // La misma luz en el canto de arriba que la pastilla del dock. Es lo que
        // hace que las dos superficies se lean como el mismo material.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Theme.withAlpha("#ffffff", Theme.isDark ? 0.07 : 0.30)
                }
                GradientStop { position: 0.5; color: "transparent" }
            }
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
