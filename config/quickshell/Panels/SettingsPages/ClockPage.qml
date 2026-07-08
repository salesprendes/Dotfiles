import QtQuick
import QtQuick.Layouts
import qs.Config

// Reloj
ColumnLayout {
    spacing: Theme.space14

    SwitchRow { label: I18n.tr("24-hour format"); desc: I18n.tr("Disabled uses AM/PM")
        checked: Settings.clock24h; onToggled: Settings.clock24h = !Settings.clock24h }
    SwitchRow { label: I18n.tr("Show seconds"); checked: Settings.clockShowSeconds
        onToggled: Settings.clockShowSeconds = !Settings.clockShowSeconds }
    SwitchRow { label: I18n.tr("Show date in the bar"); checked: Settings.clockShowDate
        onToggled: Settings.clockShowDate = !Settings.clockShowDate }
}
