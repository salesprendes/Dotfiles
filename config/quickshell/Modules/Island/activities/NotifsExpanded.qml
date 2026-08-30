import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// La hoja de notificaciones: a donde lleva pulsar un aviso. Reutiliza
// Components/NotificationItem.qml, la misma tarjeta que pintan los popups, así que
// el aviso se ve igual aquí que allí.
//
// Esta hoja es estrecha y aquella tarjeta está medida para el popup, que es más
// ancho, así que va apretada (dense) y con el cuerpo: ocupa lo mismo que sin
// apretar y a cambio se lee quién avisa, cuándo, de qué y qué dice.
//
// El ancho lo pone la ranura de Island.qml, igual para todas las hojas.
ColumnLayout {
    id: root
    spacing: Theme.space8

    readonly property var items: NotifService.list?.values ?? []

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
