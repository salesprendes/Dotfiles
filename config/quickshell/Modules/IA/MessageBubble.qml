import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Una intervención del chat. Cuatro papeles, cuatro voces:
//   user      burbuja tonal de acento, a la derecha; con etiqueta de adjuntos
//             si los llevaba, y Editar/Eliminar al posarse.
//   assistant sin burbuja — avatar + contenido a lo ancho. El texto se parte
//             en segmentos: la prosa va en Markdown y cada bloque ``` en su
//             propia lápida con etiqueta de lenguaje y COPIAR por bloque.
//   tool      tarjeta de aprobación: el modelo propone un comando o una URL
//             y NADA corre hasta que pulses Aprobar. Resuelta, enseña la
//             salida plegada.
//   error     tarjeta roja con reintento.
Item {
    id: bubble
    property string role: "user"
    property string content: ""
    property string reasoning: ""
    property string modelName: ""
    property real ms: 0
    property int tokens: 0
    property string toolName: ""
    property string toolArgs: ""
    property string toolResult: ""
    property string toolStatus: ""
    property string attachNote: ""
    property string ts: ""
    property int msgIndex: -1
    // La burbuja en vivo (streaming): sin pie ni acciones, su texto aún cambia.
    property bool live: false
    property bool isLast: false

    property bool showReasoning: false
    property bool showToolOut: false
    // Salida del diff de write_file (vacío = plegado).
    property string _diffOut: ""

    readonly property bool isUser: role === "user"
    readonly property bool isError: role === "error"
    readonly property bool isTool: role === "tool"
    readonly property bool isInfo: role === "info"
    readonly property bool isAssistant: !isUser && !isError && !isTool && !isInfo

    // Lo que pide la herramienta, ya legible, y su titular.
    readonly property var _args: {
        if (!isTool) return ({})
        try { return JSON.parse(toolArgs) } catch (e) { return ({ raw: toolArgs }) }
    }
    readonly property string toolPretty:
        toolName === "open_url"  ? (_args.url || _args.raw || "")
      : toolName === "read_file" || toolName === "list_dir"
        || toolName === "write_file" ? (_args.path || _args.raw || "")
      : toolName === "remember"  ? (_args.note || _args.raw || "")
      : (_args.command || _args.raw || "")
    // Solo write_file lleva algo más que la ruta: el contenido, previsualizado
    // ANTES de aprobar — nadie firma un archivo sin verlo.
    readonly property string toolPreview:
        toolName === "write_file" ? String(_args.content || "").slice(0, 1200) : ""
    readonly property string toolHeadline:
        toolName === "open_url"   ? I18n.tr("The assistant wants to open:")
      : toolName === "read_file"  ? I18n.tr("The assistant wants to read:")
      : toolName === "list_dir"   ? I18n.tr("The assistant wants to list:")
      : toolName === "write_file" ? I18n.tr("The assistant wants to write:")
      : toolName === "remember"   ? I18n.tr("The assistant wants to remember:")
      : I18n.tr("The assistant wants to run:")
    readonly property string toolGlyph:
        toolName === "open_url" ? "󰖟"
      : toolName === "read_file" ? "󰈙"
      : toolName === "list_dir" ? "󰉋"
      : toolName === "write_file" ? "󰷈"
      : toolName === "remember" ? "󰍩"
      : "󰆍"

    // ── Prosa y código, separados ────────────────────────────────────────────
    // El Markdown de Qt pinta los bloques ``` sin fondo ni forma de copiarlos.
    // Aquí el contenido se trocea: [{code, lang, text}…]; cada trozo de código
    // se pinta aparte. Vale también para la burbuja en vivo (una valla sin
    // cerrar cuenta como código hasta el final).
    readonly property var segments: {
        if (!isAssistant) return []
        const out = []
        let rest = content
        while (true) {
            const i = rest.indexOf("```")
            if (i === -1) {
                if (rest.trim() !== "") out.push({ code: false, lang: "", text: rest })
                break
            }
            if (rest.slice(0, i).trim() !== "")
                out.push({ code: false, lang: "", text: rest.slice(0, i) })
            rest = rest.slice(i + 3)
            const nl = rest.indexOf("\n")
            const lang = nl === -1 ? rest.trim() : rest.slice(0, nl).trim()
            rest = nl === -1 ? "" : rest.slice(nl + 1)
            const end = rest.indexOf("```")
            if (end === -1) {
                if (rest !== "") out.push({ code: true, lang: lang, text: rest })
                break
            }
            out.push({ code: true, lang: lang, text: rest.slice(0, end) })
            rest = rest.slice(end + 3)
            if (rest.startsWith("\n"))
                rest = rest.slice(1)
        }
        return out
    }

    implicitHeight: isUser ? userCol.implicitHeight
                  : isError ? errBox.height
                  : isTool ? toolBox.height
                  : isInfo ? infoText.implicitHeight
                  : aiRow.implicitHeight

    // Nota del sistema (exportado, compactado…): centrada y apagada.
    Text {
        id: infoText
        visible: bubble.isInfo
        anchors.left: parent.left
        anchors.right: parent.right
        horizontalAlignment: Text.AlignHCenter
        text: bubble.isInfo ? bubble.content : ""
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.typeLabelSmall
        wrapMode: Text.WordWrap
    }

    // Entrada: nace un punto abajo y translúcida, y se asienta.
    opacity: 0
    transform: Translate { id: rise; y: Theme.dp(6) }
    Component.onCompleted: {
        opacity = 1
        rise.y = 0
    }
    Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutQuad } }

    // ── Usuario ──────────────────────────────────────────────────────────────
    ColumnLayout {
        id: userCol
        visible: bubble.isUser
        anchors.right: parent.right
        width: Math.min(implicitWidth, bubble.width * 0.86)
        spacing: Theme.space2

        Rectangle {
            Layout.alignment: Qt.AlignRight
            Layout.maximumWidth: bubble.width * 0.86
            implicitWidth: userText.implicitWidth + Theme.space12 * 2
            implicitHeight: userText.implicitHeight + Theme.space10 * 2
            radius: Theme.shapeLg
            color: SettingsPalette.selectedTint

            TextEdit {
                id: userText
                anchors.fill: parent
                anchors.margins: Theme.space10
                anchors.leftMargin: Theme.space12
                anchors.rightMargin: Theme.space12
                text: bubble.isUser ? bubble.content : ""
                readOnly: true
                selectByMouse: true
                selectionColor: Theme.accent
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                wrapMode: TextEdit.Wrap
            }
        }

        // Pie del mensaje propio: adjuntos que llevaba + Editar/Eliminar.
        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Theme.space10
            visible: !bubble.live

            Text {
                visible: bubble.ts !== ""
                text: bubble.ts
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.typeLabelSmall
            }
            Text {
                visible: bubble.attachNote !== ""
                text: "󰏢 " + bubble.attachNote
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.typeLabelSmall
            }
            RowLayout {
                spacing: Theme.space10
                opacity: userHov.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                FootAction {
                    label: I18n.tr("Edit")
                    onDo: () => AiService.beginEdit(bubble.msgIndex)
                }
                FootAction {
                    label: I18n.tr("Delete")
                    onDo: () => AiService.removeAt(bubble.msgIndex)
                }
            }
        }
    }
    MouseArea {
        id: userHov
        anchors.fill: userCol
        visible: bubble.isUser
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // ── Asistente ────────────────────────────────────────────────────────────
    RowLayout {
        id: aiRow
        visible: bubble.isAssistant
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.space10

        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: Theme.dp(26)
            implicitHeight: Theme.dp(26)
            radius: width / 2
            color: SettingsPalette.accentSoft
            Text {
                anchors.centerIn: parent
                text: "󱙺"
                color: Theme.accentText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(13)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space6

            // Chip del razonamiento, plegado por defecto.
            Rectangle {
                visible: bubble.reasoning !== "" && !bubble.live
                width: thinkRow.implicitWidth + Theme.space12 * 2
                height: Theme.dp(26)
                radius: height / 2
                color: bubble.showReasoning ? SettingsPalette.accentSoft
                                            : SettingsPalette.settingsControl
                border.width: Theme.hairline
                border.color: SettingsPalette.settingsBorder
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                RowLayout {
                    id: thinkRow
                    anchors.centerIn: parent
                    spacing: Theme.space4
                    Text {
                        text: "󰟃"
                        color: bubble.showReasoning ? Theme.accentText : Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.sp(12)
                    }
                    Text {
                        text: I18n.tr("Reasoning")
                        color: bubble.showReasoning ? Theme.accentText : Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.typeLabelSmall
                        font.bold: bubble.showReasoning
                    }
                    Text {
                        text: bubble.showReasoning ? "󰅀" : "󰅂"
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.sp(11)
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bubble.showReasoning = !bubble.showReasoning
                }
            }

            QuoteBlock {
                visible: bubble.reasoning !== "" && bubble.showReasoning && !bubble.live
                Layout.fillWidth: true
                text: bubble.showReasoning ? bubble.reasoning : ""
            }

            // El contenido, troceado: prosa en Markdown, código en lápidas.
            Repeater {
                model: bubble.segments
                delegate: Loader {
                    required property var modelData
                    Layout.fillWidth: true
                    sourceComponent: modelData.code ? codeComp : proseComp

                    Component {
                        id: proseComp
                        TextEdit {
                            text: modelData.text
                            textFormat: TextEdit.MarkdownText
                            readOnly: true
                            selectByMouse: true
                            selectionColor: Theme.accent
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            wrapMode: TextEdit.Wrap
                            onLinkActivated: (url) => Quickshell.execDetached(["xdg-open", url])
                        }
                    }

                    Component {
                        id: codeComp
                        // Lápida de código: fondo propio, lenguaje y copiar.
                        Rectangle {
                            implicitHeight: codeCol.implicitHeight + Theme.space8 * 2
                            radius: Theme.shapeSm
                            color: Theme.withAlpha(Theme.bgAlt, 0.75)
                            border.width: Theme.hairline
                            border.color: Theme.withAlpha(Theme.overlay, 0.35)

                            ColumnLayout {
                                id: codeCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.space8
                                spacing: Theme.space4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.space8
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.lang !== "" ? modelData.lang : "code"
                                        color: Theme.fgMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.typeLabelSmall
                                        font.bold: true
                                    }
                                    FootAction {
                                        label: codeCopied.running ? I18n.tr("Copied") : I18n.tr("Copy")
                                        onDo: () => {
                                            Quickshell.execDetached(["wl-copy", modelData.text])
                                            codeCopied.restart()
                                        }
                                    }
                                    Timer { id: codeCopied; interval: 1500 }
                                }
                                TextEdit {
                                    Layout.fillWidth: true
                                    text: modelData.text
                                    readOnly: true
                                    selectByMouse: true
                                    selectionColor: Theme.accent
                                    color: Theme.fg
                                    font.family: Theme.monoFontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    wrapMode: TextEdit.Wrap
                                }
                            }
                        }
                    }
                }
            }

            // Pie: modelo · tiempo · tokens + acciones, al posarse.
            RowLayout {
                visible: !bubble.live
                spacing: Theme.space10
                opacity: aiHov.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                Text {
                    text: {
                        let parts = [bubble.modelName]
                        if (bubble.ts !== "")
                            parts.push(bubble.ts)
                        if (bubble.ms > 0)
                            parts.push((bubble.ms / 1000).toFixed(1) + " s")
                        if (bubble.tokens > 0)
                            parts.push(bubble.tokens + " tok")
                        return parts.join(" · ")
                    }
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.typeLabelSmall
                }
                FootAction {
                    label: copied.running ? I18n.tr("Copied") : I18n.tr("Copy")
                    onDo: () => {
                        Quickshell.execDetached(["wl-copy", bubble.content])
                        copied.restart()
                    }
                }
                FootAction {
                    visible: bubble.isLast && !AiService.busy
                    label: I18n.tr("Regenerate")
                    onDo: () => AiService.regenerate()
                }
                FootAction {
                    label: I18n.tr("Delete")
                    onDo: () => AiService.removeAt(bubble.msgIndex)
                }
                Timer { id: copied; interval: 1500 }
            }
        }
    }
    MouseArea {
        id: aiHov
        anchors.fill: aiRow
        visible: aiRow.visible
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // ── Herramienta: la tarjeta de aprobación ────────────────────────────────
    Rectangle {
        id: toolBox
        visible: bubble.isTool
        anchors.left: parent.left
        anchors.right: parent.right
        height: toolCol.implicitHeight + Theme.space12 * 2
        radius: Theme.shapeMd
        color: SettingsPalette.groupFill
        border.width: Theme.hairline
        border.color: bubble.toolStatus === "pending"
            ? Theme.withAlpha(Theme.accent, 0.55)
            : SettingsPalette.settingsBorder
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        ColumnLayout {
            id: toolCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.space12
            spacing: Theme.space8

            // Si el modelo dijo algo antes de proponer, se enseña.
            Text {
                Layout.fillWidth: true
                visible: bubble.content !== ""
                text: bubble.content
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                Text {
                    text: bubble.toolGlyph
                    color: Theme.accentText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize
                }
                Text {
                    Layout.fillWidth: true
                    text: bubble.toolHeadline
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.typeLabelLarge
                    font.weight: Font.Medium
                }
            }

            // Lo propuesto, en lápida de código: se lee ANTES de aprobar.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: toolCmd.implicitHeight + Theme.space8 * 2
                radius: Theme.shapeSm
                color: Theme.withAlpha(Theme.bgAlt, 0.75)
                TextEdit {
                    id: toolCmd
                    anchors.fill: parent
                    anchors.margins: Theme.space8
                    text: bubble.toolPretty
                    readOnly: true
                    selectByMouse: true
                    selectionColor: Theme.accent
                    color: Theme.fg
                    font.family: Theme.monoFontFamily
                    font.pixelSize: Theme.fontSize - 1
                    wrapMode: TextEdit.Wrap
                }
            }

            // write_file: el contenido que se va a escribir, previsualizado.
            QuoteBlock {
                visible: bubble.toolPreview !== ""
                Layout.fillWidth: true
                mono: true
                text: bubble.toolPreview
            }

            // write_file sobre un archivo EXISTENTE: diff real contra lo que
            // hay en disco, a un clic y ANTES de aprobar — lo que enseñan
            // aider y Claude Code. Con archivo nuevo lo dice y ya.
            RowLayout {
                visible: bubble.toolName === "write_file" && bubble.toolStatus === "pending"
                spacing: Theme.space8
                FootAction {
                    label: bubble._diffOut === "" ? I18n.tr("View diff") : I18n.tr("Hide diff")
                    onDo: () => {
                        if (bubble._diffOut !== "") {
                            bubble._diffOut = ""
                            return
                        }
                        const p = AiService._safePath(bubble._args.path)
                        if (p === "") {
                            bubble._diffOut = I18n.tr("Path outside your home folder")
                            return
                        }
                        diffProc.environment = ({ QS_P: p, QS_C: bubble._args.content || "" })
                        diffProc.running = true
                    }
                }
            }
            Process {
                id: diffProc
                command: ["sh", "-c",
                    'T=$(mktemp); printf %s "$QS_C" > "$T"; '
                    + 'if [ -f "$QS_P" ]; then diff -u -- "$QS_P" "$T" | head -n 120; '
                    + 'else echo "(archivo nuevo)"; fi; rm -f "$T"']
                stdout: StdioCollector { id: diffCol }
                onExited: {
                    const out = (diffCol.text || "").trim()
                    bubble._diffOut = out !== "" ? out : I18n.tr("No changes")
                }
            }
            QuoteBlock {
                visible: bubble._diffOut !== ""
                Layout.fillWidth: true
                mono: true
                text: bubble._diffOut
            }

            // Pendiente: las dos decisiones. Resuelta: el veredicto + salida.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                visible: bubble.toolStatus === "pending"

                Item { Layout.fillWidth: true }
                TextButton {
                    text: I18n.tr("Reject")
                    onClicked: AiService.rejectTool(bubble.msgIndex)
                }
                TextButton {
                    text: I18n.tr("Approve")
                    primary: true
                    onClicked: AiService.approveTool(bubble.msgIndex)
                }
            }

            RowLayout {
                visible: bubble.toolStatus !== "pending" && bubble.toolStatus !== ""
                spacing: Theme.space6
                Text {
                    text: bubble.toolStatus === "rejected" ? "󰜺" : "󰄬"
                    color: bubble.toolStatus === "rejected" ? Theme.red : Theme.green
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(12)
                }
                Text {
                    text: bubble.toolStatus === "rejected"
                        ? I18n.tr("Rejected") : I18n.tr("Executed")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.typeLabelSmall
                }
                FootAction {
                    visible: bubble.toolStatus === "done" && bubble.toolResult !== ""
                    label: bubble.showToolOut ? I18n.tr("Hide output") : I18n.tr("Show output")
                    onDo: () => bubble.showToolOut = !bubble.showToolOut
                }
            }

            QuoteBlock {
                visible: bubble.showToolOut && bubble.toolResult !== ""
                Layout.fillWidth: true
                mono: true
                text: bubble.showToolOut ? bubble.toolResult : ""
            }
        }
    }

    // ── Error ────────────────────────────────────────────────────────────────
    Rectangle {
        id: errBox
        visible: bubble.isError
        anchors.left: parent.left
        anchors.right: parent.right
        height: errCol.implicitHeight + Theme.space10 * 2
        radius: Theme.shapeMd
        color: Theme.withAlpha(Theme.red, 0.10)
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.red, 0.4)

        RowLayout {
            id: errCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.space12
            anchors.rightMargin: Theme.space12
            spacing: Theme.space10

            Text {
                text: "󰀪"
                color: Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            Text {
                Layout.fillWidth: true
                text: bubble.isError ? bubble.content : ""
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.typeBodySmall
                wrapMode: Text.WordWrap
            }
            TextButton {
                text: I18n.tr("Retry")
                onClicked: AiService.retry()
            }
        }
    }

    // ── Piezas ───────────────────────────────────────────────────────────────

    // Acción de pie: texto pequeño que se enciende al pasar. 'onDo' es una
    // función (flecha) que se ejecuta al pulsar.
    component FootAction: Text {
        id: act
        property string label: ""
        property var onDo: null
        text: label
        color: actMa.containsMouse ? Theme.accentText : Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.typeLabelSmall
        font.bold: true
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        MouseArea {
            id: actMa
            anchors.fill: parent
            anchors.margins: -Theme.space4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (act.onDo) act.onDo()
        }
    }

    // Nota al margen: texto atenuado con filete de acento al costado. La usan
    // el razonamiento desplegado y la salida de una herramienta.
    component QuoteBlock: Rectangle {
        property alias text: qbText.text
        property bool mono: false
        implicitHeight: qbText.implicitHeight + Theme.space10 * 2
        radius: Theme.shapeSm
        color: Theme.withAlpha(Theme.surfaceHi, 0.35)

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: Theme.space6
            width: Theme.dp(2)
            radius: width / 2
            color: Theme.withAlpha(Theme.accent, 0.5)
        }
        TextEdit {
            id: qbText
            anchors.fill: parent
            anchors.margins: Theme.space10
            anchors.leftMargin: Theme.space12 + Theme.space4
            readOnly: true
            selectByMouse: true
            selectionColor: Theme.accent
            color: Theme.fgMuted
            font.family: parent.mono ? Theme.monoFontFamily : Theme.fontFamily
            font.pixelSize: Theme.typeBodySmall
            wrapMode: TextEdit.Wrap
        }
    }
}
