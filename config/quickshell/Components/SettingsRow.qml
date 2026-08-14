import QtQuick
import QtQuick.Layouts
import qs.Config

// Base de toda fila de Ajustes. Existe por una razón: el bloque del filtro
// (skey/cardTitle/shown/matches/visible) estaba copiado LETRA POR LETRA en
// seis componentes, y seis copias de una regla es la garantía de que algún
// día divergen. Aquí vive una sola vez; cada fila solo declara su
// 'filterText' — el texto por el que el buscador la encuentra.
//
//   isSettingsRow  la marca que usa SettingsCard para dibujar los filetes
//                  entre filas. NO es readonly: un consejo (Hint) hereda el
//                  filtro pero pone esto a false, porque cuelga de su fila y
//                  no debe llevar filete propio.
//   skey           clave del ajuste para "solo modificados". OPT-IN: sin ella
//                  la fila no se filtra nunca, así el mismo componente sigue
//                  sirviendo fuera de Ajustes.
//   shown          condición propia de la página (p. ej. "solo con batería").
//                  Va aparte de 'visible' para no pisar el vínculo del filtro.
//   cardTitle      lo inyecta SettingsCard: buscar "terminal" encuentra las
//                  filas de esa tarjeta aunque ninguna etiqueta lo diga.
Item {
    id: srow

    property bool isSettingsRow: true
    property string skey: ""
    property string cardTitle: ""
    property bool shown: true
    // Lo que ve el buscador de esta fila. Cada derivado lo enlaza a sus
    // textos (etiqueta + descripción, etc.).
    property string filterText: ""

    readonly property bool matches: SettingsFilter.accepts(
        srow.filterText + " " + srow.cardTitle, srow.skey)
    visible: srow.shown && srow.matches

    Layout.fillWidth: true
}
