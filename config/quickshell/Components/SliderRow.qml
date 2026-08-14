import QtQuick
import QtQuick.Layouts
import qs.Config

// Fila de slider con etiqueta + valor. Mapea un rango [from, to] sobre Slider
// (0..1). El filtro del buscador y la marca de fila vienen de la base (ver
// SettingsRow.qml).
SettingsRow {
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

    filterText: slr.label

    implicitHeight: row.implicitHeight

    // El glifo va en la insignia de cabecera, no pegado a la pista: así esta
    // fila arranca en la misma vertical que las de interruptor y desplegable,
    // y la pista se alinea con el resto de controles en vez de quedar
    // desplazada por su propio icono.
    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space10

        RowBadge {
            Layout.alignment: Qt.AlignTop
            glyph: slr.glyph
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space6

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8

                Text {
                    Layout.fillWidth: true
                    text: slr.label; color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }
                Text {
                    id: readout

                    // Hueco reservado que solo crece MIENTRAS arrastras.
                    //
                    // El problema: la etiqueta se estira para rellenar la
                    // línea, así que el ancho del número decide dónde acaba
                    // ella. Al mover el slider, "9 s" pasa a "10 s" y "100%"
                    // a "115%", y cada dígito de más empujaba la etiqueta un
                    // paso a la izquierda: la línea entera temblaba justo
                    // mientras intentabas afinar el valor.
                    //
                    // Reservando el máximo visto durante el arrastre, el
                    // número se asienta en su sitio y ya no mueve nada. Al
                    // soltar se libera, para que un texto largo de un ajuste
                    // ("Hasta descartarla") no deje un hueco permanente en
                    // los demás.
                    property real reserved: 0
                    onImplicitWidthChanged: if (sld.dragging)
                        reserved = Math.max(reserved, implicitWidth)

                    Layout.preferredWidth: Math.max(implicitWidth, reserved)
                    horizontalAlignment: Text.AlignRight

                    text: slr.valueText
                    color: Theme.accentText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                }
            }
            Slider {
                id: sld
                Layout.fillWidth: true
                trackColor: slr.trackColor
                value: (slr.value - slr.from) / (slr.to - slr.from)
                onMoved: (v) => slr.moved(slr.from + v * (slr.to - slr.from))
                onDraggingChanged: if (!dragging) readout.reserved = 0
            }
        }
    }
}
