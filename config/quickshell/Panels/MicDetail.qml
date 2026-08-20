import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.Components
import qs.Config

// Detalle de micrófono separado del sonido.
ColumnLayout {
    id: root
    width: parent ? parent.width : implicitWidth
    spacing: Theme.space10

    readonly property var source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes?.values ?? []
    readonly property var sources: Utils.pwSortByDefault(nodes.filter(n => n.audio && !n.isSink && !n.isStream), source)

    function deviceName(node) {
        return Utils.pwDeviceName(node)
    }

    function inputIcon(node) {
        const name = (node?.name || "").toLowerCase()
        const desc = deviceName(node).toLowerCase()
        if (name.includes("bluez") || desc.includes("headset") || desc.includes("usb"))
            return "󰋎"
        return "󰍬"
    }

    function micIcon(audio) {
        return (!audio || audio.muted || audio.volume <= 0) ? "󰍭" : "󰍬"
    }

    PwObjectTracker {
        objects: {
            const arr = []
            for (const n of root.nodes) {
                if (n?.audio && !n.isSink)
                    arr.push(n)
            }
            return arr
        }
    }

    DetailCard {
        icon: "󰍬"
        title: I18n.tr("Input Devices")

        LabeledSlider {
            visible: root.source !== null
            label: I18n.tr("Input Volume")
            icon: root.micIcon(root.source?.audio)
            accent: Theme.accent
            value: root.source?.audio?.volume ?? 0
            valueText: (root.source?.audio?.muted ?? false) ? I18n.tr("off") : Math.round((root.source?.audio?.volume ?? 0) * 100) + "%"
            onMoved: (v) => {
                if (root.source?.audio) {
                    root.source.audio.volume = v
                    if (v > 0 && root.source.audio.muted)
                        root.source.audio.muted = false
                }
            }
            onIconClicked: {
                if (root.source?.audio)
                    root.source.audio.muted = !root.source.audio.muted
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space6
            Repeater {
                model: root.sources
                delegate: DeviceRow {
                    required property var modelData
                    Layout.fillWidth: true
                    active: modelData === root.source
                    icon: active ? "󰓃" : root.inputIcon(modelData)
                    title: root.deviceName(modelData)
                    subtitle: active ? I18n.tr("Active") : I18n.tr("Available")
                    accent: Theme.accent
                    onClicked: Pipewire.preferredDefaultAudioSource = modelData
                }
            }
            ThemedText {
                visible: root.sources.length === 0
                Layout.fillWidth: true
                text: I18n.tr("No input devices found")
                color: Theme.fgMuted
                font.pixelSize: Theme.fontSize - 3
                wrapMode: Text.WordWrap
            }
        }
    }

    component LabeledSlider: ColumnLayout {
        id: row
        property string label: ""
        property string icon: ""
        property string valueText: ""
        property color accent: Theme.accent
        property real value: 0
        signal moved(real v)
        signal iconClicked()

        Layout.fillWidth: true
        spacing: Theme.space6

        RowLayout {
            Layout.fillWidth: true
            ThemedText {
                Layout.fillWidth: true
                text: row.label
                color: Theme.fg
                font.pixelSize: Theme.fontSize - 1
            }
            ThemedText {
                text: row.valueText
                color: row.accent
                font.pixelSize: Theme.fontSize - 2
                font.bold: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space8
            Rectangle {
                implicitWidth: Theme.controlM
                implicitHeight: Theme.controlM
                radius: Theme.pillRadius
                color: muteMa.containsMouse ? Qt.rgba(row.accent.r, row.accent.g, row.accent.b, 0.18) : "transparent"
                ThemedText {
                    anchors.centerIn: parent
                    text: row.icon
                    color: row.accent
                    font.pixelSize: Theme.iconSize
                }
                MouseArea {
                    id: muteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.iconClicked()
                }
            }
            Slider {
                Layout.fillWidth: true
                accent: row.accent
                value: row.value
                onMoved: (v) => row.moved(v)
            }
        }
    }

}
