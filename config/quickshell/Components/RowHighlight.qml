import QtQuick
import qs.Config

// El resaltado de una fila, uno solo para todo el shell: una banda que sangra
// fuera de la fila y aparece por opacidad, con una onda de pulsación por debajo
// del contenido.
//
// Por opacidad y no por color, que es la diferencia que se ve: pasar de
// "transparent" a un tono interpola también el canal alfa de un negro invisible,
// y el paso deja un punto turbio a mitad de camino. Subir la opacidad de un tono
// ya compuesto aparece limpio.
//
// Se declara siempre como primer hijo de la fila para quedar por debajo del
// contenido: la onda corre por la superficie, no por encima del texto.
//
//   hovered    el ratón está encima
//   selected   es la fila elegida
//   bleedX/Y   cuánto sobresale la banda
//   press(x,y) lanza la onda desde donde se ha pulsado
Item {
    id: rh

    property bool hovered: false
    property bool selected: false
    property real bleedX: 0
    property real bleedY: 0
    property real radius: Theme.dp(10)
    // Se puede teñir de otro color cuando la fila lo pide; por defecto, el del
    // shell.
    property color tint: Theme.rowHover
    property color selectedColor: Theme.rowSelected

    // Cuánto tarda la selección en aparecer, y hay dos casos. Una fila que se
    // elige cambia una vez cada mucho, y ahí un tiempo normal se lee como "ha
    // pasado algo". Una lista que se recorre con las flechas cambia diez veces
    // por segundo, y entonces dos filas quedan medio encendidas a la vez y el
    // resaltado va permanentemente por detrás de las teclas.
    property int selectMs: Theme.animNormal

    anchors.fill: parent

    function press(x, y) { onda.press(x, y) }

    // Dos capas apiladas en vez de una que cambia de color: así los cuatro
    // estados salen solos, y pasar el ratón por la fila elegida la aviva en lugar
    // de sustituir su tono.
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -rh.bleedX
        anchors.rightMargin: -rh.bleedX
        anchors.topMargin: -rh.bleedY
        anchors.bottomMargin: -rh.bleedY
        radius: rh.radius
        color: rh.selectedColor
        opacity: rh.selected ? 1 : 0
        // La selección no persigue al puntero: cambia al elegir, y ahí un tiempo
        // normal se lee como "ha pasado algo".
        Behavior on opacity {
            enabled: rh.selectMs > 0
            NumberAnimation { duration: rh.selectMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel }
        }
    }
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -rh.bleedX
        anchors.rightMargin: -rh.bleedX
        anchors.topMargin: -rh.bleedY
        anchors.bottomMargin: -rh.bleedY
        radius: rh.radius
        color: rh.tint
        opacity: rh.hovered ? (rh.selected ? 0.45 : 1) : 0
        // El hover sí persigue al puntero: entra casi instantáneo y se va con
        // calma. La salida puede tomarse su tiempo porque para entonces el ratón
        // ya está en otro sitio; la entrada no, porque es lo único que dice dónde
        // se está.
        Behavior on opacity {
            NumberAnimation {
                duration: rh.hovered ? Theme.animHover : Theme.animHoverOut
                easing.type: rh.hovered ? Easing.OutCubic : Easing.InQuad
            }
        }
    }

    Ripple {
        id: onda
        color: Theme.rowRipple
    }
}
