import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config

// Notificaciones
ColumnLayout {
    spacing: Theme.space14

    SwitchRow { label: I18n.tr("Show popups"); desc: I18n.tr("Popup alerts when notifications arrive")
        checked: Settings.notifPopupsEnabled
        onToggled: Settings.notifPopupsEnabled = !Settings.notifPopupsEnabled }
    SwitchRow { label: I18n.tr("Do not disturb"); desc: I18n.tr("Silences popups (keeps them in the center)")
        checked: Globals.dnd; onToggled: Globals.dnd = !Globals.dnd }
    SegRow {
        label: I18n.tr("Popup position")
        options: [ { text: "↖", value: "tl" }, { text: "↗", value: "tr" },
                   { text: "↙", value: "bl" }, { text: "↘", value: "br" } ]
        current: Settings.notifPosition
        onPicked: (v) => Settings.notifPosition = v
    }
    SliderRow {
        label: I18n.tr("On-screen duration"); glyph: "󰔛"
        from: 2; to: 15; value: Settings.notifTimeout
        valueText: Settings.notifTimeout + " s"
        onMoved: (v) => Settings.notifTimeout = Math.round(v)
    }
    SegRow {
        label: I18n.tr("Maximum on screen")
        options: [ { text: "3", value: 3 }, { text: "4", value: 4 },
                   { text: "5", value: 5 }, { text: "6", value: 6 } ]
        current: Settings.notifMaxVisible
        onPicked: (v) => Settings.notifMaxVisible = v
    }
}
