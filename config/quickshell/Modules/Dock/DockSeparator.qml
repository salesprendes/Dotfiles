import QtQuick
import qs.Config

// La rayita entre las apps fijadas y las que solo están abiertas.
//
// Es un filete de 1 dp y no un hueco más ancho a propósito: el hueco solo dice
// "aquí hay una pausa", mientras que la rayita dice "lo de la izquierda lo has
// puesto tú, lo de la derecha aparece solo". Esa distinción es la que hace que
// no sorprenda que un icono desaparezca al cerrar su ventana.
Rectangle {
    id: root

    implicitWidth: 1
    color: Theme.outlineVariant
    opacity: 0.6
}
