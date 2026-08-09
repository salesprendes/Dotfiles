import QtQuick
import qs.Config

// Glifo giratorio de "cargando/escaneando". Gira solo mientras es visible.
Text {
    text: "󰑮"
    color: Theme.accent
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize

    RotationAnimation on rotation {
        from: 0
        to: 360
        duration: Theme.animLoop
        loops: Animation.Infinite
        running: parent.visible
    }
}
