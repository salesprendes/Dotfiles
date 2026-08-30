import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Notificaciones: cómo aparecen los avisos, cuánto duran y cuáles genera el
// propio shell (la batería).
SettingsPage {

    SettingsCard {
        title: I18n.tr("Popups"); glyph: "󰂚"

        SwitchRow { glyph: "󰂚"; skey: "notifPopupsEnabled"; label: I18n.tr("Show popups"); desc: I18n.tr("Popup alerts when notifications arrive")
            checked: Settings.notifPopupsEnabled
            onToggled: Settings.notifPopupsEnabled = !Settings.notifPopupsEnabled }
        SwitchRow { glyph: "󰂛"; skey: "@do-not-disturb"; aliases: ["dnd", "silencio", "no molestar", "mute"]; label: I18n.tr("Do not disturb"); desc: I18n.tr("Silences popups (keeps them in the center)")
            checked: Globals.dnd; onToggled: Globals.dnd = !Globals.dnd }
        // La esquina solo significa algo con la isla APAGADA: con ella
        // encendida, las notificaciones salen en la isla, que vive donde vive
        // la barra y no tiene esquina que elegir.
        SegRow {
            glyph: "󰆾"
            skey: "notifPosition"
            label: I18n.tr("Popup position")
            shown: !Settings.islandEnabled
            options: [ { text: "↖", value: "tl" }, { text: "↗", value: "tr" },
                       { text: "↙", value: "bl" }, { text: "↘", value: "br" } ]
            current: Settings.notifPosition
            onPicked: (v) => Settings.notifPosition = v
        }
        Hint {
            skey: "notifPosition"
            shown: Settings.islandEnabled
            text: I18n.tr("The island shows the notifications, so there is no corner to choose. Turn it off in Settings ▸ Bar to get the classic popups back.")
        }
        SegRow {
            glyph: "󰕮"
            skey: "notifMaxVisible"
            label: I18n.tr("Maximum on screen")
            options: [ { text: "3", value: 3 }, { text: "4", value: 4 },
                       { text: "5", value: 5 }, { text: "6", value: 6 } ]
            current: Settings.notifMaxVisible
            onPicked: (v) => Settings.notifMaxVisible = v
        }
        SwitchRow {
            glyph: "󰘖"
            skey: "notifCompact"
            label: I18n.tr("Compact popups")
            desc: I18n.tr("Title only, without the message body")
            checked: Settings.notifCompact
            onToggled: Settings.notifCompact = !Settings.notifCompact
        }
        SwitchRow {
            glyph: "󰔟"
            skey: "notifShowProgress"
            label: I18n.tr("Countdown bar")
            desc: I18n.tr("Shows how long is left before the popup leaves")
            checked: Settings.notifShowProgress
            onToggled: Settings.notifShowProgress = !Settings.notifShowProgress
        }
    }

    // Duración por urgencia: la manda la app que envía el aviso, y los tres
    // niveles no merecen el mismo tiempo en pantalla. Es lo que hacen tanto
    // noctalia como DankMaterialShell, y es la diferencia entre que un
    // "canción cambiada" te estorbe cinco segundos o cuatro.
    SettingsCard {
        title: I18n.tr("On-screen duration"); glyph: "󰔛"

        SliderRow {
            skey: "notifTimeoutLow"
            label: I18n.tr("Low urgency"); glyph: "󰀪"
            from: 1; to: 30; value: Settings.notifTimeoutLow
            valueText: Settings.notifTimeoutLow + " s"
            onMoved: (v) => Settings.notifTimeoutLow = Math.round(v)
        }
        SliderRow {
            skey: "notifTimeout"
            label: I18n.tr("Normal urgency"); glyph: "󰂚"
            from: 1; to: 30; value: Settings.notifTimeout
            valueText: Settings.notifTimeout + " s"
            onMoved: (v) => Settings.notifTimeout = Math.round(v)
        }
        SliderRow {
            skey: "notifTimeoutCritical"
            label: I18n.tr("Critical urgency"); glyph: "󰀪"
            from: 0; to: 60; value: Settings.notifTimeoutCritical
            // A 0 no expira. Se dice con palabras, no con un "0 s" que se lee
            // como "desaparece al instante" — lo contrario de lo que hace.
            valueText: Settings.notifTimeoutCritical === 0
                ? I18n.tr("Until dismissed") : Settings.notifTimeoutCritical + " s"
            onMoved: (v) => Settings.notifTimeoutCritical = Math.round(v)
        }
        Hint {
            skey: "notifTimeoutCritical"
            text: I18n.tr("Critical alerts at 0 stay until you dismiss them.")
        }
    }

    // Los avisos de batería los genera el propio shell, así que sus umbrales
    // viven aquí y no en una página de energía aparte: lo que se configura es
    // cuándo te avisa, no cómo gasta.
    SettingsCard {
        title: I18n.tr("Battery"); glyph: "󰁽"
        shown: SettingsPalette.hasBattery

        SwitchRow {
            glyph: "󰁾"
            skey: "batteryNotifyLow"
            label: I18n.tr("Warn on low battery")
            checked: Settings.batteryNotifyLow
            onToggled: Settings.batteryNotifyLow = !Settings.batteryNotifyLow
        }
        SliderRow {
            skey: "batteryLowThreshold"
            label: I18n.tr("Low battery at"); glyph: "󰁾"
            shown: Settings.batteryNotifyLow
            from: 5; to: 50; value: Settings.batteryLowThreshold
            valueText: Settings.batteryLowThreshold + " %"
            onMoved: (v) => Settings.batteryLowThreshold = Math.round(v)
        }
        SwitchRow {
            glyph: "󰂃"
            skey: "batteryNotifyCritical"
            label: I18n.tr("Warn on critical battery")
            checked: Settings.batteryNotifyCritical
            onToggled: Settings.batteryNotifyCritical = !Settings.batteryNotifyCritical
        }
        SliderRow {
            skey: "batteryCriticalThreshold"
            label: I18n.tr("Critical battery at"); glyph: "󰂃"
            shown: Settings.batteryNotifyCritical
            from: 1; to: 30; value: Settings.batteryCriticalThreshold
            valueText: Settings.batteryCriticalThreshold + " %"
            onMoved: (v) => Settings.batteryCriticalThreshold = Math.round(v)
        }
        Hint {
            skey: "batteryCriticalThreshold"
            shown: Settings.batteryCriticalThreshold >= Settings.batteryLowThreshold
            text: I18n.tr("The critical level is capped at the low level, so the warnings keep their order.")
        }
    }

    // El OSD es un aviso más: aparece solo, tapa parte de la pantalla y se va.
    SettingsCard {
        title: I18n.tr("Volume OSD"); glyph: "󰕾"

        SwitchRow {
            glyph: "󰕾"
            skey: "osdEnabled"
            label: I18n.tr("Show volume OSD")
            desc: I18n.tr("Floating indicator when the volume changes")
            checked: Settings.osdEnabled
            onToggled: Settings.osdEnabled = !Settings.osdEnabled
        }
        SegRow {
            glyph: "󰆾"
            skey: "osdPosition"
            label: I18n.tr("Position on screen")
            // Igual que la esquina de los popups: con la isla encendida el
            // volumen sale en ella y esto no gobierna nada.
            shown: Settings.osdEnabled && !Settings.islandEnabled
            options: [ { text: I18n.tr("Top"), value: "top" },
                       { text: I18n.tr("Bottom"), value: "bottom" } ]
            current: Settings.osdPosition
            onPicked: (v) => Settings.osdPosition = v
        }
        SliderRow {
            skey: "osdTimeout"
            label: I18n.tr("On-screen duration"); glyph: "󰔛"
            shown: Settings.osdEnabled
            from: 0.5; to: 6.0; value: Settings.osdTimeout
            valueText: Settings.osdTimeout.toFixed(1) + " s"
            onMoved: (v) => Settings.osdTimeout = Math.round(v * 10) / 10
        }
    }
}
