import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Components
import qs.Config
import qs.Services

// ─────────────────────────────────────────────────────────────
//  Ventana de Ajustes — ventana XDG real (FloatingWindow), así que
//  Hyprland la gestiona como un programa: se puede mosaiquear,
//  redimensionar y la redondea el compositor. Barra lateral de
//  categorías + contenido desplazable con sub-secciones.
//  Escribe en el singleton Settings (persistente).
// ─────────────────────────────────────────────────────────────
FloatingWindow {
    id: cfg

    title: I18n.tr("Settings") + " · Quickshell"
    color: settingsBase
    implicitWidth: Theme.dp(940)
    implicitHeight: Theme.dp(620)
    minimumSize: Qt.size(Theme.dp(680), Theme.dp(460))

    visible: Globals.settingsOpen

    readonly property color settingsBase: Theme.bgAlt
    readonly property color settingsCard: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72)
    readonly property color settingsControl: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.86)
    readonly property color settingsHover: Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.74)
    readonly property color settingsLine: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.18)
    readonly property color settingsBorder: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.28)

    // ¿Es un portátil? (para mostrar/ocultar la opción de batería)
    readonly property bool hasBattery: UPower.displayDevice?.isLaptopBattery ?? false

    property string cat: "theme"
    property int navResetToken: 0
    onVisibleChanged: {
        if (visible) {
            cat = "theme"
            navResetToken++
        }
        else if (Globals.settingsOpen) Globals.settingsOpen = false   // cerrada por Hyprland
    }

    readonly property var groups: [
        { label: I18n.tr("Personalization"), glyph: "󰏘", items: [
            { key: "theme",     glyph: "󰸌", label: I18n.tr("Theme") },
            { key: "font",      glyph: "󰛖", label: I18n.tr("Typography") },
            { key: "wallpaper", glyph: "󰋩", label: I18n.tr("Wallpaper") }
        ] },
        { label: I18n.tr("Bar and widgets"), glyph: "󰍜", items: [
            { key: "bar",   glyph: "󰕬", label: I18n.tr("Widgets") },
            { key: "clock", glyph: "󰅐", label: I18n.tr("Clock and date") }
        ] },
        { label: I18n.tr("System"), glyph: "󰒓", items: [
            { key: "weather", glyph: "󰖕", label: I18n.tr("Weather") },
            { key: "notif",   glyph: "󰂚", label: I18n.tr("Notifications") }
        ] }
    ]
    readonly property string catLabel: {
        for (let g = 0; g < groups.length; g++)
            for (let i = 0; i < groups[g].items.length; i++)
                if (groups[g].items[i].key === cat) return groups[g].items[i].label
        return ""
    }

    // ── Disposición general ──────────────────────────────────
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Barra lateral ────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Theme.dp(220)
            color: cfg.settingsBase

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.space12
                spacing: Theme.space6

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.space6
                    spacing: Theme.space8
                    Text {
                        text: "󰒓"; color: Theme.accent
                        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize + 4
                    }
                    Text {
                        text: I18n.tr("Settings"); color: Theme.fg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize + 3
                        font.bold: true
                    }
                }

                // Grupos desplegables (desplazable si no caben).
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: navCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: navCol
                        width: parent.width
                        spacing: Theme.space4
                        Repeater {
                            model: cfg.groups
                            delegate: NavGroup {
                                required property var modelData
                                label: modelData.label
                                glyph: modelData.glyph
                                items: modelData.items
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.rowM
                    radius: Theme.pillRadius
                    color: resetMa.containsMouse ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.18)
                                                 : cfg.settingsControl
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Theme.space6
                        Text {
                            text: "󰜉"; color: Theme.red
                            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize - 2
                        }
                        Text {
                            text: I18n.tr("Reset")
                            color: resetMa.containsMouse ? Theme.red : Theme.fgDim
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }
                    }
                    MouseArea {
                        id: resetMa
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.reset()
                    }
                }
            }
        }

        Rectangle { Layout.fillHeight: true; implicitWidth: Theme.hairline; color: cfg.settingsLine }

        // ── Contenido ────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.space18
                Layout.bottomMargin: Theme.space8
                Text {
                    Layout.fillWidth: true
                    text: cfg.catLabel
                    color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize + 6
                    font.bold: true
                }
                Rectangle {
                    implicitWidth: Theme.controlM; implicitHeight: Theme.controlM
                    radius: width / 2
                    color: closeMa.containsMouse ? Theme.red : cfg.settingsControl
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        anchors.centerIn: parent; text: "󰅖"
                        color: closeMa.containsMouse ? Theme.bg : Theme.fgDim
                        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Globals.settingsOpen = false
                    }
                }
            }

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: (activeCol ? activeCol.implicitHeight : 0) + Theme.space18 * 2
                boundsBehavior: Flickable.StopAtBounds

                readonly property var activeCol:
                      cfg.cat === "font"      ? fontCol
                    : cfg.cat === "bar"       ? barCol
                    : cfg.cat === "clock"     ? clockCol
                    : cfg.cat === "weather"   ? weatherCol
                    : cfg.cat === "notif"     ? notifCol
                    : cfg.cat === "wallpaper" ? wpCol
                    :                            themeCol

                // ════ TEMA ════
                ColumnLayout {
                    id: themeCol
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: Theme.space18; rightMargin: Theme.space18; topMargin: Theme.space18 }
                    spacing: Theme.space12
                    opacity: cfg.cat === "theme" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

                    SettingsCard {
                        title: I18n.tr("Language"); glyph: "󰗊"
                        DropdownRow {
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
                            label: I18n.tr("Base theme")
                            options: Settings.themeOptions
                            current: Settings.themeName
                            onPicked: (v) => Settings.themeName = v
                        }
                        ColorRow {
                            label: I18n.tr("Basic accent")
                            colors: Settings.accentSwatches
                            currentName: Settings.accentName
                            onPicked: (c) => Settings.pickAccent(c)
                        }
                        SwitchRow {
                            label: I18n.tr("Dark mode")
                            checked: Settings.darkMode
                            onToggled: Settings.darkMode = !Settings.darkMode
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.tileL
                            radius: Theme.pillRadius
                            color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.72)
                            border.width: Theme.hairline
                            border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.36)

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
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Auto by resolution · ×%1%. Controls multiply on top (100% = neutral).")
                                .arg(Math.round(Theme.densityScale * 100))
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                            wrapMode: Text.WordWrap
                        }
                        SliderRow {
                            label: I18n.tr("Interface scale"); glyph: "󰍉"
                            from: 0.8; to: 1.3; value: Settings.uiScale
                            valueText: I18n.tr("%1% · effective %2%").arg(Math.round(Settings.uiScale * 100)).arg(Math.round(Theme.scale * 100))
                            onMoved: (v) => Settings.uiScale = Math.round(v * 20) / 20
                        }
                        SegRow {
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
                            label: I18n.tr("Corner rounding"); glyph: "󰝤"
                            from: 0.3; to: 1.6; value: Settings.cornerScale
                            valueText: Math.round(Settings.cornerScale * 100) + "%"
                            onMoved: (v) => Settings.cornerScale = Math.round(v * 20) / 20
                        }
                        // Vista previa en vivo: refleja el redondeo al instante.
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.tileM
                            radius: Theme.barRadius
                            color: cfg.settingsControl
                            border.width: Math.max(2, Theme.dp(2))
                            border.color: Theme.accent
                            Behavior on radius { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                            Text {
                                anchors.centerIn: parent
                                text: I18n.tr("Preview · %1%").arg(Math.round(Settings.cornerScale * 100))
                                color: Theme.fgDim
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                            }
                        }
                    }

                    SettingsCard {
                        title: I18n.tr("Transparency"); glyph: "󰠦"
                        SliderRow {
                            label: I18n.tr("Bar opacity"); glyph: "󰠦"
                            from: 0.3; to: 1.0; value: Settings.barOpacity
                            valueText: Math.round(Settings.barOpacity * 100) + "%"
                            onMoved: (v) => Settings.barOpacity = Math.round(v * 100) / 100
                        }
                        SliderRow {
                            label: I18n.tr("Panel opacity"); glyph: "󱂬"
                            from: 0.3; to: 1.0; value: Settings.popupOpacity
                            valueText: Math.round(Settings.popupOpacity * 100) + "%"
                            onMoved: (v) => Settings.popupOpacity = Math.round(v * 100) / 100
                        }
                        SliderRow {
                            label: I18n.tr("Widget opacity"); glyph: "󰍵"
                            from: 0.3; to: 1.0; value: Settings.widgetOpacity
                            valueText: Math.round(Settings.widgetOpacity * 100) + "%"
                            onMoved: (v) => Settings.widgetOpacity = Math.round(v * 100) / 100
                        }
                    }
                }

                // ════ TIPOGRAFÍA ════
                ColumnLayout {
                    id: fontCol
                    property bool normalMenuOpen: false
                    property bool monoMenuOpen: false
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: Theme.space18; rightMargin: Theme.space18; topMargin: Theme.space18 }
                    spacing: Theme.space12
                    opacity: cfg.cat === "font" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

                    // Pliega el desplegable al salir de la página.
                    Connections {
                        target: cfg
                        function onCatChanged() {
                            if (cfg.cat !== "font") {
                                fontCol.normalMenuOpen = false
                                fontCol.monoMenuOpen = false
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: motionBox.implicitHeight + Theme.space16 * 2
                        radius: Theme.barRadius
                        color: cfg.settingsCard
                        border.width: Theme.hairline
                        border.color: cfg.settingsBorder

                        ColumnLayout {
                            id: motionBox
                            anchors.fill: parent
                            anchors.margins: Theme.space16
                            spacing: Theme.space12

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space8
                                Text {
                                    text: "󰓞"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.iconSize + 2
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Animations and motion")
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize + 1
                                    font.bold: true
                                }
                            }

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

                            Text {
                                Layout.fillWidth: true
                                text: {
                                    if (Settings.panelAnimationStyle === "fluent")
                                        return I18n.tr("Fluent: clean entrance with smooth deceleration and quick close.")
                                    if (Settings.panelAnimationStyle === "dynamic")
                                        return I18n.tr("Dynamic: elastic entrance with visible bounce and quick close.")
                                    return I18n.tr("Material: expressive entrance with soft scale and short displacement.")
                                }
                                color: Theme.fgMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                                wrapMode: Text.WordWrap
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

                            Text {
                                Layout.fillWidth: true
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
                                color: Theme.fgMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                                wrapMode: Text.WordWrap
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

                            Text {
                                Layout.fillWidth: true
                                text: {
                                    if (Settings.panelMotionEffect === "directional")
                                        return I18n.tr("Directional: wide full-size slide, without scaling.")
                                    if (Settings.panelMotionEffect === "depth")
                                        return I18n.tr("Depth: deep scale and medium displacement with approach effect.")
                                    return I18n.tr("Standard: short displacement with subtle scale and Material feel.")
                                }
                                color: Theme.fgMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: typeBox.implicitHeight + Theme.space16 * 2
                        radius: Theme.barRadius
                        color: cfg.settingsCard
                        border.width: Theme.hairline
                        border.color: cfg.settingsBorder

                        ColumnLayout {
                            id: typeBox
                            anchors.fill: parent
                            anchors.margins: Theme.space16
                            spacing: Theme.space12

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space8
                                Text {
                                    text: "󰛖"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.iconSize + 2
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Typography")
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize + 1
                                    font.bold: true
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: Theme.tileL
                                radius: Theme.pillRadius
                                color: cfg.settingsControl
                                border.width: Theme.hairline
                                border.color: cfg.settingsBorder

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

                            FontPicker {
                                label: I18n.tr("Normal Font")
                                fonts: Fonts.list
                                current: Settings.fontFamily
                                open: fontCol.normalMenuOpen
                                onToggle: {
                                    fontCol.normalMenuOpen = !fontCol.normalMenuOpen
                                    if (fontCol.normalMenuOpen) fontCol.monoMenuOpen = false
                                }
                                onPicked: (font) => {
                                    Settings.fontFamily = font
                                    fontCol.normalMenuOpen = false
                                }
                            }

                            FontPicker {
                                label: I18n.tr("Monospace Font")
                                fonts: Fonts.monoList
                                current: Settings.monoFontFamily
                                open: fontCol.monoMenuOpen
                                onToggle: {
                                    fontCol.monoMenuOpen = !fontCol.monoMenuOpen
                                    if (fontCol.monoMenuOpen) fontCol.normalMenuOpen = false
                                }
                                onPicked: (font) => {
                                    Settings.monoFontFamily = font
                                    fontCol.monoMenuOpen = false
                                }
                            }

                            SliderRow {
                                label: I18n.tr("Letter scale"); glyph: "󰗊"
                                from: 0.8; to: 1.3; value: Settings.fontScale
                                valueText: I18n.tr("%1% · effective %2%").arg(Math.round(Settings.fontScale * 100)).arg(Math.round(Theme.scale * Settings.fontScale * 100))
                                onMoved: (v) => Settings.fontScale = Math.round(v * 20) / 20
                            }
                        }
                    }
                }

                // ════ BARRA ════
                ColumnLayout {
                    id: barCol
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: Theme.space18; rightMargin: Theme.space18; topMargin: Theme.space18 }
                    spacing: Theme.space14
                    opacity: cfg.cat === "bar" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

                    // Widgets globales de la barra englobados en una "caja".
                    SettingsCard {
                        title: I18n.tr("Visible widgets"); glyph: "󰕬"
                        SwitchRow { label: I18n.tr("System tray"); checked: Settings.showTray
                            onToggled: Settings.showTray = !Settings.showTray }
                        SwitchRow { label: I18n.tr("Resource monitor"); checked: Settings.showSysmon
                            onToggled: Settings.showSysmon = !Settings.showSysmon }
                        SwitchRow { label: I18n.tr("Battery"); visible: cfg.hasBattery
                            checked: Settings.showBattery
                            onToggled: Settings.showBattery = !Settings.showBattery }
                        // Solo si está instalado power-profiles-daemon.
                        SwitchRow { label: I18n.tr("Power profile"); visible: Power.available
                            checked: Settings.showPowerProfile
                            onToggled: Settings.showPowerProfile = !Settings.showPowerProfile }
                        SwitchRow { label: I18n.tr("Clipboard"); checked: Settings.showClipboard
                            onToggled: Settings.showClipboard = !Settings.showClipboard }
                        SwitchRow { label: I18n.tr("Notifications"); checked: Settings.showNotifications
                            onToggled: Settings.showNotifications = !Settings.showNotifications }
                        SwitchRow { label: I18n.tr("Caffeine"); checked: Settings.showCaffeine
                            onToggled: Settings.showCaffeine = !Settings.showCaffeine }
                    }
                }

                // ════ RELOJ ════
                ColumnLayout {
                    id: clockCol
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: Theme.space18; rightMargin: Theme.space18; topMargin: Theme.space18 }
                    spacing: Theme.space14
                    opacity: cfg.cat === "clock" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

                    SwitchRow { label: I18n.tr("24-hour format"); desc: I18n.tr("Disabled uses AM/PM")
                        checked: Settings.clock24h; onToggled: Settings.clock24h = !Settings.clock24h }
                    SwitchRow { label: I18n.tr("Show seconds"); checked: Settings.clockShowSeconds
                        onToggled: Settings.clockShowSeconds = !Settings.clockShowSeconds }
                    SwitchRow { label: I18n.tr("Show date in the bar"); checked: Settings.clockShowDate
                        onToggled: Settings.clockShowDate = !Settings.clockShowDate }
                }

                // ════ CLIMA ════
                ColumnLayout {
                    id: weatherCol
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: Theme.space18; rightMargin: Theme.space18; topMargin: Theme.space18 }
                    spacing: Theme.space14
                    opacity: cfg.cat === "weather" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

                    SwitchRow { label: I18n.tr("Enable weather"); checked: Settings.weatherEnabled
                        onToggled: Settings.weatherEnabled = !Settings.weatherEnabled }
                    SegRow {
                        label: I18n.tr("Temperature unit")
                        options: [ { text: "°C", value: true }, { text: "°F", value: false } ]
                        current: Settings.weatherMetric
                        onPicked: (v) => Settings.weatherMetric = v
                    }
                    SegRow {
                        label: I18n.tr("Refresh interval")
                        options: [ { text: "15 min", value: 15 }, { text: "30 min", value: 30 },
                                   { text: "60 min", value: 60 } ]
                        current: Settings.weatherRefreshMin
                        onPicked: (v) => Settings.weatherRefreshMin = v
                    }
                    TextRow {
                        label: I18n.tr("Location"); placeholder: I18n.tr("Automatic (by IP)")
                        text: Settings.weatherLocation
                        onEdited: (t) => Settings.weatherLocation = t
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Empty = automatic detection. Enter a city to pin it.")
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                        wrapMode: Text.WordWrap
                    }
                }

                // ════ NOTIFICACIONES ════
                ColumnLayout {
                    id: notifCol
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: Theme.space18; rightMargin: Theme.space18; topMargin: Theme.space18 }
                    spacing: Theme.space14
                    opacity: cfg.cat === "notif" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

                    SwitchRow { label: I18n.tr("Show popups"); desc: I18n.tr("Popup alerts when notifications arrive")
                        checked: Settings.notifPopupsEnabled
                        onToggled: Settings.notifPopupsEnabled = !Settings.notifPopupsEnabled }
                    SwitchRow { label: I18n.tr("Do not disturb"); desc: I18n.tr("Silences popups (keeps them in the center)")
                        checked: Globals.dnd; onToggled: Globals.dnd = !Globals.dnd }
                    SegRow {
                        label: I18n.tr("Popup position")
                        options: [ { text: "↖", value: "tl" }, { text: "↗", value: "tr" },
                                   { text: "↙", value: "bl" }, { text: "↘", value: "br" } ]
                        current: Settings.notifPosition
                        onPicked: (v) => Settings.notifPosition = v
                    }
                    SliderRow {
                        label: I18n.tr("On-screen duration"); glyph: "󰔛"
                        from: 2; to: 15; value: Settings.notifTimeout
                        valueText: Settings.notifTimeout + " s"
                        onMoved: (v) => Settings.notifTimeout = Math.round(v)
                    }
                    SegRow {
                        label: I18n.tr("Maximum on screen")
                        options: [ { text: "3", value: 3 }, { text: "4", value: 4 },
                                   { text: "5", value: 5 }, { text: "6", value: 6 } ]
                        current: Settings.notifMaxVisible
                        onPicked: (v) => Settings.notifMaxVisible = v
                    }
                }

                // ════ FONDOS ════
                ColumnLayout {
                    id: wpCol
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: Theme.space18; rightMargin: Theme.space18; topMargin: Theme.space18 }
                    spacing: Theme.space14
                    opacity: cfg.cat === "wallpaper" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

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
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: Theme.space2
                        Text {
                            text: I18n.tr("Wallpaper folders")
                            color: Theme.fg
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                        }
                        Repeater {
                            model: Settings.wallpaperDirs
                            delegate: Text {
                                required property var modelData
                                Layout.fillWidth: true
                                text: "•  " + modelData
                                color: Theme.fgMuted
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                                elide: Text.ElideMiddle
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("%1 images · choose them in the clock Wallpapers tab").arg(Wallpaper.list.length)
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }

    // ═════════ COMPONENTES REUTILIZABLES ═════════════════════
    component SubHeader: ColumnLayout {
        id: sh
        property string text: ""
        Layout.fillWidth: true
        Layout.topMargin: Theme.space6
        spacing: Theme.space4
        Text {
            text: sh.text; color: Theme.fgDim
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2; font.bold: true
        }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: Theme.hairline
            color: cfg.settingsLine
        }
    }

    // Grupo desplegable de la barra lateral.
    component NavGroup: ColumnLayout {
        id: grp
        property string label: ""
        property string glyph: ""
        property var items: []
        property bool expanded: label === I18n.tr("Personalization")
        Layout.fillWidth: true
        spacing: Theme.space2

        Connections {
            target: cfg
            function onNavResetTokenChanged() {
                grp.expanded = grp.label === I18n.tr("Personalization")
            }
        }

        // Cabecera del grupo (clic = desplegar/plegar).
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.rowM
            radius: Theme.pillRadius
            color: "transparent"
            // Capa de hover: opacidad rápida (sin rastro de color).
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                color: cfg.settingsControl
                opacity: hdrMa.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space10
                anchors.rightMargin: Theme.space10
                spacing: Theme.space8
                Text {
                    text: grp.glyph; color: Theme.fgDim
                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                }
                Text {
                    Layout.fillWidth: true
                    text: grp.label; color: Theme.fgDim
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                    font.bold: true; elide: Text.ElideRight
                }
                Text {
                    text: "󰅀"
                    rotation: grp.expanded ? 0 : -90
                    Behavior on rotation { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize - 2
                }
            }
            MouseArea {
                id: hdrMa
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: grp.expanded = !grp.expanded
            }
        }

        // Sub-elementos (altura animada al plegar/desplegar).
        Item {
            Layout.fillWidth: true
            clip: true
            implicitHeight: grp.expanded ? sub.implicitHeight : 0
            Behavior on implicitHeight { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
            opacity: grp.expanded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            ColumnLayout {
                id: sub
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Theme.space2
                Repeater {
                    model: grp.items
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: cfg.cat === modelData.key
                        Layout.fillWidth: true
                        implicitHeight: Theme.rowM
                        radius: Theme.pillRadius
                        color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                   : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius
                            color: cfg.settingsControl
                            opacity: subMa.containsMouse && !parent.sel ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space18 + Theme.space2
                            anchors.rightMargin: Theme.space10
                            spacing: Theme.space8
                            Text {
                                text: parent.parent.modelData.glyph
                                color: parent.parent.sel ? Theme.accent : Theme.fgDim
                                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                            }
                            Text {
                                Layout.fillWidth: true
                                text: parent.parent.modelData.label
                                color: parent.parent.sel ? Theme.fg : Theme.fgDim
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                                font.bold: parent.parent.sel
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            id: subMa
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cfg.cat = parent.modelData.key
                        }
                    }
                }
            }
        }
    }


    component FontPicker: ColumnLayout {
        id: fp
        property string label: ""
        property var fonts: []
        property string current: ""
        property bool open: false
        signal toggle()
        signal picked(string fontName)

        Layout.fillWidth: true
        spacing: Theme.space6

        Text {
            text: fp.label
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.rowM
            radius: Theme.pillRadius
            color: cfg.settingsControl
            border.width: Theme.hairline
            border.color: fp.open ? Theme.accent
                         : cfg.settingsBorder
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space12
                anchors.rightMargin: Theme.space12
                spacing: Theme.space8

                Text {
                    Layout.fillWidth: true
                    text: fp.current
                    color: Theme.fg
                    font.family: fp.current
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }
                Text {
                    text: I18n.tr("%1 fonts").arg(fp.fonts.length)
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 4
                }
                Text {
                    text: "󰅀"
                    rotation: fp.open ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize - 1
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: fp.toggle()
            }
        }

        Item {
            Layout.fillWidth: true
            clip: true
            implicitHeight: fp.open ? Math.min(Theme.dp(220), fontList.contentHeight + Theme.space4 * 2) : 0
            Behavior on implicitHeight { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
            opacity: fp.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

            Rectangle {
                anchors.fill: parent
                radius: Theme.pillRadius
                color: cfg.settingsCard
                border.width: Theme.hairline
                border.color: cfg.settingsBorder

                ListView {
                    id: fontList
                    anchors.fill: parent
                    anchors.margins: Theme.space4
                    clip: true
                    model: fp.fonts
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: fontRow
                        required property var modelData
                        readonly property bool sel: fp.current === modelData
                        width: ListView.view.width
                        implicitHeight: Theme.rowM
                        radius: Theme.pillRadius - Theme.space2
                        color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                   : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: cfg.settingsHover
                            opacity: fontMa.containsMouse && !fontRow.sel ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space10
                            anchors.rightMargin: Theme.space10
                            spacing: Theme.space8

                            Text {
                                Layout.fillWidth: true
                                text: fontRow.modelData
                                color: fontRow.sel ? Theme.fg : Theme.fgDim
                                font.family: fontRow.modelData
                                font.pixelSize: Theme.fontSize
                                font.bold: fontRow.sel
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: fontRow.sel
                                text: "󰄬"
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.iconSize - 1
                            }
                        }

                        MouseArea {
                            id: fontMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: fp.picked(fontRow.modelData)
                        }
                    }
                }
            }
        }
    }


    component Switch: Rectangle {
        property bool checked: false
        signal toggled()
        implicitWidth: Theme.dp(44); implicitHeight: Theme.dp(24)
        radius: height / 2
        color: checked ? Theme.accent : cfg.settingsControl
        border.width: Theme.hairline
        border.color: checked ? Theme.accent : cfg.settingsBorder
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Rectangle {
            width: parent.height - Theme.dp(6); height: width; radius: height / 2
            y: Theme.dp(3)
            x: parent.checked ? parent.width - width - Theme.dp(3) : Theme.dp(3)
            color: parent.checked ? Theme.bg : Theme.fgDim
            Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.toggled()
        }
    }

    component SwitchRow: RowLayout {
        id: sr
        property string label: ""
        property string desc: ""
        property bool checked: false
        signal toggled()
        Layout.fillWidth: true
        spacing: Theme.space10
        ColumnLayout {
            Layout.fillWidth: true; spacing: 0
            Text {
                Layout.fillWidth: true
                text: sr.label; color: Theme.fg
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
            }
            Text {
                Layout.fillWidth: true
                visible: sr.desc !== ""
                text: sr.desc; color: Theme.fgMuted
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                wrapMode: Text.WordWrap
            }
        }
        Switch { checked: sr.checked; onToggled: sr.toggled() }
    }

    // Caja/tarjeta reutilizable con cabecera (icono + título), igual que
    // las secciones de Tipografía. El contenido se añade dentro:
    //   SettingsCard { title: "..."; glyph: "..."; <controles> }
    component SettingsCard: Rectangle {
        id: cardRoot
        property string title: ""
        property string glyph: ""
        default property alias content: cardCol.data
        Layout.fillWidth: true
        implicitHeight: cardCol.implicitHeight + Theme.space16 * 2
        radius: Theme.barRadius
        color: cfg.settingsCard
        border.width: Theme.hairline
        border.color: cfg.settingsBorder

        ColumnLayout {
            id: cardCol
            anchors.fill: parent
            anchors.margins: Theme.space16
            spacing: Theme.space12

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                visible: cardRoot.title !== ""
                Text {
                    text: cardRoot.glyph
                    visible: cardRoot.glyph !== ""
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 2
                }
                Text {
                    Layout.fillWidth: true
                    text: cardRoot.title
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
            }
        }
    }

    component SegRow: ColumnLayout {
        id: seg
        property string label: ""
        property var options: []
        property var current
        signal picked(var v)
        Layout.fillWidth: true
        spacing: Theme.space6
        Text {
            text: seg.label; color: Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
        }
        Rectangle {
            id: segBox
            Layout.fillWidth: true
            implicitHeight: Theme.rowS
            radius: Theme.pillRadius
            color: cfg.settingsControl
            border.width: Theme.hairline
            border.color: cfg.settingsBorder

            readonly property int count: seg.options ? seg.options.length : 0
            readonly property int selIndex: {
                for (let i = 0; i < count; i++)
                    if (seg.options[i].value === seg.current) return i
                return 0
            }
            readonly property real innerW: width - Theme.space4 * 2
            readonly property real segW: count > 0 ? (innerW - (count - 1) * Theme.space4) / count : 0

            // Píldora deslizante: una sola, se mueve a la opción activa con la
            // misma animación global (Theme.animFast) que el resto de ajustes.
            Rectangle {
                id: indicator
                visible: segBox.count > 0
                y: Theme.space4
                height: parent.height - Theme.space4 * 2
                width: segBox.segW
                x: Theme.space4 + segBox.selIndex * (segBox.segW + Theme.space4)
                radius: Theme.pillRadius - Theme.space2
                color: cfg.settingsHover
                Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.space4
                spacing: Theme.space4
                Repeater {
                    model: seg.options
                    delegate: Item {
                        required property var modelData
                        readonly property bool sel: modelData.value === seg.current
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Text {
                            anchors.centerIn: parent
                            text: modelData.text
                            color: parent.sel ? Theme.accent : Theme.fgMuted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                            font.bold: parent.sel
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: seg.picked(modelData.value)
                        }
                    }
                }
            }
        }
    }

    component ColorRow: ColumnLayout {
        id: cr
        property string label: ""
        property var colors: []
        property color current: Theme.accent
        property string currentName: ""
        signal picked(var c)
        Layout.fillWidth: true
        spacing: Theme.space6

        // Helpers null-safe (evitan que un modelData transitorio indefinido
        // llegue a Qt.colorEqual con argumentos inválidos).
        function _hexOf(m) {
            if (m === undefined || m === null) return ""
            return Settings.colorHex(m && m.color !== undefined ? m.color : m).toLowerCase()
        }
        function _nameOf(m) { return (m && m.name !== undefined) ? m.name : "" }
        function _isSel(m) {
            return currentName !== "" ? currentName === _nameOf(m)
                                      : Settings.colorHex(current).toLowerCase() === _hexOf(m)
        }

        // Lista ya deduplicada (oculta colores repetidos, conservando el
        // seleccionado). Se calcula UNA vez aquí, no por-delegado: así los
        // delegados no referencian 'index' (evita "index is not defined").
        // Se precomputan hex/nombres y el hex seleccionado una sola vez para no
        // repetir colorHex() dentro de los bucles de comparación.
        readonly property var visibleSwatches: {
            const arr = colors || []
            const n = arr.length
            const hexes = new Array(n)
            const names = new Array(n)
            for (let i = 0; i < n; i++) { hexes[i] = _hexOf(arr[i]); names[i] = _nameOf(arr[i]) }
            const selHex = currentName === "" ? Settings.colorHex(current).toLowerCase() : ""
            const out = []
            for (let i = 0; i < n; i++) {
                let dup = false
                for (let j = 0; j < i; j++)
                    if (hexes[j] === hexes[i]) { dup = true; break }
                let selAfter = false
                for (let j = i + 1; j < n; j++)
                    if (names[j] === currentName && hexes[j] === hexes[i]) { selAfter = true; break }
                const isSel = currentName !== "" ? names[i] === currentName : hexes[i] === selHex
                if ((!dup && !selAfter) || isSel)
                    out.push(arr[i])
            }
            return out
        }

        Text {
            text: cr.label; color: Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.space8
            Repeater {
                model: cr.visibleSwatches
                delegate: Rectangle {
                    id: swatch
                    required property var modelData
                    readonly property string swatchName: cr._nameOf(modelData)
                    readonly property string swatchLabel: (modelData && modelData.label !== undefined) ? modelData.label : swatchName
                    readonly property color swatchColor: (modelData && modelData.color !== undefined) ? modelData.color
                                                       : ((modelData !== undefined && modelData !== null) ? modelData : Theme.accent)
                    readonly property bool sel: cr._isSel(modelData)
                    width: Theme.dp(76)
                    height: Theme.dp(62)
                    radius: Theme.pillRadius
                    color: sel ? Qt.rgba(swatchColor.r, swatchColor.g, swatchColor.b, 0.22)
                               : swMa.containsMouse ? cfg.settingsHover : cfg.settingsControl
                    border.width: sel ? Math.max(1, Theme.dp(2)) : Theme.hairline
                    border.color: sel ? swatchColor : cfg.settingsBorder
                    scale: swMa.containsMouse ? 1.08 : 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Behavior on scale { NumberAnimation { duration: Theme.animFast } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.space4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: Theme.controlS
                            height: Theme.controlS
                            radius: height / 2
                            color: swatch.swatchColor
                            border.width: Theme.hairline
                            border.color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.45)
                            Text {
                                anchors.centerIn: parent
                                visible: swatch.sel
                                text: "󰄬"; color: Theme.bg
                                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize - 2
                            }
                        }

                        Text {
                            Layout.preferredWidth: swatch.width - Theme.space8
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.tr(swatch.swatchLabel)
                            color: swatch.sel ? Theme.fg : Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 5
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: swMa
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cr.picked(modelData)
                    }
                }
            }
        }
    }

    component TextRow: ColumnLayout {
        id: tr
        property string label: ""
        property string placeholder: ""
        property string text: ""
        signal edited(string t)
        Layout.fillWidth: true
        spacing: Theme.space6
        Text {
            text: tr.label; color: Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.rowM
            radius: Theme.pillRadius
            color: cfg.settingsControl
            border.width: Theme.hairline
            border.color: ti.activeFocus ? Theme.accent
                         : cfg.settingsBorder
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
            TextInput {
                id: ti
                anchors.fill: parent
                anchors.leftMargin: Theme.space12
                anchors.rightMargin: Theme.space12
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                text: tr.text
                color: Theme.fg
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                selectionColor: Theme.accent
                onEditingFinished: tr.edited(text)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ti.text === ""
                    text: tr.placeholder
                    color: Theme.fgMuted
                    font: ti.font
                }
            }
        }
    }
}
