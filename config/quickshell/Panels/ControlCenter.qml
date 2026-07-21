import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.Components
import qs.Config
import qs.Panels
import qs.Services

// Centro de control, al estilo del Control Center de macOS: tarjetas del mismo
// material sin etiquetas de sección, rejilla compacta de tiles, sliders gruesos
// tipo píldora con el icono embebido (Pantalla y Sonido en tarjeta propia) y
// las acciones de energía como pie del panel. Los tiles con detalle desplegable
// (WiFi, Bluetooth, audio, micro y perfil de energía) conservan su cableado y
// comportamiento.
Popout {
    id: cc
    ns: "qs-controlcenter"
    cardWidth: 430
    cardMinWidth: 320
    scrollable: true   // si al expandir un detalle el contenido no cabe,
                       // se desplaza en vez de ocultar lo de abajo.
    shown: Globals.controlCenterOpen

    property string expanded: ""   // "", "wifi", "bt", "audio", "mic"
    onShownChanged: if (!shown) expanded = ""

    // Cascada de entrada: cada bloque funde y sube con un pequeño retardo según
    // su índice, derivado del mismo escalar openProgress del Popout (así abre y
    // cierra coordinado con la tarjeta, sin animaciones propias que desincronizar).
    function blockReveal(i) {
        return Math.max(0, Math.min(1, (openProgress - i * 0.05) / 0.55))
    }

    // Tarjeta contenedora: mismo material en cabecera, sliders y pie, para que
    // los tiles (más opacos) queden un punto por delante.
    component SectionCard: Rectangle {
        Layout.fillWidth: true
        // Mismo radio que ControlTile: toda la retícula comparte redondeo.
        radius: Theme.pillRadius + Theme.space4
        color: Theme.withAlpha(Theme.surface, 0.62)
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.34)
    }

    // Slider grueso tipo píldora (como el de macOS): el icono va embebido en el
    // relleno y toda la pista es el control. Misma interacción que
    // Components/Slider.qml: al arrastrar sigue al puntero con un valor local
    // (dragValue) sin esperar el eco del backend, y flechas para ajuste fino.
    component FatSlider: Item {
        id: fs

        property string icon: ""
        property real value: 0
        // Atenúa el relleno (p. ej. sonido silenciado) sin tocar el valor.
        property bool dimmed: false
        signal moved(real v)

        property bool dragging: false
        property real dragValue: 0
        readonly property real shownValue: dragging ? dragValue : value
        // Interactuando: con el puntero encima, arrastrando o con foco de teclado.
        readonly property bool engaged: ma.containsMouse || dragging || activeFocus

        activeFocusOnTab: true
        Layout.fillWidth: true
        implicitHeight: Theme.dp(38)

        function nudge(delta) {
            const step = 0.05
            fs.moved(Math.max(0, Math.min(1, fs.value + delta * step)))
        }

        Keys.onLeftPressed: nudge(-1)
        Keys.onDownPressed: nudge(-1)
        Keys.onRightPressed: nudge(1)
        Keys.onUpPressed: nudge(1)
        Keys.onEscapePressed: Globals.closeAll()

        Rectangle {
            id: track
            // Como en macOS, la pista engorda al pasar el ratón o arrastrar;
            // crece centrada dentro del Item (de alto fijo) sin mover el layout.
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: fs.engaged ? parent.height : parent.height - Theme.space6
            radius: height / 2
            color: Theme.sliderTrack
            clip: true
            border.width: fs.activeFocus ? Theme.focusWidth : 0
            border.color: Theme.focusRing
            Behavior on height { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

            Rectangle {
                // Ancho mínimo = alto: la píldora del relleno nunca se deforma
                // y siempre cubre el icono embebido.
                width: Math.max(track.height, fs.shownValue * track.width)
                height: track.height
                radius: track.radius
                color: fs.dimmed ? Theme.withAlpha(Theme.fg, 0.55) : Theme.fg
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on width { enabled: !fs.dragging; NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.space10
                anchors.verticalCenter: parent.verticalCenter
                text: fs.icon
                color: Theme.bg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
        }

        // El área de pulsación cubre el Item completo (no solo la pista),
        // para que engordarla no cambie dónde se puede agarrar.
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            function update(mx) {
                const v = Math.max(0, Math.min(1, mx / track.width))
                fs.dragValue = v
                fs.moved(v)
            }
            onPressed: (m) => { fs.dragging = true; update(m.x) }
            onPositionChanged: (m) => { if (pressed) update(m.x) }
            onReleased: fs.dragging = false
            onCanceled: fs.dragging = false
        }
    }

    // Tarjeta de slider: título + valor discreto arriba, píldora debajo.
    component SliderCard: SectionCard {
        id: sc

        property string title: ""
        property string valueText: ""
        property alias icon: sldr.icon
        property alias value: sldr.value
        property alias dimmed: sldr.dimmed
        signal moved(real v)

        implicitHeight: scCol.implicitHeight + Theme.space12 * 2

        ColumnLayout {
            id: scCol
            anchors.fill: parent
            anchors.margins: Theme.space12
            anchors.leftMargin: Theme.space14
            anchors.rightMargin: Theme.space14
            spacing: Theme.space8

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                Text {
                    Layout.fillWidth: true
                    text: sc.title
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    text: sc.valueText
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
            FatSlider {
                id: sldr
                onMoved: (v) => sc.moved(v)
            }
        }
    }

    PwObjectTracker {
        objects: {
            const arr = []
            if (Pipewire.defaultAudioSink) arr.push(Pipewire.defaultAudioSink)
            if (Pipewire.defaultAudioSource) arr.push(Pipewire.defaultAudioSource)
            return arr
        }
    }
    readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
    readonly property bool audioMuted: audio?.muted ?? false
    readonly property int audioPercent: Math.round((audio?.volume ?? 0) * 100)
    readonly property real audioLevel: audio?.volume ?? 0
    readonly property var mic: Pipewire.defaultAudioSource?.audio ?? null
    readonly property bool micMuted: mic?.muted ?? true
    readonly property int micPercent: Math.round((mic?.volume ?? 0) * 100)

    // ── Cabecera · identidad del equipo ──
    SectionCard {
        implicitHeight: Theme.dp(64)
        opacity: cc.blockReveal(0)
        transform: Translate { y: (1 - cc.blockReveal(0)) * Theme.dp(14) }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space12
            anchors.rightMargin: Theme.space8
            spacing: Theme.space12

            // Glifo del distro en tesela tintada: mismo lenguaje visual que el
            // botón de icono de los tiles.
            Rectangle {
                implicitWidth: Theme.controlL
                implicitHeight: Theme.controlL
                radius: Theme.pillRadius
                color: Theme.withAlpha(Theme.accent, 0.16)
                border.width: Theme.hairline
                border.color: Theme.withAlpha(Theme.accent, 0.45)
                Text {
                    anchors.centerIn: parent
                    text: SysMon.distroGlyph
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 6
                }
            }
            // Nombre del equipo + tiempo encendido.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space2
                Text {
                    Layout.fillWidth: true
                    text: SysMon.hostname || SysMon.distroName || I18n.tr("System")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: SysMon.uptime !== ""
                    text: I18n.tr("up") + " " + SysMon.uptime
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    elide: Text.ElideRight
                }
            }
            // Abrir Ajustes.
            IconButton {
                icon: "󰒓"
                onClicked: { Globals.closeAll(); Globals.toggleSettings() }
            }

            // Acciones de energía (mantener pulsado para ejecutar), agrupadas
            // en una píldora hundida para que lean como un solo control.
            Rectangle {
                implicitWidth: powRow.implicitWidth + Theme.space4 * 2
                implicitHeight: Theme.controlS + Theme.space4 * 2
                radius: height / 2
                color: Theme.withAlpha(Theme.overlay, 0.25)
                border.width: Theme.hairline
                border.color: Theme.withAlpha(Theme.overlay, 0.4)

                RowLayout {
                    id: powRow
                    anchors.centerIn: parent
                    spacing: Theme.space4

                    Repeater {
                        // Modelo compartido con el lanzador (Config/PowerActions.qml).
                        model: PowerActions.model
                        delegate: Item {
                            id: btn
                            required property var modelData
                            implicitWidth: Theme.controlS
                            implicitHeight: Theme.controlS
                            // Crece un punto al pasar el ratón y se encoge al
                            // pulsar: el anillo de progreso acompaña.
                            scale: pwMa.pressed ? 0.92 : (pwMa.containsMouse ? 1.1 : 1.0)
                            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                            // Progreso de "mantener pulsado" (0 → 1). Al llegar a 1 ejecuta.
                            property real holdProgress: 0
                            readonly property int holdDuration: 800

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                // En reposo, transparente: la píldora ya agrupa.
                                color: pwMa.containsMouse ? btn.modelData.col : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Text {
                                    anchors.centerIn: parent
                                    text: btn.modelData.ic
                                    color: pwMa.containsMouse ? Theme.bg : Theme.fgDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.iconSize - 1
                                }
                            }

                            // Anillo que se rellena mientras se mantiene pulsado.
                            StatRing {
                                anchors.fill: parent
                                anchors.margins: -Theme.dp(2.5)
                                visible: btn.holdProgress > 0
                                value: btn.holdProgress
                                animated: false        // el progreso ya viene animado (hold)
                                tint: btn.modelData.col
                                trackColor: "transparent"
                                ringWidth: Theme.dp(2.5)
                            }

                            // Avanza el progreso mientras se pulsa; al terminar, ejecuta.
                            NumberAnimation {
                                id: holdAnim
                                target: btn; property: "holdProgress"
                                from: 0; to: 1; duration: btn.holdDuration
                                onFinished: {
                                    Globals.runPowerAction(btn.modelData.action)
                                    // Resetea el anillo: el panel solo se oculta (no se
                                    // destruye), así que sin esto reaparecería relleno la
                                    // próxima vez que se abra el centro rápido.
                                    btn.holdProgress = 0
                                }
                            }
                            // Retrocede suavemente si se suelta antes de completar.
                            NumberAnimation {
                                id: resetAnim
                                target: btn; property: "holdProgress"
                                to: 0; duration: Theme.animFast
                            }

                            MouseArea {
                                id: pwMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: { resetAnim.stop(); holdAnim.restart() }
                                onReleased: {
                                    if (btn.holdProgress < 1) { holdAnim.stop(); resetAnim.restart() }
                                }
                                onCanceled: { holdAnim.stop(); resetAnim.restart() }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Rejilla de tiles ──
    // Un solo bloque compacto, sin etiquetas: la agrupación la da el orden de
    // las filas (conexiones, audio, sistema, captura), como en macOS.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.space8

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space8
            opacity: cc.blockReveal(1)
            transform: Translate { y: (1 - cc.blockReveal(1)) * Theme.dp(14) }
            ControlTile {
                Layout.fillWidth: true
                icon: Net.icon
                // Con cable, el tile muestra Ethernet (prioritaria; el wifi va
                // en el desplegable). Si no, wifi: SSID + cobertura, o el estado.
                title: Net.primaryEthernet ? "Ethernet"
                     : Net.ssid !== "" ? Net.ssid : "WiFi"
                subtitle: Net.primaryEthernet ? I18n.tr("Connected")
                        : Net.ssid !== "" ? Net.signal + "%" : Net.label
                // Activo (icono resaltado) si la red prioritaria es ethernet o
                // el radio wifi está on.
                active: Net.primaryEthernet || Net.wifiEnabled
                accent: Theme.accent
                expandable: true
                expanded: cc.expanded === "wifi"
                // Pulsar el icono alterna el radio WiFi (ethernet es por cable).
                onToggled: Net.toggleWifi()
                onExpand: cc.expanded = (cc.expanded === "wifi" ? "" : "wifi")
            }
            ControlTile {
                Layout.fillWidth: true
                icon: BT.icon
                title: "Bluetooth"
                subtitle: BT.label
                active: BT.enabled
                accent: Theme.accent
                expandable: true
                expanded: cc.expanded === "bt"
                onToggled: BT.toggle()
                onExpand: cc.expanded = (cc.expanded === "bt" ? "" : "bt")
            }
        }
        // Detalle en línea (se despliega animando su altura).
        ExpandableDetail {
            open: cc.expanded === "wifi" || cc.expanded === "bt"
            sourceComponent: cc.expanded === "wifi" ? wifiComp
                           : cc.expanded === "bt"   ? btComp
                           : null
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space8
            opacity: cc.blockReveal(2)
            transform: Translate { y: (1 - cc.blockReveal(2)) * Theme.dp(14) }
            ControlTile {
                Layout.fillWidth: true
                icon: cc.audioMuted ? "󰝟" : "󰕾"
                title: I18n.tr("Sound")
                subtitle: cc.audioMuted ? I18n.tr("Muted") : cc.audioPercent + "%"
                active: !cc.audioMuted
                accent: Theme.accent
                expandable: true
                expanded: cc.expanded === "audio"
                onToggled: { if (cc.audio) cc.audio.muted = !cc.audio.muted }
                onExpand: cc.expanded = (cc.expanded === "audio" ? "" : "audio")
            }
            ControlTile {
                Layout.fillWidth: true
                icon: cc.micMuted ? "󰍭" : "󰍬"
                title: I18n.tr("Microphone")
                subtitle: cc.mic ? (cc.micMuted ? I18n.tr("Muted") : cc.micPercent + "%") : I18n.tr("Unavailable")
                active: cc.mic !== null && !cc.micMuted
                accent: Theme.accent
                expandable: true
                expanded: cc.expanded === "mic"
                onToggled: { if (cc.mic) cc.mic.muted = !cc.mic.muted }
                onExpand: cc.expanded = (cc.expanded === "mic" ? "" : "mic")
            }
        }
        // Detalle en línea (audio / micro).
        ExpandableDetail {
            open: cc.expanded === "audio" || cc.expanded === "mic"
            sourceComponent: cc.expanded === "audio" ? audioComp
                           : cc.expanded === "mic"   ? micComp
                           : null
        }

        // El perfil se oculta si no está instalado power-profiles-daemon;
        // en ese caso Cafeína ocupa toda la fila.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space8
            opacity: cc.blockReveal(3)
            transform: Translate { y: (1 - cc.blockReveal(3)) * Theme.dp(14) }
            ControlTile {
                Layout.fillWidth: true
                visible: Power.available
                icon: Power.icon
                title: I18n.tr("Power profile")
                subtitle: Power.name
                active: true
                accent: Power.color
                expandable: true
                expanded: cc.expanded === "power"
                onToggled: Power.cycle()   // pulsar el icono → siguiente perfil
                onExpand: cc.expanded = (cc.expanded === "power" ? "" : "power")
            }
            ControlTile {
                Layout.fillWidth: true
                icon: "󰅶"   // taza de café
                title: I18n.tr("Caffeine")
                subtitle: Settings.caffeine ? I18n.tr("Stays awake") : I18n.tr("Disabled")
                active: Settings.caffeine
                accent: Theme.accent
                onToggled: Settings.caffeine = !Settings.caffeine
            }
        }
        // Detalle en línea del perfil de energía (selector desplegable).
        ExpandableDetail {
            open: Power.available && cc.expanded === "power"
            sourceComponent: (Power.available && cc.expanded === "power") ? powerComp : null
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space8
            opacity: cc.blockReveal(4)
            transform: Translate { y: (1 - cc.blockReveal(4)) * Theme.dp(14) }
            ControlTile {
                Layout.fillWidth: true
                icon: Globals.dnd ? "󰂛" : "󰂚"
                title: I18n.tr("Do not disturb")
                subtitle: Globals.dnd ? I18n.tr("Enabled") : I18n.tr("Disabled")
                active: Globals.dnd
                accent: Theme.accent
                onToggled: Globals.dnd = !Globals.dnd
            }
            ControlTile {
                Layout.fillWidth: true
                icon: Settings.darkMode ? "󰖔" : "󰖨"   // luna / sol
                title: I18n.tr("Dark mode")
                subtitle: Settings.darkMode ? I18n.tr("Enabled") : I18n.tr("Light mode")
                active: Settings.darkMode
                accent: Theme.accent
                onToggled: Settings.darkMode = !Settings.darkMode
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space8
            opacity: cc.blockReveal(5)
            transform: Translate { y: (1 - cc.blockReveal(5)) * Theme.dp(14) }
            ControlTile {
                Layout.fillWidth: true
                icon: "󰄀"
                title: "Captura"
                subtitle: ScreenCapture.modeLabel()
                active: Globals.screenCaptureOpen && !ScreenCapture.videoMode
                accent: Theme.cyan
                onToggled: ScreenCapture.openToolbar(false)
            }
            ControlTile {
                Layout.fillWidth: true
                icon: ScreenCapture.isRecording ? "󰑊" : "󰻂"
                title: "Grabar"
                subtitle: ScreenCapture.isRecording ? ScreenCapture.formatElapsed(ScreenCapture.recordingElapsed)
                                                    : "Pantalla"
                active: ScreenCapture.isRecording || (Globals.screenCaptureOpen && ScreenCapture.videoMode)
                accent: ScreenCapture.isRecording ? Theme.red : Theme.accent
                onToggled: ScreenCapture.openToolbar(true)
            }
        }
    }

    // ── Pantalla · brillo ──
    SliderCard {
        visible: Brightness.available
        opacity: cc.blockReveal(6)
        transform: Translate { y: (1 - cc.blockReveal(6)) * Theme.dp(14) }
        title: I18n.tr("Display")
        valueText: Brightness.percent + "%"
        icon: "󰃟"
        value: Brightness.percent / 100
        onMoved: (v) => Brightness.setPercent(v * 100)
    }

    // ── Sonido · volumen ──
    SliderCard {
        opacity: cc.blockReveal(7)
        transform: Translate { y: (1 - cc.blockReveal(7)) * Theme.dp(14) }
        title: I18n.tr("Sound")
        valueText: cc.audioMuted ? "off" : cc.audioPercent + "%"
        icon: cc.audioMuted ? "󰝟" : "󰕾"
        dimmed: cc.audioMuted
        value: cc.audioLevel
        onMoved: (v) => {
            if (cc.audio) {
                cc.audio.volume = v
                if (cc.audio.muted && v > 0) cc.audio.muted = false
            }
        }
    }

    Component { id: wifiComp;  WifiDetail {} }
    Component { id: btComp;    BluetoothDetail {} }
    Component { id: audioComp; AudioDetail {} }
    Component { id: micComp;   MicDetail {} }
    Component { id: powerComp; PowerDetail {} }

}
