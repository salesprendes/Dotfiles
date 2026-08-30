import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Ajustes del dock: qué forma tiene, cuándo se ve, cómo se ve y qué lleva
// fijado.
SettingsPage {

    SettingsCard {
        title: I18n.tr("General"); glyph: "󰕰"

        SwitchRow {
            glyph: "󰕰"
            skey: "dockEnabled"
            label: I18n.tr("Dock")
            desc: I18n.tr("A bar of app icons at the bottom edge")
            checked: Settings.dockEnabled
            onToggled: Settings.dockEnabled = !Settings.dockEnabled
        }

        SegRow {
            glyph: "󰧨"
            skey: "dockStyle"
            label: I18n.tr("Dock style")
            aliases: ["pastilla", "hotseat", "pill", "android", "pixel"]
            shown: Settings.dockEnabled
            options: [ { text: I18n.tr("Pill"), value: "pill" },
                       { text: I18n.tr("Hotseat"), value: "hotseat" } ]
            current: Settings.dockStyle
            onPicked: (v) => Settings.dockStyle = v
        }

        // Con un solo monitor la fila no dice nada: la lista tendría una sola
        // casilla y apagarla dejaría el dock en ninguna parte.
        DockMonitorPicker {
            skey: "dockOnlyMonitors"
            shown: Settings.dockEnabled && Quickshell.screens.length > 1
        }
    }

    SettingsCard {
        title: I18n.tr("Behaviour"); glyph: "󰈈"
        shown: Settings.dockEnabled

        SegRow {
            glyph: "󰘖"
            skey: "dockAutoHide"
            label: I18n.tr("Auto-hide")
            aliases: ["autoocultar", "esconder", "smart"]
            options: [ { text: I18n.tr("Smart"), value: "smart" },
                       { text: I18n.tr("Always"), value: "always" },
                       { text: I18n.tr("Never"), value: "never" } ]
            current: Settings.dockAutoHide
            onPicked: (v) => Settings.dockAutoHide = v
        }
        Hint {
            skey: "dockAutoHide"
            shown: Settings.dockAutoHide === "smart"
            text: I18n.tr("Smart shows the dock while the workspace of that monitor is empty, and hides it as soon as a window opens. Touching the bottom edge always brings it back.")
        }

        // Se ATENÚA en vez de esconderse cuando no aplica: esconder una fila
        // hace que el usuario la busque por toda la página; atenuarla explica
        // por qué está ahí y por qué no hace nada.
        SwitchRow {
            glyph: "󰯌"
            skey: "dockReserveSpace"
            label: I18n.tr("Reserve space")
            desc: Settings.dockAutoHide === "never"
                  ? I18n.tr("Windows never cover the dock")
                  : I18n.tr("Only applies with auto-hide set to Never")
            enabled: Settings.dockAutoHide === "never"
            opacity: enabled ? 1 : 0.45
            checked: Settings.dockReserveSpace
            onToggled: Settings.dockReserveSpace = !Settings.dockReserveSpace
        }

        SwitchRow {
            glyph: "󰖯"
            skey: "dockShowRunning"
            label: I18n.tr("Show running apps")
            desc: I18n.tr("Apps you have open that are not pinned, behind a separator")
            checked: Settings.dockShowRunning
            onToggled: Settings.dockShowRunning = !Settings.dockShowRunning
        }

        SegRow {
            glyph: "󰇘"
            skey: "dockRunningIndicator"
            label: I18n.tr("Window indicator")
            options: [ { text: I18n.tr("Automatic"), value: "auto" },
                       { text: I18n.tr("Line"), value: "line" },
                       { text: I18n.tr("Dots"), value: "dots" },
                       { text: I18n.tr("Count"), value: "count" },
                       { text: I18n.tr("None"), value: "none" } ]
            current: Settings.dockRunningIndicator
            onPicked: (v) => Settings.dockRunningIndicator = v
        }
        Hint {
            skey: "dockRunningIndicator"
            shown: Settings.dockRunningIndicator === "auto"
            text: I18n.tr("Automatic draws a line when the app has one window and dots when it has several.")
        }

        SwitchRow {
            glyph: "󰕰"
            skey: "dockShowLauncher"
            label: I18n.tr("Launcher button")
            desc: I18n.tr("A grid button at the end of the row")
            checked: Settings.dockShowLauncher
            onToggled: Settings.dockShowLauncher = !Settings.dockShowLauncher
        }

        SwitchRow {
            glyph: "󰍉"
            skey: "dockShowSpotlight"
            label: I18n.tr("Spotlight button")
            desc: I18n.tr("A search button at the end of the row")
            checked: Settings.dockShowSpotlight
            onToggled: Settings.dockShowSpotlight = !Settings.dockShowSpotlight
        }

        SwitchRow {
            glyph: "󰂚"
            skey: "dockNotifBadges"
            label: I18n.tr("Notification badges")
            desc: I18n.tr("Pending notification count over the icon, when the app can be matched")
            checked: Settings.dockNotifBadges
            onToggled: Settings.dockNotifBadges = !Settings.dockNotifBadges
        }

        SwitchRow {
            glyph: "󰘔"
            skey: "dockPreviews"
            label: I18n.tr("Window previews")
            desc: I18n.tr("Hovering an icon lists its open windows")
            checked: Settings.dockPreviews
            onToggled: Settings.dockPreviews = !Settings.dockPreviews
        }
    }

    SettingsCard {
        title: I18n.tr("Appearance"); glyph: "󰏘"
        shown: Settings.dockEnabled

        SegRow {
            glyph: "󰸱"
            skey: "dockIconStyle"
            label: I18n.tr("Icon look")
            aliases: ["monocromo", "mono", "nandoroid", "color"]
            options: [ { text: I18n.tr("Monochrome"), value: "mono" },
                       { text: I18n.tr("Colour"), value: "color" } ]
            current: Settings.dockIconStyle
            onPicked: (v) => Settings.dockIconStyle = v
        }
        Hint {
            skey: "dockIconStyle"
            shown: Settings.dockIconStyle === "mono"
            text: I18n.tr("Each icon goes inside an accent circle, tinted to match. Tidy with a few apps; with a dozen you have to tell them apart by their silhouette.")
        }

        SwitchRow {
            glyph: "󰔎"
            skey: "dockShadow"
            label: I18n.tr("Shadow")
            desc: I18n.tr("Lifts the dock off the wallpaper")
            checked: Settings.dockShadow
            onToggled: Settings.dockShadow = !Settings.dockShadow
        }

        SliderRow {
            skey: "dockIconSize"
            label: I18n.tr("Icon size"); glyph: "󰀻"
            from: 24; to: 96; value: Settings.dockIconSize
            valueText: Settings.dockIconSize + " dp"
            onMoved: (v) => Settings.dockIconSize = Math.round(v)
        }
        SliderRow {
            skey: "dockSpacing"
            label: I18n.tr("Spacing"); glyph: "󰧟"
            from: 0; to: 32; value: Settings.dockSpacing
            valueText: Settings.dockSpacing + " dp"
            onMoved: (v) => Settings.dockSpacing = Math.round(v)
        }
        SliderRow {
            skey: "dockPadding"
            label: I18n.tr("Padding"); glyph: "󰡍"
            from: 0; to: 32; value: Settings.dockPadding
            valueText: Settings.dockPadding + " dp"
            onMoved: (v) => Settings.dockPadding = Math.round(v)
        }
        SliderRow {
            skey: "dockOpacity"
            label: I18n.tr("Opacity"); glyph: "󰂕"
            from: 0.0; to: 1.0; value: Settings.dockOpacity
            valueText: Math.round(Settings.dockOpacity * 100) + " %"
            onMoved: (v) => Settings.dockOpacity = v
        }
        // -1 significa "lo decide el estilo": pastilla entera en pill, esquinas
        // de arriba en hotseat. El texto lo dice, para que el extremo izquierdo
        // del deslizador no parezca "sin redondear".
        SliderRow {
            skey: "dockRadius"
            label: I18n.tr("Corner radius"); glyph: "󰄽"
            from: -1; to: 40; value: Settings.dockRadius
            valueText: Settings.dockRadius < 0 ? I18n.tr("Automatic")
                                               : Settings.dockRadius + " dp"
            onMoved: (v) => Settings.dockRadius = Math.round(v)
        }
        SliderRow {
            skey: "dockMagnify"
            label: I18n.tr("Magnification"); glyph: "󰍉"
            from: 1.0; to: 1.6; value: Settings.dockMagnify
            valueText: Settings.dockMagnify <= 1.001
                       ? I18n.tr("None")
                       : "×" + Settings.dockMagnify.toFixed(2)
            onMoved: (v) => Settings.dockMagnify = v
        }
    }

    SettingsCard {
        title: I18n.tr("Pinned apps"); glyph: "󰐃"
        shown: Settings.dockEnabled

        DockPinEditor {}
    }
}
