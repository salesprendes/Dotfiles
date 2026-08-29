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

    // Una ranura de widget: el id del layout se resuelve a un componente en
    // Bar/BarWidgetLoader.qml. Se declara aquí como componente en línea para
    // no repetir el mismo cableado tres veces (izquierda, centro, derecha).
    component Slot: BarWidgetLoader {
        required property var modelData
        widgetId: modelData && modelData.id ? String(modelData.id) : ""
        barScreen: bar.screen
    }

    // modelData lo inyecta Variants: es el QsScreen de este monitor.
    property var modelData
    screen: modelData

    // Borde de pantalla configurable (Ajustes → Shell → Disposición de la
    // barra): arriba o abajo. El margen de separación acompaña al borde activo.
    readonly property bool atBottom: Settings.barPosition === "bottom"

    anchors {
        top: !bar.atBottom
        bottom: bar.atBottom
        left: true
        right: true
    }

    margins {
        top: bar.atBottom ? 0 : Theme.barTopMargin
        bottom: bar.atBottom ? Theme.barTopMargin : 0
        left: Theme.barMargin
        right: Theme.barMargin
    }

    implicitHeight: Theme.barHeight
    color: "transparent"

    // Reserva el espacio justo de la barra + su margen.
    exclusiveZone: Theme.barHeight + Theme.barTopMargin

    // La barra vive toda la sesión, así que es de las que se quedan pintando
    // en el offset viejo cuando el monitor cambia de sitio en el layout
    // (dock/undock). El vigilante la desmapea un instante para que Hyprland la
    // recoloque. Ver Components/ScreenMoveRemap.qml.
    visible: !remapGuard.remapping
    ScreenMoveRemap { id: remapGuard; window: bar }

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
        // Pegada al borde (no flotante) va sin redondeo: a sangre.
        radius: Settings.barFloating ? Theme.barRadius : 0
        color: Theme.barBg
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.35)

        property bool entered: false
        Component.onCompleted: entered = true
        opacity: entered ? 1 : 0
        transform: Translate {
            // Entra deslizándose desde su borde: desde arriba si la barra vive
            // arriba, desde abajo si vive abajo.
            y: barBg.entered ? 0
               : (bar.atBottom ? 1 : -1) * (Theme.barHeight + Theme.barTopMargin + Theme.dp(6))
            // OutQuint: recorre casi todo enseguida y dedica la cola a
            // asentarse — la barra "aterriza" en vez de frenar.
            Behavior on y { NumberAnimation { duration: 460; easing.type: Easing.OutQuint } }
        }
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        // ── Las tres secciones ───────────────────────────────────────────────
        // Qué widget va en cuál y en qué orden lo dice Settings.barLayout, no
        // este archivo. Antes estaban cableados aquí y cada uno llevaba colgado
        // un `visible: Settings.showLoQueSea`: siete booleanos sueltos que solo
        // servían para simular un orden que en realidad no se podía cambiar.
        // Ahora la presencia en el layout ES la visibilidad, y reordenar,
        // mover de sección o duplicar un separador se hace desde Ajustes.

        RowLayout {
            anchors {
                left: parent.left
                leftMargin: Theme.gap
                verticalCenter: parent.verticalCenter
            }
            spacing: Theme.gap

            Repeater {
                model: BarCatalog.entriesOf(Settings.barLayout, "left")
                delegate: Slot {}
            }
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: Theme.gap

            Repeater {
                model: BarCatalog.entriesOf(Settings.barLayout, "center")
                delegate: Slot {}
            }
        }

        RowLayout {
            anchors {
                right: parent.right
                rightMargin: Theme.gap
                verticalCenter: parent.verticalCenter
            }
            spacing: Theme.gap

            Repeater {
                model: BarCatalog.entriesOf(Settings.barLayout, "right")
                delegate: Slot {}
            }
        }
    }
}