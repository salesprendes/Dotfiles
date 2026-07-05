import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
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

    // Fondo translúcido como el resto de paneles (Popout usa Theme.popupBg): en
    // liquid-glass se vuelve cristal esmerilado con el blur del compositor, en
    // vez de una losa opaca clara que "brilla" en modo claro.
    readonly property color settingsBase: Theme.popupBg
    readonly property color settingsCard: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72)
    readonly property color settingsControl: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.86)
    readonly property color settingsHover: Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.74)
    readonly property color settingsLine: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.18)
    readonly property color settingsBorder: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.28)
    // Fondo tintado de los distintivos (badges) de icono. En modo claro sube
    // el alfa para que el acento se lea sobre superficies claras.
    readonly property color accentSoft: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.16 : 0.24)

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

    // ── Reabrir cuando ya está abierta ───────────────────────────
    //  Globals.toggleSettings() pide esto si la ventana ya existe. Si está
    //  en ESTE workspace → cerrar (toggle de toda la vida). Si está en OTRO
    //  → traerla al workspace actual y enfocarla, en vez de cerrarla.
    Connections {
        target: Globals
        function onSettingsResummon() { cfg.summonOrClose() }
    }

    // Busca el toplevel de Hyprland de ESTA ventana por su título (que
    // conocemos aquí mismo, así no depende del idioma de la interfaz).
    function settingsToplevel() {
        const list = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].title === cfg.title) return list[i]
        return null
    }

    function summonOrClose() {
        const tl = settingsToplevel()
        const ws = Hyprland.focusedWorkspace
        const here = tl && ws && tl.workspace && tl.workspace.id === ws.id
        if (!tl || here) {
            Globals.settingsOpen = false            // ya está aquí (o no se halló): cerrar
            return
        }
        // En otro workspace: traerla al actual y enfocarla. Como el destino es
        // el workspace activo, el "seguir la ventana" no cambia tu vista y deja
        // la ventana enfocada. Este Hyprland está en modo Lua, así que la
        // sintaxis clásica de dispatchers NO vale: hay que usar la API Lua.
        let addr = String(tl.address)
        if (addr.indexOf("0x") !== 0) addr = "0x" + addr
        if (Hyprland.usingLua) {
            Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + ws.id
                + ', window = "address:' + addr + '" })')
        } else {
            Hyprland.dispatch("movetoworkspace " + ws.id + ",address:" + addr)
            Hyprland.dispatch("focuswindow address:" + addr)
        }
    }

    readonly property var groups: [
        { label: I18n.tr("Personalization"), glyph: "󰏘", items: [
            { key: "theme",     glyph: "󰸌", label: I18n.tr("Theme") },
            { key: "font",      glyph: "󰛖", label: I18n.tr("Typography") },
            // La pestaña Terminal solo aparece si hay kitty/alacritty/foot instalado.
            ...(Terminal.available.length > 0
                ? [{ key: "terminal", glyph: "󰆍", label: I18n.tr("Terminal") }]
                : []),
            { key: "wallpaper", glyph: "󰋩", label: I18n.tr("Wallpaper") }
        ] },
        { label: I18n.tr("Bar and widgets"), glyph: "󰍜", items: [
            { key: "bar",   glyph: "󰕬", label: I18n.tr("Widgets") },
            { key: "clock", glyph: "󰅐", label: I18n.tr("Clock and date") }
        ] },
        { label: I18n.tr("System"), glyph: "󰒓", items: [
            { key: "displays", glyph: "󰍹", label: I18n.tr("Displays") },
            { key: "network",  glyph: "󰤨", label: I18n.tr("Network") },
            { key: "weather",  glyph: "󰖕", label: I18n.tr("Weather") },
            { key: "notif",    glyph: "󰂚", label: I18n.tr("Notifications") }
        ] }
    ]
    // Índice plano key → { label, glyph, group }. Se construye UNA vez
    // (se recalcula solo si cambian los grupos: idioma o terminales). Las
    // props de la categoría activa son ya búsquedas O(1), sin bucles anidados.
    readonly property var itemIndex: {
        const idx = ({})
        for (let g = 0; g < groups.length; g++)
            for (let i = 0; i < groups[g].items.length; i++) {
                const it = groups[g].items[i]
                idx[it.key] = { label: it.label, glyph: it.glyph, group: groups[g].label }
            }
        return idx
    }
    readonly property var activeItem: itemIndex[cat] || ({ label: "", glyph: "󰒓", group: "" })
    readonly property string catLabel:      activeItem.label
    readonly property string catGroupLabel: activeItem.group
    readonly property string catGlyph:      activeItem.glyph

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
                    spacing: Theme.space10
                    Rectangle {
                        implicitWidth: Theme.controlL
                        implicitHeight: Theme.controlL
                        radius: Theme.pillRadius
                        color: cfg.accentSoft
                        Text {
                            anchors.centerIn: parent
                            text: "󰒓"; color: Theme.accent
                            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize + 4
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Settings"); color: Theme.fg
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize + 3
                            font.bold: true; elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Quickshell"; color: Theme.fgMuted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 4
                            font.letterSpacing: Theme.dp(1); elide: Text.ElideRight
                        }
                    }
                }

                // Separador cabecera → navegación.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space4
                    Layout.bottomMargin: Theme.space4
                    implicitHeight: Theme.hairline
                    color: cfg.settingsLine
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
                spacing: Theme.space12

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Theme.controlL
                    implicitHeight: Theme.controlL
                    radius: Theme.pillRadius
                    color: cfg.accentSoft
                    Text {
                        anchors.centerIn: parent
                        text: cfg.catGlyph; color: Theme.accent
                        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize + 4
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Theme.space2
                    Text {
                        Layout.fillWidth: true
                        text: cfg.catGroupLabel
                        color: Theme.accent
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 4
                        font.bold: true
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: Theme.dp(1.5)
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: cfg.catLabel
                        color: Theme.fg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize + 6
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }

                IconButton {
                    Layout.alignment: Qt.AlignVCenter
                    icon: "󰅖"
                    baseColor: cfg.settingsControl
                    hoverColor: Theme.red
                    onClicked: Globals.settingsOpen = false
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
                    : cfg.cat === "displays"  ? displaysCol
                    : cfg.cat === "network"   ? netCol
                    : cfg.cat === "terminal"  ? termCol
                    :                            themeCol

                // ════ TEMA ════
                CatPage {
                    id: themeCol
                    key: "theme"

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
                        Hint {
                            text: I18n.tr("Auto by resolution · ×%1%. Controls multiply on top (100% = neutral).")
                                .arg(Math.round(Theme.densityScale * 100))
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
                        // Editan la opacidad EFECTIVA del tema activo: con Liquid
                        // Glass ajustan glass*Opacity (y reflejan su valor); con el
                        // resto de temas, las opacidades normales. Un mismo control
                        // para cada tema, sin mezclar valores.
                        SliderRow {
                            label: I18n.tr("Bar opacity"); glyph: "󰠦"
                            from: 0.2; to: 1.0; value: Settings.effBarOpacity
                            valueText: Math.round(Settings.effBarOpacity * 100) + "%"
                            onMoved: (v) => Settings.setBarOpacity(Math.round(v * 100) / 100)
                        }
                        SliderRow {
                            label: I18n.tr("Panel opacity"); glyph: "󱂬"
                            from: 0.2; to: 1.0; value: Settings.effPopupOpacity
                            valueText: Math.round(Settings.effPopupOpacity * 100) + "%"
                            onMoved: (v) => Settings.setPopupOpacity(Math.round(v * 100) / 100)
                        }
                        SliderRow {
                            label: I18n.tr("Widget opacity"); glyph: "󰍵"
                            from: 0.2; to: 1.0; value: Settings.effWidgetOpacity
                            valueText: Math.round(Settings.effWidgetOpacity * 100) + "%"
                            onMoved: (v) => Settings.setWidgetOpacity(Math.round(v * 100) / 100)
                        }
                    }
                }

                // ════ TIPOGRAFÍA ════
                CatPage {
                    id: fontCol
                    key: "font"

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

                    // ── Renderizado de fuentes (fontconfig) ──────────────
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

                // ════ BARRA ════
                CatPage {
                    id: barCol
                    key: "bar"
                    spacing: Theme.space14

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
                CatPage {
                    id: clockCol
                    key: "clock"
                    spacing: Theme.space14

                    SwitchRow { label: I18n.tr("24-hour format"); desc: I18n.tr("Disabled uses AM/PM")
                        checked: Settings.clock24h; onToggled: Settings.clock24h = !Settings.clock24h }
                    SwitchRow { label: I18n.tr("Show seconds"); checked: Settings.clockShowSeconds
                        onToggled: Settings.clockShowSeconds = !Settings.clockShowSeconds }
                    SwitchRow { label: I18n.tr("Show date in the bar"); checked: Settings.clockShowDate
                        onToggled: Settings.clockShowDate = !Settings.clockShowDate }
                }

                // ════ CLIMA ════
                CatPage {
                    id: weatherCol
                    key: "weather"
                    spacing: Theme.space14

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
                    TextField {
                        Layout.fillWidth: true
                        label: I18n.tr("Location"); placeholder: I18n.tr("Automatic (by IP)")
                        value: Settings.weatherLocation
                        onEdited: (t) => Settings.weatherLocation = t
                    }
                    Hint {
                        text: I18n.tr("Empty = automatic detection. Enter a city to pin it.")
                    }
                }

                // ════ NOTIFICACIONES ════
                CatPage {
                    id: notifCol
                    key: "notif"
                    spacing: Theme.space14

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
                CatPage {
                    id: wpCol
                    key: "wallpaper"
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

                // ════ PANTALLAS ════
                CatPage {
                    id: displaysCol
                    key: "displays"

                    // Orden / alineación (con 2+ monitores).
                    SettingsCard {
                        title: I18n.tr("Arrangement"); glyph: "󰍹"
                        visible: Displays.monitors.length > 1
                        MonitorArrangement { Layout.fillWidth: true }
                    }

                    // Una tarjeta por monitor: resolución, escala, rotación…
                    Repeater {
                        model: Displays.monitors
                        delegate: MonitorCard {
                            required property var modelData
                            monitor: modelData
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: Displays.monitors.length === 0
                        text: I18n.tr("No displays found")
                        color: Theme.fgMuted
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
                    }
                }

                // ════ RED ════
                CatPage {
                    id: netCol
                    key: "network"

                    // Interfaz/adaptador (estilo Windows): WiFi + selección
                    // de interfaz cuyos parámetros IP se editan abajo.
                    SettingsCard {
                        title: I18n.tr("Interface"); glyph: "󰛳"
                        SwitchRow {
                            label: I18n.tr("WiFi")
                            checked: Net.wifiEnabled
                            onToggled: Net.toggleWifi()
                        }
                        DropdownRow {
                            label: I18n.tr("Interface")
                            options: NetConfig.interfaces.map(i => ({
                                text: i.device + " · " + (i.type === "wifi" ? I18n.tr("WiFi") : I18n.tr("Ethernet"))
                                      + (i.connection !== "" ? " — " + i.connection : ""),
                                value: i.device }))
                            current: NetConfig.selectedIface
                            onPicked: (v) => NetConfig.selectIface(v)
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: NetConfig.selectedIface !== "" && !NetConfig.hasConn
                            text: I18n.tr("Interface not connected. Connect it to edit its settings.")
                            color: Theme.fgMuted; wrapMode: Text.WordWrap
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
                        }
                        SwitchRow {
                            visible: NetConfig.hasConn
                            label: I18n.tr("Connect automatically")
                            checked: NetConfig.autoconnect
                            onToggled: NetConfig.autoconnect = !NetConfig.autoconnect
                        }
                        SliderRow {
                            visible: NetConfig.hasConn
                            label: I18n.tr("Priority"); glyph: "󰓅"
                            from: -100; to: 100; value: NetConfig.priority
                            valueText: NetConfig.priority
                            onMoved: (v) => NetConfig.priority = Math.round(v)
                        }
                    }

                    // IPv4 + DNS.
                    SettingsCard {
                        visible: NetConfig.hasConn
                        title: "IPv4"; glyph: "󰩟"
                        SegRow {
                            label: I18n.tr("Method")
                            options: [ { text: I18n.tr("Automatic (DHCP)"), value: "auto" },
                                       { text: I18n.tr("Manual (static)"), value: "manual" } ]
                            current: NetConfig.ip4method
                            onPicked: (v) => NetConfig.ip4method = v
                        }
                        TextField {
                            visible: NetConfig.ip4method === "manual"; Layout.fillWidth: true
                            label: I18n.tr("IP address"); placeholder: "192.168.1.50"
                            value: NetConfig.ip4addr
                            invalid: NetConfig.ip4addr !== "" && !NetConfig.validIp(NetConfig.ip4addr)
                            onEdited: (t) => NetConfig.ip4addr = t
                        }
                        TextField {
                            visible: NetConfig.ip4method === "manual"; Layout.fillWidth: true
                            label: I18n.tr("Subnet mask"); placeholder: "255.255.255.0"
                            value: NetConfig.ip4mask
                            invalid: NetConfig.ip4mask !== "" && NetConfig.maskToPrefix(NetConfig.ip4mask) < 0
                            onEdited: (t) => NetConfig.ip4mask = t
                        }
                        TextField {
                            visible: NetConfig.ip4method === "manual"; Layout.fillWidth: true
                            label: I18n.tr("Gateway"); placeholder: "192.168.1.1"
                            value: NetConfig.ip4gw
                            invalid: NetConfig.ip4gw !== "" && !NetConfig.validIp(NetConfig.ip4gw)
                            onEdited: (t) => NetConfig.ip4gw = t
                        }
                        TextField {
                            Layout.fillWidth: true
                            label: "DNS"; placeholder: "1.1.1.1, 8.8.8.8"
                            value: NetConfig.ip4dns
                            onEdited: (t) => NetConfig.ip4dns = t
                        }
                    }

                    // IPv6.
                    SettingsCard {
                        visible: NetConfig.hasConn
                        title: "IPv6"; glyph: "󰩟"
                        SegRow {
                            label: I18n.tr("Method")
                            options: [ { text: I18n.tr("Automatic (DHCP)"), value: "auto" },
                                       { text: I18n.tr("Disabled"), value: "disabled" },
                                       { text: "Link-local", value: "link-local" } ]
                            current: NetConfig.ip6method
                            onPicked: (v) => NetConfig.ip6method = v
                        }
                    }

                    // Privacidad / avanzado.
                    SettingsCard {
                        visible: NetConfig.hasConn
                        title: I18n.tr("Privacy and advanced"); glyph: "󰒃"
                        DropdownRow {
                            label: I18n.tr("MAC address")
                            options: [ { text: I18n.tr("Default"), value: "default" },
                                       { text: I18n.tr("Random"), value: "random" },
                                       { text: I18n.tr("Stable"), value: "stable" } ]
                            current: NetConfig.mac
                            onPicked: (v) => NetConfig.mac = v
                        }
                        TextField {
                            Layout.fillWidth: true
                            label: "MTU"; placeholder: I18n.tr("Automatic")
                            value: NetConfig.mtu
                            onEdited: (t) => NetConfig.mtu = t
                        }
                    }

                    // Error.
                    Text {
                        Layout.fillWidth: true
                        visible: NetConfig.error !== ""
                        text: NetConfig.error
                        color: Theme.red
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
                        wrapMode: Text.WordWrap
                    }

                    // Aplicar cambios de la interfaz seleccionada.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: NetConfig.hasConn
                        spacing: Theme.space8
                        Item { Layout.fillWidth: true }
                        TextButton {
                            text: I18n.tr("Apply")
                            primary: true
                            enabled: NetConfig.ready && !NetConfig.loading
                            onClicked: NetConfig.apply()
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: NetConfig.interfaces.length === 0
                        text: I18n.tr("No network interfaces found.")
                        color: Theme.fgMuted
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
                    }

                    // ── Gestión de wifis guardadas (conexión) ──────────
                    SettingsCard {
                        title: I18n.tr("Saved networks"); glyph: "󰤨"

                        Repeater {
                            model: NetConfig.savedWifis
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.space8

                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 0
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: Theme.space6
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name; color: Theme.fg; elide: Text.ElideRight
                                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                                        }
                                        Rectangle {
                                            visible: modelData.active
                                            radius: Theme.pillRadius
                                            color: Qt.rgba(Theme.green.r, Theme.green.g, Theme.green.b, 0.18)
                                            implicitWidth: badge.implicitWidth + Theme.space10
                                            implicitHeight: badge.implicitHeight + Theme.space4
                                            Text {
                                                id: badge; anchors.centerIn: parent
                                                text: I18n.tr("Connected"); color: Theme.green
                                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 4
                                            }
                                        }
                                    }
                                    Text {
                                        text: I18n.tr("Priority") + ": " + modelData.priority
                                              + (modelData.autoconnect ? "" : "  ·  " + I18n.tr("Auto-connect off"))
                                        color: Theme.fgMuted
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 4
                                    }
                                }

                                // Prioridad −/+
                                IconButton {
                                    icon: "󰍴"; diameter: Theme.controlS
                                    onClicked: NetConfig.setWifiPriority(modelData.name, modelData.priority - 1)
                                }
                                Text {
                                    text: modelData.priority; color: Theme.fgDim
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.minimumWidth: Theme.space18 + Theme.space6
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                                }
                                IconButton {
                                    icon: "󰐕"; diameter: Theme.controlS
                                    onClicked: NetConfig.setWifiPriority(modelData.name, modelData.priority + 1)
                                }
                                // Conectar (si no está activa)
                                IconButton {
                                    icon: "󰐊"; diameter: Theme.controlS
                                    visible: !modelData.active
                                    onClicked: NetConfig.connectWifi(modelData.name)
                                }
                                // Olvidar (borrar)
                                IconButton {
                                    icon: "󰩹"; diameter: Theme.controlS
                                    hoverColor: Theme.red
                                    onClicked: NetConfig.forgetWifi(modelData.name)
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: NetConfig.savedWifis.length === 0
                            text: I18n.tr("No saved networks.")
                            color: Theme.fgMuted
                            horizontalAlignment: Text.AlignHCenter
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }

                // ════ TERMINAL ════
                CatPage {
                    id: termCol
                    key: "terminal"

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
            }
        }
    }

    // ═════════ COMPONENTES REUTILIZABLES ═════════════════════
    // Página de una categoría: envoltorio común de cada sección (anclajes al
    // Flickable + animación de entrada/salida por opacidad). El contenido va
    // dentro; 'key' la enlaza con la categoría activa. 'spacing' se puede
    // sobreescribir (por defecto space12).
    component CatPage: ColumnLayout {
        property string key: ""
        anchors { left: parent.left; right: parent.right; top: parent.top
                  leftMargin: Theme.space18; rightMargin: Theme.space18; topMargin: Theme.space18 }
        spacing: Theme.space12
        opacity: cfg.cat === key ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
    }

    // Texto de ayuda/descripción bajo un control: apagado, a lo ancho y con
    // ajuste de línea. Uso: Hint { text: "…" } (o con visible: …).
    component Hint: Text {
        Layout.fillWidth: true
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 3
        wrapMode: Text.WordWrap
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
                        // Barra indicadora "estás aquí" (accent).
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.space4
                            width: Theme.space2
                            height: parent.height * 0.46
                            radius: width / 2
                            color: Theme.accent
                            opacity: parent.sel ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
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
        Switch {
            checked: sr.checked
            offColor: cfg.settingsControl
            offBorderColor: cfg.settingsBorder
            onToggled: sr.toggled()
        }
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
                spacing: Theme.space10
                visible: cardRoot.title !== ""
                Rectangle {
                    visible: cardRoot.glyph !== ""
                    implicitWidth: Theme.controlM
                    implicitHeight: Theme.controlM
                    radius: Theme.pillRadius
                    color: cfg.accentSoft
                    Text {
                        anchors.centerIn: parent
                        text: cardRoot.glyph
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                    }
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

            // Filete bajo la cabecera: separa el título de los controles.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: -Theme.space4
                visible: cardRoot.title !== ""
                implicitHeight: Theme.hairline
                color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.22)
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

    // ── Tarjeta de un monitor: resolución, escala, rotación, on/off ──
    component MonitorCard: SettingsCard {
        id: mc
        property var monitor
        readonly property var inf: Displays.info(monitor)
        readonly property var modes: Displays.modesFor(monitor)
        title: inf.name + (inf.description ? "  ·  " + inf.description : "")
        glyph: "󰍹"

        // Estado en edición (inicializado desde el estado actual).
        property string selMode: mc.defaultMode()
        property real   selScale: inf.scale
        property int    selTransform: inf.transform
        property bool   selEnabled: !inf.disabled

        function defaultMode() {
            const cur = mc.inf.width + "x" + mc.inf.height
            const m = mc.modes.find(x => x.res === cur)
            return m ? m.value : (mc.modes.length ? mc.modes[0].value : "")
        }

        DropdownRow {
            label: I18n.tr("Resolution")
            options: mc.modes
            current: mc.selMode
            onPicked: (v) => mc.selMode = v
        }
        DropdownRow {
            label: I18n.tr("Scale")
            options: [ { text: "100%", value: 1 }, { text: "125%", value: 1.25 },
                       { text: "150%", value: 1.5 }, { text: "175%", value: 1.75 },
                       { text: "200%", value: 2 } ]
            current: mc.selScale
            onPicked: (v) => mc.selScale = v
        }
        SegRow {
            label: I18n.tr("Rotation")
            options: [ { text: "0°", value: 0 }, { text: "90°", value: 1 },
                       { text: "180°", value: 2 }, { text: "270°", value: 3 } ]
            current: mc.selTransform
            onPicked: (v) => mc.selTransform = v
        }
        // Activar/desactivar solo con 2+ monitores (no apagar la única pantalla).
        SwitchRow {
            visible: Displays.monitors.length > 1
            label: I18n.tr("Enabled")
            checked: mc.selEnabled
            onToggled: mc.selEnabled = !mc.selEnabled
        }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            TextButton {
                text: I18n.tr("Apply")
                primary: true
                onClicked: {
                    const parts = mc.selMode.split("@")
                    Displays.apply(({
                        name: mc.inf.name,
                        res: parts[0],
                        refresh: (parts[1] || "").replace("Hz", "").trim(),
                        scale: mc.selScale,
                        transform: mc.selTransform,
                        x: mc.inf.x, y: mc.inf.y,
                        enabled: mc.selEnabled
                    }))
                }
            }
        }
    }

    // ── Orden / alineación: lienzo con arrastrar-y-soltar (estilo Windows) ──
    //  Arrastra cada monitor; al soltar, imanta sus bordes a los de los demás.
    component MonitorArrangement: ColumnLayout {
        id: arr
        spacing: Theme.space8
        Layout.fillWidth: true

        property var  pos: ({})        // name -> {x,y} lógico (en edición)
        property real f: 0.05          // escala lógico→lienzo (congelada al arrastrar)
        property real originX: 0       // lógico que mapea a canvas.pad
        property real originY: 0

        Component.onCompleted: arr.initPos()
        Connections { target: Displays; function onMonitorsChanged() { arr.initPos() } }

        function infoByName(n) {
            const m = Displays.monitors.find(x => Displays.info(x).name === n)
            return m ? Displays.info(m) : null
        }
        function initPos() {
            const p = ({})
            Displays.monitors.forEach(m => { const i = Displays.info(m); p[i.name] = ({ x: i.x, y: i.y }) })
            arr.pos = p
            arr.recalcView()
        }
        function setPos(n, x, y) {
            const p = Object.assign({}, arr.pos)
            p[n] = ({ x: x, y: y })
            arr.pos = p
        }
        // Reajusta escala+origen para encajar el conjunto (NO durante el arrastre).
        function recalcView() {
            let minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9
            Displays.monitors.forEach(m => {
                const i = Displays.info(m); const p = arr.pos[i.name] || ({ x: i.x, y: i.y })
                minX = Math.min(minX, p.x);          minY = Math.min(minY, p.y)
                maxX = Math.max(maxX, p.x + i.width); maxY = Math.max(maxY, p.y + i.height)
            })
            if (minX > maxX) return
            const w = Math.max(1, maxX - minX), h = Math.max(1, maxY - minY)
            const availW = canvas.width - canvas.pad * 2
            const availH = canvas.height - canvas.pad * 2
            arr.f = Math.max(0.001, Math.min(availW / w, availH / h))
            arr.originX = minX - (availW / arr.f - w) / 2     // centrar
            arr.originY = minY - (availH / arr.f - h) / 2
        }
        // Imán a los bordes de otros monitores al soltar.
        function snap(n) {
            const me = arr.infoByName(n); if (!me) return
            const p = arr.pos[n]; let lx = p.x, ly = p.y
            const th = Math.max(40, me.width * 0.06)
            Displays.monitors.forEach(m => {
                const o = Displays.info(m); if (o.name === n) return
                const op = arr.pos[o.name] || ({ x: o.x, y: o.y })
                if (Math.abs(lx - (op.x + o.width)) < th) lx = op.x + o.width             // a su derecha
                if (Math.abs((lx + me.width) - op.x) < th) lx = op.x - me.width            // a su izquierda
                if (Math.abs(lx - op.x) < th) lx = op.x                                    // alinear izq.
                if (Math.abs(ly - op.y) < th) ly = op.y                                    // alinear arriba
                if (Math.abs((ly + me.height) - (op.y + o.height)) < th) ly = op.y + o.height - me.height  // abajo
                if (Math.abs(ly - (op.y + o.height)) < th) ly = op.y + o.height            // debajo
                if (Math.abs((ly + me.height) - op.y) < th) ly = op.y - me.height          // encima
            })
            arr.setPos(n, Math.round(lx), Math.round(ly))
            arr.recalcView()
        }

        Rectangle {
            id: canvas
            Layout.fillWidth: true
            implicitHeight: Theme.dp(190)
            radius: Theme.barRadius
            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5)
            border.width: Theme.hairline
            border.color: cfg.settingsBorder
            clip: true
            readonly property real pad: Theme.space16
            onWidthChanged: arr.recalcView()
            onHeightChanged: arr.recalcView()

            Repeater {
                model: Displays.monitors
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    readonly property var i: Displays.info(modelData)
                    readonly property string mName: i.name
                    readonly property var p: arr.pos[mName] || ({ x: i.x, y: i.y })
                    width: i.width * arr.f
                    height: i.height * arr.f
                    x: canvas.pad + (p.x - arr.originX) * arr.f
                    y: canvas.pad + (p.y - arr.originY) * arr.f
                    radius: Theme.space4
                    color: dragMa.active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.34)
                                         : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                    border.width: Math.max(1, Theme.dp(2)); border.color: Theme.accent
                    z: dragMa.active ? 2 : 1

                    Column {
                        anchors.centerIn: parent
                        spacing: 0
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.mName
                               color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 4; font.bold: true }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.i.width + "×" + tile.i.height
                               color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 6 }
                    }

                    MouseArea {
                        id: dragMa
                        anchors.fill: parent
                        cursorShape: Qt.SizeAllCursor
                        property real grabDX: 0
                        property real grabDY: 0
                        property bool active: false
                        onPressed: (mouse) => {
                            const c = mapToItem(canvas, mouse.x, mouse.y)
                            dragMa.grabDX = c.x - tile.x
                            dragMa.grabDY = c.y - tile.y
                            dragMa.active = true
                        }
                        onPositionChanged: (mouse) => {
                            if (!dragMa.active) return
                            const c = mapToItem(canvas, mouse.x, mouse.y)
                            const lx = arr.originX + (c.x - dragMa.grabDX - canvas.pad) / arr.f
                            const ly = arr.originY + (c.y - dragMa.grabDY - canvas.pad) / arr.f
                            arr.setPos(tile.mName, lx, ly)
                        }
                        onReleased: { dragMa.active = false; arr.snap(tile.mName) }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space8
            Hint {
                text: I18n.tr("Drag monitors to arrange them")
            }
            TextButton {
                text: I18n.tr("Apply layout")
                primary: true
                onClicked: {
                    Displays.monitors.forEach(m => {
                        const i = Displays.info(m)
                        const p = arr.pos[i.name] || ({ x: i.x, y: i.y })
                        Displays.apply(({
                            name: i.name, res: i.width + "x" + i.height,
                            refresh: Number(i.refresh).toFixed(2), scale: i.scale,
                            transform: i.transform, x: p.x, y: p.y, enabled: !i.disabled
                        }))
                    })
                }
            }
        }
    }
}
