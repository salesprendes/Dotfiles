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

    // ── La isla ─────────────────────────────────────────────────────────────
    SettingsCard {
        title: I18n.tr("Dynamic island")
        glyph: "󰋙"
        description: I18n.tr("Replaces the centre of the bar with a pill that reacts to what happens: notifications, volume, music.")

        SwitchRow { glyph: "󰋙"; skey: "islandEnabled"; aliases: ["notch", "dynamic island", "isla"]; label: I18n.tr("Dynamic island")
            checked: Settings.islandEnabled
            onToggled: Settings.islandEnabled = !Settings.islandEnabled }
        SwitchRow { glyph: "󰖐"; skey: "islandShowWeather"; label: I18n.tr("Weather in the island")
            shown: Settings.islandEnabled
            checked: Settings.islandShowWeather
            onToggled: Settings.islandShowWeather = !Settings.islandShowWeather }
        // Sin 'shown': esto también manda sobre los avisos clásicos, que son
        // los que salen con la isla apagada.
        SwitchRow { glyph: "󰊓"; skey: "hideOnFullscreen"
            aliases: ["pantalla completa", "fullscreen", "video", "vídeo", "cine", "netflix", "youtube"]
            label: I18n.tr("Step aside in fullscreen")
            desc: I18n.tr("Also the notification popups when the island is off. The volume OSD and the recording pill always stay.")
            checked: Settings.hideOnFullscreen
            onToggled: Settings.hideOnFullscreen = !Settings.hideOnFullscreen }
        Hint {
            skey: "islandEnabled"
            shown: Settings.islandEnabled
            text: I18n.tr("With the island on it also takes over the volume OSD, the notification popups and the notification centre: the bell in the bar opens the island instead of the classic panel. Turning it off puts back the bar centre, the classic OSD, the classic popups and the classic centre, exactly as they were.")
        }
    }

    // El clima es un widget más: sus ajustes viven aquí, junto al resto de lo
    // que se enseña en la barra, en vez de en "Sistema" — donde estaba por su
    // servicio de red, que es un detalle de implementación, no algo que el
    // usuario tenga en la cabeza cuando busca dónde encender el clima.
    WeatherPage { Layout.fillWidth: true }
}
