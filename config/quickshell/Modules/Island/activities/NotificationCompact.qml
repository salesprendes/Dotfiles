import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Components
import qs.Config
import qs.Services

// Una notificación en una línea: icono, app y resumen. Es la forma que toma la
// isla cuando algo acaba de pasar, antes de que decidas si te importa.
//
// Una línea y con puntos suspensivos a propósito: si cupiera el cuerpo entero,
// la isla daría un salto de tamaño por cada aviso y dejaría de ser una isla
// para ser una ventana que aparece. Lo largo está a un clic.
//
// ── QUIÉN MANDA EN LA LÍNEA ─────────────────────────────────────────────────
// El resumen, y solo él. El nombre de la app iba en acento y NEGRITA, o sea
// más fuerte que el aviso: la línea se leía «SIGNAL marta ruiz te ha…», con lo
// que más pesa siendo lo que menos importa —ya lo dice el icono de al lado—.
// Ahora la app va en gris pequeño, separada por un punto medio, y el resumen
// se lleva el color del texto y el peso.
//
// La excepción es lo CRÍTICO: ahí el rojo del nombre sí es información, porque
// es lo único que distingue «batería al 4 %» de cualquier otro aviso antes de
// leerlo.
RowLayout {
    id: root
    spacing: Theme.space8

    readonly property var notif: IslandState.notifCurrent
    readonly property string appName: root.notif ? NotifService.appNameFor(root.notif) : ""
    readonly property bool critical: (root.notif?.urgency ?? 1) === 2

    // Icono de la app, con el glifo genérico de respaldo cuando no lo hay o no
    // carga: un hueco vacío al principio de la línea se lee como un fallo.
    Item {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Theme.barIconSize + Theme.dp(2)
        implicitHeight: Theme.barIconSize + Theme.dp(2)

        ThemedText {
            anchors.centerIn: parent
            visible: icon.status !== Image.Ready
            text: root.critical ? "󱅫" : "󰂚"
            color: root.critical ? Theme.red : Theme.accent
            font.pixelSize: Theme.barIconSize
        }
        IconImage {
            id: icon
            anchors.fill: parent
            source: root.notif?.appIcon ? Quickshell.iconPath(root.notif.appIcon, true) : ""
            visible: status === Image.Ready
            asynchronous: true
        }
    }

    ThemedText {
        visible: root.appName !== ""
        text: root.appName
        color: root.critical ? Theme.red : Theme.fgMuted
        font.pixelSize: Theme.typeLabelSmall
        font.weight: root.critical ? Font.DemiBold : Font.Normal
        Layout.maximumWidth: Theme.dp(96)
        elide: Text.ElideRight
    }

    // El punto de separación. Un espacio a secas dejaba «Signal Marta Ruiz»
    // leyéndose como una sola frase; el punto medio dice que son dos cosas
    // distintas sin gastar ni color ni peso en decirlo.
    ThemedText {
        visible: root.appName !== "" && root.notif?.summary
        text: "·"
        color: Theme.fgMuted
        font.pixelSize: Theme.typeLabelSmall
    }

    ThemedText {
        Layout.fillWidth: true
        // Más sitio que antes (240): el nombre de la app ya no compite por él,
        // y un resumen cortado a la mitad obliga a abrir la hoja para saber de
        // qué va — que es justo lo que la píldora tenía que ahorrarte.
        Layout.maximumWidth: Theme.dp(300)
        text: root.notif?.summary ?? ""
        color: Theme.fg
        font.pixelSize: Theme.typeBodySmall
        font.weight: Font.Medium
        elide: Text.ElideRight
    }

    // Cuántas esperan turno detrás de esta.
    Rectangle {
        visible: IslandState.notifPending > 0
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: pending.implicitWidth + Theme.space8
        implicitHeight: Theme.dp(16)
        radius: height / 2
        color: Theme.withAlpha(Theme.accent, 0.24)
        ThemedText {
            id: pending
            anchors.centerIn: parent
            text: "+" + IslandState.notifPending
            color: Theme.accentText
            font.pixelSize: Theme.typeLabelSmall
            font.bold: true
        }
    }
}
