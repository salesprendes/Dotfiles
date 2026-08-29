import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Píldora de clima: icono según el estado del cielo + temperatura actual.
// Click abre el Dashboard, donde vive la tarjeta completa con el pronóstico.
//
// Vivía escrita a mano dentro de Bar.qml como componente en línea. Con la
// barra configurable ya no puede: el catálogo mapea un id a un componente y
// necesita un archivo.
Pill {
    id: root

    shown: Weather.enabled && Weather.ready
    interactive: true
    active: Globals.dashboardOpen
    onClicked: Globals.toggleDashboard()

    BarGlyph { text: Weather.icon; color: Theme.yellow }
    BarLabel { text: Weather.temp; font.bold: true }
}
