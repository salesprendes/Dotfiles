import QtQuick
import QtQuick.Layouts
import qs.Config

// Texto de ayuda bajo un control: apagado, a lo ancho, con ajuste de línea.
Text {
    id: hint

    // Filtro de Ajustes: un consejo va pegado al control que explica, así que se
    // le da la MISMA 'skey' que su fila y aparecen/desaparecen juntos. Sin 'skey'
    // no se filtra; 'shown' es la condición propia de la página.
    property string skey: ""
    property string cardTitle: ""
    property bool shown: true
    readonly property bool matches: SettingsFilter.accepts(hint.text + " " + hint.cardTitle, hint.skey)
    visible: hint.shown && hint.matches

    Layout.fillWidth: true
    color: Theme.fgMuted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize - 3
    wrapMode: Text.WordWrap
}
