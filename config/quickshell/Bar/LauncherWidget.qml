import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Components
import qs.Services

Pill {
    id: root
    interactive: true
    onClicked: Globals.toggleLauncher()

    Text {
        text: SysMon.distroGlyph
        color: Globals.launcherOpen ? Theme.accent2 : Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize + 3
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
}
