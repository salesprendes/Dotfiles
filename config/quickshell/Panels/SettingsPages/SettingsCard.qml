import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Panels.SettingsPages
import qs.Components

// Grupo de ajustes al modo de ChromeOS: el rótulo va FUERA, encima de la
// tarjeta, y dentro las filas se pegan unas a otras separadas por un filete.
//
// Antes el rótulo vivía dentro, en versalitas espaciadas y con su glifo, y las
// filas flotaban sueltas con aire entre ellas. Se cambió por tres razones, y
// las tres son de ChromeOS:
//
//   · El rótulo fuera convierte la tarjeta en UNA superficie continua. Dentro,
//     el rótulo era una fila más y la tarjeta perdía su condición de bloque.
//   · Las versalitas espaciadas son el gesto tipográfico del Material viejo;
//     Google las abandonó. Un rótulo en caja normal se lee antes y grita menos.
//   · El filete entre filas hace el trabajo que antes hacía el hueco, y lo hace
//     mejor: separa sin dispersar, y deja las filas leerse como una lista.
//
// El glifo del rótulo desaparece: los rótulos de sección de ChromeOS no lo
// llevan, y las filas ya tienen el suyo. Dos iconos por bloque era uno de más.
Item {
    id: cardRoot
    // Marca de tarjeta: sus hermanas la usan para contarse (ver cardIndex).
    readonly property bool isSettingsCard: true
    property string title: ""
    // Frase que explica de qué va la sección. Va bajo el rótulo y FUERA de la
    // tarjeta, que es donde ChromeOS pone este texto.
    //
    // Antes esto se escribía como un Hint dentro de la tarjeta, y ahí se veía
    // mal por una razón concreta: dentro, un párrafo suelto es una fila más —
    // pero sin insignia, sin control y sin filete, así que rompe la retícula de
    // la lista justo en la primera línea. Fuera es lo que de verdad es: el
    // subtítulo del rótulo. El Hint sigue existiendo para lo que sí es un
    // consejo sobre UNA fila concreta.
    property string description: ""
    // Se mantiene por compatibilidad con las páginas que lo pasan; ya no se
    // pinta (ver la nota de arriba).
    property string glyph: ""
    // Condición propia de la página (p. ej. "solo si el terminal es configurable").
    // Va aparte de 'visible' para no pisar el binding del filtro.
    property bool shown: true
    default property alias content: cardCol.data

    Layout.fillWidth: true
    // Aire extra sobre el rótulo. ChromeOS separa las secciones bastante más de
    // lo que separa las filas dentro de una: es lo que hace que una página
    // larga se lea como varios bloques y no como una lista continua. Va aquí y
    // no en el 'spacing' de cada página porque son quince páginas.
    Layout.topMargin: hasHead ? Theme.space8 : 0
    // Bloque de cabecera (rótulo + subtítulo) y su separación de la tarjeta.
    // Se calcula aquí para que el alto total y el anclaje de la tarjeta salgan
    // los dos del mismo sitio y no puedan divergir.
    readonly property bool hasHead: heading.visible || subtitle.visible
    readonly property int headHeight:
        (heading.visible ? heading.implicitHeight : 0)
        + (subtitle.visible
           ? (heading.visible ? Theme.space2 : 0) + subtitle.implicitHeight
           : 0)
    readonly property int headGap: hasHead ? Theme.space8 : 0
    implicitHeight: headHeight + headGap + card.implicitHeight

    // ── Entrada escalonada ───────────────────────────────────────────────────
    // La página ya no aparece como un bloque: las tarjetas suben y se encienden
    // una tras otra, de arriba abajo. Es lo que convierte un cambio de pestaña
    // en un gesto con dirección — la vista se LEE en el mismo orden en que se
    // construye — en vez de un corte de plano.
    //
    // Su sitio en la página, contando solo tarjetas: un consejo suelto o un
    // Process no ocupan turno.
    readonly property int cardIndex: {
        const sibs = parent ? parent.children : []
        let n = 0
        for (let i = 0; i < sibs.length; i++) {
            if (sibs[i] === cardRoot)
                return n
            if (sibs[i] && sibs[i].isSettingsCard === true)
                n++
        }
        return n
    }
    // Sin animación propia: se deriva del reloj de la página, que es el único
    // que se anima (ver SettingsMotion).
    readonly property real enter: SettingsMotion.reveal(cardRoot.cardIndex)
    opacity: enter
    // Sube al entrar. El desplazamiento va en transform y no en el layout: una
    // tarjeta que se mueve NO debe empujar a las de abajo.
    transform: Translate { y: Math.round((1 - cardRoot.enter) * Theme.dp(14)) }

    // La tarjeta desaparece cuando el filtro ha escondido todas sus filas: si
    // no, quedarían cabeceras vacías flotando por la página.
    //
    // Se mira 'matches' (propiedad propia de la fila), NO 'visible': en QML
    // 'visible' es la visibilidad EFECTIVA e incluye la del padre, así que al
    // ocultar la tarjeta sus filas pasarían a reportar false y la tarjeta ya
    // nunca podría volver a mostrarse.
    readonly property bool anyMatch: {
        const kids = cardCol.children
        let filterable = false
        let any = false
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i]
            if (k && k.skey !== undefined && k.skey !== "") {
                filterable = true
                if (k.matches)
                    any = true
            }
        }
        // Tarjetas sin filas filtrables (Monitores, Acerca de…): se juzgan por
        // su propio título.
        return filterable ? any : SettingsFilter.acceptsCard(cardRoot.title)
    }
    visible: shown && anyMatch

    // Si alguna fila tiene su panel desplegado, la tarjeta entera se pone por
    // delante de las demás. Funciona por el mismo mecanismo que 'anyMatch': al
    // leer 'open' de cada hijo, QML apunta la dependencia y reevalúa.
    readonly property bool anyOpen: {
        const kids = cardCol.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i] && kids[i].open === true)
                return true
        return false
    }
    z: anyOpen ? 5 : 0

    // ── Tramos ───────────────────────────────────────────────────────────────
    // La tarjeta deja de ser UNA superficie con filetes dentro y pasa a ser una
    // pila de superficies pegadas: la primera redondea arriba, la última abajo,
    // y las de en medio van casi rectas. Es el patrón de lista agrupada de
    // Android 16 / M3 expresivo, y hace dos cosas que el filete no hacía:
    //
    //   · Cada ajuste es una PIEZA. El filete separaba con una raya de un
    //     píxel; aquí lo que separa es aire, y el ojo agrupa por contorno antes
    //     que por línea. Una tarjeta de ocho filas deja de leerse como un muro.
    //   · La forma dice dónde estás. Arriba del todo y abajo del todo se ven
    //     distintas del resto, así que el borde del grupo se reconoce sin
    //     contar filas.
    //
    // Un TRAMO es una fila de ajuste más lo que cuelgue de ella (los Hint, que
    // llevan isSettingsRow=false a propósito): el consejo tiene que ir DENTRO
    // de la pieza de su ajuste, no flotando entre dos.
    //
    // Se recalcula solo cuando una fila aparece o desaparece —y eso pasa
    // constantemente, con el filtro y con los 'shown' de cada página—, así que
    // los índices se derivan de los hijos VISIBLES y nunca se cablean.
    readonly property int segRadius: Theme.shapeXs
    readonly property int segGap: Theme.dp(2)

    readonly property var segments: {
        const kids = cardCol.children
        const out = []
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i]
            if (k && k.isSettingsRow === true && k.visible)
                out.push(i)
        }
        return out
    }

    // Primera fila VISIBLE de la tarjeta: la única que no lleva filete encima.
    // El filete se dibuja sobre la fila, no debajo, para que un consejo (Hint)
    // colgado de una fila quede de su lado de la raya y no del siguiente.
    readonly property int firstRowIndex: {
        const kids = cardCol.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i] && kids[i].isSettingsRow === true && kids[i].visible)
                return i
        return -1
    }

    // El título de la tarjeta se busca también: al escribir "terminal" salen
    // sus filas aunque ninguna etiqueta contenga esa palabra.
    function pushTitle() {
        const kids = cardCol.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i] && kids[i].cardTitle !== undefined)
                kids[i].cardTitle = cardRoot.title
    }
    Component.onCompleted: pushTitle()
    onTitleChanged: pushTitle()

    // Rótulo del grupo. Caja normal, peso medio, alineado al canto izquierdo de
    // la tarjeta: es el patrón de ChromeOS y de Material 3 actual.
    ThemedText {
        id: heading
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.space4
        visible: cardRoot.title !== ""
        text: cardRoot.title
        // En el ACENTO, no en gris. Es el patrón de encabezado de lista de M3
        // —los subtítulos de sección van en 'primary'— y resuelve algo que se
        // veía en la página: entre tarjetas grises, filas grises y texto de
        // apoyo gris, el rótulo era lo único que marcaba dónde empieza cada
        // bloque y estaba dicho en el mismo tono que todo lo demás. Con color,
        // la página se recorre saltando de rótulo en rótulo sin leerla.
        //
        // 'accentText' y no 'accent' a secas: en modo claro el acento puro no
        // tiene contraste suficiente sobre el fondo, y esta variante ya lo
        // resuelve para el resto del shell.
        color: Theme.accentText
        font.pixelSize: Theme.typeLabelLarge
        font.weight: Font.Medium
        elide: Text.ElideRight
    }

    // Subtítulo de la sección. Se ajusta de línea y llega hasta el borde de la
    // tarjeta: es texto para leer, no un rótulo.
    ThemedText {
        id: subtitle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: heading.visible ? heading.bottom : parent.top
        anchors.topMargin: heading.visible ? Theme.space2 : 0
        anchors.leftMargin: Theme.space4
        visible: cardRoot.description !== ""
        text: cardRoot.description
        color: Theme.fgMuted
        font.pixelSize: Theme.typeBodySmall
        wrapMode: Text.WordWrap
    }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: cardRoot.headHeight + cardRoot.headGap
        implicitHeight: cardCol.implicitHeight + Theme.space8 * 2
        height: implicitHeight
        // La tarjeta ya no se pinta: el color lo ponen los tramos, y el hueco
        // entre ellos tiene que dejar ver el fondo de la página. Si esto
        // siguiera relleno, los huecos se rellenarían solos y no habría grupo.
        color: "transparent"

        ColumnLayout {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Theme.space12
            anchors.rightMargin: Theme.space12
            anchors.topMargin: Theme.space8
            spacing: Theme.space10
        }

        // Tarjetas SIN filas de ajuste: Monitores, Acerca de, las redes
        // guardadas… su contenido son Repeater, listas o bloques propios, así
        // que no hay tramos que derivar de ellos. Sin esto se quedaban sin
        // fondo ninguno —el contenido flotando sobre la página— porque el
        // relleno pasó a depender de unas filas que ahí no existen.
        Rectangle {
            visible: cardRoot.segments.length === 0
            anchors.fill: parent
            z: -1
            radius: Theme.shapeLg
            color: SettingsPalette.groupFill
        }

        // Fondo de cada tramo. Se dibuja en una capa aparte, detrás de las
        // filas, a partir de la posición de cada hija: así las páginas no
        // tienen que saber nada de esto y no hay que tocar ni un componente de
        // fila. Sustituye a los filetes que había aquí antes.
        Repeater {
            model: cardRoot.segments
            delegate: Rectangle {
                // El índice del hijo que ABRE el tramo, y el orden del tramo.
                required property int modelData
                required property int index

                readonly property var row: cardCol.children[modelData]
                readonly property bool isFirst: index === 0
                readonly property bool isLast: index === cardRoot.segments.length - 1
                readonly property var nextRow: isLast
                    ? null : cardCol.children[cardRoot.segments[index + 1]]

                // Detrás de las filas.
                z: -1
                x: 0
                width: card.width

                // El primero arranca en el canto de la tarjeta y el último
                // llega hasta el otro canto: así el relleno de arriba y de
                // abajo queda DENTRO del grupo. Los de en medio se cortan a
                // mitad del hueco entre filas, menos medio 'segGap' a cada
                // lado — que es lo que deja el aire que separa las piezas.
                y: isFirst ? 0
                           : cardCol.y + (row ? row.y : 0)
                             - Math.round(cardCol.spacing / 2)
                             + Math.round(cardRoot.segGap / 2)
                height: Math.max(0,
                    (isLast ? card.height
                            : cardCol.y + (nextRow ? nextRow.y : 0)
                              - Math.round(cardCol.spacing / 2)
                              - Math.round(cardRoot.segGap / 2)) - y)

                color: SettingsPalette.groupFill
                topLeftRadius:     isFirst ? Theme.shapeLg : cardRoot.segRadius
                topRightRadius:    isFirst ? Theme.shapeLg : cardRoot.segRadius
                bottomLeftRadius:  isLast ? Theme.shapeLg : cardRoot.segRadius
                bottomRightRadius: isLast ? Theme.shapeLg : cardRoot.segRadius
            }
        }
    }
}
