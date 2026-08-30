import QtQuick
import qs.Config

// EL RESALTADO DE UNA FILA. Uno solo, para todo el shell.
//
// Existía ya —y muy trabajado— dentro de SwitchRow: una banda que sangra fuera
// de la fila, que aparece por OPACIDAD y no cambiando de color, con curva de
// salida, y una onda de pulsación por debajo del contenido. El problema es que
// vivía ahí dentro, así que las listas del panel de IA se resaltaban a su
// manera: fundiendo el color a pelo, sin curva y sin sangrado. Se notaba.
//
// Por qué opacidad y no color, que es la diferencia que de verdad se ve: pasar
// de "transparent" a un tono interpola también por el CANAL ALFA de un negro
// invisible, y el paso deja un punto turbio a mitad de camino. Subir la
// opacidad de un tono ya compuesto no tiene ese problema: aparece limpio.
//
// Se declara SIEMPRE como primer hijo de la fila, para que quede por debajo del
// contenido — en Material la onda corre por la superficie, no por encima del
// texto.
//
//   hovered    el ratón está encima
//   selected   es la fila elegida
//   bleedX/Y   cuánto sobresale la banda (0 en listas estrechas; en una tarjeta
//              de ajustes respira mejor sobresaliendo)
//   press(x,y) lanza la onda desde donde se ha pulsado
Item {
    id: rh

    property bool hovered: false
    property bool selected: false
    property real bleedX: 0
    property real bleedY: 0
    property real radius: Theme.dp(10)
    // Se puede teñir de otro color cuando la fila lo pide (una fila de peligro,
    // por ejemplo); por defecto, el del shell.
    property color tint: Theme.rowHover
    property color selectedColor: Theme.rowSelected

    anchors.fill: parent

    function press(x, y) { onda.press(x, y) }

    // Dos capas apiladas en vez de una que cambia de color: así los cuatro
    // estados (nada, encima, elegida, elegida y encima) salen solos, y pasar el
    // ratón por la fila elegida la aviva un punto en lugar de sustituir su
    // tono por otro.
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -rh.bleedX
        anchors.rightMargin: -rh.bleedX
        anchors.topMargin: -rh.bleedY
        anchors.bottomMargin: -rh.bleedY
        radius: rh.radius
        color: rh.selectedColor
        opacity: rh.selected ? 1 : 0
        // La SELECCIÓN no persigue al puntero: cambia cuando eliges, y ahí un
        // tiempo normal se lee como "ha pasado algo", que es lo que quieres.
        Behavior on opacity {
            NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel }
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
        // El HOVER sí persigue al puntero: entra casi instantáneo (Theme.
        // animHover) y se va con calma. La salida puede tomarse su tiempo
        // porque, cuando ocurre, el ratón ya está en otro sitio; la entrada no,
        // porque es lo único que le dice al usuario dónde está.
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
