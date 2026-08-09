import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Config

// Ventana modal centrada compartida (contraseña WiFi, ajustes IP): capa
// Overlay a pantalla completa con fondo oscurecido, teclado exclusivo
// mientras es visible y tarjeta central con entrada animada. La cabecera
// (icono + título + subtítulo) va integrada; el resto del diálogo son los
// hijos. 'dismissed' se emite al pulsar fuera de la tarjeta.
PanelWindow {
    id: modal

    property var modelData
    screen: modelData

    // Ancho deseado de la tarjeta (se acota con Theme.panelWidth).
    property int cardWidth: 360
    property int cardMinWidth: 300
    property real cardMaxRatio: 0.86
    property string ns: "qs-modal"

    // Cabecera: icono grande + título + subtítulo en acento.
    property string icon: ""
    property string heading: ""
    property string subheading: ""

    default property alias content: col.data

    signal dismissed()

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: modal.ns
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

    // Fondo oscuro: click cancela.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: modal.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        MouseArea { anchors.fill: parent; onClicked: modal.dismissed() }
    }

    // Tarjeta centrada con entrada animada.
    Rectangle {
        anchors.centerIn: parent
        width: Theme.panelWidth(modal.screen, modal.cardWidth, modal.cardMinWidth, modal.cardMaxRatio)
        height: col.implicitHeight + Theme.space18 * 2
        radius: Theme.barRadius + Theme.space2
        color: Theme.bgAlt
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.5)

        opacity: modal.visible ? 1 : 0
        scale: modal.visible ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }   // absorbe clicks

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space18 }
            spacing: Theme.space12

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space10
                Text {
                    text: modal.icon
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 6
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: modal.heading
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: modal.subheading !== ""
                        text: modal.subheading
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
