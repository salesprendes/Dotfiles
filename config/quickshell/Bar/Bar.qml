import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Bar
import qs.Components
import qs.Config
import qs.Services

// Barra superior flotante: bordes redondeados y fondo translúcido.
PanelWindow {
    id: bar

    // Píldora de clima opcional (Ajustes → Clima → Mostrar en la barra):
    // icono según el estado del cielo + temperatura actual. Click abre el
    // Dashboard, donde vive la tarjeta completa. Componente en línea porque
    // comparte pantalla con el reloj y no se usa fuera de la barra.
    component WeatherWidget: Pill {
        visible: Settings.weatherShowInBar && Weather.enabled && Weather.ready
        interactive: true
        active: Globals.dashboardOpen
        onClicked: Globals.toggleDashboard()

        Text {
            text: Weather.icon
            color: Theme.yellow
            font.family: Theme.fontFamily
            font.pixelSize: Theme.barIconSize
        }
        Text {
            text: Weather.temp
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
    }

    // modelData lo inyecta Variants: es el QsScreen de este monitor.
    property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: Theme.barTopMargin
        left: Theme.barMargin
        right: Theme.barMargin
    }

    implicitHeight: Theme.barHeight
    color: "transparent"

    // Reserva el espacio justo de la barra + su margen.
    exclusiveZone: Theme.barHeight + Theme.barTopMargin

    // ── Extractor de paleta dinámica ─────────────────────────────────────────
    // Solo con el tema base "dynamic" y solo en la barra del monitor
    // principal: un Canvas fuera del viewport (su búfer pinta igual) reduce el
    // fondo de pantalla a 64×36 px, y Settings vota el tono dominante y deriva
    // la paleta completa. Se recalcula al cambiar de fondo.
    Loader {
        active: Settings.themeName === "dynamic" && bar.screen === Quickshell.screens[0]
        sourceComponent: Canvas {
            id: paletteCanvas
            x: -width; y: -height
            width: 64; height: 36
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate

            property string current: ""
            function analyze() {
                const p = Wallpaper.current
                if (p === "" || p === current)
                    return
                current = p
                loadImage("file://" + p)
            }
            Component.onCompleted: analyze()
            Connections {
                target: Wallpaper
                function onCurrentChanged() { paletteCanvas.analyze() }
            }
            onImageLoaded: requestPaint()
            onPaint: {
                if (current === "")
                    return
                const url = "file://" + current
                if (!isImageLoaded(url))
                    return
                const ctx = getContext("2d")
                ctx.drawImage(url, 0, 0, width, height)
                Settings.computeDynamicPalette(ctx.getImageData(0, 0, width, height).data)
                unloadImage(url)
            }
        }
    }

    // Fondo de la barra. Al nacer (arranque o recarga) entra deslizándose
    // desde arriba del borde de pantalla con un fundido; las píldoras viajan
    // dentro, así que toda la barra aterriza como una sola pieza.
    Rectangle {
        id: barBg
        anchors.fill: parent
        radius: Theme.barRadius
        color: Theme.barBg
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.35)

        property bool entered: false
        Component.onCompleted: entered = true
        opacity: entered ? 1 : 0
        transform: Translate {
            y: barBg.entered ? 0 : -(Theme.barHeight + Theme.barTopMargin + Theme.dp(6))
            Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        }
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        // Izquierda: workspaces + ventana activa
        RowLayout {
            anchors {
                left: parent.left
                leftMargin: Theme.gap
                verticalCenter: parent.verticalCenter
            }
            spacing: Theme.gap

            LauncherWidget {}
            Workspaces { screen: bar.screen }
            ActiveWindow {}
        }

        // Centro: reproductor (si hay música) + reloj
        RowLayout {
            anchors.centerIn: parent
            spacing: Theme.gap

            MediaWidget {}
            WeatherWidget {}
            ClockWidget {}
        }

        // Derecha: bandeja + estado + batería, píldoras independientes.
        RowLayout {
            anchors {
                right: parent.right
                rightMargin: Theme.gap
                verticalCenter: parent.verticalCenter
            }
            spacing: Theme.gap

            Tray {}
            SysMonWidget { visible: Settings.showSysmon }
            ConnectivityAudioWidget {}
            PowerWidget {}
            CaffeineWidget { visible: Settings.showCaffeine }
            BatteryWidget {}
            ClipboardWidget { visible: Settings.showClipboard }
            NotificationsWidget { visible: Settings.showNotifications }
        }
    }
}