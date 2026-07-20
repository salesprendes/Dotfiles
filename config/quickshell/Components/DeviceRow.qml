import QtQuick
import QtQuick.Layouts
import qs.Config

// Fila de dispositivo compartida por los paneles de audio, WiFi y Bluetooth:
// icono + nombre + subtítulo + extras a la derecha (se insertan como hijos).
// Con 'active' la fila se resalta usando el 'accent' del panel. El subtítulo
// se oculta cuando queda vacío para no descentrar el título.
Rectangle {
    id: row

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property color subtitleColor: Theme.fgMuted
    property bool active: false
    property color accent: Theme.accent
    // Contenido extra a la derecha (%, candado, batería...).
    default property alias trailing: content.data

    signal clicked()

    implicitHeight: Theme.rowL
    radius: Theme.pillRadius
    color: active ? Theme.withAlpha(accent, 0.16)
                  : ma.containsMouse ? Theme.surfaceHi : Theme.withAlpha(Theme.surface, 0.36)
    border.width: active ? Math.max(1, Theme.dp(2)) : Theme.hairline
    border.color: active ? accent : Theme.withAlpha(Theme.overlay, 0.28)
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: Theme.space10
        anchors.rightMargin: Theme.space10
        spacing: Theme.space8

        Text {
            text: row.icon
            color: row.active ? row.accent : Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: row.title
                color: row.active ? Theme.fg : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: row.active
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: row.subtitle !== ""
                text: row.subtitle
                color: row.subtitleColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 4
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
}
