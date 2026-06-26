import QtQuick
import QtQuick.Layouts
import qs.Config

// Desplegable reutilizable (etiqueta + selector con panel animado). Antes era
// un componente inline de Ajustes; extraído a Components para usarlo en todo el
// shell. La animación (altura + opacidad al abrir; hover por opacidad para no
// dejar "sombra negra") es la misma que el FontPicker de Tipografía.
//
// Uso:
//   DropdownRow {
//       label: "..."; options: [{ text, value }, …]; current: value
//       onPicked: (v) => { ... }
//   }
ColumnLayout {
    id: root
    property string label: ""
    property var options: []
    property var current
    property bool open: false
    signal picked(var v)

    // Colores derivados de Theme (sobreescribibles). Equivalen a los tokens
    // settings* que usaba el inline original.
    property color controlColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.86)
    property color borderColor:  Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.28)
    property color cardColor:    Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72)
    property color hoverColor:   Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.74)

    Layout.fillWidth: true
    spacing: Theme.space6

    readonly property string currentText: {
        for (let i = 0; i < options.length; i++)
            if (options[i].value === current) return options[i].text
        return options.length > 0 ? options[0].text : ""
    }

    Text {
        text: root.label
        visible: root.label !== ""
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.rowM
        radius: Theme.pillRadius
        color: root.controlColor
        border.width: Theme.hairline
        border.color: root.open ? Theme.accent : root.borderColor
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space12
            anchors.rightMargin: Theme.space12
            spacing: Theme.space8

            Text {
                Layout.fillWidth: true
                text: root.currentText
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
            }
            Text {
                text: "󰅀"
                rotation: root.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize - 1
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open = !root.open
        }
    }

    Item {
        id: dropdownClip
        Layout.fillWidth: true
        clip: true
        readonly property int panelHeight: optionCol.implicitHeight + Theme.space4 * 2
        // Solo altura + opacidad, sin scale/desplazamiento (que causaban "salto").
        implicitHeight: root.open ? panelHeight : 0
        Behavior on implicitHeight { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

        Rectangle {
            id: dropdownPanel
            anchors.fill: parent
            radius: Theme.pillRadius
            color: root.cardColor
            border.width: Theme.hairline
            border.color: root.borderColor

            ColumnLayout {
                id: optionCol
                property var current: root.current
                anchors.fill: parent
                anchors.margins: Theme.space4
                spacing: Theme.space2

                function choose(value) {
                    root.picked(value)
                    root.open = false
                }

                Repeater {
                    model: root.options
                    delegate: Rectangle {
                        id: optionRow
                        required property var modelData
                        readonly property bool sel: modelData.value === optionCol.current
                        Layout.fillWidth: true
                        implicitHeight: Theme.rowM
                        radius: Theme.pillRadius - Theme.space2
                        // El color base solo va entre acento-tinte y "transparent";
                        // el hover es una capa aparte que anima su OPACIDAD (así no
                        // se interpola hacia el negro de "transparent").
                        color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                   : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: root.hoverColor
                            opacity: rowMa.containsMouse && !optionRow.sel ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space10
                            anchors.rightMargin: Theme.space10
                            spacing: Theme.space8

                            Text {
                                Layout.fillWidth: true
                                text: optionRow.modelData.text
                                color: optionRow.sel ? Theme.fg : Theme.fgDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: optionRow.sel
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: optionRow.sel
                                text: "󰄬"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.iconSize - 1
                            }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: optionCol.choose(optionRow.modelData.value)
                        }
                    }
                }
            }
        }
    }
}
