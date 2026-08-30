import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Selector segmentado: etiqueta a la izquierda y píldora de opciones a la derecha,
// en la misma línea, igual que una fila de interruptor, para que una página no
// parezca dos formularios distintos según el control.
//
// La píldora se ciñe a sus opciones. Ocupando todo el ancho de la tarjeta, en una
// ventana ancha tres opciones cortas se convierten en tres pancartas con la palabra
// perdida en medio: hacerlas enormes no las hace más legibles, solo más difíciles
// de apuntar, porque el ancho útil de un botón es el que separa su centro del
// siguiente y estirarlos aleja todos los destinos entre sí.
// El filtro del buscador y la marca de fila vienen de la base (ver
// Components/SettingsRow.qml).
SettingsRow {
    id: seg
    property string label: ""
    // Glifo de la insignia que abre la fila (ver Components/RowBadge.qml).
    property string glyph: ""
    property var options: []
    property var current
    signal picked(var v)

    filterText: seg.label

    readonly property int optCount: options ? options.length : 0

    // Cuando la fila se estrecha hasta que la etiqueta y la píldora ya no conviven,
    // la píldora baja a su propio renglón y ocupa todo el ancho.
    //
    // La decisión se toma con el ancho de esta fila y no con el de la ventana: la
    // misma fila puede vivir en una tarjeta ancha o en una columna estrecha, y lo
    // que decide si cabe es el sitio que tiene delante.
    //
    // Se mide de verdad —implicitWidth de la etiqueta, ancho natural de la
    // píldora— en vez de con un umbral inventado, así que el salto ocurre
    // exactamente cuando deja de caber.
    readonly property real inlineNeed: Theme.dp(28) + Theme.space10
        + lbl.implicitWidth + Theme.space10 + seg.naturalWidth
    readonly property bool stacked:
        seg.label !== "" && seg.width > 0 && seg.width < seg.inlineNeed + Theme.space8

    // Apilada, el alto es la cabecera completa —insignia incluida— más la píldora:
    // contando solo el alto de la etiqueta, la insignia se come la diferencia y la
    // píldora acaba dibujada encima de la fila siguiente.
    implicitHeight: stacked
        ? row.implicitHeight + Theme.space6 + Theme.rowS
        : Math.max(row.implicitHeight, Theme.dp(46))

    // Ancho natural de la píldora. La interfaz va en monoespaciada, así que el
    // número de caracteres de la opción más larga da su ancho exacto sin
    readonly property int maxChars: {
        let m = 1
        for (let i = 0; i < optCount; i++)
            m = Math.max(m, String(options[i].text).length)
        return m
    }
    TextMetrics {
        id: segTm
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        font.bold: true
        text: "M".repeat(Math.max(1, seg.maxChars))
    }
    readonly property real naturalWidth: optCount > 0
        ? optCount * (segTm.advanceWidth + Theme.space16) + (optCount + 1) * Theme.space4
        : 0

    // Apilada, la píldora baja a su renglón y la cabecera se queda arriba.
    //
    // La posición vertical va por 'y' y no por anclas condicionales: un ancla
    // enlazada a undefined para soltarla no siempre se suelta, y una fila que pasó
    // por apilada durante el primer pase de disposición se queda con la píldora
    // colgada del borde inferior de la cabecera, pintada encima de la fila
    // siguiente. Un 'y' es un vínculo normal: se reevalúa siempre, sin estado que
    // soltar.
    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        y: seg.stacked ? 0 : Math.round((seg.height - height) / 2)
        // Sin apilar, la cabecera se detiene antes de la píldora; apilada,
        // llega hasta el borde porque la píldora ya no comparte renglón.
        anchors.rightMargin: seg.stacked ? 0 : segBox.width + Theme.space10
        spacing: Theme.space10

        // Neutra siempre: elegir un valor no es "encender" nada.
        RowBadge {
            Layout.alignment: Qt.AlignVCenter
            glyph: seg.glyph
            offColor: SettingsPalette.settingsControl
            offBorderColor: SettingsPalette.settingsBorder
        }

        Text {
            id: lbl
            visible: seg.label !== ""
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: seg.label; color: Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
        }

    }

    // La píldora vive FUERA de la fila de cabecera y se coloca por anclas: es
    // lo que le permite estar a la derecha en una línea o debajo a lo ancho
    // sin necesitar dos árboles distintos.
    Rectangle {
        id: segBox
        // Por coordenadas, no por anclas condicionales (ver la nota de 'row').
        // Apilada arranca en el eje de texto y baja bajo la cabecera; en línea
        // se pega a la derecha, centrada en el alto de la fila.
        x: seg.stacked ? Theme.dp(28) + Theme.space10 : seg.width - width
        y: seg.stacked ? row.y + row.height + Theme.space6
                       : Math.round((seg.height - height) / 2)
        // Apilada arranca en el eje de texto de las filas, tras la insignia, y llega
        // al borde; en línea se ciñe exactamente a sus opciones.
        //
        // Sin techo de ancho a propósito: quien decide si la píldora cabe al lado de
        // la etiqueta es 'stacked', y su cuenta ya incluye el ancho natural, así que
        // si no cabe la fila se apila y la píldora se lleva su propio renglón. Un
        // techo sería el único camino por el que podría acabar más estrecha que su
        // contenido, con la fila aún sin medir y las opciones amontonadas.
        width: seg.stacked
            ? Math.max(0, seg.width - (Theme.dp(28) + Theme.space10))
            : (seg.label === "" ? seg.width : seg.naturalWidth)
        height: Theme.rowS
        radius: Theme.pillRadius
        color: SettingsPalette.settingsControl
        border.width: Theme.hairline
        border.color: SettingsPalette.settingsBorder

        readonly property int count: seg.optCount
        readonly property int selIndex: {
            for (let i = 0; i < count; i++)
                if (seg.options[i].value === seg.current) return i
            return 0
        }
        readonly property real innerW: width - Theme.space4 * 2
        readonly property real segW: count > 0 ? (innerW - (count - 1) * Theme.space4) / count : 0

        // Píldora deslizante única: se mueve a la opción activa con la
        // animación global (Theme.animFast).
        Rectangle {
            id: indicator
            visible: segBox.count > 0
            y: Theme.space4
            height: parent.height - Theme.space4 * 2
            width: segBox.segW
            x: Theme.space4 + segBox.selIndex * (segBox.segW + Theme.space4)
            radius: Theme.pillRadius - Theme.space2
            // Mismo tinte de acento que la píldora de la nav: "lo elegido" se
            // dice igual en toda la ventana. En gris, la píldora contradecía
            // al texto seleccionado, que ya iba de acento.
            color: SettingsPalette.selectedTint
            Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
            Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.space4
            spacing: Theme.space4
            Repeater {
                model: seg.options
                delegate: Item {
                    id: segItem
                    required property var modelData
                    required property int index
                    readonly property bool sel: modelData.value === seg.current
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Capa de estado (M3) de las opciones NO elegidas. Faltaba:
                    // la única señal de que un segmento era pulsable era el
                    // cursor, y la píldora solo se entera al SOLTAR — hasta
                    // entonces el control parecía muerto. Va la primera para
                    // que el separador y el texto queden por encima.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -Theme.space2
                        radius: Theme.pillRadius - Theme.space2
                        color: Theme.fg
                        opacity: segItem.sel ? 0
                               : segMa.pressed ? Theme.statePressed
                               : segMa.containsMouse ? Theme.stateHover : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                    }

                    // Separador entre segmentos, como en el botón segmentado de
                    // Material 3: es lo que hace que la píldora se lea como UN
                    // control dividido y no como varios botones sueltos pegados.
                    // Desaparece a los lados del elegido, donde la píldora ya
                    // marca el corte y una raya más solo ensuciaría.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: -Theme.space2
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.hairline
                        height: Math.round(parent.height * 0.52)
                        color: Theme.withAlpha(Theme.fg, 0.22)
                        opacity: (segItem.index >= segBox.count - 1
                                  || segItem.index === segBox.selIndex
                                  || segItem.index + 1 === segBox.selIndex) ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                    }

                    Text {
                        anchors.centerIn: parent
                        // Acotado al ancho del segmento: con muchas opciones o
                        // el panel estrecho, elide en vez de solaparse.
                        // Nunca negativo: con un ancho negativo el elide no
                        // recorta nada y el texto se desborda por los dos
                        // lados — que es lo que convertía el apiñamiento en
                        // letras superpuestas en vez de en tres huecos vacíos.
                        width: Math.max(0, Math.min(implicitWidth, parent.width - Theme.space4))
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: modelData.text
                        color: parent.sel ? Theme.accentText : Theme.fgMuted
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                        font.bold: parent.sel
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }
                    MouseArea {
                        id: segMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(modelData.value)
                    }
                }
            }
        }
        }
    }
