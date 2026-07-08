import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Terminal
ColumnLayout {
    spacing: Theme.space12

    // Las fuentes (fc-list) se cargan al entrar en esta página, no al arrancar.
    Component.onCompleted: Fonts.refresh()

    // Selección de terminal (detectados en el sistema).
    SettingsCard {
        title: I18n.tr("Terminal"); glyph: "󰆍"
        DropdownRow {
            label: I18n.tr("Terminal")
            options: Terminal.available
            current: Settings.terminalApp
            onPicked: (v) => Settings.terminalApp = v
        }
        Hint {
            visible: Terminal.available.length === 0
            text: I18n.tr("No terminals detected.")
        }
        Hint {
            visible: Terminal.available.length > 0 && !Terminal.canConfigure(Settings.terminalApp)
            text: I18n.tr("Auto-config not available for this terminal yet.")
        }
    }

    // Apariencia (los COLORES siguen el tema de Quickshell; aquí
    // solo el resto de parámetros).
    SettingsCard {
        title: I18n.tr("Appearance"); glyph: "󰉼"
        visible: Terminal.canConfigure(Settings.terminalApp)

        DropdownRow {
            label: I18n.tr("Font")
            options: Fonts.monoList.map(f => ({ text: f, value: f, font: f }))
            current: Settings.terminalFont !== "" ? Settings.terminalFont : Settings.fontFamily
            detailText: I18n.tr("%1 fonts").arg(Fonts.monoList.length)
            maxVisibleItems: 6
            onPicked: (font) => Settings.terminalFont = font
        }
        SliderRow {
            label: I18n.tr("Font size"); glyph: "󰛖"
            from: 8; to: 18; value: Settings.terminalFontSize
            valueText: Settings.terminalFontSize.toFixed(1)
            onMoved: (v) => Settings.terminalFontSize = Math.round(v * 2) / 2
        }
        SliderRow {
            label: I18n.tr("Opacity")
            from: 0.5; to: 1.0; value: Settings.terminalOpacity
            valueText: Math.round(Settings.terminalOpacity * 100) + "%"
            onMoved: (v) => Settings.terminalOpacity = Math.round(v * 20) / 20
        }
        SliderRow {
            label: I18n.tr("Padding")
            from: 0; to: 30; value: Settings.terminalPadding
            valueText: Settings.terminalPadding + " px"
            onMoved: (v) => Settings.terminalPadding = Math.round(v)
        }
        SliderRow {
            label: I18n.tr("Line spacing")
            from: 0; to: 6; value: Settings.terminalLineHeight
            valueText: Settings.terminalLineHeight + " px"
            onMoved: (v) => Settings.terminalLineHeight = Math.round(v)
        }
        SegRow {
            label: I18n.tr("Cursor")
            options: [ { text: I18n.tr("Beam"), value: "beam" },
                       { text: I18n.tr("Block"), value: "block" },
                       { text: I18n.tr("Underline"), value: "underline" } ]
            current: Settings.terminalCursorShape
            onPicked: (v) => Settings.terminalCursorShape = v
        }
        SwitchRow {
            label: I18n.tr("Cursor blink")
            checked: Settings.terminalCursorBlink
            onToggled: Settings.terminalCursorBlink = !Settings.terminalCursorBlink
        }
        SwitchRow {
            label: I18n.tr("Ligatures")
            checked: Settings.terminalLigatures
            onToggled: Settings.terminalLigatures = !Settings.terminalLigatures
        }
        SegRow {
            visible: Settings.terminalApp === "kitty"
            label: I18n.tr("Tabs")
            options: [ { text: "Powerline", value: "powerline" }, { text: "Separator", value: "separator" },
                       { text: "Fade", value: "fade" }, { text: I18n.tr("Hidden"), value: "hidden" } ]
            current: Settings.terminalTabStyle
            onPicked: (v) => Settings.terminalTabStyle = v
        }
    }
}
