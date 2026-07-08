import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Components
import qs.Config
import qs.Panels.SettingsPages
import qs.Services

// Ventana de Ajustes: ventana XDG real (FloatingWindow), así que Hyprland la
// gestiona como un programa (mosaico, redimensionar, esquinas del compositor).
// Escribe en el singleton Settings. Cada categoría vive en Panels/SettingsPages/
// y solo se instancia la activa (un Loader).
FloatingWindow {
    id: cfg

    title: I18n.tr("Settings") + " · Quickshell"
    color: settingsBase
    implicitWidth: Theme.dp(940)
    implicitHeight: Theme.dp(620)
    minimumSize: Qt.size(Theme.dp(680), Theme.dp(460))

    visible: Globals.settingsOpen

    // Paleta compartida con las páginas (ver SettingsPages/SettingsPalette.qml).
    readonly property color settingsBase: SettingsPalette.settingsBase
    readonly property color settingsCard: SettingsPalette.settingsCard
    readonly property color settingsControl: SettingsPalette.settingsControl
    readonly property color settingsHover: SettingsPalette.settingsHover
    readonly property color settingsLine: SettingsPalette.settingsLine
    readonly property color settingsBorder: SettingsPalette.settingsBorder
    readonly property color accentSoft: SettingsPalette.accentSoft
    // Resalte de hover de la navegación, tintado con el acento activo (el
    // básico o el del tema, según lo elegido en la página de Tema). Solo aquí,
    // en el panel de Ajustes.
    readonly property color settingsAccentHover: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b,
                                                         Theme.isDark ? 0.13 : 0.18)

    property string cat: "theme"
    property int navResetToken: 0
    onVisibleChanged: {
        if (visible) {
            cat = "theme"
            navResetToken++
        }
        else if (Globals.settingsOpen) Globals.settingsOpen = false   // cerrada por Hyprland
    }

    // Reabrir cuando ya está abierta. Globals.toggleSettings() pide esto si la
    // ventana existe: si está en este workspace se cierra (toggle); si está en
    // otro, se trae al actual y se enfoca en vez de cerrarla.
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
        // Pestaña fija (fuera de los grupos): su cabecera usa el nombre del
        // proyecto como antetítulo.
        idx["about"] = { label: I18n.tr("About"), glyph: "󰋼", group: "Quickshell" }
        return idx
    }
    readonly property var activeItem: itemIndex[cat] || ({ label: "", glyph: "󰒓", group: "" })
    readonly property string catLabel:      activeItem.label
    readonly property string catGroupLabel: activeItem.group
    readonly property string catGlyph:      activeItem.glyph

    // Disposición general
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Barra lateral
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

                // Separador navegación → pie fijo.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space2
                    implicitHeight: Theme.hairline
                    color: cfg.settingsLine
                }

                // Pestaña fija: About (siempre al pie, fuera de los grupos).
                Rectangle {
                    id: aboutNav
                    readonly property bool sel: cfg.cat === "about"
                    Layout.fillWidth: true
                    implicitHeight: Theme.rowM
                    radius: Theme.pillRadius
                    color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                               : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius
                        color: cfg.settingsAccentHover
                        opacity: aboutMa.containsMouse && !aboutNav.sel ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                    }
                    // Barra indicadora "estás aquí".
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.space4
                        width: Theme.space2
                        height: parent.height * 0.46
                        radius: width / 2
                        color: Theme.accent
                        opacity: aboutNav.sel ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space10
                        anchors.rightMargin: Theme.space10
                        spacing: Theme.space8
                        Text {
                            text: "󰋼"
                            color: aboutNav.sel ? Theme.accent : Theme.fgDim
                            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("About")
                            color: aboutNav.sel ? Theme.fg : Theme.fgDim
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                            font.bold: aboutNav.sel
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: aboutMa
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cfg.cat = "about"
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

        // Contenido
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
                contentHeight: (pageLoader.item ? pageLoader.item.implicitHeight : 0) + Theme.space18 * 2
                boundsBehavior: Flickable.StopAtBounds

                // Solo se instancia la página ACTIVA. Así los desplegables
                // pesados (p. ej. options: Fonts.list.map(...)) se evalúan
                // únicamente al entrar en su categoría.
                Loader {
                    id: pageLoader
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: Theme.space18; rightMargin: Theme.space18; topMargin: Theme.space18 }
                    source: {
                        switch (cfg.cat) {
                        case "font":      return "SettingsPages/FontPage.qml"
                        case "terminal":  return "SettingsPages/TerminalPage.qml"
                        case "wallpaper": return "SettingsPages/WallpaperPage.qml"
                        case "bar":       return "SettingsPages/BarPage.qml"
                        case "clock":     return "SettingsPages/ClockPage.qml"
                        case "displays":  return "SettingsPages/DisplaysPage.qml"
                        case "network":   return "SettingsPages/NetworkPage.qml"
                        case "weather":   return "SettingsPages/WeatherPage.qml"
                        case "notif":     return "SettingsPages/NotifPage.qml"
                        case "about":     return "SettingsPages/AboutPage.qml"
                        default:          return "SettingsPages/ThemePage.qml"
                        }
                    }
                    // Fundido de entrada al cargar cada página.
                    onLoaded: { flick.contentY = 0; pageFadeIn.restart() }
                    NumberAnimation {
                        id: pageFadeIn
                        target: pageLoader; property: "opacity"
                        from: 0; to: 1
                        duration: Theme.animNormal
                    }
                }
            }
        }
    }

    // Componentes de la ventana. Los bloques que reutilizan las páginas
    // (SettingsCard, SwitchRow, SegRow, ColorRow, Hint, MonitorCard,
    // MonitorArrangement) viven en Panels/SettingsPages/; aquí solo la nav lateral.

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
                color: cfg.settingsAccentHover
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
                            color: cfg.settingsAccentHover
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
}
