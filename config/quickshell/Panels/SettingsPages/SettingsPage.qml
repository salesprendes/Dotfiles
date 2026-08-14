import QtQuick.Layouts
import qs.Config

// Raíz de toda página de Ajustes. Solo fija el ritmo vertical entre tarjetas,
// pero lo fija en UN sitio: cada página traía el suyo (unas space12, otras
// space14, sin criterio detrás) y el aire entre secciones cambiaba según la
// pestaña en la que estuvieras.
ColumnLayout {
    spacing: Theme.space14
}
