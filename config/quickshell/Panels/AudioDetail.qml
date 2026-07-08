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
    readonly property var sinks: nodes.filter(n => n.audio && n.isSink && !n.isStream).sort(deviceSort)
    readonly property var playbackStreams: nodes.filter(n => n.audio && n.isSink && n.isStream)

    function deviceName(node) {
        return node?.description || node?.nickname || node?.properties?.["node.description"]
            || node?.properties?.["media.name"] || node?.name || "—"
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
        if (audio.muted || audio.volume <= 0)
            return "󰝟"
        if (audio.volume < 0.34)
            return "󰕿"
        if (audio.volume < 0.67)
            return "󰖀"
        return "󰕾"
    }

    function deviceSort(a, b) {
        if (a === root.sink && b !== root.sink)
            return -1
        if (b === root.sink && a !== root.sink)
            return 1
        return root.deviceName(a).localeCompare(root.deviceName(b))
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

    AudioCard {
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
                    device: modelData
                    selected: modelData === root.sink
                    icon: root.outputIcon(modelData)
                    title: root.deviceName(modelData)
                    subtitle: selected ? I18n.tr("Active") : I18n.tr("Available")
                    accent: Theme.green
                    onPicked: Pipewire.preferredDefaultAudioSink = modelData
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
            Text {
                text: "󰎆"
                color: Theme.green
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize - 1
            }
            Text {
                Layout.fillWidth: true
                text: I18n.tr("Playback")
                color: Theme.fgDim
                font.family: Theme.fontFamily
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

    component AudioCard: Rectangle {
        id: card
        property string title: ""
        property string icon: ""
        default property alias content: body.data

        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + Theme.space16 * 2
        radius: Theme.barRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.62)
        border.width: Theme.hairline
        border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.34)

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: Theme.space14
            spacing: Theme.space10

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                Text {
                    text: card.icon
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 1
                }
                Text {
                    Layout.fillWidth: true
                    text: card.title
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
            }
        }
    }

    component DeviceRow: Rectangle {
        id: dev
        property var device
        property string icon: ""
        property string title: ""
        property string subtitle: ""
        property bool selected: false
        property color accent: Theme.accent
        signal picked()

        Layout.fillWidth: true
        implicitHeight: Theme.rowL
        radius: Theme.pillRadius
        color: selected ? Qt.rgba(accent.r, accent.g, accent.b, 0.16)
                        : rowMa.containsMouse ? Theme.surfaceHi : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.36)
        border.width: selected ? Math.max(1, Theme.dp(2)) : Theme.hairline
        border.color: selected ? accent : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.28)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space10
            anchors.rightMargin: Theme.space10
            spacing: Theme.space8

            Text {
                text: dev.selected ? "󰓃" : dev.icon
                color: dev.selected ? dev.accent : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: dev.title
                    color: dev.selected ? Theme.fg : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: dev.selected
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: dev.subtitle
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 4
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dev.picked()
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
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.36)
        border.width: Theme.hairline
        border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.28)

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
                    Text {
                        anchors.centerIn: parent
                        text: root.volumeIcon(streamRow.stream?.audio)
                        color: (streamRow.stream?.audio?.muted ?? false) ? Theme.fgMuted : streamRow.accent
                        font.family: Theme.fontFamily
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
                Text {
                    Layout.fillWidth: true
                    text: streamRow.title
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    elide: Text.ElideRight
                }
                Text {
                    text: (streamRow.stream?.audio?.muted ?? false) ? I18n.tr("off") : Math.round((streamRow.stream?.audio?.volume ?? 0) * 100) + "%"
                    color: streamRow.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    font.bold: true
                }
            }

            Slider {
                Layout.fillWidth: true
                icon: ""
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
