import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Selector de modelo: la lámina que abre el botón de la cabecera.
//
// Antes era una fila de ajustes reaprovechada (DropdownRow con la etiqueta
// vacía) metida a presión bajo el título: un desplegable de sistema con el id
// entero — "qwen/qwen3-30b-a3b:free" — cortado a la mitad. Elegir el cerebro
// del asistente es de las tres cosas que más se tocan en el panel, y merece un
// control propio: se busca escribiendo, se lee por NOMBRE, y los modelos van
// agrupados por proveedor, así que cambiar de la nube a lo local es un clic en
// otro grupo y no un viaje a la configuración.
ColumnLayout {
    id: sheet

    // Elegido: el panel cierra la lámina.
    signal chosen()

    readonly property string q: search.text.trim().toLowerCase()
    // Los grupos ya filtrados. Se calcula UNA vez y de aquí salen tanto la
    // lista pintada como el primero (el que se lleva el Enter).
    readonly property var groups: {
        const out = []
        const gs = AiService.modelGroups
        for (let i = 0; i < gs.length; i++) {
            const ms = sheet.q === "" ? gs[i].models
                : gs[i].models.filter(m => m.toLowerCase().indexOf(sheet.q) !== -1
                                        || gs[i].label.toLowerCase().indexOf(sheet.q) !== -1)
            if (ms.length > 0)
                out.push({ provider: gs[i].provider, label: gs[i].label,
                           active: gs[i].active, models: ms })
        }
        return out
    }
    readonly property int total: {
        let n = 0
        for (let i = 0; i < groups.length; i++)
            n += groups[i].models.length
        return n
    }

    function pick(prov, m) {
        AiService.setModel(prov === Settings.aiProvider ? m : prov + ":" + m)
        sheet.chosen()
    }
    // El primero de la lista: lo que se lleva el Enter del buscador.
    function pickFirst() {
        if (groups.length === 0) {
            // Sin coincidencias, lo escrito ES el modelo: un id recién salido
            // del catálogo del proveedor se pega y se usa, sin pasar por la
            // configuración avanzada.
            if (sheet.q !== "")
                AiService.setModel(search.text.trim())
            sheet.chosen()
            return
        }
        pick(groups[0].provider, groups[0].models[0])
    }

    Layout.fillWidth: true
    spacing: Theme.space8

    SearchField {
        id: search
        Layout.fillWidth: true
        placeholder: I18n.tr("Search or paste a model id…")
        accentIconOnFocus: true
        onAccepted: sheet.pickFirst()
        Component.onCompleted: input.forceActiveFocus()

        // Refrescar el catálogo es preguntarle al servidor: la misma sonda que
        // el botón "Probar" de la configuración, aquí donde importa.
        IconButton {
            icon: "󰑐"
            diameter: Theme.dp(26)
            iconPixelSize: Theme.sp(13)
            baseColor: "transparent"
            iconColor: AiService.connState === "probing" ? Theme.accent : Theme.fgMuted
            enabled: AiService.modelsUrl !== ""
            opacity: enabled ? 1 : 0.4
            onClicked: AiService.testConnection()
            RotationAnimation on rotation {
                running: AiService.connState === "probing"
                from: 0; to: 360
                duration: Theme.animLoop
                loops: Animation.Infinite
            }
            onRotationChanged: if (AiService.connState !== "probing" && rotation !== 0)
                rotation = 0
        }
    }

    // La lista. Tope de altura con desplazamiento dentro: el catálogo de
    // OpenRouter son cientos de modelos y la lámina no puede empujar la
    // conversación fuera del panel.
    Item {
        Layout.fillWidth: true
        implicitHeight: Math.min(listCol.implicitHeight, Theme.dp(280))

        Flickable {
            id: flick
            anchors.fill: parent
            contentWidth: width
            contentHeight: listCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height + 0.5

            ScrollBar.vertical: ThinScrollBar {
                policy: flick.contentHeight > flick.height + 1
                    ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                rightPadding: 0
                restOpacity: 0.35
            }

            ColumnLayout {
                id: listCol
                // Hueco fijo para la barra de desplazamiento (ver
                // ToolPolicyList): la insignia ":free" iba a su derecha.
                width: flick.width - Theme.space8
                spacing: Theme.space2

                Repeater {
                    model: sheet.groups
                    delegate: ColumnLayout {
                        id: grupo
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: Theme.space2

                        // Cabecera de proveedor: nombre y, en el activo, el
                        // semáforo de la conexión. El botón de la cabecera dice
                        // qué modelo hay puesto; aquí se ve si contesta.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: grupo.index === 0 ? 0 : Theme.space6
                            Layout.bottomMargin: Theme.space2
                            spacing: Theme.space6

                            Rectangle {
                                visible: grupo.modelData.active
                                implicitWidth: Theme.dp(7)
                                implicitHeight: Theme.dp(7)
                                radius: width / 2
                                color: AiService.connState === "ok" ? Theme.green
                                     : AiService.connState === "fail" ? Theme.red
                                     : AiService.connState === "probing" ? Theme.accent
                                     : Theme.fgMuted
                                Behavior on color { ColorAnimation { duration: Theme.animNormal } }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: grupo.modelData.label.toUpperCase()
                                color: grupo.modelData.active ? Theme.accentText : Theme.fgMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.typeLabelSmall
                                font.bold: true
                                font.letterSpacing: Theme.typeLabelTracking
                                elide: Text.ElideRight
                            }
                        }

                        Repeater {
                            model: grupo.modelData.models
                            delegate: Rectangle {
                                id: fila
                                required property string modelData
                                readonly property bool sel: grupo.modelData.active
                                    && modelData === AiService.model
                                Layout.fillWidth: true
                                implicitHeight: Theme.dp(36)
                                radius: Theme.shapeSm
                                color: fila.sel ? SettingsPalette.selectedTint
                                     : filaMa.containsMouse ? SettingsPalette.settingsHover
                                     : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                clip: true

                                Ripple { id: filaRipple }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space8
                                    anchors.rightMargin: Theme.space10
                                    spacing: Theme.space8

                                    // La marca del elegido. Reserva su sitio
                                    // siempre, así los nombres no bailan a
                                    // izquierda y derecha al cambiar de modelo.
                                    Text {
                                        Layout.preferredWidth: Theme.dp(14)
                                        horizontalAlignment: Text.AlignHCenter
                                        text: fila.sel ? "󰄲" : ""
                                        color: Theme.accentText
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.sp(13)
                                    }
                                    // El NOMBRE, grande; la ruta entera, debajo
                                    // y en pequeño, solo cuando aporta algo.
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            Layout.fillWidth: true
                                            text: AiService.modelShort(fila.modelData)
                                            color: fila.sel ? Theme.fg : Theme.fgDim
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.typeLabelLarge
                                            font.weight: fila.sel ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: AiService.modelShort(fila.modelData) === fila.modelData
                                                ? "" : fila.modelData
                                            color: Theme.fgMuted
                                            font.family: Theme.monoFontFamily
                                            font.pixelSize: Theme.typeLabelSmall
                                            elide: Text.ElideMiddle
                                        }
                                    }
                                    // Insignia de la etiqueta del id (":free").
                                    Rectangle {
                                        visible: AiService.modelTag(fila.modelData) !== ""
                                        implicitWidth: tagTxt.implicitWidth + Theme.space8 * 2
                                        implicitHeight: Theme.dp(18)
                                        radius: height / 2
                                        color: Theme.withAlpha(Theme.green, 0.16)
                                        Text {
                                            id: tagTxt
                                            anchors.centerIn: parent
                                            text: AiService.modelTag(fila.modelData)
                                            color: Theme.green
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.typeLabelSmall
                                            font.bold: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: filaMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: (e) => filaRipple.press(e.x, e.y)
                                    onClicked: sheet.pick(grupo.modelData.provider,
                                                          fila.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Nada encontrado: lo escrito se usa tal cual. Un servidor propio puede
    // servir un id que su /models no publica, y esperar a que el catálogo lo
    // sepa sería quedarse sin hablar.
    EmptyNote {
        visible: sheet.total === 0
        text: sheet.q === "" ? I18n.tr("No models published yet — write its id.")
                             : I18n.tr("Press Enter to use \"%1\"").arg(search.text.trim())
    }

    Hint {
        Layout.leftMargin: 0
        shown: sheet.total > 0
        text: I18n.tr("Enter picks the first one. Prefix with provider: (\"ollama:qwen3\") to switch brain and provider at once.")
    }
}
