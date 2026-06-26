import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Config

// ─────────────────────────────────────────────────────────────
//  Calendario mensual (lunes primero, locale español).
//  Cabecera con nombre de mes + navegación, rejilla 7×6 con el
//  día de hoy resaltado. Botón para volver al mes actual.
// ─────────────────────────────────────────────────────────────
ColumnLayout {
    id: cal
    spacing: Theme.space8

    // Reloj para mantener "hoy" fresco aunque pase la medianoche.
    SystemClock { id: sysClock; precision: SystemClock.Minutes }
    readonly property var today: sysClock.date

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
    property var cells: buildCells()
    function rebuild() { cells = buildCells() }

    function prevMonth() {
        if (viewMonth === 0) { viewMonth = 11; viewYear-- } else viewMonth--
        rebuild()
    }
    function nextMonth() {
        if (viewMonth === 11) { viewMonth = 0; viewYear++ } else viewMonth++
        rebuild()
    }
    function goToday() {
        viewYear = today.getFullYear(); viewMonth = today.getMonth(); rebuild()
    }
    function isToday(d) {
        return d > 0 && onCurrentMonth && d === today.getDate()
    }

    // ── Cabecera: mes + navegación ───────────────────────────
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
        NavBtn { glyph: "󰃭"; visible: !cal.onCurrentMonth; onTapped: cal.goToday() }
        NavBtn { glyph: "󰅁"; onTapped: cal.prevMonth() }
        NavBtn { glyph: "󰅂"; onTapped: cal.nextMonth() }
    }

    // ── Cabecera de días de la semana ────────────────────────
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

    // ── Rejilla de días ──────────────────────────────────────
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

    // Botón redondo de navegación reutilizable.
    component NavBtn: Rectangle {
        property string glyph: ""
        signal tapped()
        implicitWidth: Theme.controlS
        implicitHeight: Theme.controlS
        radius: width / 2
        color: navMa.containsMouse ? Theme.surfaceHi : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Text {
            anchors.centerIn: parent
            text: parent.glyph
            color: navMa.containsMouse ? Theme.accent : Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize - 1
        }
        MouseArea {
            id: navMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.tapped()
        }
    }
}
