import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config

// Fondos. Era la ÚNICA página con las filas sueltas, sin tarjeta: sin fondo,
// sin filetes y con otro ritmo vertical — parecía de otro programa. Ahora
// agrupa como todas: cómo se pinta la imagen y cómo va cambiando sola.
SettingsPage {

    SettingsCard {
        title: I18n.tr("Presentation"); glyph: "󰹁"

        SegRow {
            glyph: "󰹁"
            skey: "wallpaperFillMode"
            label: I18n.tr("Fit to screen")
            options: [ { text: I18n.tr("Crop"), value: "crop" },
                       { text: I18n.tr("Fit"), value: "fit" },
                       { text: I18n.tr("Stretch"), value: "stretch" } ]
            current: Settings.wallpaperFillMode
            onPicked: (v) => Settings.wallpaperFillMode = v
        }
        Hint {
            skey: "wallpaperFillMode"
            text: I18n.tr("Crop fills the screen and trims the excess. Fit shows the whole image with bars. Stretch distorts it.")
        }

        SegRow {
            glyph: "󰵸"
            skey: "wallpaperTransition"
            label: I18n.tr("Transition")
            options: [ { text: "Fade", value: "fade" }, { text: "Zoom", value: "zoom" },
                       { text: "Slide", value: "slide" }, { text: "Push", value: "push" },
                       { text: "Wipe", value: "wipe" } ]
            current: Settings.wallpaperTransition
            onPicked: (v) => Settings.wallpaperTransition = v
        }
        SliderRow {
            skey: "wallpaperTransitionDuration"
            label: I18n.tr("Transition duration"); glyph: "󰓞"
            from: 0.2; to: 3.0; value: Settings.wallpaperTransitionDuration
            valueText: Settings.wallpaperTransitionDuration.toFixed(1) + " s"
            onMoved: (v) => Settings.wallpaperTransitionDuration = Math.round(v * 10) / 10
        }
    }

    // Rotación automática: la ejecuta Services/Wallpaper.qml.
    SettingsCard {
        title: I18n.tr("Rotation"); glyph: "󰑖"

        SegRow {
            glyph: "󰑖"
            skey: "wallpaperAutoMin"
            label: I18n.tr("Auto-change wallpaper")
            options: [ { text: I18n.tr("Off"), value: 0 },  { text: "15 min", value: 15 },
                       { text: "30 min", value: 30 },       { text: "1 h", value: 60 },
                       { text: "3 h", value: 180 },         { text: "24 h", value: 1440 } ]
            current: Settings.wallpaperAutoMin
            onPicked: (v) => Settings.wallpaperAutoMin = v
        }
        SwitchRow {
            glyph: "󰒝"
            skey: "wallpaperRandom"
            label: I18n.tr("Random order")
            desc: I18n.tr("Disabled follows folder order")
            checked: Settings.wallpaperRandom
            onToggled: Settings.wallpaperRandom = !Settings.wallpaperRandom
        }
    }
}
