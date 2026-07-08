import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config

// Fondos
ColumnLayout {
    spacing: Theme.space14

    SegRow {
        label: I18n.tr("Transition")
        options: [ { text: "Fade", value: "fade" }, { text: "Zoom", value: "zoom" },
                   { text: "Slide", value: "slide" }, { text: "Push", value: "push" },
                   { text: "Wipe", value: "wipe" } ]
        current: Settings.wallpaperTransition
        onPicked: (v) => Settings.wallpaperTransition = v
    }
    SliderRow {
        label: I18n.tr("Transition duration"); glyph: "󰓞"
        from: 0.2; to: 3.0; value: Settings.wallpaperTransitionDuration
        valueText: Settings.wallpaperTransitionDuration.toFixed(1) + " s"
        onMoved: (v) => Settings.wallpaperTransitionDuration = Math.round(v * 10) / 10
    }
}
