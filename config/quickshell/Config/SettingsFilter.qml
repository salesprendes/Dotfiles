pragma Singleton

import QtQuick
import Quickshell
import qs.Config

// Filtro de la ventana de Ajustes (buscador + "solo modificados"). Vive en
// Config —y no en SettingsPages— porque las filas que filtra
// (SliderRow, DropdownRow) están en Components, que ya depende de Config.
//
// El filtro es OPT-IN: solo actúa sobre las filas que declaran 'skey'. Las
// mismas filas usadas fuera de Ajustes (la barra de captura, p. ej.) no lo
// declaran y por tanto nunca se ocultan al escribir en el buscador.
//
// Valor de 'skey':
//   "algo"   → clave de Settings; cuenta para "solo modificados".
//   "@algo"  → la fila se busca, pero no persiste nada (p. ej. No molestar,
//              que vive en Globals): nunca cuenta como "modificada".
//   ""       → la fila no participa en el filtro.
Singleton {
    id: f

    property string query: ""
    property bool modifiedOnly: false

    readonly property string _q: query.trim().toLowerCase()
    readonly property bool searching: _q !== ""
    readonly property bool active: searching || modifiedOnly

    function clear() {
        query = ""
        modifiedOnly = false
    }

    function isPersisted(skey) {
        return skey !== "" && skey.charAt(0) !== "@"
    }

    // ¿Se ve esta fila? 'text' es lo que se busca (etiqueta + descripción +
    // título de su tarjeta).
    function accepts(text, skey) {
        if (!skey || skey === "")   // no participa: siempre visible
            return true
        if (!active)
            return true
        if (modifiedOnly && !(isPersisted(skey) && Settings.isModified(skey)))
            return false
        if (searching && String(text || "").toLowerCase().indexOf(_q) === -1)
            return false
        return true
    }

    // Para tarjetas sin filas filtrables (Monitores, Acerca de…): se juzgan por
    // su propio título. Con "solo modificados" desaparecen, que es lo correcto:
    // no tienen nada persistido que pueda estar modificado.
    function acceptsCard(title) {
        if (!active)
            return true
        if (modifiedOnly)
            return false
        return String(title || "").toLowerCase().indexOf(_q) !== -1
    }
}
