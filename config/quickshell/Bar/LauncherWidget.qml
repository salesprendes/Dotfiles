import QtQuick
import qs.Config
import qs.Components
import qs.Services

Pill {
    id: root
    interactive: true
    active: Globals.launcherOpen
    onClicked: Globals.toggleLauncher()

    BarGlyph {
        text: SysMon.distroGlyph
        color: Globals.launcherOpen ? Theme.accent2 : Theme.accent
        sizeDelta: 3
        animateColor: true
    }
}
