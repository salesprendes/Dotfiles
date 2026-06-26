pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Daemon de notificaciones. Quickshell se registra como servidor
//  org.freedesktop.Notifications y conserva las notificaciones en
//  'list' (centro de notificaciones). Emite 'posted' para popups.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Notificación nueva entrante (para los popups transitorios).
    signal posted(var notif)
    signal clearedAll()
    signal clearAllFinished()

    readonly property var list: server.trackedNotifications
    readonly property int count: server.trackedNotifications.values.length
    property bool clearingAll: false
    property var _clearQueue: []

    // Marca temporal de llegada por notificación (para "hace X min").
    property var _arrival: new Map()
    property int nowTick: 0
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.nowTick++ }

    function timeText(n) {
        const _ = root.nowTick   // dependencia reactiva
        const t = root._arrival.get(n)
        if (!t) return I18n.tr("now")
        const s = Math.floor((Date.now() - t) / 1000)
        if (s < 60) return I18n.tr("now")
        const m = Math.floor(s / 60)
        if (m < 60) return I18n.tr("%1 min ago").arg(m)
        const h = Math.floor(m / 60)
        if (h < 24) return I18n.tr("%1 h ago").arg(h)
        return I18n.tr("%1 d ago").arg(Math.floor(h / 24))
    }

    NotificationServer {
        id: server
        keepOnReload: false

        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true

        onNotification: function (notif) {
            // Conservar en la lista persistente del centro.
            notif.tracked = true
            root._arrival.set(notif, Date.now())
            // Mostrar popup solo si "No molestar" está desactivado.
            if (!Globals.dnd)
                root.posted(notif)
        }
    }

    Timer {
        id: clearStep
        interval: 16
        repeat: true
        onTriggered: {
            const n = root._clearQueue.shift()
            if (n)
                n.dismiss()

            if (root._clearQueue.length === 0) {
                clearStep.stop()
                root.clearingAll = false
                root.clearAllFinished()
            }
        }
    }

    function clearAll() {
        if (root.clearingAll)
            return
        root.clearedAll()
        root._clearQueue = server.trackedNotifications.values.slice()
        if (root._clearQueue.length === 0) {
            root.clearAllFinished()
            return
        }
        root.clearingAll = true
        clearStep.restart()
    }
}
