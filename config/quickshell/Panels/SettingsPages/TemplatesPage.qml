pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config

// Plantillas: el interruptor maestro (Settings.templatesOn) vive en su propia
// tarjeta, separado de la parrilla de casillas — así queda claro que es un
// control aparte, no una fila más de la lista. Con el maestro apagado, la
// tarjeta de la parrilla entera desaparece (vía ExpandableDetail: barrido de
// recorte + fundido animados, no un corte en seco) y por tanto no se puede
// activar/desactivar nada; con el maestro encendido, reaparece completa y
// cada casilla se activa/desactiva a mano. El maestro NO toca qué
// apps tenía marcadas cada uno (Settings.templatesEnabled/gtkThemingEnabled
// siguen intactos apagado o no) — al reactivar, vuelve exactamente a lo que
// ya estaba. Nada de plantillas de comunidad (esas se descargan de una API
// externa y no las traemos). Solo se listan las apps detectadas en el
// sistema (AppTemplates.installed) — GTK es la excepción, siempre cuenta
// como instalado y aparece como una casilla más en "Sistema". Cada plantilla
// activa se aplica sin pasos manuales: el archivo de config de la app se
// edita solo (ver Config/AppTemplates.qml).
ColumnLayout {
    id: page
    spacing: Theme.space14

    readonly property var categoryOrder: ["system", "terminal", "editor", "compositor", "audio", "misc"]
    function categoryLabel(cat) {
        switch (cat) {
        case "system":     return I18n.tr("System")
        case "terminal":   return I18n.tr("Terminal")
        case "editor":     return I18n.tr("Editor")
        case "compositor": return I18n.tr("Compositor")
        case "audio":      return I18n.tr("Audio")
        default:           return I18n.tr("Other")
        }
    }

    // Solo se listan las apps detectadas en el sistema (AppTemplates.installed,
    // 'which <bin>'); GTK siempre cuenta como instalado (ver isInstalled).
    readonly property var installedList: AppTemplates.registry.filter(function (r) { return AppTemplates.isInstalled(r.id) })
    readonly property var groups: categoryOrder
        .map(function (cat) { return { category: cat, items: page.installedList.filter(function (r) { return r.category === cat }) } })
        .filter(function (g) { return g.items.length > 0 })

    // Grilla compartida por todas las categorías, para que las columnas
    // queden alineadas entre secciones en vez de recalcularse por grupo.
    readonly property int chipMinWidth: Theme.dp(108)
    readonly property int gridSpacing: Theme.space8
    readonly property int columns: Math.max(2, Math.floor((width + gridSpacing) / (chipMinWidth + gridSpacing)))
    readonly property real chipWidth: (width - (columns - 1) * gridSpacing) / columns

    SettingsCard {
        title: I18n.tr("Templates"); glyph: "󰈔"

        Hint {
            text: I18n.tr("Built-in templates render this theme's colors into other apps' config files, fully automatically — no extra steps.")
        }

        SwitchRow {
            skey: "templatesOn"
            label: I18n.tr("Enable templates")
            desc: I18n.tr("Turns the whole feature on or off. Your picks below stay saved either way.")
            checked: Settings.templatesOn
            onToggled: Settings.templatesOn = !Settings.templatesOn
        }
    }

    // Aparece/desaparece con un barrido de recorte + fundido (ver
    // Components/ExpandableDetail.qml), no de golpe: es la misma firma de
    // movimiento que usa el resto del shell (paneles de Centro de control).
    ExpandableDetail {
        open: Settings.templatesOn
        sourceComponent: availableCardComp
    }

    Component {
        id: availableCardComp
        SettingsCard {
            title: I18n.tr("Available templates"); glyph: "󰈔"

            Repeater {
                model: page.groups

                delegate: ColumnLayout {
                    id: catGroup
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space8
                    spacing: Theme.space8

                    Text {
                        text: page.categoryLabel(catGroup.modelData.category)
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.sp(11)
                        font.bold: true
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: page.columns
                        columnSpacing: page.gridSpacing
                        rowSpacing: page.gridSpacing

                        Repeater {
                            model: catGroup.modelData.items

                            delegate: TemplateChip {
                                id: chipItem
                                required property var modelData
                                Layout.preferredWidth: page.chipWidth
                                glyph: chipItem.modelData.glyph
                                label: chipItem.modelData.label
                                active: AppTemplates.isActive(chipItem.modelData.id)
                                onToggled: AppTemplates.setEnabled(chipItem.modelData.id, !AppTemplates.isEnabled(chipItem.modelData.id))
                            }
                        }
                    }
                }
            }

            Hint {
                shown: page.installedList.length === 0
                text: I18n.tr("No supported apps detected on this system yet.")
            }
        }
    }
}
