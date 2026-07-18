pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.Config

// Daemon de notificaciones. Quickshell se registra como servidor
// org.freedesktop.Notifications y conserva las notificaciones en list (centro
// de notificaciones). Emite posted para los popups.
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

    // Marca temporal de llegada por notificación (para "hace X min"), indexada
    // por notif.id.
    //
    // No usar un WeakMap con las notificaciones como clave: son QObjects de
    // C++, y cuando uno se destruye (descarte/expiración) su wrapper JS puede
    // colectarse mientras la clave sigue en la tabla interna del WeakMap. La
    // siguiente escritura recorre esas claves comparándolas (sameValueZero) y
    // desreferencia la muerta → segfault dentro del handler de onNotification.
    // La clave es un uint, así que no retiene nada; _pruneArrival() evita que
    // el mapa crezca sin límite.
    property var _arrival: ({})
    property int nowTick: 0
    // El tick solo late con el centro de notificaciones abierto: los "hace X
    // min" no se ven en otro sitio (los popups viven segundos y nacen como
    // "ahora"), y al abrir el centro los bindings se evalúan frescos solos. El
    // tick solo refresca mientras se mira.
    Timer {
        interval: 30000
        running: root.count > 0 && Globals.notifCenterOpen
        repeat: true
        onTriggered: root.nowTick++
    }

    // Las notificaciones que sobreviven a una recarga (keepOnReload) pierden
    // su marca de llegada (el mapa muere con cada generación): se sellan con la
    // hora de carga, envejecen desde ahí, mejor que "ahora" perpetuo.
    Component.onCompleted: {
        const vals = server.trackedNotifications.values
        const now = Date.now()
        for (let i = 0; i < vals.length; i++)
            if (root._arrival[vals[i].id] === undefined)
                root._arrival[vals[i].id] = now
    }

    // Descarta las marcas de las notificaciones que ya no existen. Se llama al
    // llegar una nueva: es el único momento en que el mapa puede crecer.
    function _pruneArrival() {
        const vals = server.trackedNotifications.values
        const alive = ({})
        for (let i = 0; i < vals.length; i++) {
            const t = root._arrival[vals[i].id]
            if (t !== undefined)
                alive[vals[i].id] = t
        }
        root._arrival = alive
    }

    function appNameFor(n) {
        if (n && n.appName && n.appName !== "")
            return n.appName
        if (n && n.desktopEntry && n.desktopEntry !== "")
            return n.desktopEntry
        return "Sistema"
    }

    function isMutedApp(appName) {
        return Settings.mutedNotificationApps.indexOf(appName) !== -1
    }

    function muteApp(appName) {
        if (!appName || isMutedApp(appName))
            return

        const muted = Settings.mutedNotificationApps.slice()
        muted.push(appName)
        Settings.mutedNotificationApps = muted

        const current = server.trackedNotifications.values.slice()
        for (let i = 0; i < current.length; i++)
            if (appNameFor(current[i]) === appName)
                current[i].dismiss()
    }

    function unmuteApp(appName) {
        const muted = Settings.mutedNotificationApps.filter(x => x !== appName)
        Settings.mutedNotificationApps = muted
    }

    function timeText(n) {
        const _ = root.nowTick   // dependencia reactiva
        const t = n ? root._arrival[n.id] : undefined
        if (!t) return I18n.tr("now")
        const s = Math.floor((Date.now() - t) / 1000)
        if (s < 60) return I18n.tr("now")
        const m = Math.floor(s / 60)
        if (m < 60) return I18n.tr("%1 min ago").arg(m)
        const h = Math.floor(m / 60)
        if (h < 24) return I18n.tr("%1 h ago").arg(h)
        const d = Math.floor(h / 24)
        if (d < 7)  return I18n.tr("%1 d ago").arg(d)
        if (d < 30) return I18n.tr("%1 wk ago").arg(Math.floor(d / 7))
        return I18n.tr("%1 mo ago").arg(Math.floor(d / 30))
    }

    NotificationServer {
        id: server
        // true: el registro D-Bus y las notificaciones retenidas pasan a la
        // generación nueva en cada recarga en vivo. Con false, el servidor
        // nuevo intentaba registrarse con el viejo aún vivo, fallaba
        // ("already registered") y no reintentaba: el daemon quedaba muerto en
        // silencio (sin popups ni centro) hasta reiniciar el shell entero.
        keepOnReload: true

        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true

        onNotification: function (notif) {
            if (root.isMutedApp(root.appNameFor(notif)))
                return

            // Conservar en la lista persistente del centro.
            notif.tracked = true
            root._pruneArrival()
            root._arrival[notif.id] = Date.now()
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
