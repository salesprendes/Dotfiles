import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Panels.SettingsPages

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
    Text {
        id: heading
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.space4
        visible: cardRoot.title !== ""
        text: cardRoot.title
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.typeLabelLarge
        font.weight: Font.Medium
        elide: Text.ElideRight
    }

    // Subtítulo de la sección. Se ajusta de línea y llega hasta el borde de la
    // tarjeta: es texto para leer, no un rótulo.
    Text {
        id: subtitle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: heading.visible ? heading.bottom : parent.top
        anchors.topMargin: heading.visible ? Theme.space2 : 0
        anchors.leftMargin: Theme.space4
        visible: cardRoot.description !== ""
        text: cardRoot.description
        color: Theme.fgMuted
        font.family: Theme.fontFamily
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
        radius: Theme.shapeLg
        // Sin borde: la tarjeta se separa del fondo por TONO, como en ChromeOS.
        // Un filete alrededor de cada bloque, seis veces por página, convertía
        // la página en una rejilla de cajas.
        color: SettingsPalette.groupFill

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

        // Filetes entre filas. Se dibujan en una capa aparte, a partir de la
        // posición de cada hija: así las páginas no tienen que saber nada de
        // esto y no hay que tocar cada componente de fila.
        //
        // Van sangrados hasta el eje de texto (tras la insignia), que es como
        // los pinta ChromeOS: la raya empieza donde empieza el contenido, no
        // en el canto de la tarjeta.
        Repeater {
            model: cardCol.children
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool isRow: modelData
                    && modelData.isSettingsRow === true && modelData.visible
                visible: isRow && index !== cardRoot.firstRowIndex
                x: cardCol.x + Theme.dp(28) + Theme.space10
                width: Math.max(0, cardCol.width - Theme.dp(28) - Theme.space10)
                y: cardCol.y + (modelData ? modelData.y : 0) - Math.round(cardCol.spacing / 2)
                height: Theme.hairline
                color: Theme.withAlpha(Theme.overlay, Theme.isDark ? 0.55 : 0.42)
            }
        }
    }
}
