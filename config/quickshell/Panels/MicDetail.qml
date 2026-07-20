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
    readonly property var sources: nodes.filter(n => n.audio && !n.isSink && !n.isStream).sort(inputSort)

    function deviceName(node) {
        return node?.description || node?.nickname || node?.properties?.["node.description"]
            || node?.properties?.["media.name"] || node?.name || "—"
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

    function inputSort(a, b) {
        if (a === root.source && b !== root.source)
            return -1
        if (b === root.source && a !== root.source)
            return 1
        return root.deviceName(a).localeCompare(root.deviceName(b))
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

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + Theme.space16 * 2
        radius: Theme.barRadius
        color: Theme.withAlpha(Theme.surface, 0.62)
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.34)

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: Theme.space14
            spacing: Theme.space10

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                Text {
                    text: "󰍬"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 1
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Input Devices")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
            }

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
                        selected: modelData === root.source
                        icon: root.inputIcon(modelData)
                        title: root.deviceName(modelData)
                        subtitle: selected ? I18n.tr("Active") : I18n.tr("Available")
                        accent: Theme.accent
                        onPicked: Pipewire.preferredDefaultAudioSource = modelData
                    }
                }
                Text {
                    visible: root.sources.length === 0
                    Layout.fillWidth: true
                    text: I18n.tr("No input devices found")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    wrapMode: Text.WordWrap
                }
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
            Text {
                Layout.fillWidth: true
                text: row.label
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
            Text {
                text: row.valueText
                color: row.accent
                font.family: Theme.fontFamily
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
                Text {
                    anchors.centerIn: parent
                    text: row.icon
                    color: row.accent
                    font.family: Theme.fontFamily
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
                icon: ""
                accent: row.accent
                value: row.value
                onMoved: (v) => row.moved(v)
            }
        }
    }

    component DeviceRow: Rectangle {
        id: dev
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
                        : rowMa.containsMouse ? Theme.surfaceHi : Theme.withAlpha(Theme.surface, 0.36)
        border.width: selected ? Math.max(1, Theme.dp(2)) : Theme.hairline
        border.color: selected ? accent : Theme.withAlpha(Theme.overlay, 0.28)
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
}
