import QtQuick
import QtQuick.Layouts
import qs.Config

// Base de toda fila de Ajustes: el bloque del filtro
// (skey/cardTitle/shown/matches/visible) vive aquí una sola vez, y cada fila solo
// declara su 'filterText', el texto por el que el buscador la encuentra.
//
//   isSettingsRow  la marca que usa SettingsCard para dibujar los filetes entre
//                  filas. No es readonly: un consejo hereda el filtro pero la pone
//                  a false, porque cuelga de su fila y no lleva filete propio.
//   skey           clave del ajuste para "solo modificados". Opt-in: sin ella la
//                  fila no se filtra, así que el componente sigue sirviendo fuera
//                  de Ajustes.
//   shown          condición propia de la página. Va aparte de 'visible' para no
//                  pisar el vínculo del filtro.
//   cardTitle      lo inyecta SettingsCard: buscar el título encuentra las filas
//                  de esa tarjeta aunque ninguna etiqueta lo diga.
Item {
    id: srow

    property bool isSettingsRow: true
    property string skey: ""
    property string cardTitle: ""
    property bool shown: true
    // Lo que ve el buscador de esta fila. Cada derivado lo enlaza a sus
    // textos (etiqueta + descripción, etc.).
    property string filterText: ""

    // Palabras por las que esta fila debe encontrarse AUNQUE no aparezcan en su
    // etiqueta ni en su descripción.
    //
    // La gente busca por el nombre que conoce, no por el que pusimos nosotros:
    // quien quiere el color de acento escribe "material you" o "matugen", y
    // quien quiere la isla escribe "notch". Sin esto, un ajuste que existe se
    // comporta como si no existiera — que es el peor fallo de un buscador.
    //
    // Va como lista y no como cadena para que sea evidente que son términos
    // sueltos y no una frase, y lo recoge también SettingsSearchIndex, así que
    // los mismos alias sirven en Spotlight (prefijo "?").
    property var aliases: []

    readonly property bool matches: SettingsFilter.accepts(
        srow.filterText + " " + srow.cardTitle + " "
        + (srow.aliases.length > 0 ? srow.aliases.join(" ") : ""), srow.skey)
    visible: srow.shown && srow.matches

    Layout.fillWidth: true

    // El resaltado va en la base y no solo en la fila de interruptor: la banda es
    // lo que dice dónde estás en una lista larga de ajustes, y con la mitad de las
    // filas reaccionando y la otra mitad no, el puntero se pierde entre filas del
    // mismo alto.
    //
    // Va con HoverHandler y no con MouseArea a propósito: un handler solo escucha,
    // no captura. Una MouseArea a lo ancho de la fila se tragaría los clics del
    // propio control —arrastrar un deslizador, elegir un segmento—.
    //
    // La fila de interruptor mantiene el suyo, con onda de pulsación porque ahí la
    // fila entera es pulsable, y apaga este.
    property bool rowHighlight: srow.isSettingsRow

    RowHighlight {
        visible: srow.rowHighlight
        hovered: srow.rowHighlight && hh.hovered
        bleedX: Theme.space8
        bleedY: Theme.space4
    }
    HoverHandler { id: hh }
}
