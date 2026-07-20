pragma Singleton

import QtQuick
import Quickshell
import qs.Config

// Reloj del sistema compartido: un solo SystemClock para todas las barras. La
// fecha (today, dateString) solo se recalcula al cambiar el día o el idioma,
// no en cada tick.
Singleton {
    id: root

    readonly property date now: clock.date

    // Formato de hora según ajustes (24h/12h y segundos), compartido por los
    // consumidores que pintan la hora para no repetir la expresión.
    readonly property string clockFormat: (Settings.clock24h ? "HH:mm" : "hh:mm")
        + (Settings.clockShowSeconds ? ":ss" : "")
        + (Settings.clock24h ? "" : " AP")

    // Fecha "estable": solo se reasigna al cambiar de día, para que
    // los bindings que dependen del día (calendario, resaltado de
    // hoy…) no se re-evalúen en cada tick del reloj.
    property date today: new Date()

    // Fecha larga precalculada una vez por día (no en cada tick).
    property string dateString: ""

    // Clave del último día formateado (aaaammdd); -1 fuerza recálculo.
    property int _lastDayKey: -1

    SystemClock {
        id: clock
        precision: Settings.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
        onDateChanged: root._refresh()
    }

    // Si cambia el idioma, la fecha formateada debe regenerarse
    // aunque el día siga siendo el mismo.
    Connections {
        target: I18n
        function onLanguageChanged() { root._lastDayKey = -1; root._refresh() }
    }

    function _refresh() {
        const d = clock.date
        const key = (d.getFullYear() * 100 + d.getMonth()) * 100 + d.getDate()
        if (key === root._lastDayKey)
            return
        root._lastDayKey = key
        root.today = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        root.dateString = d.toLocaleDateString(I18n.locale(), "ddd dd MMM")
    }

    Component.onCompleted: _refresh()
}
