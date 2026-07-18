import QtQuick
import QtQuick.Layouts
import qs.Config

// Fila de slider con etiqueta + valor. Mapea un rango [from, to] sobre Slider (0..1).
ColumnLayout {
    id: slr
    property string label: ""
    property string glyph: ""
    property string valueText: ""
    property real from: 0
    property real to: 1
    property real value: 0
    // Color de la pista.
    property color trackColor: Theme.sliderTrack
    signal moved(real v)

    // Filtro de la ventana de Ajustes (buscador + "solo modificados").
    // OPT-IN: sin 'skey' la fila no se filtra nunca, así el mismo componente
    // sigue funcionando fuera de Ajustes. 'shown' es la condición propia de la
    // página (p. ej. "solo si hay batería"), que se combina con el filtro.
    property string skey: ""
    property string cardTitle: ""
    property bool shown: true
    readonly property bool matches: SettingsFilter.accepts(
        slr.label + " " + slr.cardTitle, slr.skey)
    visible: slr.shown && slr.matches

    Layout.fillWidth: true
    spacing: Theme.space6

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: slr.label; color: Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
        }
        Text {
            text: slr.valueText; color: Theme.accent
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1; font.bold: true
        }
    }
    Slider {
        Layout.fillWidth: true
        icon: slr.glyph
        trackColor: slr.trackColor
        value: (slr.value - slr.from) / (slr.to - slr.from)
        onMoved: (v) => slr.moved(slr.from + v * (slr.to - slr.from))
    }
}
