import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Panels.SettingsPages

// Tarjeta reutilizable con cabecera (icono + título). El contenido va dentro.
Rectangle {
    id: cardRoot
    property string title: ""
    property string glyph: ""
    default property alias content: cardCol.data
    Layout.fillWidth: true
    implicitHeight: cardCol.implicitHeight + Theme.space16 * 2
    radius: Theme.barRadius
    color: SettingsPalette.settingsCard
    border.width: Theme.hairline
    border.color: SettingsPalette.settingsBorder

    ColumnLayout {
        id: cardCol
        anchors.fill: parent
        anchors.margins: Theme.space16
        spacing: Theme.space12

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space10
            visible: cardRoot.title !== ""
            Rectangle {
                visible: cardRoot.glyph !== ""
                implicitWidth: Theme.controlM
                implicitHeight: Theme.controlM
                radius: Theme.pillRadius
                color: SettingsPalette.accentSoft
                Text {
                    anchors.centerIn: parent
                    text: cardRoot.glyph
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize
                }
            }
            Text {
                Layout.fillWidth: true
                text: cardRoot.title
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
            }
        }

        // Filete que separa la cabecera de los controles.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: -Theme.space4
            visible: cardRoot.title !== ""
            implicitHeight: Theme.hairline
            color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.22)
        }
    }
}
