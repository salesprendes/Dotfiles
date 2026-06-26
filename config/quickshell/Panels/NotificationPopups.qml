import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

// ─────────────────────────────────────────────────────────────
//  Popups transitorios. Escuchan NotifService.posted y muestran
//  la notificación arriba a la derecha; se autodescarta a los 5s
//  (se pausa al pasar el ratón por encima).
// ─────────────────────────────────────────────────────────────
PanelWindow {
    id: popups

    property var modelData
    screen: modelData

    property int nextKey: 1
    property var notificationsByKey: ({})
    property var cleanupKeys: []

    visible: popupModel.count > 0 && Settings.notifPopupsEnabled
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Theme.panelWidth(screen, 410, 320, 0.94)
    implicitHeight: Math.max(1, list.contentHeight)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-popups"

    // Posición configurable: tr | tl | br | bl.
    readonly property string pos: Settings.notifPosition
    anchors {
        top: pos.charAt(0) === "t"
        bottom: pos.charAt(0) === "b"
        left: pos.charAt(1) === "l"
        right: pos.charAt(1) === "r"
    }
    margins {
        top: Theme.barHeight + Theme.barMargin * 2
        bottom: Theme.barMargin
        left: Theme.barMargin
        right: Theme.barMargin
    }

    Connections {
        target: NotifService
        function onPosted(n) {
            if (Settings.notifPopupsEnabled) popups.add(n)
        }
        function onClearedAll() {
            popups.clear()
        }
    }

    function notificationFor(key) {
        return notificationsByKey[key] || null
    }

    function add(n) {
        const key = nextKey++
        const map = Object.assign({}, notificationsByKey)
        map[key] = n
        notificationsByKey = map

        popupModel.insert(0, { "key": key })
        if (popupModel.count > Settings.notifMaxVisible)
            removeKey(popupModel.get(popupModel.count - 1).key)
    }

    function clear() {
        popupModel.clear()
        notificationsByKey = ({})
        cleanupKeys = []
    }

    function removeKey(key) {
        for (let i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).key === key) {
                popupModel.remove(i)
                break
            }
        }

        const pending = cleanupKeys.slice()
        pending.push(key)
        cleanupKeys = pending
        cleanupTimer.restart()
    }

    Timer {
        id: cleanupTimer
        interval: 520
        repeat: false
        onTriggered: {
            const map = Object.assign({}, notificationsByKey)
            for (let i = 0; i < cleanupKeys.length; i++)
                delete map[cleanupKeys[i]]
            cleanupKeys = []
            notificationsByKey = map
        }
    }

    ListModel {
        id: popupModel
    }

    ListView {
        id: list
        width: parent.width
        height: contentHeight
        interactive: false
        clip: false
        spacing: Theme.space8
        model: popupModel

        add: Transition {
            NumberAnimation { property: "x"; from: Theme.dp(24); to: 0; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 230; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.985; to: 1; duration: 260; easing.type: Easing.OutCubic }
        }

        remove: Transition {
            NumberAnimation { property: "x"; to: Theme.controlXS; duration: 360; easing.type: Easing.InOutCubic }
            NumberAnimation { property: "opacity"; to: 0; duration: 300; easing.type: Easing.InOutCubic }
            NumberAnimation { property: "scale"; to: 0.985; duration: 360; easing.type: Easing.InOutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 110 }
                NumberAnimation { property: "height"; to: 0; duration: 280; easing.type: Easing.InOutCubic }
            }
        }

        displaced: Transition {
            NumberAnimation { properties: "x,y"; duration: 340; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: row
            required property int key
            readonly property var notification: popups.notificationFor(key)

            width: ListView.view.width
            height: card.implicitHeight
            clip: true

            NotificationItem {
                id: card
                width: parent.width
                notif: row.notification
                popupMode: true
                onCloseRequested: popups.removeKey(row.key)
            }

            MouseArea {
                id: hov
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }

            Timer {
                interval: Math.max(1000, Settings.notifTimeout * 1000)
                repeat: false
                running: !hov.containsMouse
                onTriggered: popups.removeKey(row.key)
            }
        }
    }
}
