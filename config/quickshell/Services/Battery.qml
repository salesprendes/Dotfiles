pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Config

// Estado de batería (UPower), compartido por la barra, Ajustes y el aviso de
// batería baja. Único punto que lee displayDevice, para que los consumidores no
// dupliquen la lógica.
Singleton {
    id: batt

    readonly property var device: UPower.displayDevice
    readonly property bool present: device?.isLaptopBattery ?? false
    readonly property int percent: Math.round(device?.percentage ?? 0)
    readonly property bool charging: (device?.state ?? 0) === UPowerDeviceState.Charging
                                     || (device?.state ?? 0) === UPowerDeviceState.PendingCharge
    readonly property bool discharging: device ? device.state === UPowerDeviceState.Discharging : false

    // Aviso de batería baja, solo en portátiles. Los umbrales y si avisar o no
    // se configuran, porque lo que en una batería nueva son dos horas en una
    // gastada son quince minutos.
    //
    // Un aviso por cruce de umbral, rearmado al subir por encima del umbral bajo
    // con margen.
    property int _stage: 0
    readonly property real _pct: present ? (device?.percentage ?? -1) : -1
    readonly property int lowThreshold: Settings.batteryLowThreshold
    // El crítico nunca puede quedar por encima del bajo: cruzados, el aviso
    // crítico saltaría antes que el bajo y el orden de gravedad se leería al
    // revés.
    readonly property int criticalThreshold: Math.min(Settings.batteryCriticalThreshold,
                                                      Settings.batteryLowThreshold)
    on_PctChanged: _check()
    onDischargingChanged: _check()
    function _check() {
        if (_pct < 0 || !discharging) {
            if (_pct >= lowThreshold + 5) _stage = 0
            return
        }
        if (_pct <= criticalThreshold && _stage < 2) {
            _stage = 2
            if (Settings.batteryNotifyCritical)
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Quickshell",
                    I18n.tr("Critical battery"),
                    I18n.tr("%1% remaining — plug in now").arg(Math.round(_pct))])
        } else if (_pct <= lowThreshold && _stage < 1) {
            _stage = 1
            if (Settings.batteryNotifyLow)
                Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "Quickshell",
                    I18n.tr("Low battery"),
                    I18n.tr("%1% remaining").arg(Math.round(_pct))])
        }
    }
}
