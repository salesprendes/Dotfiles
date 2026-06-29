import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

Popout {
    id: panel
    ns: "qs-clipboard"
    cardWidth: 420
    cardMinWidth: 320
    keyboardExclusive: true
    shown: Globals.clipboardOpen
    property bool clearing: false
    property bool emptyMessageReady: true
    property bool showingClearedState: false
    property real listClearOpacity: 1
    property real listClearOffset: 0
    property bool freezeListHeight: false
    property real frozenListHeight: 0
    property real emptyBodyHeight: 120
    property real bodyHeight: emptyBodyHeight
    property int selectedIndex: 0

    Behavior on bodyHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    function refreshBodyHeight() {
        if (freezeListHeight || showingClearedState)
            return

        bodyHeight = Clipboard.filteredEntries.length > 0 ? Math.max(emptyBodyHeight, Math.min(Theme.dp(430), historyList.contentHeight))
                                                          : emptyBodyHeight
    }

    function clearAnimated() {
        if (clearing)
            return
        if (Clipboard.filteredEntries.length === 0) {
            Clipboard.clear()
            return
        }
        clearing = true
        showingClearedState = false
        refreshBodyHeight()
        frozenListHeight = historyBody.height
        bodyHeight = frozenListHeight
        freezeListHeight = true
        clearAnim.restart()
    }

    function moveSelection(delta) {
        const count = Clipboard.filteredEntries.length
        if (count <= 0)
            return
        selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta))
        historyList.currentIndex = selectedIndex
        historyList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function copySelected() {
        Clipboard.copy(Clipboard.filteredEntries[selectedIndex])
    }

    onShownChanged: {
        if (shown) {
            Clipboard.search = ""
            searchInput.text = ""
            selectedIndex = 0
            Clipboard.refresh()
            refreshBodyHeight()
            focusTimer.restart()
        }
    }

    Connections {
        target: Clipboard
        function onFilteredEntriesChanged() {
            panel.selectedIndex = Clipboard.filteredEntries.length > 0
                ? Math.min(panel.selectedIndex, Clipboard.filteredEntries.length - 1)
                : -1
            historyList.currentIndex = panel.selectedIndex
            panel.refreshBodyHeight()
        }
    }

    Timer {
        id: focusTimer
        interval: 60
        onTriggered: searchInput.forceActiveFocus()
    }

    SequentialAnimation {
        id: clearAnim
        ScriptAction {
            script: {
                panel.emptyMessageReady = false
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: panel
                property: "listClearOpacity"
                to: 0
                duration: 260
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: panel
                property: "listClearOffset"
                to: 18
                duration: 260
                easing.type: Easing.OutCubic
            }
        }
        ScriptAction {
            script: {
                panel.emptyMessageReady = true
                panel.showingClearedState = true
                Clipboard.clear()
                panel.freezeListHeight = false
                panel.bodyHeight = panel.emptyBodyHeight
            }
        }
        PauseAnimation { duration: 80 }
        ScriptAction {
            script: {
                panel.showingClearedState = false
                panel.clearing = false
                panel.listClearOpacity = 1
                panel.listClearOffset = 0
                panel.refreshBodyHeight()
            }
        }
    }

    Component.onCompleted: refreshBodyHeight()

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: I18n.tr("Clipboard")
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }

        Rectangle {
            implicitWidth: Theme.controlM
            implicitHeight: Theme.controlM
            radius: height / 2
            color: refreshMa.containsMouse ? Theme.surfaceHi : Theme.surface
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Text {
                anchors.centerIn: parent
                text: Clipboard.loading ? "󰑓" : "󰑐"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
                RotationAnimation on rotation {
                    running: Clipboard.loading
                    loops: Animation.Infinite
                    from: 0; to: 360
                    duration: 900
                }
            }
            MouseArea {
                id: refreshMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Clipboard.refresh()
            }
        }

        IconButton {
            visible: Clipboard.filteredEntries.length > 0 && !panel.clearing
            icon: "󰆴"
            iconColor: Theme.red
            hoverIconColor: Theme.red
            hoverColor: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.22)
            onClicked: panel.clearAnimated()
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.rowM
        radius: Theme.pillRadius
        color: Theme.surface
        border.width: Theme.hairline
        border.color: searchInput.activeFocus ? Theme.accent
                     : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space12
            anchors.rightMargin: Theme.space12
            spacing: Theme.space8

            Text {
                text: "󰍉"
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
                font.pixelSize: Theme.fontSize + 1
                selectionColor: Theme.accent
                verticalAlignment: TextInput.AlignVCenter
                focus: true
                onTextChanged: Clipboard.search = text
                Keys.onEscapePressed: Globals.closeAll()
                Keys.onReturnPressed: panel.copySelected()
                Keys.onEnterPressed: panel.copySelected()
                Keys.onDownPressed: panel.moveSelection(1)
                Keys.onUpPressed: panel.moveSelection(-1)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text === ""
                    text: I18n.tr("Search history...")
                    color: Theme.fgMuted
                    font: searchInput.font
                }
            }

            Text {
                text: Clipboard.filteredEntries.length
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: !Clipboard.available
        implicitHeight: Theme.dp(58)
        radius: Theme.pillRadius
        color: Qt.rgba(Theme.orange.r, Theme.orange.g, Theme.orange.b, 0.12)
        border.width: Theme.hairline
        border.color: Qt.rgba(Theme.orange.r, Theme.orange.g, Theme.orange.b, 0.35)

        Text {
            anchors.fill: parent
            anchors.margins: Theme.space12
            text: I18n.tr("Install %1 to use history").arg(Clipboard.missingTools)
            color: Theme.yellow
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
        }
    }

    Item {
        id: historyBody

        Layout.fillWidth: true
        Layout.preferredHeight: panel.bodyHeight
        clip: true

        Text {
            anchors.centerIn: parent
            visible: Clipboard.available && (Clipboard.filteredEntries.length === 0 || panel.showingClearedState) && panel.emptyMessageReady
            opacity: visible ? 1 : 0
            text: Clipboard.search === "" ? I18n.tr("No history yet") : I18n.tr("No results")
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize

            Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        }

        ListView {
            id: historyList
            anchors.fill: parent
            visible: (Clipboard.filteredEntries.length > 0 || panel.clearing) && !panel.showingClearedState
            enabled: !panel.clearing
            clip: true
            spacing: Theme.space4
            model: Clipboard.filteredEntries
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: panel.selectedIndex
            opacity: panel.listClearOpacity
            transform: Translate { y: panel.listClearOffset }
            onContentHeightChanged: panel.refreshBodyHeight()

            // Al borrar una entrada, las filas de debajo suben deslizándose
            // en vez de dar un salto seco.
            removeDisplaced: Transition {
                NumberAnimation { properties: "y"; duration: Theme.animFast; easing.type: Easing.OutCubic }
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index

                width: ListView.view.width
                implicitHeight: Math.max(Theme.rowL, preview.implicitHeight + Theme.controlXS)
                x: deleting ? 24 : 0
                opacity: deleting ? 0 : 1
                scale: deleting ? 0.96 : 1
                radius: Theme.pillRadius
                readonly property bool selected: ListView.isCurrentItem
                color: rowMa.containsMouse || selected ? Theme.surfaceHi : Theme.surface
                border.width: selected ? Theme.focusWidth : Theme.hairline
                border.color: selected ? Theme.focusRing : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.28)
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                property bool deleting: false

                // Salida rápida: desliza+desvanece y, en cuanto termina (no antes,
                // para no ver el "pop"), elimina la entrada. La pausa se liga a
                // animFast para respetar la velocidad de animación del usuario.
                SequentialAnimation {
                    id: deleteAnim
                    ScriptAction { script: row.deleting = true }
                    PauseAnimation { duration: Theme.animFast }
                    ScriptAction { script: Clipboard.remove(row.modelData) }
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    enabled: !row.deleting && !panel.clearing
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onEntered: panel.selectedIndex = index
                    onClicked: Clipboard.copy(modelData)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space10
                    anchors.rightMargin: Theme.space8
                    spacing: Theme.space10

                    Rectangle {
                        implicitWidth: Theme.controlM
                        implicitHeight: Theme.controlM
                        radius: height / 2
                        color: modelData.type === "image"
                            ? Qt.rgba(Theme.magenta.r, Theme.magenta.g, Theme.magenta.b, 0.20)
                            : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                        Text {
                            anchors.centerIn: parent
                            text: modelData.type === "image" ? "󰋩" : "󰉿"
                            color: modelData.type === "image" ? Theme.magenta : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.iconSize
                        }
                    }

                    Text {
                        id: preview
                        Layout.fillWidth: true
                        text: modelData.preview
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        implicitWidth: Theme.controlS
                        implicitHeight: Theme.controlS
                        radius: height / 2
                        color: deleteMa.containsMouse ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.22) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "󰆴"
                            color: deleteMa.containsMouse ? Theme.red : Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.iconSize - 1
                        }
                        MouseArea {
                            id: deleteMa
                            anchors.fill: parent
                            enabled: !row.deleting && !panel.clearing
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: deleteAnim.restart()
                        }
                    }
                }
            }
        }
    }
}
