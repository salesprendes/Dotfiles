import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Services
import qs.Panels.SettingsPages

// Barra
ColumnLayout {
    spacing: Theme.space14

    // Widgets de la barra, agrupados en una tarjeta.
    SettingsCard {
        title: I18n.tr("Visible widgets"); glyph: "󰕬"
        SwitchRow { skey: "showTray"; label: I18n.tr("System tray"); checked: Settings.showTray
            onToggled: Settings.showTray = !Settings.showTray }
        SwitchRow { skey: "showSysmon"; label: I18n.tr("Resource monitor"); checked: Settings.showSysmon
            onToggled: Settings.showSysmon = !Settings.showSysmon }
        SwitchRow { skey: "showBattery"; label: I18n.tr("Battery"); shown: SettingsPalette.hasBattery
            checked: Settings.showBattery
            onToggled: Settings.showBattery = !Settings.showBattery }
        // Solo si está instalado power-profiles-daemon.
        SwitchRow { skey: "showPowerProfile"; label: I18n.tr("Power profile"); shown: Power.available
            checked: Settings.showPowerProfile
            onToggled: Settings.showPowerProfile = !Settings.showPowerProfile }
        SwitchRow { skey: "showClipboard"; label: I18n.tr("Clipboard"); checked: Settings.showClipboard
            onToggled: Settings.showClipboard = !Settings.showClipboard }
        SwitchRow { skey: "showNotifications"; label: I18n.tr("Notifications"); checked: Settings.showNotifications
            onToggled: Settings.showNotifications = !Settings.showNotifications }
        SwitchRow { skey: "showCaffeine"; label: I18n.tr("Caffeine"); checked: Settings.showCaffeine
            onToggled: Settings.showCaffeine = !Settings.showCaffeine }
    }
}
