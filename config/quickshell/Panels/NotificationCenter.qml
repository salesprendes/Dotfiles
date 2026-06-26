import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Centro de notificaciones: lista con descartar individual y
// "limpiar todo".
Popout {
    id: nc
    ns: "qs-notifcenter"
    cardWidth: 430
    cardMinWidth: 320
    shown: Globals.notifCenterOpen
    property bool clearing: false
    property bool emptyMessageReady: true
    property bool showingClearedState: false
    property real listClearOpacity: 1
    property real listClearOffset: 0
    property bool freezeListHeight: false
    property real frozenListHeight: 0
    property real emptyBodyHeight: 76
    property real bodyHeight: emptyBodyHeight

    Behavior on bodyHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    function refreshBodyHeight() {
        if (freezeListHeight || showingClearedState)
            return

        bodyHeight = NotifService.count > 0 ? Math.max(emptyBodyHeight, Math.min(500, notifList.contentHeight))
                                            : emptyBodyHeight
    }

    function clearAnimated() {
        if (clearing)
            return
        if (NotifService.count === 0) {
            NotifService.clearAll()
            return
        }
        clearing = true
        showingClearedState = false
        refreshBodyHeight()
        frozenListHeight = notifBody.height
        bodyHeight = frozenListHeight
        freezeListHeight = true
        clearAnim.restart()
    }

    Connections {
        target: NotifService
        function onCountChanged() {
            nc.refreshBodyHeight()
        }

        function onClearAllFinished() {
            if (nc.clearing)
                clearDoneAnim.restart()
        }
    }

    SequentialAnimation {
        id: clearAnim
        ScriptAction {
            script: {
                nc.emptyMessageReady = false
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: nc
                property: "listClearOpacity"
                to: 0
                duration: 260
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: nc
                property: "listClearOffset"
                to: 18
                duration: 260
                easing.type: Easing.OutCubic
            }
        }
        ScriptAction {
            script: {
                nc.emptyMessageReady = true
                nc.showingClearedState = true
                NotifService.clearAll()
                nc.freezeListHeight = false
                nc.bodyHeight = nc.emptyBodyHeight
            }
        }
    }

    SequentialAnimation {
        id: clearDoneAnim
        PauseAnimation { duration: 80 }
        ScriptAction {
            script: {
                nc.showingClearedState = false
                nc.clearing = false
                nc.listClearOpacity = 1
                nc.listClearOffset = 0
                nc.refreshBodyHeight()
            }
        }
    }

    Component.onCompleted: refreshBodyHeight()

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space10

        Text {
            Layout.fillWidth: true
            text: I18n.tr("Notifications")
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }

        Rectangle {
            visible: NotifService.count > 0 && !nc.clearing
            implicitWidth: clearRow.implicitWidth + 18
            implicitHeight: Theme.controlM
            radius: height / 2
            color: clearMa.containsMouse ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.18)
                                         : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85)
            border.width: Theme.hairline
            border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.34)
            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            RowLayout {
                id: clearRow
                anchors.centerIn: parent
                spacing: Theme.space6
                Text {
                    text: "󰆴"
                    color: Theme.red
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize - 1
                }
                Text {
                    text: I18n.tr("Clear")
                    color: clearMa.containsMouse ? Theme.red : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    font.bold: true
                }
            }

            MouseArea {
                id: clearMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: nc.clearAnimated()
            }
        }
    }

    Item {
        id: notifBody

        Layout.fillWidth: true
        Layout.preferredHeight: nc.bodyHeight
        clip: true

        Text {
            anchors.centerIn: parent
            visible: (NotifService.count === 0 || nc.showingClearedState) && nc.emptyMessageReady
            opacity: visible ? 1 : 0
            horizontalAlignment: Text.AlignHCenter
            text: "󰂜\n" + I18n.tr("No notifications")
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            lineHeight: 1.35

            Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        }

        ListView {
            id: notifList
            anchors.fill: parent
            visible: (NotifService.count > 0 || nc.clearing) && !nc.showingClearedState
            clip: true
            enabled: !nc.clearing
            spacing: Theme.space10
            model: NotifService.list
            boundsBehavior: Flickable.StopAtBounds
            opacity: nc.listClearOpacity
            transform: Translate { y: nc.listClearOffset }
            onContentHeightChanged: nc.refreshBodyHeight()

            delegate: NotificationItem {
                required property var modelData
                width: ListView.view.width
                notif: modelData
            }
        }
    }
}
