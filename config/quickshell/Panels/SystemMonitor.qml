import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Services

// Monitor de sistema: info del SO con logo, CPU, memoria, buscador
// y lista de procesos (con icono por proceso).
Popout {
    id: sm
    ns: "qs-sysmon"
    cardWidth: 440
    cardMinWidth: 330
    shown: Globals.sysMonOpen

    property string search: ""
    property string processSortKey: "cpu"
    property bool cpuSortDesc: true
    property bool ramSortDesc: true
    property bool nameSortDesc: false   // false = A→Z
    property bool processListReady: false
    property bool processListLoaded: false
    readonly property bool showProcessPlaceholder: shown && !processListReady && SysMon.processes.length === 0
    readonly property int processSectionPlaceholderHeight: Theme.rowS + Theme.controlXS + processListHeight + Theme.space8 * 2 + Theme.space12 * 2
    readonly property int processRowsForHeight: processListReady ? Math.max(1, filtered.length) : 6
    readonly property int processListHeight: Math.min(Theme.dp(280), processRowsForHeight * (Theme.rowS + Theme.space2))
    onShownChanged: {
        if (shown) {
            if (SysMon.processes.length > 0) {
                processListLoaded = true
                processListReady = true
            } else {
                processListReady = false
                processRevealTimer.restart()
            }
        } else {
            search = ""
            processRevealTimer.stop()
        }
    }

    Timer {
        id: processRevealTimer
        interval: 520
        onTriggered: {
            if (!sm.shown)
                return
            sm.processListLoaded = true
            sm.processListReady = true
        }
    }

    Connections {
        target: SysMon
        function onProcessesChanged() {
            if (sm.shown && !sm.processListReady && SysMon.processes.length > 0) {
                processRevealTimer.stop()
                sm.processListLoaded = true
                sm.processListReady = true
            }
        }
    }

    readonly property var filtered: {
        if (!processListReady)
            return []
        const q = search.toLowerCase()
        const list = q === "" ? SysMon.processes
                              : SysMon.processes.filter(p => p.name.toLowerCase().includes(q) || String(p.pid).includes(q))
        const sorted = list.slice()
        sorted.sort((a, b) => {
            if (processSortKey === "name") {
                const cmp = String(a.name).localeCompare(String(b.name))
                return nameSortDesc ? -cmp : cmp
            }
            const desc = processSortKey === "ram" ? ramSortDesc : cpuSortDesc
            const av = processSortKey === "ram" ? (a.memKB || 0) : (a.cpu || 0)
            const bv = processSortKey === "ram" ? (b.memKB || 0) : (b.cpu || 0)
            if (av === bv) return String(a.name).localeCompare(String(b.name))
            return desc ? bv - av : av - bv
        })
        return sorted
    }

    function toggleProcessSort(key) {
        if (processSortKey === key) {
            if (key === "ram") ramSortDesc = !ramSortDesc
            else if (key === "name") nameSortDesc = !nameSortDesc
            else cpuSortDesc = !cpuSortDesc
        } else {
            processSortKey = key
        }
    }

    // ── Cabecera: logo + info del SO ─────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space14

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Theme.rowL; implicitHeight: Theme.rowL

            // Distro con glifo Nerd Font → glifo. Si no, intenta el
            // icono del tema (LOGO de os-release); si tampoco, Tux.
            Image {
                anchors.fill: parent
                anchors.margins: Theme.hairline
                visible: !SysMon.hasGlyph && SysMon.distroLogoIcon !== ""
                source: SysMon.distroLogoIcon
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
            }
            Text {
                anchors.centerIn: parent
                visible: SysMon.hasGlyph || SysMon.distroLogoIcon === ""
                text: SysMon.distroGlyph
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(46)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.hairline

            Text {
                Layout.fillWidth: true
                text: SysMon.distroName !== "" ? SysMon.distroName : "Linux"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 3
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: SysMon.hostname + "  ·  " + SysMon.arch
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                elide: Text.ElideRight
                visible: SysMon.hostname !== ""
            }
            Text {
                Layout.fillWidth: true
                text: "󰌽 " + SysMon.kernel + "    󰅐 " + SysMon.uptime
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                elide: Text.ElideRight
            }
        }
    }

    Rectangle { Layout.fillWidth: true; implicitHeight: Theme.hairline; color: Theme.overlay; opacity: 0.4 }

    // ── Recursos ─────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.dp(142)
        radius: Theme.barRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72)
        border.width: Theme.hairline
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.38)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space12
            spacing: Theme.space10

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8

                Text {
                            text: "󰓅  " + I18n.tr("Resources")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                    Layout.fillWidth: true
                }
                Text {
                    text: I18n.tr("Load %1").arg(SysMon.loadAvg)
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    text: I18n.tr("%1 proc.").arg(SysMon.procCount)
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.space10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.fillHeight: true
                    radius: Theme.pillRadius
                    color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.7)
                    border.width: Theme.hairline
                    border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.5)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.space10
                        spacing: Theme.space8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space8
                            Text {
                                text: "󰻠"
                                color: SysMon.color(SysMon.cpu)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.iconSize + 3
                                Layout.preferredWidth: 22
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                text: "CPU"
                                color: Theme.fgDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                Layout.fillWidth: true
                            }
                            Text {
                                text: Math.round(SysMon.cpu) + "%"
                                color: SysMon.color(SysMon.cpu)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 4
                                font.bold: true
                                Layout.preferredWidth: 54
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.dp(9)
                            radius: 5
                            color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.32)
                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                width: parent.width * Math.min(1, SysMon.cpu / 100)
                                color: SysMon.color(SysMon.cpu)
                                Behavior on width { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: SysMon.cpuModel !== "" ? SysMon.cpuModel : I18n.tr("Current usage")
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.fillHeight: true
                    radius: Theme.pillRadius
                    color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.7)
                    border.width: Theme.hairline
                    border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.5)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.space10
                        spacing: Theme.space8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space8
                            Text {
                                text: "󰍛"
                                color: SysMon.color(SysMon.memPercent)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.iconSize + 3
                                Layout.preferredWidth: 22
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                text: I18n.tr("Memory")
                                color: Theme.fgDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: Math.round(SysMon.memPercent) + "%"
                                color: SysMon.color(SysMon.memPercent)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 4
                                font.bold: true
                                Layout.preferredWidth: 54
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.dp(9)
                            radius: 5
                            color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.32)
                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                width: parent.width * Math.min(1, SysMon.memPercent / 100)
                                color: SysMon.color(SysMon.memPercent)
                                Behavior on width { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: SysMon.memUsedGB.toFixed(1) + " / " + SysMon.memTotalGB.toFixed(1) + " GB"
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    Rectangle { Layout.fillWidth: true; implicitHeight: Theme.hairline; color: Theme.overlay; opacity: 0.4 }

    // ── Buscador ─────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.rowS
        radius: Theme.pillRadius
        color: Theme.surface
        border.width: Theme.hairline
        border.color: searchInput.activeFocus ? Theme.accent
                     : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: Theme.space8

            Text {
                text: "󰍉"   // lupa
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            TextInput {
                id: searchInput
                Layout.fillWidth: true
                clip: true
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                selectionColor: Theme.accent
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: sm.search = text

                // Limpia el texto al cerrar el panel.
                Connections {
                    target: sm
                    function onShownChanged() { if (!sm.shown) searchInput.text = "" }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text === ""
                    text: I18n.tr("Search process...")
                    color: Theme.fgMuted
                    font: searchInput.font
                }
            }
            Text {
                visible: searchInput.text !== ""
                text: "󰅖"
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: searchInput.text = ""
                }
            }
        }
    }

    Loader {
        Layout.fillWidth: true
        Layout.preferredHeight: sm.processListReady ? (item ? item.implicitHeight : sm.processSectionPlaceholderHeight)
                                                    : (sm.showProcessPlaceholder ? sm.processSectionPlaceholderHeight : 0)
        visible: sm.processListReady || sm.showProcessPlaceholder
        opacity: sm.processListReady ? 1 : 0
        active: sm.processListLoaded
        asynchronous: true
        sourceComponent: processSection
        Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        id: processSkeleton
        Layout.fillWidth: true
        Layout.preferredHeight: sm.processSectionPlaceholderHeight
        visible: sm.showProcessPlaceholder
        opacity: sm.showProcessPlaceholder ? 1 : 0
        radius: Theme.barRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72)
        border.width: Theme.hairline
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
        Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space12
            spacing: Theme.space8

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8

                Rectangle {
                    Layout.preferredWidth: Theme.dp(96)
                    Layout.preferredHeight: Theme.dp(15)
                    radius: Theme.space4
                    color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.34)
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: Theme.dp(62)
                    Layout.preferredHeight: Theme.dp(12)
                    radius: Theme.space4
                    color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.24)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space8
                Layout.rightMargin: Theme.space8
                spacing: Theme.space8

                Rectangle {
                    Layout.preferredWidth: Theme.iconSize
                    Layout.preferredHeight: Theme.dp(10)
                    radius: Theme.space4
                    color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.2)
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.dp(10)
                    radius: Theme.space4
                    color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.2)
                }
                Rectangle {
                    Layout.preferredWidth: Theme.dp(52)
                    Layout.preferredHeight: Theme.dp(10)
                    radius: Theme.space4
                    color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.2)
                }
                Rectangle {
                    Layout.preferredWidth: Theme.dp(70)
                    Layout.preferredHeight: Theme.dp(10)
                    radius: Theme.space4
                    color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.2)
                }
                Item { Layout.preferredWidth: 26 }
            }

            Repeater {
                model: 6

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.rowS
                    radius: Theme.pillRadius - 2
                    color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.34)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space8
                        anchors.rightMargin: Theme.space8
                        spacing: Theme.space8

                        Rectangle {
                            Layout.preferredWidth: Theme.iconSize
                            Layout.preferredHeight: Theme.iconSize
                            radius: Theme.iconSize / 2
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.dp(11)
                            radius: Theme.space4
                            color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.26)
                        }
                        Rectangle {
                            Layout.preferredWidth: Theme.dp(38 + index * 3)
                            Layout.preferredHeight: Theme.dp(11)
                            radius: Theme.space4
                            color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.22)
                        }
                        Rectangle {
                            Layout.preferredWidth: Theme.dp(56)
                            Layout.preferredHeight: Theme.dp(11)
                            radius: Theme.space4
                            color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.22)
                        }
                        Item { Layout.preferredWidth: 26 }
                    }
                }
            }
        }
    }

    Component {
        id: processSection

        SystemProcessList {
            processes: sm.filtered
            sortKey: sm.processSortKey
            cpuSortDesc: sm.cpuSortDesc
            ramSortDesc: sm.ramSortDesc
            nameSortDesc: sm.nameSortDesc
            processListHeight: sm.processListHeight
            onSortRequested: (key) => sm.toggleProcessSort(key)
        }
    }
}
