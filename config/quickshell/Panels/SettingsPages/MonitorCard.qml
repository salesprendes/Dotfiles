import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Tarjeta de un monitor: resolución, escala, rotación, on/off.
SettingsCard {
    id: mc
    property var monitor
    readonly property var inf: Displays.info(monitor)
    readonly property var modes: Displays.modesFor(monitor)
    title: inf.name + (inf.description ? "  ·  " + inf.description : "")
    glyph: "󰍹"

    // Estado en edición (inicializado desde el estado actual).
    property string selMode: mc.defaultMode()
    property real   selScale: inf.scale
    property int    selTransform: inf.transform
    property bool   selEnabled: !inf.disabled

    function defaultMode() {
        const cur = mc.inf.width + "x" + mc.inf.height
        const m = mc.modes.find(x => x.res === cur)
        return m ? m.value : (mc.modes.length ? mc.modes[0].value : "")
    }

    DropdownRow {
        label: I18n.tr("Resolution")
        options: mc.modes
        current: mc.selMode
        onPicked: (v) => mc.selMode = v
    }
    DropdownRow {
        label: I18n.tr("Scale")
        options: [ { text: "100%", value: 1 }, { text: "125%", value: 1.25 },
                   { text: "150%", value: 1.5 }, { text: "175%", value: 1.75 },
                   { text: "200%", value: 2 } ]
        current: mc.selScale
        onPicked: (v) => mc.selScale = v
    }
    SegRow {
        label: I18n.tr("Rotation")
        options: [ { text: "0°", value: 0 }, { text: "90°", value: 1 },
                   { text: "180°", value: 2 }, { text: "270°", value: 3 } ]
        current: mc.selTransform
        onPicked: (v) => mc.selTransform = v
    }
    // Activar/desactivar solo con 2+ monitores (no apagar la única pantalla).
    SwitchRow {
        visible: Displays.monitors.length > 1
        label: I18n.tr("Enabled")
        checked: mc.selEnabled
        onToggled: mc.selEnabled = !mc.selEnabled
    }
    RowLayout {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        TextButton {
            text: I18n.tr("Apply")
            primary: true
            onClicked: {
                const parts = mc.selMode.split("@")
                Displays.apply(({
                    name: mc.inf.name,
                    res: parts[0],
                    refresh: (parts[1] || "").replace("Hz", "").trim(),
                    scale: mc.selScale,
                    transform: mc.selTransform,
                    x: mc.inf.x, y: mc.inf.y,
                    enabled: mc.selEnabled
                }))
            }
        }
    }
}
