import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config

// Texto de ayuda bajo un control: apagado, a lo ancho, con ajuste de línea.
//
// Hereda el filtro del buscador de SettingsRow (misma 'skey' que su fila →
// aparecen y desaparecen juntos), pero NO es una fila: isSettingsRow va a
// false para que SettingsCard no le dibuje un filete encima — un consejo
// cuelga de su fila, no la separa de ella.
SettingsRow {
    id: hint

    isSettingsRow: false
    property alias text: body.text
    // Sobreescribible: un aviso de error se pinta en rojo sin cambiar de
    // componente (ver NetworkPage).
    property alias color: body.color

    filterText: body.text

    // Sangrado hasta el eje de texto de las filas (ancho de insignia + hueco):
    // un consejo explica un control, así que cuelga de su misma vertical en
    // vez de arrancar pegado al borde de la tarjeta.
    Layout.leftMargin: Theme.dp(28) + Theme.space10
    implicitHeight: body.implicitHeight

    ThemedText {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        color: Theme.fgMuted
        font.pixelSize: Theme.typeBodySmall
        wrapMode: Text.WordWrap
    }
}
