import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services
import qs.Panels.SettingsPages

// Tipografía
ColumnLayout {
    spacing: Theme.space12

    // Las fuentes (fc-list) se cargan al entrar en esta página, no al arrancar.
    Component.onCompleted: Fonts.refresh()

    SettingsCard {
        title: I18n.tr("Animations and motion"); glyph: "󰓞"

        SegRow {
            label: I18n.tr("Animation Style")
            options: [
                { text: "Material", value: "material" },
                { text: "Fluent", value: "fluent" },
                { text: "Dynamic", value: "dynamic" }
            ]
            current: Settings.panelAnimationStyle
            onPicked: (v) => Settings.panelAnimationStyle = v
        }

        Hint {
            text: {
                if (Settings.panelAnimationStyle === "fluent")
                    return I18n.tr("Fluent: clean entrance with smooth deceleration and quick close.")
                if (Settings.panelAnimationStyle === "dynamic")
                    return I18n.tr("Dynamic: elastic entrance with visible bounce and quick close.")
                return I18n.tr("Material: expressive entrance with soft scale and short displacement.")
            }
        }

        SegRow {
            label: I18n.tr("Animation Speed")
            options: [
                { text: I18n.tr("None"), value: 0 },
                { text: I18n.tr("Short"), value: 1 },
                { text: I18n.tr("Medium"), value: 2 },
                { text: I18n.tr("Long"), value: 3 },
                { text: I18n.tr("Custom"), value: 4 }
            ]
            current: Settings.animationSpeed
            onPicked: (v) => Settings.animationSpeed = v
        }

        Hint {
            text: {
                if (Settings.animationSpeed === 0)
                    return I18n.tr("None: panels change instantly, with no transition.")
                if (Settings.animationSpeed === 1)
                    return I18n.tr("Short: fast rhythm, with light opening and agile closing.")
                if (Settings.animationSpeed === 3)
                    return I18n.tr("Long: slower rhythm, with a more visible effect.")
                if (Settings.animationSpeed === 4)
                    return I18n.tr("Custom: custom duration applied at 500 ms.")
                return I18n.tr("Medium: balanced speed for panels and controls.")
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.hairline
            color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.32)
        }

        SegRow {
            label: I18n.tr("Panel motion")
            options: [
                { text: I18n.tr("Standard"), value: "standard" },
                { text: I18n.tr("Directional"), value: "directional" },
                { text: I18n.tr("Depth"), value: "depth" }
            ]
            current: Settings.panelMotionEffect
            onPicked: (v) => Settings.panelMotionEffect = v
        }

        Hint {
            text: {
                if (Settings.panelMotionEffect === "directional")
                    return I18n.tr("Directional: wide full-size slide, without scaling.")
                if (Settings.panelMotionEffect === "depth")
                    return I18n.tr("Depth: deep scale and medium displacement with approach effect.")
                return I18n.tr("Standard: short displacement with subtle scale and Material feel.")
            }
        }
    }

    SettingsCard {
        title: I18n.tr("Typography"); glyph: "󰛖"

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.tileL
            radius: Theme.pillRadius
            color: SettingsPalette.settingsControl
            border.width: Theme.hairline
            border.color: SettingsPalette.settingsBorder

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.space2
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "AaBbCc 0123  󰋩 󰒓 󰂚"
                    color: Theme.fg
                    font.family: Settings.fontFamily
                    font.pixelSize: Theme.fontSize + 8
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "mono: /proc/cpuinfo  0x7aa2f7"
                    color: Theme.fgMuted
                    font.family: Settings.monoFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }

        DropdownRow {
            label: I18n.tr("Normal Font")
            options: Fonts.list.map(f => ({ text: f, value: f, font: f }))
            current: Settings.fontFamily
            detailText: I18n.tr("%1 fonts").arg(Fonts.list.length)
            maxVisibleItems: 6
            onPicked: (font) => Settings.fontFamily = font
        }

        DropdownRow {
            label: I18n.tr("Monospace Font")
            options: Fonts.monoList.map(f => ({ text: f, value: f, font: f }))
            current: Settings.monoFontFamily
            detailText: I18n.tr("%1 fonts").arg(Fonts.monoList.length)
            maxVisibleItems: 6
            onPicked: (font) => Settings.monoFontFamily = font
        }

        SliderRow {
            label: I18n.tr("Letter scale"); glyph: "󰗊"
            from: 0.8; to: 1.3; value: Settings.fontScale
            valueText: I18n.tr("%1% · effective %2%").arg(Math.round(Settings.fontScale * 100)).arg(Math.round(Theme.scale * Settings.fontScale * 100))
            onMoved: (v) => Settings.fontScale = Math.round(v * 20) / 20
        }
    }

    // Renderizado de fuentes (fontconfig)
    SettingsCard {
        title: I18n.tr("Font rendering"); glyph: "󰚌"

        SwitchRow {
            label: I18n.tr("Antialiasing")
            checked: Settings.fontAntialias
            onToggled: Settings.fontAntialias = !Settings.fontAntialias
        }
        SwitchRow {
            label: I18n.tr("Hinting")
            checked: Settings.fontHinting
            onToggled: Settings.fontHinting = !Settings.fontHinting
        }
        SegRow {
            label: I18n.tr("Hint style")
            options: [
                { text: I18n.tr("None"),   value: "hintnone" },
                { text: I18n.tr("Slight"), value: "hintslight" },
                { text: I18n.tr("Medium"), value: "hintmedium" },
                { text: I18n.tr("Full"),   value: "hintfull" }
            ]
            current: Settings.fontHintstyle
            onPicked: (v) => Settings.fontHintstyle = v
        }
        DropdownRow {
            label: I18n.tr("Subpixel order (RGBA)")
            options: [
                { text: I18n.tr("None (grayscale)"), value: "none" },
                { text: "RGB",  value: "rgb" },
                { text: "BGR",  value: "bgr" },
                { text: I18n.tr("Vertical RGB"), value: "vrgb" },
                { text: I18n.tr("Vertical BGR"), value: "vbgr" }
            ]
            current: Settings.fontRgba
            onPicked: (v) => Settings.fontRgba = v
        }
        DropdownRow {
            label: I18n.tr("LCD filter")
            options: [
                { text: I18n.tr("None"),    value: "none" },
                { text: I18n.tr("Default"), value: "lcddefault" },
                { text: I18n.tr("Light"),   value: "lcdlight" },
                { text: I18n.tr("Legacy"),  value: "lcdlegacy" }
            ]
            current: Settings.fontLcdfilter
            onPicked: (v) => Settings.fontLcdfilter = v
        }
        SwitchRow {
            label: I18n.tr("Embedded bitmaps")
            desc: I18n.tr("Disabled avoids pixelated bitmap fonts")
            checked: Settings.fontEmbeddedbitmap
            onToggled: Settings.fontEmbeddedbitmap = !Settings.fontEmbeddedbitmap
        }
        Hint {
            text: I18n.tr("Affects Brave, Discord and GTK/Qt apps. Reopen them to apply.")
        }
    }
}
