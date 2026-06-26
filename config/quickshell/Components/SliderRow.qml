import QtQuick
import QtQuick.Layouts
import qs.Config

// Fila de slider con etiqueta + valor (estilo Ajustes). Mapea un rango
// [from, to] sobre la base reutilizable `Slider` (0..1). Antes era inline en
// Settings.qml; extraído a Components para reutilizarlo y reducir código.
//
// Uso:
//   SliderRow {
//       label: "..."; glyph: "..."; valueText: "..."
//       from: 0.8; to: 1.3; value: Settings.uiScale
//       onMoved: (v) => Settings.uiScale = v
//   }
ColumnLayout {
    id: slr
    property string label: ""
    property string glyph: ""
    property string valueText: ""
    property real from: 0
    property real to: 1
    property real value: 0
    // Color de la pista (por defecto = el antiguo cfg.settingsControl).
    property color trackColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.86)
    signal moved(real v)

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
