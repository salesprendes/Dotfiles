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

            Text {
                Layout.fillWidth: true
                text: slr.label; color: Theme.fg
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8

                Slider {
                    id: sld
                    Layout.fillWidth: true
                    // TOPE DE ANCHO. La columna de Ajustes mide 760 dp, así
                    // que sin esto la pista se estiraba hasta ~700 px con un
                    // agarre de 4: dejaba de leerse como un control y parecía
                    // una regla, con el agarre perdido en medio. Además, a esa
                    // longitud apuntar a un valor concreto exige una precisión
                    // absurda para lo que se gana.
                    //
                    // 400 dp deja unos 4 px por unidad en una escala de 0 a
                    // 100 —de sobra para afinar a mano— y una proporción de
                    // 25:1 en vez de 47:1. Sigue siendo 'fillWidth' para que
                    // en ventana estrecha se encoja con todo lo demás.
                    Layout.maximumWidth: Theme.dp(400)
                    trackColor: slr.trackColor
                    value: (slr.value - slr.from) / (slr.to - slr.from)
                    onMoved: (v) => slr.moved(slr.from + v * (slr.to - slr.from))
                }

                // La lectura va PEGADA a la pista, no al otro extremo de la
                // fila. Aparte de que el número se lee donde está el control
                // que lo mueve, esto quita de en medio el apaño que hacía
                // falta antes: con la etiqueta estirándose hasta el número,
                // cada dígito de más ("9 s" → "10 s") empujaba la etiqueta y
                // la línea entera temblaba mientras arrastrabas. Ahora el que
                // cede es el hueco sobrante del final, que no se ve.
                //
                // Y sin espaciador flexible detrás a propósito: dos elementos
                // con fillWidth se reparten el hueco a partes iguales, así que
                // en ventana estrecha el espaciador le robaría al slider la
                // mitad del ancho. Cuando la pista topa con su máximo, el
                // layout ya deja el sobrante al final sin ayuda.
                ThemedText {
                    // Un respiro a la derecha. En ventana ancha da igual —la
                    // pista topa con su máximo y sobra sitio—, pero en cuanto
                    // se estrecha, la pista se come todo el hueco y el número
                    // acaba EXACTAMENTE en el borde de la fila: dentro, pero
                    // pegado, y con el color de acento se lee como si se
                    // estuviera saliendo de la tarjeta.
                    Layout.rightMargin: Theme.space4
                    text: slr.valueText
                    color: Theme.accentText
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                }
            }
        }
    }
}
