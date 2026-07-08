import QtQuick
import qs.Config

// Insignia contadora para iconos de la barra: círculo con el número, tope en "9+".
// El anclaje lo decide el consumidor.
Rectangle {
    id: badge

    property int count: 0
    property color badgeColor: Theme.accent

    visible: count > 0
    width: Theme.dp(14); height: Theme.dp(14); radius: height / 2
    color: badgeColor

    Text {
        anchors.centerIn: parent
        text: badge.count > 9 ? "9+" : badge.count
        color: Theme.bg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.sp(9)
        font.bold: true
    }
}
