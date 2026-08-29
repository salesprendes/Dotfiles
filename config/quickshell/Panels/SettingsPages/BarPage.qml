import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Services
import qs.Panels.SettingsPages

// Barra
SettingsPage {

    // Disposición de la barra. Antes esto era una lista de ocho interruptores
    // —uno por widget— que solo sabían encender y apagar: el ORDEN estaba
    // cableado en el QML de la barra, así que "quiero la batería antes que el
    // reloj" no tenía respuesta. Ahora es un editor: se arrastra.
    SettingsCard {
        title: I18n.tr("Bar widgets"); glyph: "󰕬"
        description: I18n.tr("What the bar shows, on which side and in what order.")

        BarLayoutEditor {}
    }

    // El clima es un widget más: sus ajustes viven aquí, junto al resto de lo
    // que se enseña en la barra, en vez de en "Sistema" — donde estaba por su
    // servicio de red, que es un detalle de implementación, no algo que el
    // usuario tenga en la cabeza cuando busca dónde encender el clima.
    WeatherPage { Layout.fillWidth: true }
}
