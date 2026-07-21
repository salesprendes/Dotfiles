import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

PanelWindow {
    id: win

    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: Globals.screenCaptureOpen || openProgress > 0.01
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-screen-capture"
    WlrLayershell.keyboardFocus: Globals.screenCaptureOpen ? WlrKeyboardFocus.Exclusive
                                                           : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    property real openProgress: Globals.screenCaptureOpen ? 1 : 0
    property bool settingsExpanded: false
    // La barra se ajusta a su contenido (no ocupa un ancho fijo). Solo pasa a
    // modo compacto (iconos sin etiqueta) si la pantalla es demasiado estrecha.
    readonly property real availWidth: root.width - Theme.dp(24)
    readonly property int settingsWidth: Math.min(availWidth, Theme.dp(680))

    // Grupo exclusivo de los desplegables de ajustes: solo uno abierto a la vez.
    QtObject { id: settingsDropdowns; property var openItem: null }

    Behavior on openProgress {
        NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }

    Connections {
        target: Globals
        function onOpenPanelChanged() {
            if (Globals.screenCaptureOpen)
                Qt.callLater(root.forceActiveFocus)
            else
                win.settingsExpanded = false
        }
    }

    Item {
        id: root
        anchors.fill: parent
        focus: true
        opacity: win.openProgress
        scale: 0.96 + win.openProgress * 0.04

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                ScreenCapture.closeToolbar()
                event.accepted = true
            } else if (event.key === Qt.Key_Space) {
                ScreenCapture.primaryAction()
                event.accepted = true
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.bg, 0.20)
            MouseArea {
                anchors.fill: parent
                enabled: Globals.screenCaptureOpen
                onClicked: ScreenCapture.closeToolbar()
            }
        }

        ColumnLayout {
            id: stack
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Theme.barHeight + Theme.dp(34)
            // Ancho constante: animar el ancho de un Layout hace que el motor de
            // layouts pelee con la animación cada frame y la barra tiemble. Fijo,
            // solo se animan alto + opacidad + deslizamiento (sobre un Item). Con
            // el panel cerrado el ancho extra es transparente, así que solo se ve
            // la barra centrada y no hay salto.
            width: Math.min(win.availWidth, Math.max(toolbar.implicitWidth, win.settingsWidth))
            spacing: Theme.space10

            Rectangle {
                id: toolbar
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: toolbarRow.implicitWidth + Theme.space12 * 2
                implicitHeight: Theme.dp(60)
                radius: height / 2
                color: Theme.withAlpha(Theme.bg, 0.92)
                border.width: Theme.hairline
                border.color: Theme.withAlpha(Theme.overlay, 0.48)
                antialiasing: true

                MouseArea { anchors.fill: parent }

                RowLayout {
                    id: toolbarRow
                    anchors.centerIn: parent
                    spacing: Theme.space4

                    ModeButton {
                        icon: "󰄀"
                        active: !ScreenCapture.videoMode
                        onClicked: ScreenCapture.videoMode = false
                    }
                    ModeButton {
                        icon: ScreenCapture.isRecording ? "󰑊" : "󰻂"
                        active: ScreenCapture.videoMode
                        danger: ScreenCapture.isRecording
                        onClicked: ScreenCapture.videoMode = true
                    }

                    VSep {}

                    Repeater {
                        model: ScreenCapture.modeOptions
                        delegate: ModeButton {
                            required property var modelData
                            icon: modelData.icon
                            active: ScreenCapture.captureMode === modelData.value
                            onClicked: ScreenCapture.captureMode = modelData.value
                        }
                    }

                    VSep {}

                    IconButton {
                        icon: "󰒓"
                        diameter: Theme.dp(44)
                        iconPixelSize: Theme.iconSize + 4
                        baseColor: win.settingsExpanded ? Theme.withAlpha(Theme.accent, 0.22) : Theme.surface
                        hoverColor: Theme.accent
                        onClicked: win.settingsExpanded = !win.settingsExpanded
                    }

                    ActionButton {
                        text: ""
                        icon: ScreenCapture.videoMode
                              ? (ScreenCapture.isRecording ? "󰓛" : "󰻂")
                              : "󰄀"
                        compact: true
                        danger: ScreenCapture.videoMode
                        onClicked: ScreenCapture.primaryAction()
                    }
                }
            }

            Item {
                id: settingsClip
                Layout.fillWidth: true
                implicitHeight: win.settingsExpanded
                                ? Math.min(settingsContent.implicitHeight + Theme.space16 * 2,
                                           root.height - stack.anchors.topMargin - toolbar.height - Theme.dp(48))
                                : 0
                opacity: win.settingsExpanded ? 1 : 0
                clip: true
                // Alto y opacidad comparten curva y duración (Theme.animNormal),
                // así apertura y cierre van sincronizados.
                Behavior on implicitHeight { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.barRadius
                    color: Theme.popupBg
                    border.width: Theme.hairline
                    border.color: Theme.withAlpha(Theme.overlay, 0.50)
                    // Leve deslizamiento: el panel entra desde arriba y se asienta
                    // al abrir (acoplado a la opacidad ya animada, sin timers).
                    transform: Translate { y: (1 - settingsClip.opacity) * -Theme.dp(10) }

                    // Absorbe los clics dentro del panel pero fuera de una opción,
                    // para que uno accidental no atraviese al fondo y cierre.
                    MouseArea { anchors.fill: parent; onClicked: {} }

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Theme.space16
                        contentWidth: width
                        contentHeight: settingsContent.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        interactive: contentHeight > height + 1

                        ColumnLayout {
                            id: settingsContent
                            // Ancho fijo al valor final (no el del Flickable, que se
                            // anima): si no, alto y ancho se realimentan y tiembla.
                            // Mientras crece la caja, el contenido queda recortado.
                            width: Math.max(1, win.settingsWidth - Theme.space16 * 2)
                            spacing: Theme.space14

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space12
                                DropdownRow {
                                    group: settingsDropdowns
                                    Layout.fillWidth: true
                                    label: "Modo"
                                    options: ScreenCapture.modeOptions
                                    current: ScreenCapture.captureMode
                                    onPicked: (v) => ScreenCapture.captureMode = v
                                }
                                DropdownRow {
                                    group: settingsDropdowns
                                    Layout.fillWidth: true
                                    visible: ScreenCapture.captureMode === "monitor"
                                    label: "Monitor"
                                    options: ScreenCapture.monitorOptions
                                    current: ScreenCapture.videoMode ? ScreenCapture.recordMonitor : ScreenCapture.captureMonitor
                                    onPicked: (v) => {
                                        if (ScreenCapture.videoMode) ScreenCapture.recordMonitor = v
                                        else ScreenCapture.captureMonitor = v
                                    }
                                }
                            }

                            SettingsLabel { text: "Captura"; visible: !ScreenCapture.videoMode }
                            GridLayout {
                                Layout.fillWidth: true
                                visible: !ScreenCapture.videoMode
                                columns: 2
                                columnSpacing: Theme.space14
                                rowSpacing: Theme.space8

                                ToggleLine {
                                    label: "Guardar archivo"
                                    checked: ScreenCapture.saveToDisk
                                    onToggled: ScreenCapture.saveToDisk = !ScreenCapture.saveToDisk
                                }
                                ToggleLine {
                                    label: "Copiar"
                                    checked: ScreenCapture.copyToClipboard
                                    onToggled: ScreenCapture.copyToClipboard = !ScreenCapture.copyToClipboard
                                }
                                ToggleLine {
                                    label: "Notificar"
                                    checked: ScreenCapture.showNotify
                                    onToggled: ScreenCapture.showNotify = !ScreenCapture.showNotify
                                }
                                ToggleLine {
                                    // Sin hyprpicker, hyprshot omite el congelado en
                                    // silencio: mejor decirlo que fingir que funciona.
                                    label: ScreenCapture.hyprpickerAvailable
                                           ? "Congelar" : "Congelar (falta hyprpicker)"
                                    enabled: ScreenCapture.hyprpickerAvailable
                                    opacity: enabled ? 1 : 0.45
                                    checked: ScreenCapture.freeze && ScreenCapture.hyprpickerAvailable
                                    onToggled: ScreenCapture.freeze = !ScreenCapture.freeze
                                }
                                ToggleLine {
                                    label: "Puntero"
                                    checked: ScreenCapture.showPointer
                                    onToggled: ScreenCapture.showPointer = !ScreenCapture.showPointer
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: !ScreenCapture.videoMode
                                spacing: Theme.space12
                                DropdownRow {
                                    group: settingsDropdowns
                                    Layout.fillWidth: true
                                    label: "Formato"
                                    options: ScreenCapture.imageFormatOptions
                                    current: ScreenCapture.imageFormat
                                    onPicked: (v) => ScreenCapture.imageFormat = v
                                }
                                SliderRow {
                                    Layout.fillWidth: true
                                    visible: ScreenCapture.imageFormat === "jpg"
                                    label: "Calidad JPG"
                                    from: 10
                                    to: 100
                                    value: ScreenCapture.imageQuality
                                    valueText: ScreenCapture.imageQuality + "%"
                                    onMoved: (v) => ScreenCapture.imageQuality = Math.round(v)
                                }
                            }

                            TextField {
                                Layout.fillWidth: true
                                visible: !ScreenCapture.videoMode
                                label: "Carpeta de capturas"
                                placeholder: ScreenCapture.defaultScreenshotDir()
                                leftIcon: "󰉋"
                                value: ScreenCapture.screenshotDir
                                onEdited: (text) => ScreenCapture.screenshotDir = text
                            }
                            TextField {
                                Layout.fillWidth: true
                                visible: !ScreenCapture.videoMode
                                label: "Nombre de captura"
                                placeholder: "screenshot_%Y-%m-%d_%H-%M-%S." + ScreenCapture.imageFormat
                                leftIcon: "󰈔"
                                value: ScreenCapture.screenshotFilename
                                onEdited: (text) => ScreenCapture.screenshotFilename = text
                            }

                            SettingsLabel { text: "Grabación"; visible: ScreenCapture.videoMode }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: ScreenCapture.videoMode
                                spacing: Theme.space12
                                DropdownRow {
                                    group: settingsDropdowns
                                    Layout.fillWidth: true
                                    label: "Formato"
                                    options: ScreenCapture.videoFormatOptions
                                    current: ScreenCapture.videoFormat
                                    onPicked: (v) => ScreenCapture.videoFormat = v
                                }
                                DropdownRow {
                                    group: settingsDropdowns
                                    Layout.fillWidth: true
                                    label: "FPS"
                                    options: ScreenCapture.fpsOptions
                                    current: ScreenCapture.videoFps
                                    onPicked: (v) => ScreenCapture.videoFps = v
                                }
                                DropdownRow {
                                    group: settingsDropdowns
                                    Layout.fillWidth: true
                                    label: "Calidad"
                                    options: ScreenCapture.qualityOptions
                                    current: ScreenCapture.videoQuality
                                    onPicked: (v) => ScreenCapture.videoQuality = v
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: ScreenCapture.videoMode
                                spacing: Theme.space12
                                DropdownRow {
                                    group: settingsDropdowns
                                    Layout.fillWidth: true
                                    label: "Códec vídeo"
                                    options: ScreenCapture.videoCodecOptions
                                    current: ScreenCapture.videoCodec
                                    onPicked: (v) => ScreenCapture.videoCodec = v
                                }
                                DropdownRow {
                                    group: settingsDropdowns
                                    Layout.fillWidth: true
                                    label: "Códec audio"
                                    options: ScreenCapture.audioCodecOptions
                                    current: ScreenCapture.audioCodec
                                    onPicked: (v) => ScreenCapture.audioCodec = v
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                visible: ScreenCapture.videoMode
                                columns: 2
                                columnSpacing: Theme.space14
                                rowSpacing: Theme.space8

                                ToggleLine {
                                    label: "Audio del sistema"
                                    checked: ScreenCapture.recordSystemAudio
                                    onToggled: ScreenCapture.recordSystemAudio = !ScreenCapture.recordSystemAudio
                                }
                                ToggleLine {
                                    label: "Micrófono"
                                    checked: ScreenCapture.recordMic
                                    onToggled: ScreenCapture.recordMic = !ScreenCapture.recordMic
                                }
                                ToggleLine {
                                    label: "Píldora flotante"
                                    checked: ScreenCapture.showRecordingPill
                                    onToggled: ScreenCapture.showRecordingPill = !ScreenCapture.showRecordingPill
                                }
                            }

                            TextField {
                                Layout.fillWidth: true
                                visible: ScreenCapture.videoMode
                                label: "Carpeta de vídeos"
                                placeholder: ScreenCapture.videosDir
                                leftIcon: "󰉋"
                                value: ScreenCapture.videoDir
                                onEdited: (text) => ScreenCapture.videoDir = text
                            }
                            TextField {
                                Layout.fillWidth: true
                                visible: ScreenCapture.videoMode
                                label: "Nombre de vídeo"
                                placeholder: "recording_%Y-%m-%d_%H-%M-%S." + ScreenCapture.videoFormat
                                leftIcon: "󰈔"
                                value: ScreenCapture.videoFilename
                                onEdited: (text) => ScreenCapture.videoFilename = text
                            }

                            Text {
                                Layout.fillWidth: true
                                text: ScreenCapture.status !== "" ? ScreenCapture.status
                                    : ScreenCapture.gsrAvailable ? ""
                                    : "gpu-screen-recorder no está instalado; las capturas funcionan, grabar queda pendiente."
                                visible: text !== ""
                                color: ScreenCapture.gsrAvailable ? Theme.fgMuted : Theme.yellow
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }

    // Separador vertical fino entre grupos de la barra.
    component VSep: Rectangle {
        Layout.preferredWidth: Theme.hairline
        Layout.preferredHeight: Theme.dp(22)
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: Theme.space4
        Layout.rightMargin: Theme.space4
        color: Theme.withAlpha(Theme.overlay, 0.5)
    }

    component SettingsLabel: Text {
        Layout.fillWidth: true
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 3
        font.bold: true
        font.capitalization: Font.AllUppercase
    }

    component ToggleLine: RowLayout {
        id: row
        property string label: ""
        property bool checked: false
        signal toggled()
        Layout.fillWidth: true
        spacing: Theme.space8

        Text {
            Layout.fillWidth: true
            text: row.label
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
        }
        Switch {
            checked: row.checked
            onToggled: row.toggled()
        }
    }

    // Botón solo-icono de la barra (sin texto). Look segmentado: inactivo
    // transparente; activo/hover relleno.
    component ModeButton: Rectangle {
        id: btn
        property string icon: ""
        property bool active: false
        property bool danger: false
        signal clicked()

        readonly property bool hovered: ma.containsMouse || activeFocus
        readonly property color tint: danger ? Theme.red : Theme.accent
        activeFocusOnTab: enabled
        implicitWidth: Theme.dp(44)
        implicitHeight: Theme.dp(44)
        radius: height / 2
        color: active ? Theme.withAlpha(tint, hovered ? 0.34 : 0.26)
                      : hovered ? Theme.withAlpha(Theme.surfaceHi, 0.9)
                                : "transparent"
        border.width: activeFocus ? Theme.focusWidth : (active ? Theme.hairline : 0)
        border.color: activeFocus ? Theme.focusRing : Theme.withAlpha(tint, 0.55)
        // Resalte fluido: fundido de color/borde y leve escalado al pasar el ratón.
        scale: hovered && !active ? 1.08 : 1.0
        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

        Keys.onReturnPressed: btn.clicked()
        Keys.onEnterPressed: btn.clicked()
        Keys.onSpacePressed: btn.clicked()

        Text {
            anchors.centerIn: parent
            text: btn.icon
            color: btn.active ? btn.tint : (btn.hovered ? Theme.fg : Theme.fgDim)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize + 7
            // El glifo funde a la vez que el fondo, en lugar de saltar.
            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    component ActionButton: Rectangle {
        id: btn
        property string text: ""
        property string icon: ""
        property bool danger: false
        property bool compact: false
        signal clicked()

        readonly property bool hovered: ma.containsMouse || activeFocus
        activeFocusOnTab: enabled
        implicitWidth: compact ? Theme.dp(44)
                               : Math.max(Theme.dp(104), label.implicitWidth + Theme.controlL + Theme.space12)
        implicitHeight: Theme.dp(44)
        radius: height / 2
        color: hovered ? Qt.lighter(danger ? Theme.red : Theme.accent, 1.08)
                       : (danger ? Theme.red : Theme.accent)
        border.width: activeFocus ? Theme.focusWidth : 0
        border.color: Theme.focusRing
        // Resalte fluido: fundido con curva suave y leve escalado al hover.
        scale: hovered ? 1.05 : 1.0
        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

        Keys.onReturnPressed: btn.clicked()
        Keys.onEnterPressed: btn.clicked()
        Keys.onSpacePressed: btn.clicked()

        RowLayout {
            anchors.centerIn: parent
            spacing: Theme.space8
            Text {
                text: btn.icon
                color: Theme.bg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize + 7
            }
            Text {
                id: label
                visible: !btn.compact
                text: btn.text
                color: Theme.bg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
