import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// La hoja de notificaciones: a donde lleva pulsar un aviso. Reutiliza
// Components/NotificationItem.qml, la misma tarjeta que pintan los popups — el
// aviso se ve igual aquí que allí, que es justo lo que evita que el shell
// parezca dos programas distintos.
//
// ── EN MODO DENSO, Y ENSEÑANDO EL CUERPO ────────────────────────────────────
// Esta hoja mide 360 dp y aquella tarjeta está medida para el popup, que es
// más ancho. Sin apretarla, cada aviso salía como una caja enorme con un icono
// de 38, un título a 16 en negrita y el nombre de la app colgando en la
// esquina de abajo… y nada más, porque iba en 'compact' y el cuerpo no se
// enseñaba. Cajas grandes que no dicen nada.
//
// Va al revés: apretada (dense) y CON el cuerpo. Ocupa lo mismo y ahora se lee
// quién avisa, cuándo, de qué y qué dice.
//
// ── POR QUÉ HAY UN Item ENVOLVIENDO AL ColumnLayout ─────────────────────────
// Para que la lista LLENE la hoja. La ranura de la isla pide el ancho así:
//
//     width: Math.min(parent.width - Theme.space12 * 2, implicitWidth)
//
// …y un ColumnLayout se calcula su implicitWidth a partir de sus hijos, y se
// lo REESCRIBE en cada pasada de medida: ponerle uno a mano no sirve de nada.
// El resultado eran dos franjas vacías de casi cien píxeles a los lados,
// porque la hoja expandida siempre mide lo mismo (maxExpandedWidth) y no se
// encoge para ceñirse al contenido — se quedaba el contenido flotando dentro.
//
// Un Item corriente sí conserva el implicitWidth que se le pone. Pide de más
// (600) y deja que el recorte de la ranura mande: así llena la hoja mida lo
// que mida, hoy y si mañana cambia.
Item {
    id: root
    implicitWidth: Theme.dp(600)
    implicitHeight: col.implicitHeight

    readonly property var items: NotifService.list?.values ?? []

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.space8

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space8

            ThemedText {
                text: I18n.tr("Notifications")
                color: Theme.fg
                font.pixelSize: Theme.typeLabelLarge
                font.weight: Font.Medium
            }
            // Cuántas hay. Va aquí y no en el título para que el número no se lea
            // como parte del nombre; y en gris, porque es un dato, no un rótulo.
            ThemedText {
                Layout.fillWidth: true
                visible: root.items.length > 0
                text: root.items.length
                color: Theme.fgMuted
                font.pixelSize: Theme.typeLabelSmall
                font.features: ({ "tnum": 1 })
            }
            TextButton {
                visible: root.items.length > 0
                text: I18n.tr("Clear all")
                onClicked: NotifService.clearAll()
            }
        }

        ThemedText {
            Layout.fillWidth: true
            Layout.topMargin: Theme.space12
            Layout.bottomMargin: Theme.space12
            visible: root.items.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr("Nothing pending")
            color: Theme.fgMuted
            font.pixelSize: Theme.typeBodySmall
        }

        ListView {
            id: lista
            Layout.fillWidth: true
            // Se ciñe al contenido hasta un tope: la hoja debe crecer con lo que
            // hay, no reservar siempre el máximo y quedarse medio vacía.
            Layout.preferredHeight: Math.min(Theme.dp(380), contentHeight)
            visible: root.items.length > 0
            clip: true
            spacing: Theme.space6
            model: root.items
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true

            // Con el tope alcanzado, la última tarjeta queda cortada por la mitad
            // — que es lo correcto (dice que hay más), pero sin barra parecía un
            // recorte. Solo aparece cuando de verdad hay más de lo que cabe.
            readonly property bool desborda: lista.contentHeight > lista.height + 0.5
            // Sitio para la barra. Sin esto se dibuja ENCIMA del borde derecho de
            // las tarjetas, y una barra pisando una tarjeta se lee como un fallo
            // de pintado, no como un control.
            readonly property real canal: lista.desborda ? Theme.dp(10) : 0

            ScrollBar.vertical: ThinScrollBar {
                policy: lista.desborda ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }

            delegate: NotificationItem {
                required property var modelData
                width: ListView.view.width - lista.canal
                notif: modelData
                dense: true
            }
        }
    }
}
