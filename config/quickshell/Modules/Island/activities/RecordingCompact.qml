import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// "Se está grabando": punto rojo latiendo y el tiempo que llevas.
//
// Un punto rojo quieto se mira una vez y se convierte en parte del decorado.
// Late porque tiene que seguir contando algo a los veinte minutos, que es justo
// cuando ya no te acuerdas de que le diste a grabar. Al PAUSAR se para y se
// vuelve ámbar: parado quiere decir parado, y un punto que sigue latiendo en
// pausa diría lo contrario.
RowLayout {
    id: root
    spacing: Theme.space8

    readonly property bool pausada: ScreenCapture.isPaused

    Rectangle {
        id: punto
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Theme.dp(10)
        implicitHeight: Theme.dp(10)
        radius: height / 2
        color: root.pausada ? Theme.yellow : Theme.red
        antialiasing: true

        SequentialAnimation on opacity {
            // "Sin animaciones" en Ajustes ▸ Tema deja el punto fijo y opaco.
            running: !root.pausada && Theme.animNormal > 0
            loops: Animation.Infinite
            NumberAnimation { to: 0.42; duration: 720; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 720; easing.type: Easing.InOutSine }
        }
        // Al pausar, la animación se detiene DONDE IBA: si la para a mitad, el
        // punto se queda medio transparente para siempre. Se devuelve a mano.
        onColorChanged: if (root.pausada) punto.opacity = 1
    }

    ThemedText {
        text: root.pausada ? I18n.tr("Paused") : I18n.tr("Recording")
        color: Theme.fg
        font.pixelSize: Theme.typeBodySmall
    }

    ThemedText {
        text: ScreenCapture.formatElapsed(ScreenCapture.recordingElapsed)
        color: Theme.fgDim
        font.family: Theme.monoFontFamily
        font.pixelSize: Theme.typeBodySmall
        // Cifras de ancho fijo: sin esto la isla se ensancha y se estrecha un
        // pelo cada segundo, porque el 1 mide menos que el 8 — y la isla mide
        // su ancho a partir del contenido, así que el muelle lo perseguiría.
        font.features: ({ "tnum": 1 })
    }
}
