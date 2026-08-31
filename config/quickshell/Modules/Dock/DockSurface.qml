import QtQuick
import QtQuick.Effects
import qs.Config

// La superficie de la que están hechos el dock y sus tres globos.
//
// Existe porque las cuatro se habían ido separando sin que nadie lo decidiera:
// la luz del canto era 0,07 con corte en 0,45 en la pastilla, 0,07 con corte en
// 0,50 en la etiqueta y 0,06 con corte en 0,45 en la vista previa, y el menú no
// tenía ni luz ni sombra — un globo flotante con el filete plano de una tarjeta
// empotrada, al lado de otros dos que sí flotaban. Ninguna de esas diferencias
// respondía a nada; son las que aparecen al tocar tres archivos en tres días
// distintos.
//
// Lo que se unifica es lo que no tenía por qué diferir: la sombra y la luz del
// canto. El COLOR y el FILETE se dejan a quien la usa, y eso sí es deliberado:
// la pastilla del dock es translúcida sobre el fondo de escritorio y necesita un
// filete de 'overlay' para no parecer un recorte; los globos son opacos y llevan
// el 'outlineVariant' que usa el resto del shell para contenedores opacos. Un
// solo filete para las dos cosas sería unificar de más.
Rectangle {
    id: sup

    // Redondeo por esquina. Se declaran los cuatro aquí en vez de dejar que cada
    // consumidor toque 'topLeftRadius' y compañía porque el degradado de la luz
    // tiene que seguir EXACTAMENTE la misma forma: si se sale por una esquina,
    // asoma una uña de blanco fuera del borde.
    property real radioTL: sup.radius
    property real radioTR: sup.radius
    property real radioBL: sup.radius
    property real radioBR: sup.radius

    // Cuánto baja la luz del canto antes de apagarse. Es lo único que se deja
    // ajustar del degradado: en una pastilla baja de 73 px y en una etiqueta de
    // 30 px, el mismo 0,45 no cae en el mismo sitio del arco.
    property real corteLuz: 0.45
    property bool luz: true

    property bool sombra: Settings.dockShadow
    property real sombraBlur: Theme.dp(18)
    property real sombraSpread: Theme.dp(1)
    property real sombraBaja: Theme.dp(2)

    color: Theme.surfaceContainer
    border.width: 1
    border.color: Theme.outlineVariant
    antialiasing: true

    topLeftRadius: sup.radioTL
    topRightRadius: sup.radioTR
    bottomLeftRadius: sup.radioBL
    bottomRightRadius: sup.radioBR

    // La sombra va DENTRO con z negativo y no como hermana en el padre: como
    // hermana obliga a cada consumidor a colocarla y a mantener sincronizados el
    // radio y el tamaño a mano, que es justo lo que se acaba de arreglar. Un
    // Rectangle con radio no recorta a sus hijos —solo lo haría con clip o con
    // layer.enabled—, así que la sombra desborda el borde sin problema.
    RectangularShadow {
        anchors.fill: parent
        visible: sup.sombra
        radius: sup.radius
        blur: sup.sombraBlur
        spread: sup.sombraSpread
        offset: Qt.vector2d(0, sup.sombraBaja)
        color: Theme.withAlpha("#000000", Theme.isDark ? 0.45 : 0.22)
        cached: true
        z: -1
    }

    // Luz en el canto de arriba. Es lo que separa "rectángulo semitransparente"
    // de "cristal": una superficie translúcida se lee como material cuando el
    // borde superior recoge algo de luz.
    //
    // Va como degradado y no como filete de 1 px porque el borde de arriba de
    // una pastilla es un arco, y un rectángulo no lo sigue. El degradado sí, y
    // sirve igual para el radio que tenga.
    Rectangle {
        anchors.fill: parent
        visible: sup.luz
        topLeftRadius: sup.radioTL
        topRightRadius: sup.radioTR
        bottomLeftRadius: sup.radioBL
        bottomRightRadius: sup.radioBR
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Theme.withAlpha("#ffffff", Theme.isDark ? 0.07 : 0.30)
            }
            GradientStop { position: sup.corteLuz; color: "transparent" }
        }
    }
}
