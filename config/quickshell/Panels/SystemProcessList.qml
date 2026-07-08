import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Services

Rectangle {
    id: root

    property var processes: []
    property string sortKey: "cpu"
    property bool cpuSortDesc: true
    property bool ramSortDesc: true
    property bool nameSortDesc: false
    property int processListHeight: Theme.dp(220)

    signal sortRequested(string key)

    implicitHeight: processesHeader.implicitHeight + processColumns.implicitHeight
                  + processListHeight + processesBox.spacing * 2 + Theme.space12 * 2
    radius: Theme.barRadius
    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72)
    border.width: Theme.hairline
    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.38)

    function formatProcessMem(p) {
        const kb = Math.round(p.memKB || 0)
        const mb = Math.round(p.memMB || 0)
        return mb > 0 ? mb + " MB" : kb + " KB"
    }

    ColumnLayout {
        id: processesBox
        anchors.fill: parent
        anchors.margins: Theme.space12
        spacing: Theme.space8

        RowLayout {
            id: processesHeader
            Layout.fillWidth: true
            spacing: Theme.space8

            Text {
                text: "󰊢  " + I18n.tr("Processes")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
                Layout.fillWidth: true
            }

            Text {
                text: I18n.tr("%1 processes").arg(root.processes.length)
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }

        RowLayout {
            id: processColumns
            Layout.fillWidth: true
            Layout.leftMargin: Theme.space8
            Layout.rightMargin: Theme.space8
            spacing: Theme.space8

            Item { Layout.preferredWidth: Theme.iconSize }

            // Cabecera "Nombre" pulsable: ordena alfabéticamente (A→Z / Z→A).
            // Ocupa el ancho y se alinea a la izquierda (a diferencia de los
            // SortChip de ancho fijo de CPU/RAM), pero comparte su estilo.
            Rectangle {
                id: nameChip
                Layout.fillWidth: true
                implicitHeight: Theme.controlXS
                radius: Theme.space8 - Theme.hairline
                readonly property bool active: root.sortKey === "name"
                color: active || nameMa.containsMouse
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, active ? 0.18 : 0.08)
                    : "transparent"
                border.width: active ? Theme.hairline : 0
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.space6
                    text: I18n.tr("Name") + " " + (nameChip.active ? (root.nameSortDesc ? "↓" : "↑") : "↕")
                    color: nameChip.active ? Theme.accent : Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    font.bold: nameChip.active
                }

                MouseArea {
                    id: nameMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortRequested("name")
                }
            }

            SortChip {
                keyName: "cpu"
                label: "CPU"
                active: root.sortKey === keyName
                desc: root.cpuSortDesc
                onClicked: root.sortRequested(keyName)
            }

            SortChip {
                keyName: "ram"
                label: "RAM"
                active: root.sortKey === keyName
                desc: root.ramSortDesc
                widthHint: 70
                onClicked: root.sortRequested(keyName)
            }

            Item { Layout.preferredWidth: 26 }
        }

        ListView {
            id: processList
            Layout.fillWidth: true
            Layout.preferredHeight: root.processListHeight
            clip: true
            spacing: Theme.space2
            model: root.processes
            reuseItems: true
            cacheBuffer: Theme.dp(280)

            // Resaltado por índice COMPARTIDO: solo una fila marcada a la vez
            // (la última señalada). Si al ir muy rápido un MouseArea pierde su
            // evento de salida, esa fila se apaga igualmente en cuanto otra
            // toma el relevo. El HoverHandler limpia al salir de la lista.
            property int hoveredIndex: -1
            HoverHandler { onHoveredChanged: if (!hovered) processList.hoveredIndex = -1 }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index

                width: ListView.view.width
                implicitHeight: Theme.rowS
                radius: Theme.pillRadius - 2
                // Estado apagado = surfaceHi con alfa 0 (NO "transparent", que es
                // negro: interpolar hacia él deja una sombra gris/negra). Así la
                // transición solo cambia la opacidad, sin pasar por tonos grises.
                readonly property color rowOff: Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0)
                readonly property bool hovered: processList.hoveredIndex === row.index
                // Resalte instantáneo, sin Behavior: animar solo la entrada
                // dejaba varias filas marcadas al mover el ratón rápido.
                color: hovered ? Theme.surfaceHi : rowOff

                RowLayout {
                    z: 1
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space8
                    anchors.rightMargin: Theme.space8
                    spacing: Theme.space8

                    Text {
                        text: SysMon.processIcon(row.modelData.name)
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                        opacity: 0.9
                    }

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        elide: Text.ElideRight
                    }

                    Text {
                        text: row.modelData.cpu.toFixed(1) + "%"
                        color: Theme.accent
                        font.family: Theme.monoFontFamily
                        font.pixelSize: Theme.fontSize - 2
                        Layout.preferredWidth: 52
                        horizontalAlignment: Text.AlignRight
                    }

                    Text {
                        text: root.formatProcessMem(row.modelData)
                        color: Theme.fgMuted
                        font.family: Theme.monoFontFamily
                        font.pixelSize: Theme.fontSize - 2
                        Layout.preferredWidth: 70
                        horizontalAlignment: Text.AlignRight
                    }

                    Rectangle {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        radius: 13
                        // Capa base ligada a la fila: instantánea (si fundiera,
                        // dejaría un circulito residual al saltar entre filas).
                        color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, row.hovered ? 0.12 : 0.0)

                        // Hover rojo del propio botón: aislado del movimiento
                        // entre filas, así su fundido no deja estela.
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, killMa.containsMouse ? 0.18 : 0)
                            border.width: killMa.containsMouse ? 1 : 0
                            border.color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.45)
                            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            color: killMa.containsMouse ? Theme.red : Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            id: killMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SysMon.killProcess(row.modelData.pid)
                        }
                    }
                }

                MouseArea {
                    id: rowMa
                    z: 0
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    // Al entrar, esta fila pasa a ser la marcada (índice único).
                    onContainsMouseChanged: if (containsMouse) processList.hoveredIndex = row.index
                }
            }
        }
    }

    component SortChip: Rectangle {
        id: chip

        property string keyName: ""
        property string label: ""
        property bool active: false
        property bool desc: true
        property int widthHint: 52

        signal clicked()

        Layout.preferredWidth: widthHint
        implicitHeight: Theme.controlXS
        radius: Theme.space8 - Theme.hairline
        color: active || chipMa.containsMouse
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, active ? 0.18 : 0.08)
            : "transparent"
        border.width: active ? Theme.hairline : 0
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)

        Text {
            anchors.centerIn: parent
            text: chip.label + " " + (chip.active ? (chip.desc ? "↓" : "↑") : "↕")
            color: chip.active ? Theme.accent : Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
            font.bold: chip.active
        }

        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }
}
