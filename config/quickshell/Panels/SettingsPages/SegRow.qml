import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Panels.SettingsPages

// Selector segmentado: etiqueta + fila de opciones con píldora deslizante.
ColumnLayout {
    id: seg
    property string label: ""
    property var options: []
    property var current
    signal picked(var v)
    Layout.fillWidth: true
    spacing: Theme.space6
    Text {
        text: seg.label; color: Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
    }
    Rectangle {
        id: segBox
        Layout.fillWidth: true
        implicitHeight: Theme.rowS
        radius: Theme.pillRadius
        color: SettingsPalette.settingsControl
        border.width: Theme.hairline
        border.color: SettingsPalette.settingsBorder

        readonly property int count: seg.options ? seg.options.length : 0
        readonly property int selIndex: {
            for (let i = 0; i < count; i++)
                if (seg.options[i].value === seg.current) return i
            return 0
        }
        readonly property real innerW: width - Theme.space4 * 2
        readonly property real segW: count > 0 ? (innerW - (count - 1) * Theme.space4) / count : 0

        // Píldora deslizante única: se mueve a la opción activa con la
        // animación global (Theme.animFast).
        Rectangle {
            id: indicator
            visible: segBox.count > 0
            y: Theme.space4
            height: parent.height - Theme.space4 * 2
            width: segBox.segW
            x: Theme.space4 + segBox.selIndex * (segBox.segW + Theme.space4)
            radius: Theme.pillRadius - Theme.space2
            color: SettingsPalette.settingsHover
            Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.space4
            spacing: Theme.space4
            Repeater {
                model: seg.options
                delegate: Item {
                    required property var modelData
                    readonly property bool sel: modelData.value === seg.current
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Text {
                        anchors.centerIn: parent
                        text: modelData.text
                        color: parent.sel ? Theme.accent : Theme.fgMuted
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                        font.bold: parent.sel
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(modelData.value)
                    }
                }
            }
        }
    }
}
