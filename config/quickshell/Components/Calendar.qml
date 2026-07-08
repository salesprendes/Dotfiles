import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Services

// Calendario mensual (lunes primero, locale español). Rejilla 7×6 con el día de
// hoy resaltado y botón para volver al mes actual.
ColumnLayout {
    id: cal
    spacing: Theme.space8

    // "Hoy" viene de Time: solo cambia a medianoche, no en cada tick del reloj.
    readonly property var today: Time.today

    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()    // 0–11

    readonly property var dayNames: I18n.weekdayInitialsMondayFirst()

    readonly property bool onCurrentMonth:
        viewYear === today.getFullYear() && viewMonth === today.getMonth()

    function buildCells() {
        const first = new Date(viewYear, viewMonth, 1)
        const startW = (first.getDay() + 6) % 7          // lunes = 0
        const dim = new Date(viewYear, viewMonth + 1, 0).getDate()
        const out = []
        for (let i = 0; i < startW; i++) out.push(0)     // huecos previos
        for (let d = 1; d <= dim; d++) out.push(d)
        while (out.length % 7 !== 0) out.push(0)
        return out
    }
    // Se re-evalúa solo al cambiar viewYear/viewMonth.
    readonly property var cells: buildCells()

    function prevMonth() {
        if (viewMonth === 0) { viewMonth = 11; viewYear-- } else viewMonth--
    }
    function nextMonth() {
        if (viewMonth === 11) { viewMonth = 0; viewYear++ } else viewMonth++
    }
    function goToday() {
        viewYear = today.getFullYear(); viewMonth = today.getMonth()
    }
    function isToday(d) {
        return d > 0 && onCurrentMonth && d === today.getDate()
    }

    // Cabecera: mes + navegación
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space6

        Text {
            Layout.fillWidth: true
            text: I18n.monthName(cal.viewMonth, true) + " " + cal.viewYear
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
        }

        // Volver a hoy (solo si no estamos en el mes actual).
        NavBtn { icon: "󰃭"; visible: !cal.onCurrentMonth; onClicked: cal.goToday() }
        NavBtn { icon: "󰅁"; onClicked: cal.prevMonth() }
        NavBtn { icon: "󰅂"; onClicked: cal.nextMonth() }
    }

    // Días de la semana
    Grid {
        Layout.fillWidth: true
        columns: 7
        Repeater {
            model: cal.dayNames
            delegate: Item {
                required property var modelData
                width: (cal.width - 0) / 7
                height: Theme.dp(20)
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    font.bold: true
                }
            }
        }
    }

    // Rejilla de días
    Grid {
        Layout.fillWidth: true
        columns: 7
        Repeater {
            model: cal.cells
            delegate: Item {
                required property var modelData
                width: cal.width / 7
                height: cal.width / 7 * 0.82

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) - Theme.space4
                    height: width
                    radius: width / 2
                    visible: parent.modelData > 0
                    color: cal.isToday(parent.modelData) ? Theme.accent : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: parent.parent.modelData > 0 ? parent.parent.modelData : ""
                        color: cal.isToday(parent.parent.modelData) ? Theme.bg : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: cal.isToday(parent.parent.modelData)
                    }
                }
            }
        }
    }

    // Botón redondo de navegación = IconButton con el estilo del calendario.
    component NavBtn: IconButton {
        diameter: Theme.controlS
        iconPixelSize: Theme.iconSize - 1
        baseColor: Theme.surface
        hoverColor: Theme.surfaceHi
        iconColor: Theme.fgDim
        hoverIconColor: Theme.accent
    }
}
