import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Excepciones por herramienta, para cuando el modo general no basta: "que
// pueda escribir archivos sin preguntar, pero que jamás toque systemd".
//
// Aquí había cuarenta y una filas de tres botones, todas a la vista y todas
// iguales. Ahora son cuarenta y una LÍNEAS, agrupadas por lo que hace cada
// herramienta y con una sola píldora que cicla Preguntar → Auto → No. Lo que
// coincide con el modo no se guarda (ver AiService.setToolPolicy), así que el
// contador de excepciones dice la verdad y volver atrás limpia de verdad.
ColumnLayout {
    id: lista

    readonly property string q: buscar.text.trim().toLowerCase()

    // Las herramientas, repartidas por su clase de riesgo — la misma que
    // gobierna la aprobación, así que el grupo explica por qué una pide
    // permiso y otra no.
    readonly property var grupos: {
        const orden = ["read", "external", "write", "exec", "critical", "ask", "plan"]
        const nombres = ({
            read: I18n.tr("Read and query"),
            external: I18n.tr("Reach outside"),
            write: I18n.tr("Write files"),
            exec: I18n.tr("Run and act"),
            // Las que ejecutan código arbitrario: por más que se afloje la
            // correa, estas siempre pasan por ti.
            critical: I18n.tr("Critical — never automatic"),
            ask: I18n.tr("Ask you"),
            plan: I18n.tr("Plan")
        })
        const cubo = ({})
        const defs = AiService.toolDefs
        for (let i = 0; i < defs.length; i++) {
            const n = defs[i]["function"].name
            if (lista.q !== "" && n.toLowerCase().indexOf(lista.q) === -1)
                continue
            const r = AiService.riskClass(n)
            if (!cubo[r])
                cubo[r] = []
            cubo[r].push(n)
        }
        const out = []
        for (let k = 0; k < orden.length; k++)
            if (cubo[orden[k]])
                out.push({ risk: orden[k], label: nombres[orden[k]],
                           tools: cubo[orden[k]] })
        return out
    }

    Layout.fillWidth: true
    spacing: Theme.space6

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8
        SearchField {
            id: buscar
            Layout.fillWidth: true
            placeholder: I18n.tr("Filter tools…")
        }
        Chip {
            label: "󰩹 " + I18n.tr("Reset")
            danger: true
            enabled: AiService.toolOverrides > 0
            onDo: () => AiService.clearToolPolicies()
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: Math.min(inner.implicitHeight, Theme.dp(260))

        Flickable {
            id: flick
            anchors.fill: parent
            contentWidth: width
            contentHeight: inner.implicitHeight
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
                id: inner
                // Hueco fijo para la barra de desplazamiento: sin él, la
                // píldora de la derecha quedaba debajo de la barra.
                width: flick.width - Theme.space8
                spacing: Theme.space2

                Repeater {
                    model: lista.grupos
                    delegate: ColumnLayout {
                        id: grupo
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: Theme.space2

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: grupo.index === 0 ? 0 : Theme.space6
                            text: grupo.modelData.label.toUpperCase()
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.typeLabelSmall
                            font.bold: true
                            font.letterSpacing: Theme.typeLabelTracking
                        }

                        Repeater {
                            model: grupo.modelData.tools
                            delegate: Item {
                                id: fila
                                required property string modelData
                                readonly property string pol:
                                    AiService.toolPolicy(fila.modelData)
                                readonly property bool excepcion:
                                    (Settings.aiToolPolicies || {})[fila.modelData] !== undefined
                                Layout.fillWidth: true
                                implicitHeight: Math.max(filaRow.implicitHeight,
                                                         Theme.dp(30))

                                // Cuarenta filas sin ninguna respuesta al ratón:
                                // en una lista así, saber a cuál estás apuntando
                                // no es un lujo. Mismo resaltado que el resto del
                                // shell, y la fila ENTERA cicla la política —
                                // como cualquier fila de Ajustes, donde tocar la
                                // fila hace lo que hace su control.
                                RowHighlight {
                                    id: filaRealce
                                    hovered: filaMa.containsMouse
                                    bleedX: Theme.space6
                                    bleedY: Theme.space2
                                }
                                MouseArea {
                                    id: filaMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: (e) => filaRealce.press(e.x, e.y)
                                    onClicked: AiService.setToolPolicy(fila.modelData,
                                        fila.pol === "ask" ? "auto"
                                      : fila.pol === "auto" ? "off" : "ask")
                                }

                                RowLayout {
                                    id: filaRow
                                    anchors.fill: parent
                                    spacing: Theme.space8

                                    // Un punto marca lo que se ha tocado a mano: en
                                    // una lista de cuarenta, lo que se sale de la
                                    // norma tiene que verse sin leerla entera.
                                    Rectangle {
                                        implicitWidth: Theme.dp(5)
                                        implicitHeight: Theme.dp(5)
                                        radius: width / 2
                                        color: fila.excepcion ? Theme.accent : "transparent"
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: fila.modelData
                                        color: fila.pol === "off" ? Theme.fgMuted : Theme.fgDim
                                        font.family: Theme.monoFontFamily
                                        font.pixelSize: Theme.typeLabelMedium
                                        elide: Text.ElideMiddle
                                    }
                                    PolicyPill {
                                        policy: fila.pol
                                        onCycled: (v) => AiService.setToolPolicy(fila.modelData, v)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    EmptyNote {
        visible: lista.grupos.length === 0
        text: I18n.tr("No tool matches.")
    }

    Hint {
        Layout.leftMargin: 0
        text: I18n.tr("Ask · Auto (no card) · Off (the model never sees it). Anything you leave as the mode says is not stored.")
    }

    // Píldora de tres estados: un clic la cicla. Tres botones por fila
    // ocupaban el ancho entero cuarenta veces; el estado se lee igual de bien
    // en una palabra, y cambiarlo es un clic en vez de apuntar a un tercio.
    component PolicyPill: Rectangle {
        id: pill
        property string policy: "ask"
        signal cycled(string v)

        readonly property color tinte:
            policy === "auto" ? Theme.green
          : policy === "off" ? Theme.red
                             : Theme.fgMuted

        implicitWidth: Theme.dp(78)
        implicitHeight: Theme.dp(24)
        radius: height / 2
        color: Theme.withAlpha(tinte, pillMa.containsMouse ? 0.24 : 0.13)
        Behavior on color {
            ColorAnimation {
                duration: pillMa.containsMouse ? Theme.animHover : Theme.animHoverOut
                easing.type: pillMa.containsMouse ? Easing.OutCubic : Easing.InQuad
            }
        }
        scale: pillMa.pressed ? 0.95 : 1
        Behavior on scale {
            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.centerIn: parent
            text: pill.policy === "auto" ? I18n.tr("Auto")
                : pill.policy === "off" ? I18n.tr("Off")
                                        : I18n.tr("Ask")
            color: pill.tinte
            font.family: Theme.fontFamily
            font.pixelSize: Theme.typeLabelSmall
            font.bold: true
        }
        MouseArea {
            id: pillMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.cycled(pill.policy === "ask" ? "auto"
                                 : pill.policy === "auto" ? "off" : "ask")
        }
    }
}
