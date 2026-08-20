import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.Components
import qs.Config

ColumnLayout {
    id: root
    width: parent ? parent.width : implicitWidth
    spacing: Theme.space10

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var nodes: Pipewire.nodes?.values ?? []
    readonly property var sinks: Utils.pwSortByDefault(nodes.filter(n => n.audio && n.isSink && !n.isStream), sink)
    readonly property var playbackStreams: nodes.filter(n => n.audio && n.isSink && n.isStream)

    function deviceName(node) {
        return Utils.pwDeviceName(node)
    }

    function streamName(node) {
        const app = node?.properties?.["application.name"] || deviceName(node)
        const media = node?.properties?.["media.name"] || ""
        return media && media !== app ? app + ": " + media : app
    }

    function outputIcon(node) {
        const name = (node?.name || "").toLowerCase()
        const desc = deviceName(node).toLowerCase()
        if (name.includes("bluez") || desc.includes("bluetooth"))
            return "󰥰"
        if (desc.includes("headphone") || desc.includes("headset") || desc.includes("auricular"))
            return "󰋋"
        if (desc.includes("hdmi") || desc.includes("display"))
            return "󰍹"
        return "󰕾"
    }

    function volumeIcon(audio) {
        if (!audio)
            return "󰝟"
        return Utils.volumeGlyph(audio.volume, audio.muted)
    }

    PwObjectTracker {
        objects: {
            const arr = []
            for (const n of root.nodes) {
                if (n?.audio)
                    arr.push(n)
            }
            return arr
        }
    }

    DetailCard {
        title: I18n.tr("Audio Devices")
        icon: "󰕾"

        // Dispositivos de salida.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space6
            Repeater {
                model: root.sinks
                delegate: DeviceRow {
                    required property var modelData
                    Layout.fillWidth: true
                    active: modelData === root.sink
                    icon: active ? "󰓃" : root.outputIcon(modelData)
                    title: root.deviceName(modelData)
                    subtitle: active ? I18n.tr("Active") : I18n.tr("Available")
                    accent: Theme.green
                    onClicked: Pipewire.preferredDefaultAudioSink = modelData
                }
            }
            EmptyRow {
                visible: root.sinks.length === 0
                text: I18n.tr("No output devices found")
            }
        }

        // Sub-cabecera Playback, misma tarjeta.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.space4
            visible: root.playbackStreams.length > 0
            spacing: Theme.space8
            ThemedText {
                text: "󰎆"
                color: Theme.green
                font.pixelSize: Theme.iconSize - 1
            }
            ThemedText {
                Layout.fillWidth: true
                text: I18n.tr("Playback")
                color: Theme.fgDim
                font.pixelSize: Theme.fontSize - 2
                font.bold: true
            }
        }

        // Reproducciones por aplicación.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.playbackStreams.length > 0
            spacing: Theme.space6
            Repeater {
                model: root.playbackStreams
                delegate: StreamRow {
                    required property var modelData
                    stream: modelData
                    title: root.streamName(modelData)
                    accent: Theme.green
                }
            }
        }
    }

    component StreamRow: Rectangle {
        id: streamRow
        property var stream
        property string title: ""
        property color accent: Theme.accent

        Layout.fillWidth: true
        // Altura pegada al contenido para que el slider no se salga por abajo.
        implicitHeight: streamCol.implicitHeight + Theme.space10 * 2
        radius: Theme.pillRadius
        color: Theme.withAlpha(Theme.surface, 0.36)
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.28)

        PwObjectTracker { objects: streamRow.stream ? [streamRow.stream] : [] }

        ColumnLayout {
            id: streamCol
            anchors.fill: parent
            anchors.margins: Theme.space10
            spacing: Theme.space6

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8

                // El icono hace de botón de silencio; el % ya va a la derecha.
                Rectangle {
                    implicitWidth: Theme.controlM
                    implicitHeight: Theme.controlM
                    radius: height / 2
                    color: muteMa.containsMouse ? Qt.rgba(streamRow.accent.r, streamRow.accent.g, streamRow.accent.b, 0.18) : "transparent"
                    ThemedText {
                        anchors.centerIn: parent
                        text: root.volumeIcon(streamRow.stream?.audio)
                        color: (streamRow.stream?.audio?.muted ?? false) ? Theme.fgMuted : streamRow.accent
                        font.pixelSize: Theme.iconSize
                    }
                    MouseArea {
                        id: muteMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (streamRow.stream?.audio)
                                streamRow.stream.audio.muted = !streamRow.stream.audio.muted
                        }
                    }
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: streamRow.title
                    color: Theme.fg
                    font.pixelSize: Theme.fontSize - 1
                    elide: Text.ElideRight
                }
                ThemedText {
                    text: (streamRow.stream?.audio?.muted ?? false) ? I18n.tr("off") : Math.round((streamRow.stream?.audio?.volume ?? 0) * 100) + "%"
                    color: streamRow.accent
                    font.pixelSize: Theme.fontSize - 3
                    font.bold: true
                }
            }

            Slider {
                Layout.fillWidth: true
                accent: streamRow.accent
                value: streamRow.stream?.audio?.volume ?? 0
                onMoved: (v) => {
                    if (streamRow.stream?.audio) {
                        streamRow.stream.audio.volume = v
                        if (v > 0 && streamRow.stream.audio.muted)
                            streamRow.stream.audio.muted = false
                    }
                }
            }
        }
    }

    component EmptyRow: Text {
        Layout.fillWidth: true
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 3
        wrapMode: Text.WordWrap
    }
}
