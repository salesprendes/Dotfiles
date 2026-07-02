import QtQuick
import QtQuick.Layouts
import Quickshell
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
    property var groups: []

    Behavior on bodyHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    function appNameFor(n) {
        if (n && n.appName && n.appName !== "")
            return n.appName
        if (n && n.desktopEntry && n.desktopEntry !== "")
            return n.desktopEntry
        return "Sistema"
    }

    function appIconFor(group) {
        if (!group || !group.items || group.items.length === 0)
            return ""
        const n = group.items[0]
        const icon = n && n.appIcon ? n.appIcon : ""
        if (icon !== "")
            return Quickshell.iconPath(icon, true)
        const desktop = n && n.desktopEntry ? n.desktopEntry : ""
        if (desktop !== "")
            return Quickshell.iconPath(desktop, true)
        const app = n && n.appName ? n.appName : ""
        return app !== "" ? Quickshell.iconPath(app.toLowerCase(), true) : ""
    }

    function rebuildGroups() {
        const src = (NotifService.list && NotifService.list.values) ? NotifService.list.values.slice() : []
        const newest = src.reverse()
        const byApp = {}
        const out = []

        for (let i = 0; i < newest.length; i++) {
            const n = newest[i]
            const title = appNameFor(n)
            if (!byApp[title]) {
                byApp[title] = { "title": title, "items": [] }
                out.push(byApp[title])
            }
            byApp[title].items.push(n)
        }

        groups = out
    }

    function dismissGroup(group) {
        if (!group || !group.items)
            return
        const items = group.items.slice()
        for (let i = 0; i < items.length; i++)
            if (items[i]) items[i].dismiss()
    }

    function previewItems(group, expanded) {
        if (!group || !group.items)
            return []
        return expanded ? group.items : group.items.slice(0, Math.min(3, group.items.length))
    }

    function notificationText(n) {
        if (!n)
            return ""
        const summary = n.summary || ""
        const body = n.body || ""
        if (summary !== "" && body !== "")
            return summary + " - " + body
        return summary !== "" ? summary : body
    }

    function refreshBodyHeight() {
        if (freezeListHeight || showingClearedState)
            return

        bodyHeight = NotifService.count > 0 ? Math.max(emptyBodyHeight, Math.min(500, groupList.contentHeight))
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
            nc.rebuildGroups()
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

    onShownChanged: if (shown) {
        rebuildGroups()
        refreshBodyHeight()
    }
    Component.onCompleted: {
        rebuildGroups()
        refreshBodyHeight()
    }

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
            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

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
                    // Funde junto al fondo; antes cambiaba de golpe.
                    Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
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

    Flow {
        Layout.fillWidth: true
        visible: Settings.mutedNotificationApps.length > 0
        spacing: Theme.space6

        Repeater {
            model: Settings.mutedNotificationApps
            delegate: Rectangle {
                required property string modelData
                implicitWidth: mutedRow.implicitWidth + Theme.space12
                implicitHeight: Theme.controlS
                radius: height / 2
                color: unmuteMa.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                                               : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72)
                border.width: Theme.hairline
                border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.34)
                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

                RowLayout {
                    id: mutedRow
                    anchors.centerIn: parent
                    spacing: Theme.space4
                    Text {
                        text: "󰂛"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize - 4
                    }
                    Text {
                        text: modelData
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        font.bold: true
                    }
                    Text {
                        text: "󰅖"
                        color: unmuteMa.containsMouse ? Theme.red : Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize - 5
                        // Funde junto al fondo del chip; antes saltaba de golpe.
                        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                }

                MouseArea {
                    id: unmuteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotifService.unmuteApp(modelData)
                }
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
            id: groupList
            anchors.fill: parent
            visible: (NotifService.count > 0 || nc.clearing) && !nc.showingClearedState
            clip: true
            enabled: !nc.clearing
            spacing: Theme.space10
            model: nc.groups
            boundsBehavior: Flickable.StopAtBounds
            opacity: nc.listClearOpacity
            transform: Translate { y: nc.listClearOffset }
            onContentHeightChanged: nc.refreshBodyHeight()

            delegate: Item {
                id: groupDelegate
                required property var modelData
                property bool expanded: false
                property bool closing: false
                onExpandedChanged: Qt.callLater(nc.refreshBodyHeight)
                readonly property var group: modelData
                readonly property var items: group.items || []
                readonly property var latest: items.length > 0 ? items[0] : null
                readonly property string appIcon: nc.appIconFor(group)

                width: ListView.view.width
                height: groupSurface.implicitHeight
                clip: true

                Item {
                    id: groupSurface
                    width: parent.width
                    implicitHeight: groupCard.implicitHeight
                    x: 0
                    opacity: groupDelegate.closing ? 0 : 1
                    scale: groupDelegate.closing ? 0.985 : 1

                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    Behavior on x {
                        enabled: !drag.active
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    Timer {
                        id: closeGroupTimer
                        interval: 170
                        onTriggered: nc.dismissGroup(groupDelegate.group)
                    }

                    Timer {
                        id: muteGroupTimer
                        interval: 170
                        onTriggered: NotifService.muteApp(groupDelegate.group.title)
                    }

                    Rectangle {
                        id: groupCard
                        width: parent.width
                        implicitHeight: groupContent.implicitHeight + Theme.space12 * 2
                        radius: Theme.pillRadius + Theme.space4
                        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.74)
                        border.width: Theme.hairline
                        border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.34)

                        ColumnLayout {
                            id: groupContent
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: Theme.space12
                            }
                            spacing: Theme.space8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space8

                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: Theme.dp(34)
                                    implicitHeight: Theme.dp(34)
                                    radius: height / 2
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                    border.width: Theme.hairline
                                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.38)
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: Theme.dp(5)
                                        visible: groupDelegate.appIcon !== ""
                                        source: groupDelegate.appIcon
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        asynchronous: true
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: groupDelegate.appIcon === ""
                                        text: "󰂚"
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.iconSize
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: groupDelegate.group.title
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                // Botón unificado: muestra el total del grupo
                                // y, al pulsarlo, lo despliega/colapsa (chevron
                                // visible solo si hay más de una notificación).
                                Rectangle {
                                    id: countExpandButton
                                    readonly property bool canExpand: groupDelegate.items.length > 1
                                    implicitWidth: ceRow.implicitWidth + Theme.space12
                                    implicitHeight: Theme.controlS
                                    radius: height / 2
                                    scale: ceMa.pressed && canExpand ? 0.93 : ceMa.containsMouse && canExpand ? 1.05 : 1
                                    color: groupDelegate.expanded
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, ceMa.containsMouse ? 0.30 : 0.24)
                                        : ceMa.containsMouse && canExpand ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.24)
                                                                          : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                    border.width: Theme.hairline
                                    border.color: groupDelegate.expanded
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
                                        : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }

                                    RowLayout {
                                        id: ceRow
                                        anchors.centerIn: parent
                                        spacing: Theme.space4
                                        Text {
                                            text: "󰂚"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.iconSize - 4
                                        }
                                        Text {
                                            text: groupDelegate.items.length
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                            font.bold: true
                                        }
                                        Text {
                                            visible: countExpandButton.canExpand
                                            text: "󰅂"
                                            rotation: groupDelegate.expanded ? 90 : 0
                                            color: groupDelegate.expanded || ceMa.containsMouse ? Theme.accent : Theme.fgMuted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.iconSize - 4
                                            Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                        }
                                    }

                                    MouseArea {
                                        id: ceMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: countExpandButton.canExpand ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: if (countExpandButton.canExpand) groupDelegate.expanded = !groupDelegate.expanded
                                    }
                                }

                                // Cerrar grupo (descarta todas sus notificaciones).
                                IconButton {
                                    icon: "󰅖"
                                    diameter: Theme.controlS
                                    iconPixelSize: Theme.iconSize - 1
                                    baseColor: "transparent"
                                    iconColor: Theme.fgMuted
                                    hoverIconColor: Theme.red
                                    hoverColor: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.18)
                                    onClicked: {
                                        if (groupDelegate.closing)
                                            return
                                        groupDelegate.closing = true
                                        closeGroupTimer.restart()
                                    }
                                }

                                // Silenciar la app del grupo.
                                IconButton {
                                    icon: "󰂛"
                                    diameter: Theme.controlS
                                    iconPixelSize: Theme.iconSize - 1
                                    baseColor: "transparent"
                                    iconColor: Theme.fgMuted
                                    hoverIconColor: Theme.yellow
                                    hoverColor: Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.18)
                                    onClicked: {
                                        if (groupDelegate.closing)
                                            return
                                        groupDelegate.closing = true
                                        muteGroupTimer.restart()
                                    }
                                }
                            }

                            ColumnLayout {
                                id: previewCol
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.dp(42)
                                spacing: Theme.space6

                                Repeater {
                                    model: nc.previewItems(groupDelegate.group, groupDelegate.expanded)
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: Theme.space8

                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop
                                            implicitWidth: Theme.dp(6)
                                            implicitHeight: Theme.dp(6)
                                            radius: width / 2
                                            color: Theme.accent
                                            opacity: 0.8
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: nc.notificationText(modelData)
                                            color: Theme.fgDim
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                            maximumLineCount: groupDelegate.expanded ? 3 : 1
                                            elide: Text.ElideRight
                                            wrapMode: groupDelegate.expanded ? Text.WordWrap : Text.NoWrap
                                            textFormat: Text.PlainText
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: !groupDelegate.expanded && groupDelegate.items.length > 3
                                    text: "+" + (groupDelegate.items.length - 3)
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                    font.bold: true
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }
                    }

                    DragHandler {
                        id: drag
                        target: groupSurface
                        xAxis.enabled: true
                        yAxis.enabled: false
                        xAxis.minimum: -groupDelegate.width
                        xAxis.maximum: groupDelegate.width
                        onActiveChanged: {
                            if (active)
                                return
                            if (Math.abs(groupSurface.x) > groupDelegate.width * 0.30) {
                                groupSurface.x = groupSurface.x < 0 ? -groupDelegate.width : groupDelegate.width
                                nc.dismissGroup(groupDelegate.group)
                            } else {
                                groupSurface.x = 0
                            }
                        }
                    }
                }
            }
        }
    }
}
