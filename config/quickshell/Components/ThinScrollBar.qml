import QtQuick
import QtQuick.Controls.Basic
import qs.Config

// La barra de desplazamiento fina del shell: tirador de acento, sin carril.
// Estaba definida tres veces (nav de Ajustes, contenido de Ajustes, panel del
// desplegable) con el mismo Rectangle copiado; cualquier retoque había que
// repetirlo en las tres y ya habían empezado a divergir en opacidades.
//
// Sin fondo a propósito: el carril ocupaba TODO el alto del control, márgenes
// incluidos, así que era él —y no el tirador— el que cruzaba por encima de
// las esquinas redondeadas y parecía salirse de la tarjeta.
//
// Los paddings (cuánto retranquear el tirador para librar la esquina del
// contenedor) los pone cada sitio: dependen del radio de SU contenedor.
ScrollBar {
    id: bar

    // Opacidad del tirador en reposo. 0 = solo se ve mientras se usa (la
    // barra de la página); 0.4 = siempre presente cuando hay recorrido.
    property real restOpacity: 0.4

    contentItem: Rectangle {
        implicitWidth: Theme.dp(5)
        radius: width / 2
        color: Theme.accent
        opacity: bar.pressed ? 0.9 : (bar.active ? 0.65 : bar.restOpacity)
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
    }
    background: Item {}
}
