import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config

// Fondos
ColumnLayout {
    spacing: Theme.space14

    SegRow {
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

    // Rotación automática: la ejecuta Services/Wallpaper.qml.
    SegRow {
        skey: "wallpaperAutoMin"
        label: I18n.tr("Auto-change wallpaper")
        options: [ { text: I18n.tr("Off"), value: 0 },  { text: "15 min", value: 15 },
                   { text: "30 min", value: 30 },       { text: "1 h", value: 60 },
                   { text: "3 h", value: 180 },         { text: "24 h", value: 1440 } ]
        current: Settings.wallpaperAutoMin
        onPicked: (v) => Settings.wallpaperAutoMin = v
    }
    SwitchRow {
        skey: "wallpaperRandom"
        label: I18n.tr("Random order")
        desc: I18n.tr("Disabled follows folder order")
        checked: Settings.wallpaperRandom
        onToggled: Settings.wallpaperRandom = !Settings.wallpaperRandom
    }
}
