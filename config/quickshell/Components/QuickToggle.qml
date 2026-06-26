import QtQuick
import QtQuick.Layouts
import qs.Config

// "Tile" de ajuste rápido (Material): icono + título + subtítulo y,
// opcionalmente, un chevron para desplegar su detalle.
//   · click en el cuerpo  → toggled()
//   · click en el chevron → expand()
Rectangle {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property bool expandable: false
    property bool expanded: false
    property color accent: Theme.accent
    signal toggled()
    signal expand()

    implicitHeight: Theme.tileM
    radius: Theme.pillRadius
    color: active ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
                  : Theme.surface
    border.width: Theme.hairline
    border.color: active ? root.accent
                         : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)

    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.space10
        anchors.rightMargin: Theme.space8
        spacing: Theme.space8

        // Cuerpo (icono + texto) → toggled()
        MouseArea {
            Layout.fillWidth: true
            Layout.fillHeight: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()

            RowLayout {
                anchors.fill: parent
                spacing: Theme.space10

                Rectangle {
                    implicitWidth: Theme.rowS; implicitHeight: Theme.rowS; radius: height / 2
                    color: root.active ? root.accent
                                       : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.5)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        anchors.centerIn: parent
                        text: root.icon
                        color: root.active ? Theme.bg : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize + 2
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: root.title
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: root.subtitle
                        visible: root.subtitle !== ""
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // Chevron → expand()
        Rectangle {
            visible: root.expandable
            implicitWidth: Theme.controlM; implicitHeight: Theme.controlM; radius: height / 2
            Layout.alignment: Qt.AlignVCenter
            color: chevMa.containsMouse ? Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.5)
                                        : "transparent"
            Text {
                anchors.centerIn: parent
                text: "󰅀"
                rotation: root.expanded ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            MouseArea {
                id: chevMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expand()
            }
        }
    }
}
