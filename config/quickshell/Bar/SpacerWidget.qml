import QtQuick
import qs.Config

// Hueco fijo entre widgets. No pinta nada: existe para separar grupos dentro
// de una misma sección de la barra —dejar la bandeja pegada al borde y el
// resto del estado agrupado a su izquierda, por ejemplo— sin tener que
// inventar una cuarta sección.
//
// Es el único widget que admite varias instancias (BarCatalog: multiple), por
// razones obvias: un separador solo tiene sentido si puedes poner los que
// necesites.
Item {
    id: root

    // Mismo contrato que Pill: la barra pregunta 'shown' para saber si el
    // widget ocupa sitio.
    property bool shown: true

    implicitWidth: Theme.dp(24)
    implicitHeight: Theme.barPillHeight
}
