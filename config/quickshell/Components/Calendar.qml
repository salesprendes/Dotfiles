import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Services

// Calendario mensual (lunes primero, locale español). Rejilla 7×6 con:
// hoy resaltado (círculo de acento con halo) y su columna e inicial en acento,
// días de los meses adyacentes en tenue (clic para saltar a ese mes), fines de
// semana atenuados, resaltado al pasar el ratón, números de semana ISO con la
// semana actual en acento, rueda del ratón para navegar meses, clic en el
// mes/año para volver a hoy y deslizamiento direccional al cambiar de mes.
ColumnLayout {
    id: cal
    spacing: Theme.space8

    // "Hoy" viene de Time: solo cambia a medianoche, no en cada tick del reloj.
    readonly property var today: Time.today

    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()    // 0–11

    property bool showWeekNumbers: true

    readonly property var dayNames: I18n.weekdayInitialsMondayFirst()

    readonly property bool onCurrentMonth:
        viewYear === today.getFullYear() && viewMonth === today.getMonth()

    // Columna (lunes = 0) del día de hoy, para resaltar su inicial.
    readonly property int todayColumn: (today.getDay() + 6) % 7

    // Día de la semana (lunes = 0) del 1 del mes visible.
    readonly property int startWeekday:
        (new Date(viewYear, viewMonth, 1).getDay() + 6) % 7

    // Fila de la rejilla donde cae hoy (-1 fuera del mes actual), para teñir
    // su número de semana.
    readonly property int todayRow: onCurrentMonth
        ? Math.floor((startWeekday + today.getDate() - 1) / 7) : -1

    // Ancho reservado a los números de semana y ancho resultante de cada celda.
    readonly property real wkColW: showWeekNumbers ? Theme.dp(20) : 0
    readonly property real cellW: (width - wkColW) / 7
    readonly property real cellH: cellW * 0.82

    // Celdas como {d, cur}: 'cur' distingue el mes visible de los días de
    // relleno de los meses anterior/siguiente (que también se muestran).
    function buildCells() {
        const dim = new Date(viewYear, viewMonth + 1, 0).getDate()
        const prevDim = new Date(viewYear, viewMonth, 0).getDate()
        const out = []
        for (let i = startWeekday - 1; i >= 0; i--) out.push({ d: prevDim - i, cur: false })
        for (let d = 1; d <= dim; d++) out.push({ d: d, cur: true })
        let next = 1
        while (out.length % 7 !== 0) out.push({ d: next++, cur: false })
        return out
    }
    // Se re-evalúa solo al cambiar viewYear/viewMonth.
    readonly property var cells: buildCells()

    // Semana ISO 8601 (la semana 1 es la que contiene el primer jueves).
    function isoWeek(date) {
        const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
        d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7) + 3)   // jueves de esa semana
        const ft = new Date(Date.UTC(d.getUTCFullYear(), 0, 4))
        ft.setUTCDate(ft.getUTCDate() - ((ft.getUTCDay() + 6) % 7) + 3)
        return 1 + Math.round((d - ft) / (7 * 86400000))
    }

    // Número de semana de cada fila visible (por su jueves, criterio ISO).
    readonly property var weekNums: {
        const out = []
        for (let r = 0; r < cells.length / 7; r++)
            out.push(isoWeek(new Date(viewYear, viewMonth, 1 - startWeekday + r * 7 + 3)))
        return out
    }

    // dir: -1 mes anterior (entra desde la izquierda), +1 siguiente, 0 hoy.
    property int _slideDir: 0
    function _animate(dir) { _slideDir = dir; monthAnim.restart() }

    function prevMonth() {
        if (viewMonth === 0) { viewMonth = 11; viewYear-- } else viewMonth--
        _animate(-1)
    }
    function nextMonth() {
        if (viewMonth === 11) { viewMonth = 0; viewYear++ } else viewMonth++
        _animate(1)
    }
    function goToday() {
        if (onCurrentMonth)
            return
        viewYear = today.getFullYear(); viewMonth = today.getMonth()
        _animate(0)
    }
    function isToday(cell) {
        return cell.cur && onCurrentMonth && cell.d === today.getDate()
    }

    // Cabecera: mes en negrita + año atenuado (clic: volver a hoy) y
    // navegación a la derecha.
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space6

        Item {
            Layout.fillWidth: true
            implicitHeight: hdrRow.implicitHeight

            Row {
                id: hdrRow
                spacing: Theme.space4
                Text {
                    text: I18n.monthName(cal.viewMonth, true)
                    color: hdrMa.containsMouse && !cal.onCurrentMonth ? Theme.accent : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }
                Text {
                    text: cal.viewYear
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                }
            }
            MouseArea {
                id: hdrMa
                anchors.fill: hdrRow
                hoverEnabled: true
                cursorShape: cal.onCurrentMonth ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: cal.goToday()
            }
        }

        // Volver a hoy (solo si no estamos en el mes actual).
        NavBtn { icon: "󰃭"; visible: !cal.onCurrentMonth; onClicked: cal.goToday() }
        NavBtn { icon: "󰅁"; onClicked: cal.prevMonth() }
        NavBtn { icon: "󰅂"; onClicked: cal.nextMonth() }
    }

    // Días de la semana, con la columna de hoy en acento.
    RowLayout {
        Layout.fillWidth: true
        spacing: 0
        Item { implicitWidth: cal.wkColW; implicitHeight: 1; visible: cal.showWeekNumbers }
        Grid {
            Layout.fillWidth: true
            columns: 7
            Repeater {
                model: cal.dayNames
                delegate: Item {
                    id: wdCell
                    required property var modelData
                    required property int index
                    width: cal.cellW
                    height: Theme.dp(20)
                    Text {
                        anchors.centerIn: parent
                        text: wdCell.modelData
                        color: cal.onCurrentMonth && wdCell.index === cal.todayColumn
                               ? Theme.accent : Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        font.bold: true
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.hairline
        color: Theme.withAlpha(Theme.overlay, 0.35)
    }

    // Números de semana + rejilla de días. La rueda del ratón navega meses.
    RowLayout {
        id: daysArea
        Layout.fillWidth: true
        spacing: 0
        opacity: 1
        transform: Translate { id: slideT; x: 0 }

        // Acumula el desplazamiento para que los touchpads (muchos eventos
        // pequeños) no salten varios meses de golpe.
        property real _wheelAcc: 0
        WheelHandler {
            target: null
            onWheel: (ev) => {
                daysArea._wheelAcc += ev.angleDelta.y
                if (daysArea._wheelAcc <= -120) { daysArea._wheelAcc = 0; cal.nextMonth() }
                else if (daysArea._wheelAcc >= 120) { daysArea._wheelAcc = 0; cal.prevMonth() }
            }
        }

        ColumnLayout {
            visible: cal.showWeekNumbers
            Layout.alignment: Qt.AlignTop
            spacing: 0
            Repeater {
                model: cal.weekNums
                delegate: Item {
                    id: wkCell
                    required property var modelData
                    required property int index
                    implicitWidth: cal.wkColW
                    implicitHeight: cal.cellH
                    Text {
                        anchors.centerIn: parent
                        text: wkCell.modelData
                        color: wkCell.index === cal.todayRow
                               ? Theme.accent : Theme.withAlpha(Theme.fgMuted, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 4
                        font.bold: wkCell.index === cal.todayRow
                    }
                }
            }
        }

        Grid {
            Layout.fillWidth: true
            columns: 7
            Repeater {
                model: cal.cells
                delegate: Item {
                    id: dayCell
                    required property var modelData
                    required property int index
                    readonly property bool today: cal.isToday(modelData)
                    readonly property bool weekend: index % 7 >= 5
                    width: cal.cellW
                    height: cal.cellH

                    // Halo suave alrededor de hoy.
                    Rectangle {
                        visible: dayCell.today
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) + Theme.space2
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: Theme.dp(2)
                        border.color: Theme.withAlpha(Theme.accent, 0.3)
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) - Theme.space4
                        height: width
                        radius: width / 2
                        color: dayCell.today ? Theme.accent
                             : dayMa.containsMouse ? Theme.surfaceHi : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Text {
                            anchors.centerIn: parent
                            text: dayCell.modelData.d
                            color: dayCell.today ? Theme.bg
                                 : !dayCell.modelData.cur ? Theme.withAlpha(Theme.fgMuted, 0.45)
                                 : dayMa.containsMouse ? Theme.fg
                                 : dayCell.weekend ? Theme.fgMuted : Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: dayCell.today
                        }
                    }

                    // Hover; clic en un día tenue salta a su mes.
                    MouseArea {
                        id: dayMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: dayCell.modelData.cur ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            if (dayCell.modelData.cur)
                                return
                            if (dayCell.index < 7) cal.prevMonth()
                            else cal.nextMonth()
                        }
                    }
                }
            }
        }
    }

    // Deslizamiento direccional + fundido al navegar: el mes nuevo entra
    // desde el lado hacia el que avanzas (las celdas se reconstruyen al
    // instante; esto solo suaviza el cambio visual).
    ParallelAnimation {
        id: monthAnim
        NumberAnimation {
            target: slideT; property: "x"
            from: cal._slideDir * Theme.dp(26); to: 0
            duration: 240; easing.type: Easing.OutCubic
        }
        SequentialAnimation {
            NumberAnimation { target: daysArea; property: "opacity"; to: 0.35; duration: 60 }
            NumberAnimation { target: daysArea; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
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
