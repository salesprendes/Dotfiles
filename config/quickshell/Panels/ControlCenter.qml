import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.Components
import qs.Config
import qs.Panels
import qs.Services

// Centro de control estilo macOS: tarjetas compactas, sliders y
// detalles desplegables para WiFi / Bluetooth / Audio / Micro.
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

    function runPowerAction(action) {
        Globals.closeAll()
        if (action === "exit") {
            // El config de Hyprland usa parser Lua: cada dispatch se evalúa como
            // `hl.dispatch(<arg>)`. Por eso "exit" pelado falla (`hl.dispatch(exit)`
            // → variable inexistente); hay que pasar el dispatcher nativo válido.
            Hyprland.dispatch("hl.dsp.exit()")
        } else if (action === "lock") {
            // Pausa breve para que el popout termine de cerrarse y SUELTE el
            // teclado antes de que hyprlock tome el foco (si no, la pantalla
            // de contraseña aparece con el panel aún encima → se "bugea").
            Quickshell.execDetached(["sh", "-c", "sleep 0.25; command -v hyprlock >/dev/null && hyprlock || loginctl lock-session"])
        } else if (action === "reboot") {
            Quickshell.execDetached(["systemctl", "reboot"])
        } else if (action === "poweroff") {
            Quickshell.execDetached(["systemctl", "poweroff"])
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.dp(64)
        radius: Theme.barRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.62)
        border.width: Theme.hairline
        border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.34)

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
            model: [
                { ic: "󰍁", action: "lock", col: Theme.accent },
                { ic: "󰍃", action: "exit", col: Theme.yellow },
                { ic: "󰜉", action: "reboot",  col: Theme.orange },
                { ic: "󰐥", action: "poweroff", col: Theme.red }
            ]
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

                // Anillo que se rellena alrededor del botón mientras se mantiene.
                Canvas {
                    id: ring
                    anchors.fill: parent
                    anchors.margins: -2
                    visible: btn.holdProgress > 0
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var cx = width / 2, cy = height / 2
                        var r = width / 2 - 2
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, -Math.PI / 2,
                                -Math.PI / 2 + btn.holdProgress * 2 * Math.PI)
                        ctx.lineWidth = 2.5
                        ctx.lineCap = "round"
                        ctx.strokeStyle = btn.modelData.col
                        ctx.stroke()
                    }
                }
                onHoldProgressChanged: ring.requestPaint()

                // Avanza el progreso mientras se pulsa; al terminar, ejecuta.
                NumberAnimation {
                    id: holdAnim
                    target: btn; property: "holdProgress"
                    from: 0; to: 1; duration: btn.holdDuration
                    onFinished: {
                        cc.runPowerAction(btn.modelData.action)
                    }
                }
                // Retrocede suavemente si se suelta antes de completar.
                NumberAnimation {
                    id: resetAnim
                    target: btn; property: "holdProgress"
                    to: 0; duration: 150
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
                // Display inteligente: si hay cable, el tile representa la
                // conexión ETHERNET (prioritaria; convive con el wifi, que se
                // gestiona en el desplegable). Si no, la WiFi: SSID + cobertura,
                // o el estado cuando no hay red.
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
                subtitle: Globals.caffeine ? I18n.tr("Stays awake") : I18n.tr("Disabled")
                active: Globals.caffeine
                accent: Theme.accent
                onToggled: Globals.caffeine = !Globals.caffeine
            }
        }
        // Detalle en línea del perfil de energía (selector desplegable).
        ExpandableDetail {
            open: Power.available && cc.expanded === "power"
            sourceComponent: (Power.available && cc.expanded === "power") ? powerComp : null
        }

        // Fila 4 · No molestar + Modo oscuro (media fila, como en el grid original).
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
