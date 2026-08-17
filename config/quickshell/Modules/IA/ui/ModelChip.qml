import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages
import qs.Modules.IA.core

// El botón que elige el cerebro, en la cabecera del panel.
//
// Dice tres cosas en una línea de 30 px: qué modelo hay puesto (por su NOMBRE,
// no por su ruta), de quién es, y si contesta — el punto es el mismo semáforo
// de la conexión, así que el botón que abre el selector ya avisa de que el
// servidor está caído sin abrir nada. Antes esto era un desplegable de ajustes
// con la etiqueta vacía: enseñaba el id entero cortado a la mitad y no decía
// nada del estado.
Rectangle {
    id: chip

    property bool open: false
    signal toggled()

    readonly property bool ready: AiService.model !== ""
    readonly property color dotColor:
        AiService.connState === "ok" ? Theme.green
      : AiService.connState === "fail" ? Theme.red
      : AiService.connState === "probing" ? Theme.accent
      : Theme.fgMuted

    implicitWidth: fila.implicitWidth + Theme.space10 * 2
    implicitHeight: Theme.dp(28)
    radius: height / 2
    color: chip.open ? SettingsPalette.accentSoft
         : ma.containsMouse ? SettingsPalette.settingsHover
         : "transparent"
    // Entra casi instantáneo y sale con calma: el fondo sigue al
    // puntero, y los 100 ms de una transición normal se notan
    // como retraso (ver Theme.animHover).
    Behavior on color {
        ColorAnimation {
            duration: ma.containsMouse ? Theme.animHover
                                       : Theme.animHoverOut
            easing.type: ma.containsMouse ? Easing.OutCubic
                                          : Easing.InQuad
        }
    }
    // Se hunde al pulsar: el gesto se siente antes de que la lámina abra.
    scale: ma.pressed ? 0.97 : 1
    Behavior on scale {
        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }
    clip: true

    Ripple { id: ripple }

    RowLayout {
        id: fila
        anchors.centerIn: parent
        spacing: Theme.space6

        // Semáforo de la conexión. Late mientras sondea, como en la ficha de
        // estado de la configuración.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Theme.dp(7)
            implicitHeight: Theme.dp(7)
            radius: width / 2
            color: chip.dotColor
            Behavior on color { ColorAnimation { duration: Theme.animNormal } }
            SequentialAnimation on opacity {
                running: AiService.connState === "probing"
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: Math.round(Theme.animLoop / 3) }
                NumberAnimation { to: 1.0; duration: Math.round(Theme.animLoop / 3) }
            }
            onOpacityChanged: if (AiService.connState !== "probing" && opacity !== 1)
                opacity = 1
        }

        Text {
            Layout.maximumWidth: Theme.dp(170)
            text: chip.ready ? AiService.modelShort(AiService.model)
                             : I18n.tr("Choose a model")
            color: chip.ready ? Theme.fgDim : Theme.accentText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.typeLabelMedium
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Text {
            visible: chip.ready
            // providerLabel y no provider.label: el servidor propio se rotula
            // con I18n, que una biblioteca pura no puede ver.
            text: AiService.providerLabel
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.typeLabelSmall
        }
        Text {
            text: "󰅀"
            rotation: chip.open ? 180 : 0
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.sp(11)
            Behavior on rotation {
                NumberAnimation {
                    duration: Theme.animNormal
                    easing.type: Theme.reflowEasing
                }
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (e) => ripple.press(e.x, e.y)
        onClicked: chip.toggled()
    }
}
