import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services
import qs.Panels.SettingsPages

// Orden/alineación: lienzo de arrastrar y soltar. Al soltar, cada monitor
// imanta sus bordes a los de los demás.
ColumnLayout {
    id: arr
    spacing: Theme.space8
    Layout.fillWidth: true

    property var  pos: ({})        // name -> {x,y} lógico (en edición)
    property real f: 0.05          // escala lógico→lienzo (congelada al arrastrar)
    property real originX: 0       // lógico que mapea a canvas.pad
    property real originY: 0

    Component.onCompleted: arr.initPos()
    Connections { target: Displays; function onMonitorsChanged() { arr.initPos() } }

    function infoByName(n) {
        const m = Displays.monitors.find(x => Displays.info(x).name === n)
        return m ? Displays.info(m) : null
    }
    function initPos() {
        const p = ({})
        Displays.monitors.forEach(m => { const i = Displays.info(m); p[i.name] = ({ x: i.x, y: i.y }) })
        arr.pos = p
        arr.recalcView()
    }
    function setPos(n, x, y) {
        const p = Object.assign({}, arr.pos)
        p[n] = ({ x: x, y: y })
        arr.pos = p
    }
    // Reajusta escala+origen para encajar el conjunto (NO durante el arrastre).
    function recalcView() {
        let minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9
        Displays.monitors.forEach(m => {
            const i = Displays.info(m); const p = arr.pos[i.name] || ({ x: i.x, y: i.y })
            minX = Math.min(minX, p.x);          minY = Math.min(minY, p.y)
            maxX = Math.max(maxX, p.x + i.width); maxY = Math.max(maxY, p.y + i.height)
        })
        if (minX > maxX) return
        const w = Math.max(1, maxX - minX), h = Math.max(1, maxY - minY)
        const availW = canvas.width - canvas.pad * 2
        const availH = canvas.height - canvas.pad * 2
        arr.f = Math.max(0.001, Math.min(availW / w, availH / h))
        arr.originX = minX - (availW / arr.f - w) / 2     // centrar
        arr.originY = minY - (availH / arr.f - h) / 2
    }
    // Imán a los bordes de otros monitores al soltar.
    function snap(n) {
        const me = arr.infoByName(n); if (!me) return
        const p = arr.pos[n]; let lx = p.x, ly = p.y
        const th = Math.max(40, me.width * 0.06)
        Displays.monitors.forEach(m => {
            const o = Displays.info(m); if (o.name === n) return
            const op = arr.pos[o.name] || ({ x: o.x, y: o.y })
            if (Math.abs(lx - (op.x + o.width)) < th) lx = op.x + o.width             // a su derecha
            if (Math.abs((lx + me.width) - op.x) < th) lx = op.x - me.width            // a su izquierda
            if (Math.abs(lx - op.x) < th) lx = op.x                                    // alinear izq.
            if (Math.abs(ly - op.y) < th) ly = op.y                                    // alinear arriba
            if (Math.abs((ly + me.height) - (op.y + o.height)) < th) ly = op.y + o.height - me.height  // abajo
            if (Math.abs(ly - (op.y + o.height)) < th) ly = op.y + o.height            // debajo
            if (Math.abs((ly + me.height) - op.y) < th) ly = op.y - me.height          // encima
        })
        arr.setPos(n, Math.round(lx), Math.round(ly))
        arr.recalcView()
    }

    Rectangle {
        id: canvas
        Layout.fillWidth: true
        implicitHeight: Theme.dp(190)
        radius: Theme.barRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5)
        border.width: Theme.hairline
        border.color: SettingsPalette.settingsBorder
        clip: true
        readonly property real pad: Theme.space16
        onWidthChanged: arr.recalcView()
        onHeightChanged: arr.recalcView()

        Repeater {
            model: Displays.monitors
            delegate: Rectangle {
                id: tile
                required property var modelData
                readonly property var i: Displays.info(modelData)
                readonly property string mName: i.name
                readonly property var p: arr.pos[mName] || ({ x: i.x, y: i.y })
                width: i.width * arr.f
                height: i.height * arr.f
                x: canvas.pad + (p.x - arr.originX) * arr.f
                y: canvas.pad + (p.y - arr.originY) * arr.f
                radius: Theme.space4
                color: dragMa.active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.34)
                                     : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                border.width: Math.max(1, Theme.dp(2)); border.color: Theme.accent
                z: dragMa.active ? 2 : 1

                Column {
                    anchors.centerIn: parent
                    spacing: 0
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.mName
                           color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 4; font.bold: true }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.i.width + "×" + tile.i.height
                           color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 6 }
                }

                MouseArea {
                    id: dragMa
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    property real grabDX: 0
                    property real grabDY: 0
                    property bool active: false
                    onPressed: (mouse) => {
                        const c = mapToItem(canvas, mouse.x, mouse.y)
                        dragMa.grabDX = c.x - tile.x
                        dragMa.grabDY = c.y - tile.y
                        dragMa.active = true
                    }
                    onPositionChanged: (mouse) => {
                        if (!dragMa.active) return
                        const c = mapToItem(canvas, mouse.x, mouse.y)
                        const lx = arr.originX + (c.x - dragMa.grabDX - canvas.pad) / arr.f
                        const ly = arr.originY + (c.y - dragMa.grabDY - canvas.pad) / arr.f
                        arr.setPos(tile.mName, lx, ly)
                    }
                    onReleased: { dragMa.active = false; arr.snap(tile.mName) }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8
        Hint {
            text: I18n.tr("Drag monitors to arrange them")
        }
        TextButton {
            text: I18n.tr("Apply layout")
            primary: true
            onClicked: {
                Displays.monitors.forEach(m => {
                    const i = Displays.info(m)
                    const p = arr.pos[i.name] || ({ x: i.x, y: i.y })
                    Displays.apply(({
                        name: i.name, res: i.width + "x" + i.height,
                        refresh: Number(i.refresh).toFixed(2), scale: i.scale,
                        transform: i.transform, x: p.x, y: p.y, enabled: !i.disabled
                    }))
                })
            }
        }
    }
}
