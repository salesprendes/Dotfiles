import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Lo que suena, en una línea, con un ecualizador que rebota mientras suena y
// se aplana al pausar.
//
// Quién es "el reproductor activo" lo decide Services/Media.qml, no este
// archivo: es lo que evita que aquí aparezca el reproductor fantasma que deja
// registrado el navegador por el mero hecho de estar abierto.
RowLayout {
    id: root
    spacing: Theme.space8

    readonly property var player: Media.active
    readonly property bool playing: Media.playing

    MediaEqualizer {
        Layout.alignment: Qt.AlignVCenter
        playing: root.playing
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.maximumWidth: Theme.dp(260)
        spacing: 0

        ThemedText {
            Layout.fillWidth: true
            text: root.player?.trackTitle || I18n.tr("Untitled")
            color: Theme.fg
            font.pixelSize: Theme.typeBodySmall
            elide: Text.ElideRight
        }
        ThemedText {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.player?.trackArtist || ""
            color: Theme.fgMuted
            font.pixelSize: Theme.typeLabelSmall
            elide: Text.ElideRight
        }
    }
}
