import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.Components
import qs.Config
import qs.Services

// Panel resumen: clima + sistema arriba, reloj/calendario/anillos en el
// centro y mini-reproductor abajo (solo si hay reproducción).
Popout {
    id: dash
    ns: "qs-dashboard"
    cardWidth: 680
    cardMinWidth: 520
    alignCenter: true
    shown: Globals.dashboardOpen

    readonly property var tabKeys: ["overview", "system", "music", "wallpaper"]
    property string tab: "overview"
    readonly property int activeIndex: tabKeys.indexOf(tab)
    readonly property int tabAnim: 260   // duración unificada del cambio de pestaña
    // Lado de los botones del riel; el indicador deslizante lo comparte.
    readonly property int railTabSize: Theme.dp(36)

    // Con el panel oculto basta precisión de minuto (sin tick por segundo).
    SystemClock { id: clock; precision: dash.shown ? SystemClock.Seconds : SystemClock.Minutes }
    // Selección del reproductor activo
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
        // Solo con el panel a la vista: si no, cada avance de posición MPRIS
        // re-evaluaba las barras de progreso de un panel oculto (por monitor).
        enabled: dash.shown
        ignoreUnknownSignals: true
        function onPositionChanged() { dash.displayPos = dash.player?.position ?? 0 }
        function onTrackTitleChanged() { dash.displayPos = 0 }
        function onPlaybackStateChanged() { dash.displayPos = dash.player?.position ?? 0 }
    }

    // Tasa de red legible: KB/s hasta 1 MB/s, MB/s a partir de ahí.
    function fmtRate(kb) {
        if (kb >= 1024) return (kb / 1024).toFixed(1) + " MB/s"
        return Math.round(kb) + " KB/s"
    }

    function fmt(sec) {
        if (!sec || sec < 0) return "0:00"
        const s = Math.floor(sec % 60)
        const m = Math.floor(sec / 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    onShownChanged: if (shown) {
        tab = "overview"
        displayPos = player?.position ?? 0   // ponte al día (Connections inactivo en oculto)
        // Solo re-escanea las carpetas de fondos si el último escaneo es viejo:
        // refresh() en cada apertura reseteaba el GridView (modelo = array
        // plano) y re-pedía todas las miniaturas.
        Wallpaper.refreshIfStale(5 * 60 * 1000)
        Weather.refreshIfStale(10 * 60 * 1000)
    }

    // Riel vertical a altura completa: pestañas arriba (solo iconos, con
    // indicador deslizante) y el acceso a Ajustes anclado abajo, separado por
    // un hueco elástico. El contenido va a su derecha.
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space12

        Rectangle {
            id: tabRail
            Layout.fillHeight: true
            implicitWidth: Theme.dp(48)
            radius: Theme.pillRadius
            color: Theme.withAlpha(Theme.surface, 0.45)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.space6
                spacing: Theme.space6

                Item {
                    id: railTabs
                    Layout.fillWidth: true
                    implicitHeight: railTabsCol.implicitHeight

                    Rectangle {
                        width: parent.width
                        height: dash.railTabSize
                        y: dash.activeIndex * (dash.railTabSize + railTabsCol.spacing)
                        radius: Theme.pillRadius - Theme.space2
                        color: Theme.surfaceHi
                        Behavior on y { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }
                    }

                    ColumnLayout {
                        id: railTabsCol
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        spacing: Theme.space6
                        TabBtn { Layout.fillWidth: true; glyph: "\u{f056e}"; key: "overview" }
                        TabBtn { Layout.fillWidth: true; glyph: "\u{f0ee0}"; key: "system" }
                        TabBtn { Layout.fillWidth: true; glyph: "\u{f075a}"; key: "music" }
                        TabBtn { Layout.fillWidth: true; glyph: "\u{f02e9}"; key: "wallpaper" }
                    }
                }

                Item { Layout.fillHeight: true }

                // Atajos a otros paneles: mismos destinos que la barra, pero a
                // mano desde el panel. Abrir cualquiera cierra este (openPanel
                // es de plaza única), así que no hace falta cerrar a mano.
                RailBtn { icon: "\u{f009a}"; onClicked: Globals.toggleNotifCenter() }
                RailBtn { icon: "󰅌"; onClicked: Globals.toggleClipboard() }
                RailBtn { icon: "󰍛"; onClicked: Globals.toggleSysMon() }
                RailBtn { icon: "󰌾"; onClicked: Globals.runPowerAction("lock") }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.space4
                    Layout.rightMargin: Theme.space4
                    implicitHeight: Theme.hairline
                    color: Theme.withAlpha(Theme.overlay, 0.4)
                }

                RailBtn {
                    icon: "\u{f0493}"
                    onClicked: {
                        Globals.closeAll()
                        Globals.toggleSettings()
                    }
                }
            }
        }

    // Contenedor de páginas (crossfade + deslizamiento)
    Item {
        id: pages
        Layout.fillWidth: true
        // Altura ÚNICA para todas las pestañas: la de la página más alta.
        // Así el panel no cambia de tamaño al cambiar de pestaña y el riel
        // (con el botón de Ajustes abajo) nunca se queda sin sitio.
        Layout.preferredHeight: Math.max(overviewPage.implicitHeight, systemPage.implicitHeight,
                                         musicPage.implicitHeight, wallpaperPage.implicitHeight)
        Behavior on Layout.preferredHeight {
            NumberAnimation { duration: dash.tabAnim; easing.type: Easing.InOutCubic }
        }
        clip: true

        // Desplazamiento horizontal según la posición de la pestaña.
        readonly property int slide: Theme.dp(18)

        // Página: resumen
        ColumnLayout {
            id: overviewPage
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: Theme.space10
            opacity: dash.tab === "overview" ? 1 : 0
            visible: opacity > 0.01
            transform: Translate {
                x: (0 - dash.activeIndex) * pages.slide
                Behavior on x { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }

            // Dos columnas para ganar anchura sin crecer hacia abajo: a la
            // izquierda hora/clima, sistema, acciones rápidas y reproductor;
            // a la derecha el calendario a toda altura.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space10

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: Theme.space10

                    // Hora grande y clima (con sensación y humedad), sobre un
                    // degradado suave de acento que distingue la tarjeta.
                    OverviewCard {
                        implicitHeight: Theme.dp(92)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.16 : 0.20) }
                            GradientStop { position: 1.0; color: Theme.withAlpha(Theme.surface, 0.42) }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space16
                            anchors.rightMargin: Theme.space16
                            spacing: Theme.space12

                            ColumnLayout {
                                spacing: 0
                                Text {
                                    text: Qt.formatDateTime(clock.date, Settings.clock24h ? "HH:mm" : "hh:mm")
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.sp(36)
                                    font.bold: true
                                }
                                Text {
                                    readonly property string day:
                                        clock.date.toLocaleDateString(I18n.locale(), "dddd d MMMM")
                                    text: day.charAt(0).toUpperCase() + day.slice(1)
                                          + (!Settings.clock24h ? " \u00b7 " + Qt.formatDateTime(clock.date, "AP") : "")
                                          + (Settings.clockShowSeconds ? " \u00b7 " + Qt.formatDateTime(clock.date, "ss") + "s" : "")
                                    color: Theme.fgMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                    font.bold: true
                                }
                            }
                            // Clima a la derecha DENTRO del espacio sobrante:
                            // icono+temperatura arriba y la condición debajo,
                            // alineada a la derecha, en hasta dos líneas con
                            // elipsis. Antes tenía ancho fijo (150dp) y en la
                            // tarjeta estrecha desbordaba sobre el calendario
                            // con textos largos ("Parcialmente nublado").
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: Weather.enabled && Weather.ready
                                spacing: 0
                                RowLayout {
                                    Layout.alignment: Qt.AlignRight
                                    spacing: Theme.space6
                                    Text {
                                        text: Weather.icon
                                        color: Theme.yellow
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.sp(24)
                                    }
                                    Text {
                                        text: Weather.temp
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize + 5
                                        font.bold: true
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    text: Weather.condition
                                    color: Theme.fgMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // El tiempo: cabecera con la ubicación y los detalles (sensación y
            // humedad), y el pronóstico diario con HOY destacado en acento.
            OverviewCard {
                visible: Weather.enabled && Weather.ready && Weather.forecast.length > 0
                         && Settings.weatherShowForecast
                implicitHeight: wxCol.implicitHeight + Theme.space12 * 2

                ColumnLayout {
                    id: wxCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: Theme.space12; rightMargin: Theme.space12 }
                    spacing: Theme.space6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space6
                        Text {
                            text: Weather.icon
                            color: Theme.yellow
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.iconSize
                        }
                        Text {
                            Layout.fillWidth: true
                            text: Weather.location
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            readonly property var bits: [
                                Settings.weatherShowDetails ? "ST " + Weather.feels : "",
                                Settings.weatherShowDetails ? "\u{f058e} " + Weather.humidity : "",
                                Settings.weatherShowWind && Weather.windSpeed !== ""
                                    ? "\u{f059e} " + Weather.windSpeed : ""
                            ].filter(b => b !== "")
                            visible: bits.length > 0
                            text: bits.join("  \u00b7  ")
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }

                    RowLayout {
                        id: wxDivider
                        Layout.fillWidth: true
                        spacing: Theme.space8
                        readonly property bool sun: Settings.weatherShowSun && Weather.sunrise !== ""
                        Text {
                            visible: wxDivider.sun
                            text: "\u{f059c} " + Weather.sunrise
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.hairline
                            color: Theme.withAlpha(Theme.overlay, 0.25)
                        }
                        Text {
                            visible: wxDivider.sun
                            text: "\u{f059b} " + Weather.sunset
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space4

                        Repeater {
                            model: Weather.forecast
                            delegate: Rectangle {
                                id: dayCell
                                required property var modelData
                                required property int index
                                readonly property bool today: index === 0
                                // Mismo peso de anchura para las cinco celdas
                                // (sin depender del contenido) y márgenes
                                // idénticos arriba y abajo: la pastilla de hoy
                                // queda simétrica por construcción.
                                Layout.fillWidth: true
                                Layout.preferredWidth: 100
                                implicitHeight: dayCol.implicitHeight + Theme.space6 * 2
                                radius: Theme.dp(10)
                                color: today ? Theme.withAlpha(Theme.accent, Theme.isDark ? 0.16 : 0.22)
                                             : "transparent"

                                // Máxima y mínima apiladas: en celdas de ~60 px
                                // el par en horizontal quedaba al límite.
                                ColumnLayout {
                                    id: dayCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.dp(1)
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: dayCell.modelData.label
                                        color: dayCell.today ? Theme.fg : Theme.fgMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 4
                                        font.bold: dayCell.today
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: dayCell.modelData.glyph
                                        color: Theme.yellow
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.iconSize + 1
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: dayCell.modelData.max + "\u00b0"
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 2
                                        font.bold: true
                                    }
                                    Text {
                                        visible: Settings.weatherShowRain
                                                 && dayCell.modelData.rain !== undefined
                                                 && dayCell.modelData.rain >= 0
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "\u{f058c} " + dayCell.modelData.rain + "%"
                                        color: Theme.cyan
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 4
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: dayCell.modelData.min + "\u00b0"
                                        color: Theme.fgMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 3
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Estado del sistema: CPU, RAM y disco en fila.
                    OverviewCard {
                        implicitHeight: Theme.dp(92)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space10
                            anchors.rightMargin: Theme.space10
                            spacing: 0

                            StatCluster { glyph: "\u{f0ee0}"; label: "CPU"
                                value: SysMon.cpu / 100; percent: Math.round(SysMon.cpu) }
                            StatCluster { glyph: "\u{f035b}"; label: "RAM"
                                value: SysMon.memPercent / 100; percent: Math.round(SysMon.memPercent) }
                            StatCluster { glyph: "\u{f02ca}"; label: I18n.tr("Disk")
                                value: SysMon.diskPercent / 100; percent: Math.round(SysMon.diskPercent) }
                        }
                    }

                    // Acciones rápidas: conmutadores de un toque + captura.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space8

                        QuickTile {
                            glyph: "\u{f009b}"
                            active: Globals.dnd
                            onTapped: Globals.dnd = !Globals.dnd
                        }
                        QuickTile {
                            glyph: "\u{f0176}"
                            active: Settings.caffeine
                            onTapped: Settings.caffeine = !Settings.caffeine
                        }
                        QuickTile {
                            glyph: "\u{f0594}"
                            active: Settings.darkMode
                            onTapped: Settings.darkMode = !Settings.darkMode
                        }
                        QuickTile {
                            glyph: "\u{f0100}"
                            onTapped: {
                                Globals.closeAll()
                                ScreenCapture.openToolbar(false)
                            }
                        }
                    }

            // Mini-reproductor con línea de progreso
            OverviewCard {
                visible: dash.hasMedia
                implicitHeight: miniCol.implicitHeight + Theme.space12 * 2

                ColumnLayout {
                    id: miniCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: Theme.space12; rightMargin: Theme.space12 }
                    spacing: Theme.space8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space12

                        ClippingRectangle {
                            implicitWidth: Theme.tileM; implicitHeight: Theme.tileM
                            radius: Theme.space8; color: Theme.bgAlt
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

                    Rectangle {
                        Layout.fillWidth: true
                        visible: (dash.player?.lengthSupported ?? false) && (dash.player?.length ?? 0) > 0
                        implicitHeight: Theme.dp(3)
                        radius: height / 2
                        color: Theme.withAlpha(Theme.overlay, 0.45)
                        Rectangle {
                            height: parent.height; radius: parent.radius
                            width: parent.width * Math.max(0, Math.min(1,
                                dash.displayPos / Math.max(1, dash.player?.length ?? 1)))
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 250 } }
                        }
                    }
                }
            }
                }

                // Calendario: columna derecha, a toda la altura disponible.
                OverviewCard {
                    Layout.fillWidth: false
                    Layout.preferredWidth: Theme.dp(300)
                    Layout.fillHeight: true
                    implicitHeight: calBox.implicitHeight + Theme.space12 * 2

                    Calendar {
                        id: calBox
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                  leftMargin: Theme.space12; rightMargin: Theme.space12 }
                    }
                }
            }

        }

        // Página: sistema — recursos en vivo de un vistazo. El panel
        // "Monitor de sistema" completo (procesos, servicios…) sigue aparte;
        // esto solo sondea mientras la pestaña está a la vista.
        ColumnLayout {
            id: systemPage
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: Theme.space10
            opacity: dash.tab === "system" ? 1 : 0
            visible: opacity > 0.01
            transform: Translate {
                x: (1 - dash.activeIndex) * pages.slide
                Behavior on x { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }

            // Históricos para las gráficas (40 muestras ≈ 2 min), rellenados
            // en cada tick solo mientras la pestaña está a la vista.
            property var cpuHist: []
            property var cpuTempHist: []
            property var memHist: []
            property var gpuHist: []
            property var gpuTempHist: []
            property var netHist: []
            property var netUpHist: []

            // Nº de muestras retenidas (compartido con las gráficas).
            readonly property int histSamples: 40

            // Añade una muestra al final del histórico y lo recorta.
            function pushH(arr, v) { return arr.concat([v]).slice(-histSamples) }

            // Normaliza un histórico de red a 0..1 contra el pico conjunto de
            // bajada y subida (mínimo 100 KB/s), para que ambas líneas
            // compartan escala.
            function netNorm(h) {
                const d = netHist, u = netUpHist
                let peak = 100
                for (let i = 0; i < d.length; i++) if (d[i] > peak) peak = d[i]
                for (let i = 0; i < u.length; i++) if (u[i] > peak) peak = u[i]
                return h.map(v => v / peak)
            }

            Timer {
                running: dash.shown && dash.tab === "system"
                interval: 3000; repeat: true; triggeredOnStart: true
                onTriggered: {
                    SysMon.refreshStats(true)
                    systemPage.cpuHist = systemPage.pushH(systemPage.cpuHist, SysMon.cpu / 100)
                    systemPage.cpuTempHist = systemPage.pushH(systemPage.cpuTempHist, SysMon.cpuTemp / 100)
                    systemPage.memHist = systemPage.pushH(systemPage.memHist, SysMon.memPercent / 100)
                    systemPage.gpuHist = systemPage.pushH(systemPage.gpuHist, Math.max(0, SysMon.gpuBusy) / 100)
                    systemPage.gpuTempHist = systemPage.pushH(systemPage.gpuTempHist, SysMon.gpuTemp / 100)
                    systemPage.netHist = systemPage.pushH(systemPage.netHist, SysMon.netDownKB)
                    systemPage.netUpHist = systemPage.pushH(systemPage.netUpHist, SysMon.netUpKB)
                }
            }

            // Rejilla 2×2 de gráficas: la gráfica domina cada tarjeta y las
            // cifras van debajo. La temperatura se superpone como segunda
            // línea (roja) en CPU y GPU; en Red, la subida va en acento2.
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: Theme.space10
                columnSpacing: Theme.space10

                GraphCard {
                    title: "CPU"
                    capacity: systemPage.histSamples
                    values: systemPage.cpuHist
                    values2: systemPage.cpuTempHist
                    footer: "\u{f0ee0} " + Math.round(SysMon.cpu) + "%"
                            + (SysMon.cpuTemp > 0 ? "  \u00b7  \u{f050f} " + Math.round(SysMon.cpuTemp) + "\u00b0C" : "")
                }
                GraphCard {
                    title: I18n.tr("Memory")
                    capacity: systemPage.histSamples
                    values: systemPage.memHist
                    footer: "\u{f035b} " + SysMon.memUsedGB.toFixed(1) + " GiB  \u00b7  " + Math.round(SysMon.memPercent) + "%"
                }
                GraphCard {
                    title: "GPU"
                    capacity: systemPage.histSamples
                    values: systemPage.gpuHist
                    values2: systemPage.gpuTempHist
                    footer: "\u{f0379} " + (SysMon.gpuBusy >= 0 ? SysMon.gpuBusy + "%" : "\u2014")
                            + (SysMon.gpuTemp > 0 ? "  \u00b7  \u{f050f} " + Math.round(SysMon.gpuTemp) + "\u00b0C" : "")
                }
                GraphCard {
                    title: I18n.tr("Network")
                    capacity: systemPage.histSamples
                    tint2: Theme.accent2
                    values: systemPage.netNorm(systemPage.netHist)
                    values2: systemPage.netNorm(systemPage.netUpHist)
                    footer: "\u2193 " + dash.fmtRate(SysMon.netDownKB) + "   \u2191 " + dash.fmtRate(SysMon.netUpKB)
                }
            }

            // Información del equipo y recursos en cifras, lado a lado.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space10

                OverviewCard {
                    Layout.preferredWidth: 100
                    Layout.fillHeight: true
                    implicitHeight: sysCol.implicitHeight + Theme.space12 * 2

                    ColumnLayout {
                        id: sysCol
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                  leftMargin: Theme.space12; rightMargin: Theme.space12 }
                        spacing: Theme.space4

                        Text {
                            text: I18n.tr("System")
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            font.bold: true
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: Theme.dp(1)
                        }
                        InfoLine { glyph: "\u{f0ee0}"; text: SysMon.cpuModel }
                        InfoLine { glyph: SysMon.distroGlyph; text: SysMon.distroName }
                        InfoLine { glyph: "\u{f0494}"; text: "Linux " + SysMon.kernel }
                        InfoLine { glyph: "\u{f05af}"; text: "Hyprland" }
                        InfoLine { glyph: "\u{f07c0}"; text: SysMon.hostname }
                        InfoLine { glyph: "\u{f13ab}"; text: SysMon.uptime }
                    }
                }

                OverviewCard {
                    Layout.preferredWidth: 100
                    Layout.fillHeight: true
                    implicitHeight: resCol.implicitHeight + Theme.space12 * 2

                    ColumnLayout {
                        id: resCol
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                  leftMargin: Theme.space12; rightMargin: Theme.space12 }
                        spacing: Theme.space4

                        Text {
                            text: I18n.tr("Resources")
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            font.bold: true
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: Theme.dp(1)
                        }
                        ResRow {
                            glyph: "\u{f0ee0}"; label: I18n.tr("Load")
                            value: SysMon.loadAvg !== "" ? SysMon.loadAvg.split(/\s+/).join(" / ") : "\u2014"
                        }
                        ResRow {
                            glyph: "\u{f035b}"; label: "RAM"
                            value: SysMon.memUsedGB.toFixed(1) + " / " + SysMon.memTotalGB.toFixed(1) + " GiB"
                        }
                        ResRow {
                            glyph: "\u{f04e1}"; label: "Swap"
                            value: SysMon.swapTotalGB > 0
                                   ? SysMon.swapUsedGB.toFixed(1) + " / " + SysMon.swapTotalGB.toFixed(1) + " GiB"
                                   : "\u2014"
                        }
                        ResRow {
                            glyph: "\u{f02ca}"; label: I18n.tr("Disk")
                            value: Math.round(SysMon.diskUsedGB) + " / " + Math.round(SysMon.diskTotalGB)
                                   + " GB (" + Math.round(SysMon.diskPercent) + "%)"
                        }
                    }
                }
            }
        }

        // Página: música
        ColumnLayout {
            id: musicPage
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: Theme.space12
            opacity: dash.tab === "music" ? 1 : 0
            visible: opacity > 0.01
            // La carátula grande solo se decodifica tras visitar la pestaña
            // (y se conserva: el panel entero se destruye al cerrar).
            property bool artArmed: false
            onVisibleChanged: if (visible) artArmed = true
            transform: Translate {
                x: (2 - dash.activeIndex) * pages.slide
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
                            color: sel ? Theme.withAlpha(Theme.accent, 0.22)
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
                        // Atado a shown: visible:false no evita la decodificación,
                        // y así no re-decodifica 440dp² por canción con el panel cerrado.
                        // artArmed: tampoco antes de visitar la pestaña.
                        source: dash.shown && musicPage.artArmed ? (dash.player?.trackArtUrl ?? "") : ""
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

        // Página: fondos — tarjeta héroe con el fondo en uso (velo degradado,
        // nombre y chip "Activo") y rejilla con zoom al pasar el ratón.
        ColumnLayout {
            id: wallpaperPage
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: Theme.space8
            opacity: dash.tab === "wallpaper" ? 1 : 0
            visible: opacity > 0.01
            // Las miniaturas de la rejilla solo se decodifican tras visitar la
            // pestaña (y se conservan: el panel entero se destruye al cerrar).
            property bool thumbsArmed: false
            onVisibleChanged: if (visible) thumbsArmed = true
            transform: Translate {
                x: (3 - dash.activeIndex) * pages.slide
                Behavior on x { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: dash.tabAnim; easing.type: Easing.OutCubic } }

            // Nombre legible: archivo sin extensión, guiones/guiones bajos
            // como espacios y primera letra en mayúscula.
            function wpName(path) {
                if (!path) return ""
                let n = path.split("/").pop()
                const dot = n.lastIndexOf(".")
                if (dot > 0) n = n.slice(0, dot)
                n = n.replace(/[-_]+/g, " ").trim()
                return n.charAt(0).toUpperCase() + n.slice(1)
            }

            // Cabecera: título con contador debajo y recarga a la derecha
            // (el icono gira mientras se escanean las carpetas).
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: I18n.tr("Wallpapers title")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 2
                        font.bold: true
                    }
                    Text {
                        text: Wallpaper.scanning ? I18n.tr("Searching...")
                                                 : I18n.tr("%1 wallpapers").arg(Wallpaper.list.length)
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                }

                Rectangle {
                    implicitWidth: Theme.controlM; implicitHeight: Theme.controlM
                    radius: width / 2
                    color: refMa.containsMouse ? Theme.surfaceHi : Theme.withAlpha(Theme.surface, 0.6)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        id: refIcon
                        anchors.centerIn: parent; text: "󰑐"
                        color: refMa.containsMouse ? Theme.accent : Theme.fgDim
                        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                        NumberAnimation on rotation {
                            running: Wallpaper.scanning
                            from: 0; to: 360
                            duration: 900; loops: Animation.Infinite
                            onStopped: refIcon.rotation = 0
                        }
                    }
                    MouseArea {
                        id: refMa
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Wallpaper.refresh()
                    }
                }
            }

            // Héroe: el fondo en uso a lo ancho, en formato banner compacto
            // para que la página no supere la altura de las demás pestañas.
            // El pie va sobre un velo oscuro fijo (no tonal) para leerse
            // sobre cualquier imagen.
            ClippingRectangle {
                Layout.fillWidth: true
                visible: Wallpaper.current !== ""
                implicitHeight: Theme.dp(104)
                radius: Theme.dp(16)
                color: Theme.bgAlt

                Image {
                    anchors.fill: parent
                    // Atado a shown para no decodificar con el panel cerrado,
                    // y a thumbsArmed para no hacerlo antes de visitar la pestaña.
                    source: dash.shown && wallpaperPage.thumbsArmed && Wallpaper.current !== ""
                            ? "file://" + Wallpaper.current : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Theme.dp(640); sourceSize.height: Theme.dp(220)
                    asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }
                }

                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: parent.height * 0.65
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.62) }
                    }
                }

                RowLayout {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                              leftMargin: Theme.space12; rightMargin: Theme.space12; bottomMargin: Theme.space10 }
                    spacing: Theme.space8

                    Text {
                        Layout.fillWidth: true
                        text: wallpaperPage.wpName(Wallpaper.current)
                        color: Qt.rgba(1, 1, 1, 0.95)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        implicitWidth: heroChip.implicitWidth + Theme.space12
                        implicitHeight: Theme.dp(20)
                        radius: height / 2
                        color: Theme.accent
                        Text {
                            id: heroChip
                            anchors.centerIn: parent
                            text: "󰄬 " + I18n.tr("Active")
                            color: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 4
                            font.bold: true
                        }
                    }
                }
            }

            // Sin imágenes: icono grande, mensaje y las carpetas escaneadas.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space16; Layout.bottomMargin: Theme.space16
                visible: Wallpaper.list.length === 0
                spacing: Theme.space8
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "\u{f02e9}"; color: Theme.fgMuted
                    font.family: Theme.fontFamily; font.pixelSize: Theme.sp(44)
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: I18n.tr("No images in wallpaper folders.")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Settings.wallpaperDirs.map(d => d.replace(Settings.home, "~")).join("  ·  ")
                    color: Theme.fgDim
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                }
            }

            // 4 columnas y tope de ~2 filas: junto con el héroe compacto, la
            // página queda a la altura que tenía la pestaña original (el panel
            // dimensiona todas las pestañas a la más alta). Con más fondos, la
            // rejilla desplaza.
            GridView {
                id: wpGrid
                Layout.fillWidth: true
                visible: Wallpaper.list.length > 0
                implicitHeight: Math.min(Theme.dp(190), contentHeight)
                cellWidth: Math.floor(width / 4)
                cellHeight: Math.floor(cellWidth * 0.62)
                cacheBuffer: cellHeight * 2
                clip: true
                model: Wallpaper.list
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: wpCell
                    required property var modelData
                    width: wpGrid.cellWidth; height: wpGrid.cellHeight
                    readonly property bool active: Wallpaper.current === modelData

                    ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: Theme.space4
                        radius: Theme.dp(10)
                        color: Theme.bgAlt

                        Image {
                            id: wpImg
                            anchors.fill: parent
                            source: wallpaperPage.thumbsArmed ? "file://" + wpCell.modelData : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: Theme.dp(150); sourceSize.height: Theme.dp(94)
                            asynchronous: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
                            // Zoom sutil al pasar el ratón; el recorte lo da
                            // el ClippingRectangle.
                            scale: wpMa.containsMouse ? 1.07 : 1.0
                            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: wpImg.status !== Image.Ready
                            text: "\u{f02e9}"; color: Theme.fgMuted
                            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize + 4
                        }

                        // Nombre sobre velo inferior, solo al pasar el ratón.
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: parent.height * 0.55
                            opacity: wpMa.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.65) }
                            }
                            Text {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                                          leftMargin: Theme.space6; rightMargin: Theme.space6; bottomMargin: Theme.space4 }
                                text: wallpaperPage.wpName(wpCell.modelData)
                                color: Qt.rgba(1, 1, 1, 0.95)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 4
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Aro por encima de la imagen: acento en el activo, fino
                    // al pasar el ratón por los demás.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Theme.space4
                        radius: Theme.dp(10)
                        color: "transparent"
                        border.width: wpCell.active ? Theme.dp(2) : (wpMa.containsMouse ? Theme.hairline : 0)
                        border.color: wpCell.active ? Theme.accent : Theme.withAlpha(Theme.overlay, 0.8)
                    }

                    Rectangle {
                        visible: scale > 0.01
                        anchors { top: parent.top; right: parent.right; margins: Theme.space6 }
                        width: Theme.dp(18); height: Theme.dp(18); radius: width / 2
                        color: Theme.accent
                        scale: wpCell.active ? 1 : 0
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        Text {
                            anchors.centerIn: parent; text: "󰄬"; color: Theme.bg
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                        }
                    }

                    MouseArea {
                        id: wpMa
                        anchors.fill: parent
                        anchors.margins: Theme.space4
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: Wallpaper.apply(wpCell.modelData)
                    }
                }
            }
        }
    }

    }

    // Componentes reutilizables

    // Tarjeta tonal del resumen (superficie suave, radio amplio).
    component OverviewCard: Rectangle {
        Layout.fillWidth: true
        radius: Theme.dp(18)
        color: Theme.withAlpha(Theme.surface, 0.5)
    }

    // Celda de estado: anillo con el porcentaje DENTRO y debajo el icono con
    // la etiqueta. El color del anillo reacciona a la carga (acento → naranja
    // desde el 70% → rojo desde el 90%), con transición suave. Cada celda
    // ocupa un tercio exacto de la tarjeta, centrada, así la fila queda
    // simétrica en tarjetas estrechas.
    component StatCluster: Item {
        id: cell
        property real value: 0
        property string glyph: ""
        property string label: ""
        property int percent: 0
        readonly property color loadColor: value >= 0.9 ? Theme.red
                                         : value >= 0.7 ? Theme.orange
                                         : Theme.accent
        Layout.fillWidth: true
        Layout.preferredWidth: 100
        implicitHeight: cl.implicitHeight

        ColumnLayout {
            id: cl
            anchors.centerIn: parent
            spacing: Theme.space4

            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: Theme.dp(46)
                implicitHeight: Theme.dp(46)

                StatRing {
                    anchors.fill: parent
                    value: cell.value
                    tint: cell.loadColor
                    animated: dash.shown
                    Behavior on tint { ColorAnimation { duration: Theme.animNormal } }
                }
                Text {
                    anchors.centerIn: parent
                    text: cell.percent + "%"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.space4
                Text {
                    text: cell.glyph
                    color: cell.loadColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    Behavior on color { ColorAnimation { duration: Theme.animNormal } }
                }
                Text {
                    text: cell.label
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    font.bold: true
                }
            }
        }
    }

    // Botón del riel: icono cuadrado, sin texto. El color marca la pestaña
    // activa; el fondo lo pone el indicador deslizante del riel.
    component TabBtn: Item {
        property string glyph: ""
        property string key: ""
        readonly property bool sel: dash.tab === key
        implicitWidth: dash.railTabSize
        implicitHeight: dash.railTabSize
        Text {
            anchors.centerIn: parent
            text: parent.glyph
            color: parent.sel ? Theme.accent
                 : tbMa.containsMouse ? Theme.fg : Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize + 3
            Behavior on color { ColorAnimation { duration: dash.tabAnim } }
        }
        MouseArea {
            id: tbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dash.tab = parent.key
        }
    }

    // Tarjeta de gráfica: título arriba, la gráfica dominando el cuerpo y
    // las cifras centradas debajo. Las dos columnas del GridLayout se
    // reparten a partes iguales (preferredWidth idéntico + fillWidth).
    component GraphCard: Rectangle {
        property string title: ""
        property alias values: gcGraph.values
        property alias values2: gcGraph.values2
        property alias tint2: gcGraph.tint2
        property alias capacity: gcGraph.capacity
        property string footer: ""
        Layout.fillWidth: true
        Layout.preferredWidth: 100
        implicitHeight: Theme.dp(108)
        radius: Theme.dp(18)
        color: Theme.withAlpha(Theme.surface, 0.5)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space10
            spacing: Theme.space4
            Text {
                text: parent.parent.title
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Theme.dp(1)
            }
            HistoryGraph {
                id: gcGraph
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: parent.parent.footer
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }

    // Gráfica de histórico: línea con relleno degradado, anclada a la derecha
    // (las muestras nuevas entran por la derecha y las viejas salen por la
    // izquierda, como un osciloscopio). values = lista de 0..1.
    component HistoryGraph: Canvas {
        id: hg
        property var values: []
        property var values2: []
        property color tint: Theme.accent
        property color tint2: Theme.red
        property int capacity: 40
        onValuesChanged: requestPaint()
        onValues2Changed: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const vs = values
            if (!vs || vs.length < 2)
                return
            const stepX = width / (capacity - 1)
            const x0 = width - (vs.length - 1) * stepX
            const yFor = (v) => height - Math.max(0, Math.min(1, v)) * (height - 2) - 1
            ctx.beginPath()
            ctx.moveTo(x0, yFor(vs[0]))
            for (let i = 1; i < vs.length; i++)
                ctx.lineTo(x0 + i * stepX, yFor(vs[i]))
            ctx.strokeStyle = tint
            ctx.lineWidth = 1.5
            ctx.stroke()
            ctx.lineTo(width, height)
            ctx.lineTo(x0, height)
            ctx.closePath()
            const grad = ctx.createLinearGradient(0, 0, 0, height)
            grad.addColorStop(0, Qt.rgba(tint.r, tint.g, tint.b, 0.28))
            grad.addColorStop(1, Qt.rgba(tint.r, tint.g, tint.b, 0.02))
            ctx.fillStyle = grad
            ctx.fill()
            const v2 = values2
            if (v2 && v2.length >= 2) {
                const x2 = width - (v2.length - 1) * stepX
                ctx.beginPath()
                ctx.moveTo(x2, yFor(v2[0]))
                for (let i = 1; i < v2.length; i++)
                    ctx.lineTo(x2 + i * stepX, yFor(v2[i]))
                ctx.strokeStyle = tint2
                ctx.lineWidth = 1.2
                ctx.stroke()
            }
        }
    }

    // Línea de información: glifo en acento + texto, en una sola línea.
    component InfoLine: RowLayout {
        property string glyph: ""
        property string text: ""
        Layout.fillWidth: true
        spacing: Theme.space6
        Text {
            text: parent.glyph
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            Layout.fillWidth: true
            text: parent.text
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            elide: Text.ElideRight
        }
    }

    // Fila de recurso: icono + etiqueta a la izquierda y valor a la derecha.
    component ResRow: RowLayout {
        property string glyph: ""
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: Theme.space6
        Text {
            text: parent.glyph
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            Layout.fillWidth: true
            text: parent.label
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
        Text {
            text: parent.value
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            font.bold: true
        }
    }

    // Baldosa de acción rápida: icono + etiqueta; las conmutables se tiñen de
    // acento cuando están activas.
    component RailBtn: IconButton {
        Layout.alignment: Qt.AlignHCenter
        diameter: Theme.dp(34)
        iconPixelSize: Theme.iconSize + 2
        baseColor: "transparent"
        hoverColor: Theme.surfaceHi
        iconColor: Theme.fgMuted
        hoverIconColor: Theme.accent
    }

    component QuickTile: Rectangle {
        property string glyph: ""
        property bool active: false
        signal tapped()
        Layout.fillWidth: true
        implicitHeight: Theme.dp(46)
        radius: Theme.dp(14)
        color: active ? Theme.withAlpha(Theme.accent, Theme.isDark ? 0.24 : 0.3)
             : qtMa.containsMouse ? Theme.surfaceHi
             : Theme.withAlpha(Theme.surface, 0.5)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Text {
            anchors.centerIn: parent
            text: parent.glyph
            color: parent.active ? Theme.accent : Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize + 6
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
        MouseArea {
            id: qtMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.tapped()
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
