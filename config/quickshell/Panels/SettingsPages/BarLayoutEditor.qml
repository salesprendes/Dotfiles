import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages
import qs.Services

// Editor de la disposición de la barra: tres carriles (izquierda, centro,
// derecha) con las píldoras que hay puestas, y debajo el cajón de las que
// quedan por poner. Se arrastra de un sitio a otro.
//
// CÓMO FUNCIONA EL ARRASTRE, y por qué así:
//
// La píldora que se arrastra NO se reparenta ni se mueve. Se queda en su
// carril, atenuada, haciendo de hueco de origen; lo que sigue al ratón es un
// FANTASMA dibujado aparte, en una capa por encima de todo. Reparentar el
// delegate de un Repeater —que es lo que hace el manual— funciona hasta que el
// modelo cambia: entonces el Repeater reclama a su hijo, se encuentra con que
// tiene otro padre, y lo que se ve es una píldora que desaparece a mitad del
// gesto o que se queda pegada en la capa de arrastre para siempre.
//
// El destino se decide con DropArea: entre cada dos píldoras (y en las puntas)
// hay un hueco de suelta que se enciende cuando el fantasma pasa por encima.
// Es más código que calcular el índice por la coordenada x, pero no se
// equivoca cuando un carril tiene píldoras de anchos muy distintos, que es
// justo lo que pasa aquí — "Ventana activa" mide seis veces lo que "Cafeína".
SettingsRow {
    id: editor

    skey: "barLayout"
    filterText: I18n.tr("Bar widgets") + " " + I18n.tr("Left") + " "
                + I18n.tr("Center") + " " + I18n.tr("Right") + " " + _allNames
    // Es un bloque, no una fila: sin filete propio ni banda de hover.
    isSettingsRow: false
    rowHighlight: false

    readonly property string _allNames: {
        let out = ""
        for (const w of BarCatalog.widgets)
            out += BarCatalog.nameFor(w.id) + " "
        return out
    }

    implicitHeight: body.implicitHeight

    readonly property var layout: Settings.barLayout

    function commit(next) {
        Settings.barLayout = next
    }

    // ── Disponibilidad ───────────────────────────────────────────────────────
    // BarCatalog no importa qs.Services (Config no debe depender de la capa de
    // servicios), así que la comprobación vive aquí, que es donde ya se conocen
    // Power y Battery. Un widget cuyo servicio no está no se ofrece: añadirlo
    // solo daría una píldora que nunca aparece.
    function isAvailable(id) {
        const meta = BarCatalog.metaFor(id)
        if (!meta)
            return false
        if (meta.needs === "power")   return Power.available
        if (meta.needs === "battery") return Battery.present
        return true
    }

    // Widgets que se pueden añadir: los disponibles que no estén ya puestos
    // (salvo los que admiten varias instancias, que siempre se ofrecen).
    readonly property var addable: {
        const out = []
        for (const w of BarCatalog.widgets) {
            if (!editor.isAvailable(w.id))
                continue
            if (!w.multiple && BarCatalog.has(editor.layout, w.id))
                continue
            out.push(w.id)
        }
        return out
    }

    // ── Estado del arrastre ──────────────────────────────────────────────────
    property bool dragging: false
    property string dragId: ""
    property string dragSection: ""
    property int dragIndex: -1
    property real dragX: 0
    property real dragY: 0
    // Destino en curso, o null. { section, index }
    property var dropAt: null
    // Un arrastre que viene del cajón AÑADE en vez de mover.
    property bool dragFromDrawer: false

    function beginDrag(section, index, id, pt, fromDrawer) {
        editor.dragging = true
        editor.dragId = id
        editor.dragSection = section
        editor.dragIndex = index
        editor.dragFromDrawer = fromDrawer === true
        editor.dropAt = null
        moveDrag(pt)
    }

    function moveDrag(pt) {
        editor.dragX = pt.x
        editor.dragY = pt.y
    }

    function endDrag() {
        if (!editor.dragging)
            return
        const target = editor.dropAt
        const fromDrawer = editor.dragFromDrawer
        const id = editor.dragId
        const from = { section: editor.dragSection, index: editor.dragIndex }
        cancelDrag()
        if (!target)
            return
        if (fromDrawer) {
            // Añadir en el punto exacto donde se ha soltado, no al final de su
            // sección de fábrica: si te has molestado en apuntar, va ahí.
            let next = BarCatalog.add(editor.layout, id, target.section)
            const placed = BarCatalog.locate(next, id)
            if (placed)
                next = BarCatalog.move(next, placed.section, placed.index,
                                       target.section, target.index)
            editor.commit(next)
            return
        }
        // Soltar en el mismo hueco del que salió no es un cambio; evitarlo
        // ahorra una reescritura de settings.json por cada arrastre en falso.
        if (target.section === from.section
            && (target.index === from.index || target.index === from.index + 1))
            return
        // El índice de destino se cuenta sobre la lista CON la píldora todavía
        // dentro (es lo que el usuario ve), pero move() lo interpreta sobre la
        // lista ya sin ella: dentro del mismo carril y hacia la derecha hay que
        // descontar el hueco que deja al salir.
        let to = target.index
        if (target.section === from.section && to > from.index)
            to--
        editor.commit(BarCatalog.move(editor.layout, from.section, from.index,
                                      target.section, to))
    }

    function cancelDrag() {
        editor.dragging = false
        editor.dragId = ""
        editor.dragSection = ""
        editor.dragIndex = -1
        editor.dragFromDrawer = false
        editor.dropAt = null
    }

    function sectionName(section) {
        return section === "left" ? I18n.tr("Left")
             : section === "center" ? I18n.tr("Center")
             : I18n.tr("Right")
    }

    // ── Píldora ──────────────────────────────────────────────────────────────
    component WidgetChip: Rectangle {
        id: chip

        property string wid: ""
        property string section: ""
        property int idx: -1
        property bool fromDrawer: false
        // La que se está arrastrando se queda como hueco fantasma.
        readonly property bool isSource: editor.dragging && !chip.fromDrawer
                                         && editor.dragSection === chip.section
                                         && editor.dragIndex === chip.idx

        implicitWidth: chipRow.implicitWidth + Theme.space10 * 2
        implicitHeight: Theme.dp(32)
        radius: height / 2
        color: chip.fromDrawer ? "transparent"
             : (chipMa.containsMouse ? Theme.surfaceHi : SettingsPalette.settingsControl)
        border.width: chip.fromDrawer ? Math.max(1, Theme.hairline) : 0
        border.color: SettingsPalette.settingsBorder
        opacity: chip.isSource ? 0.3 : 1
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Theme.space6

            ThemedText {
                text: BarCatalog.glyphFor(chip.wid)
                color: chip.fromDrawer ? Theme.fgMuted : Theme.accent
                font.pixelSize: Theme.fontSize
            }
            ThemedText {
                text: BarCatalog.nameFor(chip.wid)
                color: chip.fromDrawer ? Theme.fgDim : Theme.fg
                font.pixelSize: Theme.typeBodySmall
            }
            // Quitar. Solo en las puestas: en el cajón no hay nada que quitar.
            IconButton {
                visible: !chip.fromDrawer
                icon: "󰅖"
                diameter: Theme.dp(20)
                iconPixelSize: Theme.dp(11)
                baseColor: "transparent"
                iconColor: Theme.fgMuted
                onClicked: editor.commit(
                    BarCatalog.removeAt(editor.layout, chip.section, chip.idx))
            }
        }

        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // La página de Ajustes va dentro de un Flickable: sin esto, el
            // primer píxel de movimiento vertical se lo lleva el desplazamiento
            // y el arrastre nunca llega a empezar.
            preventStealing: true
            // El botón de quitar se dibuja después y captura sus propios clics;
            // este MouseArea solo ve el resto de la píldora.
            z: -1

            property point origin: Qt.point(0, 0)
            property bool armed: false

            onPressed: (m) => {
                origin = Qt.point(m.x, m.y)
                armed = true
            }
            onPositionChanged: (m) => {
                if (!armed)
                    return
                const pt = chipMa.mapToItem(editor, m.x, m.y)
                if (!editor.dragging) {
                    // Umbral: sin él, un clic con un temblor de un píxel entra
                    // en modo arrastre y la píldora parpadea en cada toque.
                    if (Math.abs(m.x - origin.x) < 4 && Math.abs(m.y - origin.y) < 4)
                        return
                    editor.beginDrag(chip.section, chip.idx, chip.wid, pt, chip.fromDrawer)
                    return
                }
                editor.moveDrag(pt)
            }
            onReleased: {
                armed = false
                editor.endDrag()
            }
            // Si el gesto se lo lleva otro (cambio de pestaña a media
            // arrastrada, por ejemplo) no se puede dar por soltado: eso
            // movería la píldora a donde estuviera el ratón por casualidad.
            onCanceled: {
                armed = false
                editor.cancelDrag()
            }
        }
    }

    // ── Hueco de suelta ──────────────────────────────────────────────────────
    // Uno entre cada dos píldoras y otro en cada punta. Estrecho en reposo; se
    // ensancha y se enciende cuando el fantasma está encima, que es lo que
    // dice "aquí es donde va a caer".
    component DropGap: Item {
        id: gap

        property string section: ""
        property int index: 0
        readonly property bool isTarget: editor.dropAt
                                         && editor.dropAt.section === gap.section
                                         && editor.dropAt.index === gap.index

        implicitWidth: gap.isTarget ? Theme.dp(22) : Theme.dp(8)
        implicitHeight: Theme.dp(32)
        Behavior on implicitWidth { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }

        Rectangle {
            anchors.centerIn: parent
            width: Theme.dp(3)
            height: parent.height * 0.8
            radius: width / 2
            color: Theme.accent
            opacity: gap.isTarget ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        }

        DropArea {
            anchors.fill: parent
            // Margen generoso alrededor: un hueco de 8 px es un blanco
            // imposible con el ratón en movimiento.
            anchors.margins: -Theme.dp(10)
            keys: ["qs-bar-widget"]
            onEntered: editor.dropAt = { section: gap.section, index: gap.index }
        }
    }

    // ── Cuerpo ───────────────────────────────────────────────────────────────
    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.space10

        // Los tres carriles.
        Repeater {
            model: BarCatalog.sections
            delegate: ColumnLayout {
                id: lane
                required property string modelData
                readonly property var entries: BarCatalog.entriesOf(editor.layout, lane.modelData)

                Layout.fillWidth: true
                spacing: Theme.space4

                ThemedText {
                    text: editor.sectionName(lane.modelData)
                    color: Theme.fgMuted
                    font.pixelSize: Theme.typeLabelSmall
                    font.weight: Font.Medium
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: laneFlow.implicitHeight + Theme.space6 * 2
                    radius: Theme.shapeSm
                    color: Theme.withAlpha(Theme.overlay, 0.10)
                    border.width: Math.max(1, Theme.hairline)
                    // El carril de destino se marca entero, no solo el hueco:
                    // con tres carriles pegados hace falta saber en cuál vas a
                    // soltar antes de afinar la posición.
                    border.color: editor.dropAt && editor.dropAt.section === lane.modelData
                                  ? Theme.withAlpha(Theme.accent, 0.7)
                                  : "transparent"
                    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                    Flow {
                        id: laneFlow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.space6
                        spacing: 0

                        // Un hueco por cada posición posible (n+1) y, tras cada
                        // uno salvo el último, su píldora.
                        Repeater {
                            model: lane.entries.length + 1
                            delegate: Row {
                                id: slotRow
                                required property int index
                                readonly property bool hasChip: slotRow.index < lane.entries.length
                                spacing: 0

                                DropGap {
                                    section: lane.modelData
                                    index: slotRow.index
                                }
                                WidgetChip {
                                    visible: slotRow.hasChip
                                    wid: slotRow.hasChip
                                         ? String(lane.entries[slotRow.index].id) : ""
                                    section: lane.modelData
                                    idx: slotRow.index
                                }
                            }
                        }
                    }

                    ThemedText {
                        anchors.centerIn: parent
                        visible: lane.entries.length === 0
                        text: I18n.tr("Drop a widget here")
                        color: Theme.fgMuted
                        font.pixelSize: Theme.typeBodySmall
                    }
                }
            }
        }

        // Cajón de widgets por poner.
        ThemedText {
            Layout.topMargin: Theme.space4
            text: I18n.tr("Available")
            color: Theme.fgMuted
            font.pixelSize: Theme.typeLabelSmall
            font.weight: Font.Medium
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.space6

            Repeater {
                model: editor.addable
                delegate: WidgetChip {
                    required property string modelData
                    wid: modelData
                    fromDrawer: true
                    section: ""
                    idx: -1
                }
            }
        }

        ThemedText {
            Layout.fillWidth: true
            visible: editor.addable.length === 0
            text: I18n.tr("Every widget is already in the bar.")
            color: Theme.fgMuted
            font.pixelSize: Theme.typeBodySmall
            wrapMode: Text.WordWrap
        }

        ThemedText {
            Layout.fillWidth: true
            text: I18n.tr("Drag to reorder or move between sides. Drag one from Available to add it.")
            color: Theme.fgMuted
            font.pixelSize: Theme.typeBodySmall
            wrapMode: Text.WordWrap
        }

        TextButton {
            Layout.topMargin: Theme.space4
            text: I18n.tr("Restore default layout")
            outlined: true
            enabled: JSON.stringify(editor.layout) !== JSON.stringify(BarCatalog.defaultLayout())
            onClicked: editor.commit(BarCatalog.defaultLayout())
        }
    }

    // ── Capa de arrastre ─────────────────────────────────────────────────────
    // Por encima de todo lo demás y SIN input: si capturara el ratón, el
    // MouseArea de la píldora dejaría de recibir los movimientos en cuanto el
    // fantasma se pusiera bajo el cursor — que es siempre.

    // Ancla de 1×1 con Drag activo: es lo que hacen sonar los DropArea. El
    // fantasma visible va aparte porque un item con Drag activo y tamaño real
    // dispararía los huecos por su esquina, no por la punta del ratón.
    Item {
        id: dragAnchor
        x: editor.dragX
        y: editor.dragY
        width: 1
        height: 1
        Drag.active: editor.dragging
        Drag.keys: ["qs-bar-widget"]
        Drag.hotSpot: Qt.point(0, 0)
    }

    Rectangle {
        id: ghost
        visible: editor.dragging
        z: 100
        // Colgando bajo el cursor y un poco a su derecha: centrado, el propio
        // fantasma tapa el hueco que estás intentando apuntar.
        x: editor.dragX + Theme.dp(8)
        y: editor.dragY - height / 2
        implicitWidth: ghostRow.implicitWidth + Theme.space10 * 2
        width: implicitWidth
        height: Theme.dp(32)
        radius: height / 2
        color: Theme.surfaceHi
        border.width: Math.max(1, Theme.hairline)
        border.color: Theme.withAlpha(Theme.accent, 0.8)
        opacity: 0.94

        RowLayout {
            id: ghostRow
            anchors.centerIn: parent
            spacing: Theme.space6
            ThemedText {
                text: editor.dragId !== "" ? BarCatalog.glyphFor(editor.dragId) : ""
                color: Theme.accent
                font.pixelSize: Theme.fontSize
            }
            ThemedText {
                text: editor.dragId !== "" ? BarCatalog.nameFor(editor.dragId) : ""
                color: Theme.fg
                font.pixelSize: Theme.typeBodySmall
            }
        }
    }
}
