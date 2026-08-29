import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Selector de emojis: buscador + rejilla. Elegir uno lo copia al portapapeles
// y cierra el panel; el emoji entra además en el historial del portapapeles,
// porque cliphist ve el cambio de selección como cualquier otra copia.
//
// El catálogo se carga la primera vez que se abre (Emoji.load()), no al
// arrancar el shell: son 2.500 entradas que la mayoría de las sesiones nunca
// llegan a mirar.
Popout {
    id: panel

    ns: "qs-emoji"
    cardWidth: 420
    cardMinWidth: 320
    shown: Globals.emojiOpen
    // Las flechas mueven el cursor por la rejilla, así que aquí no pueden
    // saltar de panel.
    switchWithArrows: false

    // Cuántas caben por fila. No es fijo: el ancho de la tarjeta depende del
    // monitor (ver Theme.panelWidth), y con un número clavado la última
    // columna se salía en pantallas estrechas.
    readonly property int cellSize: Theme.dp(40)
    readonly property int columns: Math.max(6, Math.floor(
        (panel.effectiveCardWidth - Theme.space16 * 2) / panel.cellSize))

    property int selectedIndex: 0

    // Mismo filtro de hover fantasma que el portapapeles y el lanzador: al
    // teclear, la rejilla se refiltra bajo un cursor parado. Ver
    // Components/PointerMoveGate.qml.
    PointerMoveGate {
        id: hoverGate
        referenceItem: grid
    }

    readonly property var results: Emoji.filtered

    function moveSelection(delta) {
        const n = panel.results.length
        if (n <= 0)
            return
        hoverGate.reset()
        panel.selectedIndex = Math.max(0, Math.min(n - 1, panel.selectedIndex + delta))
        grid.positionViewAtIndex(panel.selectedIndex, GridView.Contain)
    }

    function pickSelected() {
        const e = panel.results[panel.selectedIndex]
        if (!e)
            return
        Emoji.copy(e.c)
        Globals.closeAll()
    }

    onShownChanged: {
        if (!shown)
            return
        Emoji.load()
        Emoji.query = ""
        Emoji.group = ""
        searchField.text = ""
        panel.selectedIndex = 0
        hoverGate.reset()
        focusTimer.restart()
    }

    // El foco se pide con un pulso y no directamente: al abrir, la ventana aún
    // no tiene el foco del compositor y un forceActiveFocus() inmediato se
    // pierde. Mismo patrón que el resto de paneles con buscador.
    Timer {
        id: focusTimer
        interval: 80
        onTriggered: searchField.input.forceActiveFocus()
    }

    SearchField {
        id: searchField
        Layout.fillWidth: true
        placeholder: I18n.tr("Search emoji…")
        onTextChanged: {
            Emoji.query = text
            panel.selectedIndex = 0
            hoverGate.reset()
        }
        onAccepted: panel.pickSelected()
        onDownPressed: panel.moveSelection(panel.columns)
        onUpPressed: panel.moveSelection(-panel.columns)
        // Izquierda y derecha mueven de uno en uno, pero SOLO cuando no hay
        // nada escrito: con texto en el campo, las flechas horizontales son
        // del cursor de edición y robárselas hace el buscador inusable.
        onLeftPressed: (event) => {
            if (searchField.text !== "")
                return
            panel.moveSelection(-1)
            event.accepted = true
        }
        onRightPressed: (event) => {
            if (searchField.text !== "")
                return
            panel.moveSelection(1)
            event.accepted = true
        }
    }

    // Filtro por grupo. Una fila de fichas, la elegida en acento.
    Flickable {
        Layout.fillWidth: true
        implicitHeight: groupRow.implicitHeight
        contentWidth: groupRow.implicitWidth
        contentHeight: groupRow.implicitHeight
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: groupRow
            spacing: Theme.space6

            GroupChip { label: I18n.tr("All"); value: "" }
            Repeater {
                model: Emoji.groups
                delegate: GroupChip {
                    required property string modelData
                    label: modelData
                    value: modelData
                }
            }
        }
    }

    component GroupChip: Rectangle {
        id: chip
        property string label: ""
        property string value: ""
        readonly property bool current: Emoji.group === chip.value

        implicitWidth: chipText.implicitWidth + Theme.space10 * 2
        implicitHeight: Theme.dp(26)
        radius: height / 2
        color: chip.current ? Theme.withAlpha(Theme.accent, 0.22)
             : Theme.stateLayer(Theme.surface, Theme.fg,
                                Theme.stateAlpha(chipMa.containsMouse, chipMa.pressed, false))
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        ThemedText {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.current ? Theme.accentText : Theme.fgDim
            font.pixelSize: Theme.typeLabelSmall
        }

        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Emoji.group = chip.value
                panel.selectedIndex = 0
                hoverGate.reset()
            }
        }
    }

    // Estado vacío: hay que decir POR QUÉ no hay nada, que no es lo mismo
    // "todavía cargando" que "tu búsqueda no encuentra nada".
    ThemedText {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space12
        Layout.bottomMargin: Theme.space12
        visible: panel.results.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: !Emoji.loaded ? I18n.tr("Loading…")
                            : I18n.tr("Nothing matches “%1”.").arg(Emoji.query)
        color: Theme.fgMuted
        font.pixelSize: Theme.typeBodySmall
        wrapMode: Text.WordWrap
    }

    GridView {
        id: grid

        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(Theme.dp(300), grid.contentHeight)
        visible: panel.results.length > 0
        clip: true
        cellWidth: Math.floor(grid.width / panel.columns)
        cellHeight: panel.cellSize
        model: panel.results
        currentIndex: panel.selectedIndex
        boundsBehavior: Flickable.StopAtBounds
        // La rejilla puede tener miles de celdas y todas son del mismo tamaño y
        // la misma forma: es el caso para el que se inventó el reciclado.
        reuseItems: true
        cacheBuffer: Theme.dp(400)

        delegate: Item {
            id: cell
            required property var modelData
            required property int index

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: Theme.dp(2)
                radius: Theme.shapeSm
                // Sobre fondo TRANSPARENTE la capa de estado no se mezcla: se
                // pinta ella sola con su propia opacidad. Mezclar contra un
                // transparente daría un color con alfa 0 — invisible.
                color: cell.index === panel.selectedIndex
                       ? Theme.withAlpha(Theme.accent, 0.22)
                       : Theme.withAlpha(Theme.fg,
                                         Theme.stateAlpha(cellMa.containsMouse, cellMa.pressed, false))
                border.width: cell.index === panel.selectedIndex ? Theme.hairline : 0
                border.color: Theme.withAlpha(Theme.accent, 0.55)
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }

            Text {
                anchors.centerIn: parent
                text: cell.modelData ? cell.modelData.c : ""
                // Fuente por defecto del sistema, NO la del shell: la
                // tipografía del shell es una Nerd Font monoespaciada y sus
                // emojis, cuando los tiene, son los de respaldo en blanco y
                // negro. Dejando que Qt elija, entra la fuente de emoji en
                // color que haya instalada (Noto Color Emoji y compañía).
                font.pixelSize: Theme.sp(22)
                color: Theme.fg
            }

            MouseArea {
                id: cellMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: (m) => {
                    if (hoverGate.moved(cellMa, m))
                        panel.selectedIndex = cell.index
                }
                onClicked: {
                    panel.selectedIndex = cell.index
                    panel.pickSelected()
                }
            }
        }
    }

    // Nombre del emoji bajo el cursor. Es lo que hace buscable el catálogo de
    // verdad: "flag spain es" no se adivina mirando la bandera.
    ThemedText {
        Layout.fillWidth: true
        visible: panel.results.length > 0
        text: panel.results[panel.selectedIndex]
              ? panel.results[panel.selectedIndex].n : ""
        color: Theme.fgMuted
        font.pixelSize: Theme.typeBodySmall
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
    }
}
