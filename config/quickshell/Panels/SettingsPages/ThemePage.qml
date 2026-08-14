import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Tema
SettingsPage {

    SettingsCard {
        title: I18n.tr("Language"); glyph: "󰗊"
        DropdownRow {
            glyph: "󰗊"
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
            glyph: "󰸌"
            skey: "themeName"
            label: I18n.tr("Base theme")
            options: Settings.themeOptions
            current: Settings.themeName
            onPicked: (v) => Settings.themeName = v
        }
        // El acento se elige en un botón que ENSEÑA el color, no en una
        // rejilla de seis discos con su nombre debajo. La rejilla ocupaba
        // media tarjeta a cambio de enseñar cinco colores que no has elegido;
        // el botón enseña el que tienes puesto y saca los demás solo cuando
        // lo abres. Las muestras las dibuja el propio desplegable a partir
        // del campo 'color' de cada opción.
        DropdownRow {
            glyph: "󰈊"
            skey: "accentName"
            label: I18n.tr("Basic accent")
            options: Settings.accentSwatches.map(s => ({
                text: I18n.tr(s.label), value: s.name, color: s.color
            }))
            current: Settings.accentName
            onPicked: (v) => Settings.pickAccent(
                Settings.accentSwatches.find(s => s.name === v))
        }
        SwitchRow {
            glyph: "󰖔"
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
        // El zoom automático era un aviso de texto que contaba lo que hacía la
        // densidad sin dejar elegirla. Ahora es un interruptor: encendido, la
        // interfaz se adapta a la resolución del monitor; apagado, manda solo
        // la escala de abajo. El factor vigente ya se ve en el «efectivo %»
        // del slider, así que el aviso no contaba nada que no esté a un
        // renglón de distancia.
        SwitchRow {
            glyph: "󰍋"
            skey: "autoDensity"
            label: I18n.tr("Automatic zoom")
            desc: Settings.autoDensity
                ? I18n.tr("Adapts to this monitor's resolution (now ×%1%)")
                    .arg(Math.round(Theme.densityScale * 100))
                : I18n.tr("Off: only your interface scale applies")
            checked: Settings.autoDensity
            onToggled: Settings.autoDensity = !Settings.autoDensity
        }
        SliderRow {
            skey: "uiScale"
            // Solo con el zoom automático apagado: encendido, la escala la
            // decide la resolución y este slider era un segundo mando sobre lo
            // mismo — dos controles gobernando un valor es una invitación a no
            // saber cuál manda. Al apagar el zoom, aparece y tomas el control.
            shown: !Settings.autoDensity
            label: I18n.tr("Interface scale"); glyph: "󰍉"
            from: 0.8; to: 1.3; value: Settings.uiScale
            valueText: I18n.tr("%1% · effective %2%").arg(Math.round(Settings.uiScale * 100)).arg(Math.round(Theme.scale * 100))
            onMoved: (v) => Settings.uiScale = Math.round(v * 20) / 20
        }
        SegRow {
            glyph: "󰤼"
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
        // Vista previa en vivo. Es una barra en miniatura con sus píldoras
        // dentro, no un rectángulo con el porcentaje escrito: el número ya
        // está justo encima, a la derecha del slider, y repetirlo dentro de
        // una caja vacía la convertía en un hueco de relleno. Lo que hace
        // falta ver aquí es la FORMA, y las dos esquinas que gobierna el
        // ajuste (la de la barra y la de los widgets) se mueven a la vez.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.dp(44)
            radius: Theme.barRadius
            color: SettingsPalette.settingsControl
            border.width: Theme.hairline
            border.color: Theme.withAlpha(Theme.accent, 0.55)
            Behavior on radius { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.space10
                anchors.rightMargin: Theme.space10
                spacing: Theme.space6

                // Anchos dispares a propósito: una barra real no lleva cuatro
                // widgets del mismo tamaño, y con todos iguales la miniatura
                // se leía como una barra de progreso.
                Repeater {
                    model: [Theme.dp(54), Theme.dp(30), Theme.dp(72), Theme.dp(30)]
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: modelData
                        height: Theme.dp(20)
                        radius: Theme.pillRadius
                        color: index === 2 ? Theme.withAlpha(Theme.accent, 0.42)
                                           : Theme.withAlpha(Theme.fg, 0.13)
                        Behavior on radius { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    }
                }
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
        SliderRow {
            skey: "panelBackdropDim"
            label: I18n.tr("Dim wallpaper behind panels"); glyph: "󰖔"
            from: 0.0; to: 0.7; value: Settings.panelBackdropDim
            valueText: Math.round(Settings.panelBackdropDim * 100) + "%"
            onMoved: (v) => Settings.panelBackdropDim = Math.round(v * 100) / 100
        }
    }

    // Plantillas de aplicaciones: ya no es una sección aparte. Lo que hace es
    // llevar ESTE tema a GTK, al terminal, a Hyprland…, así que su sitio es el
    // final de Tema, después de haberlo elegido — no una parada suelta en la
    // navegación a la que había que saber ir.
    TemplatesPage { Layout.fillWidth: true }
}
