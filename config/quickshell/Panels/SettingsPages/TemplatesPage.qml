pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config

// Plantillas: el interruptor maestro vive en su propia tarjeta, separado de la
// parrilla de casillas, para que quede claro que es un control aparte y no una
// fila más de la lista.
//
// Con el maestro apagado, la tarjeta de la parrilla desaparece con barrido y
// fundido, no de golpe. El maestro no toca qué apps tenía marcadas cada una, así
// que al reactivar vuelve exactamente lo que ya estaba.
//
// Solo se listan las apps detectadas en el sistema, con GTK como excepción porque
// siempre cuenta como instalado. Cada plantilla activa se aplica sin pasos
// manuales: el archivo de configuración de la app se edita solo.
SettingsPage {
    id: page

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
        // Va como subtítulo del rótulo, fuera de la tarjeta (ver
        // SettingsCard.description): dentro era un párrafo suelto sin insignia
        // ni control que rompía la retícula de filas en la primera línea.
        description: I18n.tr("Built-in templates render this theme's colors into other apps' config files, fully automatically — no extra steps.")

        SwitchRow {
            glyph: "󰈙"
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

                    // Rótulo de categoría, en caja normal. Iba en versalitas
                    // espaciadas, que es justo el gesto que se quitó de los
                    // rótulos de sección: dejarlo aquí hacía que dentro de una
                    // misma página convivieran las dos tipografías de rótulo.
                    ThemedText {
                        text: page.categoryLabel(catGroup.modelData.category)
                        color: Theme.fgDim
                        font.pixelSize: Theme.typeLabelMedium
                        font.weight: Font.Medium
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
