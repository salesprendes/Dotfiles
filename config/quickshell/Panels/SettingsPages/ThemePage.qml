import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Tema
ColumnLayout {
    spacing: Theme.space12

    SettingsCard {
        title: I18n.tr("Language"); glyph: "󰗊"
        DropdownRow {
            skey: "language"
            label: I18n.tr("Language")
            options: [
                { text: I18n.tr("English"), value: "en" },
                { text: I18n.tr("Spanish"), value: "es" },
                { text: I18n.tr("Catalan"), value: "ca" }
            ]
            current: Settings.language
            onPicked: (v) => Settings.language = v
        }
    }

    SettingsCard {
        title: I18n.tr("Color"); glyph: "󰏘"
        DropdownRow {
            skey: "themeName"
            label: I18n.tr("Base theme")
            options: Settings.themeOptions
            current: Settings.themeName
            onPicked: (v) => Settings.themeName = v
        }
        ColorRow {
            skey: "accentName"
            label: I18n.tr("Basic accent")
            colors: Settings.accentSwatches
            currentName: Settings.accentName
            onPicked: (c) => Settings.pickAccent(c)
        }
        SwitchRow {
            skey: "darkMode"
            label: I18n.tr("Dark mode")
            checked: Settings.darkMode
            onToggled: Settings.darkMode = !Settings.darkMode
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.tileL
            radius: Theme.pillRadius
            color: Theme.withAlpha(Theme.bgAlt, 0.72)
            border.width: Theme.hairline
            border.color: Theme.withAlpha(Theme.overlay, 0.36)

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.space10
                spacing: Theme.space10

                Rectangle {
                    implicitWidth: Theme.controlL
                    implicitHeight: Theme.controlL
                    radius: Theme.pillRadius
                    color: Theme.accent
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2
                    Text {
                        Layout.fillWidth: true
                        text: Settings.themeOptions.find(o => o.value === Settings.themeName)?.text || Settings.themeName
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Basic accent") + " · " + I18n.tr(Settings.accentLabel(Settings.accentName))
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    implicitWidth: Theme.dp(76)
                    implicitHeight: Theme.controlS
                    radius: Theme.pillRadius
                    color: Theme.pillBg
                    border.width: Theme.hairline
                    border.color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: Settings.darkMode ? I18n.tr("Dark") : I18n.tr("Light")
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        font.bold: true
                    }
                }
            }
        }
    }

    SettingsCard {
        title: I18n.tr("Size and scale"); glyph: "󰍉"
        Hint {
            text: I18n.tr("Auto by resolution · ×%1%. Controls multiply on top (100% = neutral).")
                .arg(Math.round(Theme.densityScale * 100))
        }
        SliderRow {
            skey: "uiScale"
            label: I18n.tr("Interface scale"); glyph: "󰍉"
            from: 0.8; to: 1.3; value: Settings.uiScale
            valueText: I18n.tr("%1% · effective %2%").arg(Math.round(Settings.uiScale * 100)).arg(Math.round(Theme.scale * 100))
            onMoved: (v) => Settings.uiScale = Math.round(v * 20) / 20
        }
        SegRow {
            skey: "barScale"
            label: I18n.tr("Bar height")
            options: [ { text: I18n.tr("Compact"), value: 0.85 }, { text: I18n.tr("Normal"), value: 1.0 },
                       { text: I18n.tr("Large"), value: 1.2 } ]
            current: Settings.barScale
            onPicked: (v) => Settings.barScale = v
        }
    }

    SettingsCard {
        title: I18n.tr("Corners"); glyph: "󰝤"
        SliderRow {
            skey: "cornerScale"
            label: I18n.tr("Corner rounding"); glyph: "󰝤"
            // Rango real 0.0 (cuadrado) → 1.6 (máximo), mostrado como 0%–100%
            // (el 1.6 interno es el 100%). El slider trabaja sobre cornerScale y
            // el porcentaje se deriva dividiendo entre 1.6.
            from: 0.0; to: 1.6; value: Settings.cornerScale
            valueText: Math.round(Settings.cornerScale / 1.6 * 100) + "%"
            onMoved: (v) => Settings.cornerScale = Math.round(v * 20) / 20
        }
        // Vista previa en vivo: refleja el redondeo al instante.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.tileM
            radius: Theme.barRadius
            color: SettingsPalette.settingsControl
            border.width: Math.max(2, Theme.dp(2))
            border.color: Theme.accent
            Behavior on radius { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            Text {
                anchors.centerIn: parent
                text: I18n.tr("Preview · %1%").arg(Math.round(Settings.cornerScale / 1.6 * 100))
                color: Theme.fgDim
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    SettingsCard {
        title: I18n.tr("Transparency"); glyph: "󰠦"
        SliderRow {
            skey: "barOpacity"
            label: I18n.tr("Bar opacity"); glyph: "󰠦"
            from: 0.2; to: 1.0; value: Settings.effBarOpacity
            valueText: Math.round(Settings.effBarOpacity * 100) + "%"
            onMoved: (v) => Settings.setBarOpacity(Math.round(v * 100) / 100)
        }
        SliderRow {
            skey: "popupOpacity"
            label: I18n.tr("Panel opacity"); glyph: "󱂬"
            from: 0.2; to: 1.0; value: Settings.effPopupOpacity
            valueText: Math.round(Settings.effPopupOpacity * 100) + "%"
            onMoved: (v) => Settings.setPopupOpacity(Math.round(v * 100) / 100)
        }
        SliderRow {
            skey: "widgetOpacity"
            label: I18n.tr("Widget opacity"); glyph: "󰍵"
            from: 0.2; to: 1.0; value: Settings.effWidgetOpacity
            valueText: Math.round(Settings.effWidgetOpacity * 100) + "%"
            onMoved: (v) => Settings.setWidgetOpacity(Math.round(v * 100) / 100)
        }
    }
}
