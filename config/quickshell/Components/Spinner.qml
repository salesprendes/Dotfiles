import QtQuick
import qs.Config

// Glifo giratorio de "cargando/escaneando". Gira solo mientras es visible.
ThemedText {
    text: "󰑮"
    color: Theme.accent

    RotationAnimation on rotation {
        from: 0
        to: 360
        duration: Theme.animLoop
        loops: Animation.Infinite
        running: parent.visible
    }
}
