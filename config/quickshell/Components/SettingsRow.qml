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

    // ── El resaltado, para TODAS las filas ───────────────────────────────────
    // Estaba solo en la fila de interruptor. El resultado era una página donde
    // la mitad de las filas se encienden al pasar por encima y la otra mitad no
    // reacciona: en el panel de IA, donde casi todo son selectores segmentados,
    // deslizadores y desplegables, prácticamente nada respondía. Y no es un
    // adorno — la banda es lo que dice DÓNDE ESTÁS en una lista larga de
    // ajustes; sin ella el puntero se pierde entre filas del mismo alto.
    //
    // Va con HoverHandler y no con MouseArea a propósito: un HoverHandler solo
    // escucha, no captura. Una MouseArea a lo ancho de la fila se tragaría los
    // clics del propio control —arrastrar un deslizador, elegir un segmento—,
    // que es exactamente por lo que estas filas no lo llevaban.
    //
    // La fila de interruptor mantiene el suyo (con onda de pulsación, porque
    // ahí la fila ENTERA es pulsable) y apaga este.
    property bool rowHighlight: srow.isSettingsRow

    RowHighlight {
        visible: srow.rowHighlight
        hovered: srow.rowHighlight && hh.hovered
        bleedX: Theme.space8
        bleedY: Theme.space4
    }
    HoverHandler { id: hh }
}
