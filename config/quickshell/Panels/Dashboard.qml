import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import qs.Components
import qs.Config
import qs.Services

// ─────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────
Popout {
    id: dash
    ns: "qs-dashboard"
    cardWidth: 460
    cardMinWidth: 360
    alignCenter: true
    shown: Globals.dashboardOpen

    readonly property var tabKeys: ["overview", "music", "wallpaper"]
    property string tab: "overview"
    readonly property int activeIndex: tabKeys.indexOf(tab)
    readonly property int tabAnim: 260   // duración unificada del cambio de pestaña

    SystemClock { id: clock; precision: SystemClock.Seconds }
    readonly property string timeFormat: (Settings.clock24h ? "HH:mm" : "hh:mm")
        + (Settings.clockShowSeconds ? ":ss" : "") + (Settings.clock24h ? "" : " AP")

    // ── Selección del reproductor activo ─────────────────────
    readonly property var players: Mpris.players?.values ?? []
    readonly property var player: {
        if (players.length === 0) return null
        for (let i = 0; i < players.length; i++)
            if (players[i].isPlaying) return players[i]
        return players[0]
    }
    readonly property bool hasMedia: player !== null

    property real displayPos: 0
    Timer {
        running: dash.shown && (dash.player?.isPlaying ?? false)
        interval: 1000; repeat: true
        onTriggered: dash.displayPos = dash.player?.position ?? 0
    }
    Connections {
        target: dash.player
        ignoreUnknownSignals: true
        function onPositionChanged() { dash.displayPos = dash.player?.position ?? 0 }
        function onTrackTitleChanged() { dash.displayPos = 0 }
        function onPlaybackStateChanged() { dash.displayPos = dash.player?.position ?? 0 }
    }

    function fmt(sec) {
        if (!sec || sec < 0) return "0:00"
        const s = Math.floor(sec % 60)
        const m = Math.floor(sec / 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    onShownChanged: if (shown) {
        tab = "overview"
        Wallpaper.refresh()
        Weather.refresh()
    }

    // ── Cabecera: hora + fecha + clima compacto ──────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 0

        Item { Layout.fillWidth: true }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.space12

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDateTime(clock.date, dash.timeFormat)
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(38)
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: {
                        const d = clock.date
                        if (Settings.language === "en")
                            return I18n.dayName(d.getDay()) + ", " + I18n.monthName(d.getMonth(), true) + " " + d.getDate()
                        return I18n.dayName(d.getDay()) + ", " + d.getDate()
                             + " de " + I18n.monthName(d.getMonth(), false)
                    }
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }

            RowLayout {
                visible: Weather.enabled && Weather.ready
                Layout.alignment: Qt.AlignVCenter
                spacing: Theme.space6
                Text {
                    text: Weather.icon
                    color: Theme.yellow
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 8
                }
                Text {
                    text: Weather.temp
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 4
                    font.bold: true
                }
            }
        }

        Item { Layout.fillWidth: true }
    }

    // ── Barra de pestañas ────────────────────────────────────
    Rectangle {
        id: tabBar
        Layout.fillWidth: true
        implicitHeight: Theme.rowS
        radius: Theme.pillRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5)

        // Ancho de cada ranura (3 botones, márgenes y huecos de space4).
        readonly property real slotW: (width - Theme.space4 * 4) / 3

        // Indicador deslizante: resalta solo la pestaña activa y se
        // desliza hasta ella (sin sombras residuales por botón).
        Rectangle {
            y: Theme.space4
            height: parent.height - Theme.space4 * 2
            width: tabBar.slotW
            x: Theme.space4 + dash.activeIndex * (tabBar.slotW + Theme.space4)
            radius: Theme.pillRadius - Theme.space2
            color: Theme.surfaceHi
            Behavior on x { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.space4
            spacing: Theme.space4
            TabBtn { label: I18n.tr("Overview"); glyph: "󰕮"; key: "overview" }
            TabBtn { label: I18n.tr("Music");  glyph: "󰝚"; key: "music" }
            TabBtn { label: I18n.tr("Wallpapers");  glyph: "󰋩"; key: "wallpaper" }
        }
    }

    // ── Contenedor de páginas (crossfade + deslizamiento) ────
    Item {
        id: pages
        Layout.fillWidth: true
        readonly property Item active: dash.tab === "music" ? musicPage
                                      : dash.tab === "wallpaper" ? wallpaperPage
                                      : overviewPage
        Layout.preferredHeight: active ? active.implicitHeight : 0
        Behavior on Layout.preferredHeight {
            NumberAnimation { duration: dash.tabAnim; easing.type: Easing.InOutCubic }
        }
        clip: true

        // Desplazamiento horizontal según la posición de la pestaña.
        readonly property int slide: Theme.dp(18)

        // ═════════ PÁGINA: RESUMEN ═══════════════════════════
        ColumnLayout {
            id: overviewPage
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: Theme.space12
            opacity: dash.tab === "overview" ? 1 : 0
            visible: opacity > 0.01
            transform: Translate {
                x: (0 - dash.activeIndex) * pages.slide
                Behavior on x { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }

            // Clima.
            Rectangle {
                Layout.fillWidth: true
                visible: Weather.enabled && Weather.ready
                implicitHeight: wRow.implicitHeight + Theme.space12 * 2
                radius: Theme.pillRadius
                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.45)
                border.width: Theme.hairline
                border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)

                RowLayout {
                    id: wRow
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: Theme.space14; rightMargin: Theme.space14 }
                    spacing: Theme.space12

                    Text {
                        text: Weather.icon
                        color: Theme.yellow
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize + 22
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: Weather.temp + "  ·  " + Weather.condition
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 1
                            font.bold: true; elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: Weather.location
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            elide: Text.ElideRight
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: I18n.tr("Feels like %1").arg(Weather.feels)
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: I18n.tr("Humidity %1").arg(Weather.humidity)
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                }
            }

            // Mini-reproductor.
            Rectangle {
                Layout.fillWidth: true
                visible: dash.hasMedia
                implicitHeight: miniRow.implicitHeight + Theme.space12 * 2
                radius: Theme.pillRadius
                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.55)
                border.width: Theme.hairline
                border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)

                RowLayout {
                    id: miniRow
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: Theme.space12; rightMargin: Theme.space12 }
                    spacing: Theme.space12

                    Rectangle {
                        implicitWidth: Theme.tileM; implicitHeight: Theme.tileM
                        radius: Theme.space6; color: Theme.bgAlt; clip: true
                        Image {
                            anchors.fill: parent
                            source: dash.player?.trackArtUrl ?? ""
                            visible: status === Image.Ready
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: Theme.tileM * 2; sourceSize.height: Theme.tileM * 2
                            asynchronous: true
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: (dash.player?.trackArtUrl ?? "") === ""
                            text: "󰝚"; color: Theme.fgMuted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize + 6
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: dash.player?.trackTitle || I18n.tr("Untitled")
                            color: Theme.fg
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                            font.bold: true; elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: dash.player?.trackArtist || dash.player?.identity || ""
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                            elide: Text.ElideRight
                        }
                    }
                    MediaBtn {
                        glyph: (dash.player?.isPlaying ?? false) ? "󰏤" : "󰐊"
                        size: Theme.controlM; primary: true
                        enabled: dash.player?.canTogglePlaying ?? false
                        onTapped: dash.player?.togglePlaying()
                    }
                    MediaBtn {
                        glyph: "󰒭"; size: Theme.controlM
                        enabled: dash.player?.canGoNext ?? false
                        onTapped: dash.player?.next()
                    }
                }
            }

            // Calendario.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: calBox.implicitHeight + Theme.space14 * 2
                radius: Theme.pillRadius
                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.45)
                border.width: Theme.hairline
                border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)

                Calendar {
                    id: calBox
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: Theme.space14; rightMargin: Theme.space14 }
                }
            }
        }

        // ═════════ PÁGINA: MÚSICA ════════════════════════════
        ColumnLayout {
            id: musicPage
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: Theme.space12
            opacity: dash.tab === "music" ? 1 : 0
            visible: opacity > 0.01
            transform: Translate {
                x: (1 - dash.activeIndex) * pages.slide
                Behavior on x { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }

            // Sin reproducción.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space18; Layout.bottomMargin: Theme.space18
                visible: !dash.hasMedia
                spacing: Theme.space8
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "󰝛"; color: Theme.fgMuted
                    font.family: Theme.fontFamily; font.pixelSize: Theme.sp(48)
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: I18n.tr("No active playback")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                }
            }

            // Reproductor grande.
            ColumnLayout {
                Layout.fillWidth: true
                visible: dash.hasMedia
                spacing: Theme.space12

                RowLayout {
                    Layout.fillWidth: true
                    visible: dash.players.length > 1
                    spacing: Theme.space6
                    Repeater {
                        model: dash.players
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool sel: modelData === dash.player
                            implicitWidth: chipText.implicitWidth + Theme.space12
                            implicitHeight: Theme.controlS
                            radius: height / 2
                            color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                       : Theme.surface
                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: modelData.identity || I18n.tr("Player")
                                color: parent.sel ? Theme.accent : Theme.fgDim
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                                font.bold: parent.sel
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: Math.min(dash.effectiveCardWidth - Theme.space16 * 2, Theme.dp(220))
                    implicitHeight: implicitWidth
                    radius: Theme.space12; color: Theme.bgAlt; clip: true
                    Image {
                        anchors.fill: parent
                        source: dash.player?.trackArtUrl ?? ""
                        visible: status === Image.Ready
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: Theme.dp(440); sourceSize.height: Theme.dp(440)
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: (dash.player?.trackArtUrl ?? "") === ""
                        text: "󰝚"; color: Theme.fgMuted
                        font.family: Theme.fontFamily; font.pixelSize: Theme.sp(64)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2
                    Text {
                        Layout.fillWidth: true
                        text: dash.player?.trackTitle || I18n.tr("Untitled")
                        color: Theme.fg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize + 4
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: dash.player?.trackArtist || dash.player?.identity || ""
                        color: Theme.fgDim
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: (dash.player?.trackAlbum ?? "") !== ""
                        text: dash.player?.trackAlbum ?? ""
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
                        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: (dash.player?.lengthSupported ?? false) && (dash.player?.length ?? 0) > 0
                    spacing: Theme.space2
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6; radius: 3; color: Theme.surface
                        Rectangle {
                            height: parent.height; radius: 3
                            width: parent.width * Math.max(0, Math.min(1,
                                dash.displayPos / Math.max(1, dash.player?.length ?? 1)))
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 250 } }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: dash.fmt(dash.displayPos)
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                        }
                        Text {
                            text: dash.fmt(dash.player?.length ?? 0)
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.space18
                    MediaBtn {
                        glyph: "󰒮"; size: Theme.controlL
                        enabled: dash.player?.canGoPrevious ?? false
                        onTapped: dash.player?.previous()
                    }
                    MediaBtn {
                        glyph: (dash.player?.isPlaying ?? false) ? "󰏤" : "󰐊"
                        size: Theme.controlL + Theme.dp(12); primary: true
                        enabled: dash.player?.canTogglePlaying ?? false
                        onTapped: dash.player?.togglePlaying()
                    }
                    MediaBtn {
                        glyph: "󰒭"; size: Theme.controlL
                        enabled: dash.player?.canGoNext ?? false
                        onTapped: dash.player?.next()
                    }
                }
            }
        }

        // ═════════ PÁGINA: FONDOS ════════════════════════════
        ColumnLayout {
            id: wallpaperPage
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: Theme.space8
            opacity: dash.tab === "wallpaper" ? 1 : 0
            visible: opacity > 0.01
            transform: Translate {
                x: (2 - dash.activeIndex) * pages.slide
                Behavior on x { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Wallpapers title")
                    color: Theme.fgDim
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                }
                Text {
                    text: I18n.tr("%1 wallpapers").arg(Wallpaper.list.length)
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                }
                // Recargar lista.
                Rectangle {
                    implicitWidth: Theme.controlS; implicitHeight: Theme.controlS
                    radius: width / 2
                    color: refMa.containsMouse ? Theme.surfaceHi : Theme.surface
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        anchors.centerIn: parent; text: "󰑐"
                        color: refMa.containsMouse ? Theme.accent : Theme.fgDim
                        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize - 1
                    }
                    MouseArea {
                        id: refMa
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Wallpaper.refresh()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space12; Layout.bottomMargin: Theme.space12
                visible: Wallpaper.list.length === 0
                text: I18n.tr("No images in wallpaper folders.") + "\n"
                      + Settings.wallpaperDirs.map(d => d.replace(Settings.home, "~")).join(" · ")
                color: Theme.fgMuted
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
                horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
            }

            GridView {
                id: wpGrid
                Layout.fillWidth: true
                visible: Wallpaper.list.length > 0
                implicitHeight: Math.min(Theme.dp(320), contentHeight)
                cellWidth: Math.floor(width / 3)
                cellHeight: Math.floor(cellWidth * 0.66)
                clip: true
                model: Wallpaper.list
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    required property var modelData
                    width: wpGrid.cellWidth; height: wpGrid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Theme.space4
                        readonly property bool active: Wallpaper.current === modelData
                        radius: Theme.space8; color: Theme.bgAlt; clip: true
                        border.width: active ? 2 : (wpMa.containsMouse ? 1 : 0)
                        border.color: active ? Theme.accent : Theme.overlay

                        Image {
                            anchors.fill: parent
                            anchors.margins: parent.active ? 2 : 0
                            source: "file://" + parent.parent.modelData
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: Theme.dp(180); sourceSize.height: Theme.dp(120)
                            asynchronous: true
                        }
                        Rectangle {
                            visible: parent.active
                            anchors { top: parent.top; right: parent.right; margins: Theme.space4 }
                            width: Theme.dp(18); height: Theme.dp(18); radius: width / 2
                            color: Theme.accent
                            Text {
                                anchors.centerIn: parent; text: "󰄬"; color: Theme.bg
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                            }
                        }
                        MouseArea {
                            id: wpMa
                            anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Wallpaper.apply(parent.parent.modelData)
                        }
                    }
                }
            }
        }
    }

    // ── Componentes reutilizables ────────────────────────────
    component TabBtn: Item {
        property string label: ""
        property string glyph: ""
        property string key: ""
        readonly property bool sel: dash.tab === key
        Layout.fillWidth: true
        Layout.fillHeight: true
        RowLayout {
            anchors.centerIn: parent
            spacing: Theme.space6
            Text {
                text: parent.parent.glyph
                color: parent.parent.sel ? Theme.accent : Theme.fgMuted
                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                Behavior on color { ColorAnimation { duration: dash.tabAnim } }
            }
            Text {
                text: parent.parent.label
                color: parent.parent.sel ? Theme.fg : Theme.fgMuted
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                font.bold: parent.parent.sel
                Behavior on color { ColorAnimation { duration: dash.tabAnim } }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: dash.tab = parent.key
        }
    }

    component MediaBtn: Rectangle {
        property string glyph: ""
        property int size: Theme.controlM
        property bool primary: false
        signal tapped()
        implicitWidth: size; implicitHeight: size
        radius: width / 2
        opacity: enabled ? 1 : 0.35
        color: primary ? Theme.accent
              : (mbMa.containsMouse ? Theme.surfaceHi : Theme.surface)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Text {
            anchors.centerIn: parent
            text: parent.glyph
            color: parent.primary ? Theme.bg
                  : (mbMa.containsMouse ? Theme.accent : Theme.fgDim)
            font.family: Theme.fontFamily
            font.pixelSize: parent.primary ? Theme.iconSize + 5 : Theme.iconSize + 1
        }
        MouseArea {
            id: mbMa
            anchors.fill: parent
            enabled: parent.enabled
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: parent.tapped()
        }
    }
}
