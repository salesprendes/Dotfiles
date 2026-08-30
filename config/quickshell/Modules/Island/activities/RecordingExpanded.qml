import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Hoja de la grabación: el cronómetro grande y los mandos.
//
// ── POR QUÉ EXISTE ESTE ARCHIVO ─────────────────────────────────────────────
// Con la isla encendida, Panels/RecordingPill.qml no se construye. Esa píldora
// no era solo un aviso: llevaba PARAR, pausar y capturar sin cortar. Enseñar el
// punto rojo y quedarse ahí habría dejado una grabación que solo se para por el
// panel de capturas o matando el proceso a mano — un cambio que resta.
//
// Así que los mandos se mudan aquí: el punto rojo avisa, y un clic sobre él da
// exactamente lo mismo que daba la píldora.
ColumnLayout {
    id: root
    spacing: Theme.space12
    implicitWidth: Theme.dp(300)

    readonly property bool pausada: ScreenCapture.isPaused

    // ── Cabecera: estado y cronómetro ────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space10

        Rectangle {
            id: punto
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Theme.dp(12)
            implicitHeight: Theme.dp(12)
            radius: height / 2
            color: root.pausada ? Theme.yellow : Theme.red
            antialiasing: true

            SequentialAnimation on opacity {
                running: !root.pausada && Theme.animNormal > 0
                loops: Animation.Infinite
                NumberAnimation { to: 0.42; duration: 720; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 720; easing.type: Easing.InOutSine }
            }
            onColorChanged: if (root.pausada) punto.opacity = 1
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            ThemedText {
                Layout.fillWidth: true
                text: root.pausada ? I18n.tr("Paused") : I18n.tr("Recording")
                color: Theme.fg
                font.pixelSize: Theme.sp(15)
                elide: Text.ElideRight
            }
            ThemedText {
                Layout.fillWidth: true
                visible: text !== ""
                text: ScreenCapture.recordMonitor === "focused" ? ""
                                                                : ScreenCapture.recordMonitor
                color: Theme.fgMuted
                font.pixelSize: Theme.typeLabelSmall
                elide: Text.ElideRight
            }
        }

        ThemedText {
            text: ScreenCapture.formatElapsed(ScreenCapture.recordingElapsed)
            color: root.pausada ? Theme.yellow : Theme.red
            font.family: Theme.monoFontFamily
            font.pixelSize: Theme.sp(19)
            font.features: ({ "tnum": 1 })
        }
    }

    // ── Mandos ───────────────────────────────────────────────────────────────
    // Los mismos tres de la píldora y en el mismo orden, para que quien ya se
    // sabía aquello no tenga que volver a aprendérselo. El de PARAR va aparte,
    // al final y en rojo: es el único que no se puede deshacer.
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8

        IconButton {
            icon: "󰄀"
            diameter: Theme.controlL
            baseColor: Theme.withAlpha(Theme.cyan, 0.18)
            hoverColor: Theme.cyan
            iconColor: Theme.cyan
            // Captura una foto sin cortar el vídeo. El servicio se esconde a sí
            // mismo unos segundos para no salir en ella (pillSuppressed), y eso
            // arrastra a la isla: ver Modules/Island/sources/RecordSource.qml.
            onClicked: ScreenCapture.captureWhileRecording()
        }

        IconButton {
            icon: root.pausada ? "󰐊" : "󰏤"
            diameter: Theme.controlL
            baseColor: Theme.withAlpha(Theme.yellow, 0.18)
            hoverColor: Theme.yellow
            iconColor: Theme.yellow
            onClicked: root.pausada ? ScreenCapture.resumeRecording()
                                    : ScreenCapture.pauseRecording()
        }

        Item { Layout.fillWidth: true }

        IconButton {
            icon: "󰓛"
            diameter: Theme.controlL
            baseColor: Theme.withAlpha(Theme.red, 0.22)
            hoverColor: Theme.red
            iconColor: Theme.red
            onClicked: ScreenCapture.stopRecording()
        }
    }
}
