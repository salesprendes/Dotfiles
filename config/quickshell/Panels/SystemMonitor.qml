import QtQuick
import QtQuick.Layouts
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
    // Lista visible de verdad: datos listos Y el componente async ya creado.
    // Hasta entonces se muestra la animación de carga, que reserva la misma
    // altura, así el panel no cambia de tamaño cuando llegan los procesos.
    readonly property bool processViewReady: processListReady && procLoader.status === Loader.Ready
    readonly property int processListHeight: Math.min(Theme.dp(280), Math.max(1, filtered.length) * (Theme.rowS + Theme.space2))
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
            searchInput.clear()   // limpia el texto del buscador al cerrar
            processRevealTimer.stop()
        }
    }

    // Cortacircuitos: si `ps` fallara y nunca llegaran datos, muestra la
    // lista (vacía) en vez de dejar la animación de carga girando sin fin.
    // El camino normal es onProcessesChanged (~0,5 s tras abrir).
    Timer {
        id: processRevealTimer
        interval: 2500
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

    // Cabecera: logo + info del SO
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space14

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Theme.rowL; implicitHeight: Theme.rowL

            // Glifo Nerd Font del distro. Si no, el icono del tema
            // (LOGO de os-release); si tampoco, Tux.
            Image {
                anchors.fill: parent
                anchors.margins: Theme.hairline
                visible: !SysMon.hasGlyph && SysMon.distroLogoIcon !== ""
                source: SysMon.distroLogoIcon
                sourceSize: Qt.size(Theme.rowL * 2, Theme.rowL * 2)
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

    // Recursos
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.dp(142)
        radius: Theme.barRadius
        color: Theme.withAlpha(Theme.surface, 0.72)
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.accent, 0.38)

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
                    color: Theme.withAlpha(Theme.bgAlt, 0.7)
                    border.width: Theme.hairline
                    border.color: Theme.withAlpha(Theme.overlay, 0.5)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.space10
                        spacing: Theme.space8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space8
                            Text {
                                text: "󰻠"
                                color: Theme.accent
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
                                color: Theme.accent
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
                            color: Theme.withAlpha(Theme.overlay, 0.32)
                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                width: parent.width * Math.min(1, SysMon.cpu / 100)
                                color: Theme.accent
                                Behavior on width { enabled: sm.shown; NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
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
                    color: Theme.withAlpha(Theme.bgAlt, 0.7)
                    border.width: Theme.hairline
                    border.color: Theme.withAlpha(Theme.overlay, 0.5)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.space10
                        spacing: Theme.space8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space8
                            Text {
                                text: "󰍛"
                                color: Theme.accent
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
                                color: Theme.accent
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
                            color: Theme.withAlpha(Theme.overlay, 0.32)
                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                width: parent.width * Math.min(1, SysMon.memPercent / 100)
                                color: Theme.accent
                                Behavior on width { enabled: sm.shown; NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
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

    // Buscador. Debounce del filtrado (patrón de ClipboardPanel): agrupa la
    // ráfaga de teclas antes de re-filtrar y reordenar toda la lista de
    // procesos.
    Timer {
        id: searchDebounce
        interval: 80
        onTriggered: sm.search = searchInput.text
    }
    SearchField {
        id: searchInput
        Layout.fillWidth: true
        implicitHeight: Theme.rowS
        textPixelSize: Theme.fontSize
        placeholder: I18n.tr("Search process...")
        onTextChanged: searchDebounce.restart()
    }

    // Sección de procesos. Carga y lista superpuestas con fundido cruzado. La
    // tarjeta de carga reserva la misma altura que la lista cargada (misma
    // fórmula que SystemProcessList, tope dp(280)), así el panel no salta al
    // llegar los datos.
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: sm.processViewReady && procLoader.item
                                ? procLoader.item.implicitHeight
                                : processSkeleton.implicitHeight

        Loader {
            id: procLoader
            anchors.fill: parent
            active: sm.processListLoaded
            asynchronous: true
            sourceComponent: processSection
            opacity: sm.processViewReady ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        }

        // Tarjeta "cargando servicios": engranaje girando + texto pulsante.
        Rectangle {
            id: processSkeleton
            anchors.fill: parent
            implicitHeight: skelHeader.implicitHeight + Theme.controlXS + Theme.dp(280)
                          + Theme.space8 * 2 + Theme.space12 * 2
            radius: Theme.barRadius
            color: Theme.withAlpha(Theme.surface, 0.72)
            border.width: Theme.hairline
            border.color: Theme.withAlpha(Theme.accent, 0.25)
            opacity: sm.processViewReady ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.space12
                spacing: Theme.space8

                // Cabecera real (mismo texto y fuente que la lista) para que
                // la altura reservada coincida al píxel con la definitiva.
                Text {
                    id: skelHeader
                    Layout.fillWidth: true
                    text: "󰊢  " + I18n.tr("Processes")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.space12

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: Theme.dp(56)
                            implicitHeight: Theme.dp(56)
                            radius: width / 2
                            color: Theme.withAlpha(Theme.accent, 0.12)
                            border.width: Math.max(1, Theme.hairline)
                            border.color: Theme.withAlpha(Theme.accent, 0.45)

                            Text {
                                anchors.centerIn: parent
                                text: "󰒓"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.sp(26)
                                RotationAnimation on rotation {
                                    running: processSkeleton.visible && sm.shown
                                    loops: Animation.Infinite
                                    from: 0; to: 360
                                    duration: 1600
                                }
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.tr("Loading services...")
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            SequentialAnimation on opacity {
                                running: processSkeleton.visible && sm.shown
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 1;    duration: 700; easing.type: Easing.InOutQuad }
                            }
                        }
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
