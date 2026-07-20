import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.Components
import qs.Config
import qs.Panels
import qs.Services

// Centro de control: tarjetas compactas, sliders y detalles desplegables para
// WiFi, Bluetooth, audio y micrófono.
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

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.dp(64)
        radius: Theme.barRadius
        color: Theme.withAlpha(Theme.surface, 0.62)
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.34)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space14
            anchors.rightMargin: Theme.space8
            spacing: Theme.space10

            // Logo del sistema operativo (glifo Nerd Font del distro).
            Text {
                text: SysMon.distroGlyph
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.dp(34)
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
        Repeater {
            // Modelo compartido con el lanzador (Config/PowerActions.qml).
            model: PowerActions.model
            delegate: Item {
                id: btn
                required property var modelData
                implicitWidth: Theme.controlM; implicitHeight: Theme.controlM

                // Progreso de "mantener pulsado" (0 → 1). Al llegar a 1 ejecuta.
                property real holdProgress: 0
                readonly property int holdDuration: 800

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: pwMa.containsMouse ? btn.modelData.col : Theme.surface
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        anchors.centerIn: parent
                        text: btn.modelData.ic
                        color: pwMa.containsMouse ? Theme.bg : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
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

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space10

        ControlSlider {
            Layout.fillWidth: true
            icon: cc.audioMuted ? "󰝟" : "󰕾"
            title: I18n.tr("Sound")
            valueText: cc.audioMuted ? "off" : cc.audioPercent + "%"
            accent: Theme.accent
            value: cc.audioLevel
            onMoved: (v) => {
                if (cc.audio) {
                    cc.audio.volume = v
                    if (cc.audio.muted && v > 0) cc.audio.muted = false
                }
            }
        }
        ControlSlider {
            Layout.fillWidth: true
            visible: Brightness.available
            icon: "󰃟"
            title: I18n.tr("Display")
            valueText: Brightness.percent + "%"
            accent: Theme.accent
            value: Brightness.percent / 100
            onMoved: (v) => Brightness.setPercent(v * 100)
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.space10

        // Fila 1 · WiFi + Bluetooth
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space10
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

        // Detalle en línea de la fila 1 (se despliega animando su altura).
        ExpandableDetail {
            open: cc.expanded === "wifi" || cc.expanded === "bt"
            sourceComponent: cc.expanded === "wifi" ? wifiComp
                           : cc.expanded === "bt"   ? btComp
                           : null
        }

        // Fila 2 · Sonido + Micrófono
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space10
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
        // Detalle en línea de la fila 2 (audio / micro).
        ExpandableDetail {
            open: cc.expanded === "audio" || cc.expanded === "mic"
            sourceComponent: cc.expanded === "audio" ? audioComp
                           : cc.expanded === "mic"   ? micComp
                           : null
        }

        // Fila 3 · Perfil de energía + Cafeína.
        // El perfil se oculta si no está instalado power-profiles-daemon;
        // en ese caso Cafeína ocupa toda la fila.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space10
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

        // Fila 4 · Captura + grabacion.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space10
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

        // Fila 5 · No molestar + Modo oscuro.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space10
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
    }

    Component { id: wifiComp;  WifiDetail {} }
    Component { id: btComp;    BluetoothDetail {} }
    Component { id: audioComp; AudioDetail {} }
    Component { id: micComp;   MicDetail {} }
    Component { id: powerComp; PowerDetail {} }

}
