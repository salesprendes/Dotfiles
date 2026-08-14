import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Panel del asistente IA (estilo Material 3, mismo lenguaje que el resto de
// popouts del shell). La lógica vive en AiService: aquí burbujas, entrada,
// adjuntos, conversaciones y la lámina de configuración de proveedores.
Popout {
    id: panel
    ns: "qs-ai"
    cardWidth: 480
    cardMinWidth: 340
    shown: Globals.aiOpen

    property bool configOpen: AiService.keyMissing && AiService.messages.count === 0
    property bool convOpen: false







    // El servicio pide reescribir un mensaje (Editar / ↑): a la entrada.
    Connections {
        target: AiService
        function onEditRequest(text) {
            input.text = text
            input.cursorPosition = input.length
            input.forceActiveFocus()
        }
    }

    // ── Cabecera ─────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space10

        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: Theme.dp(34)
            implicitHeight: Theme.dp(34)
            radius: width / 2
            color: SettingsPalette.accentSoft
            // Respira mientras el modelo trabaja: la vida del panel se ve
            // desde la primera mirada, sin leer nada.
            SequentialAnimation on scale {
                running: AiService.busy
                loops: Animation.Infinite
                NumberAnimation { to: 1.12; duration: Math.round(Theme.animLoop / 2); easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: Math.round(Theme.animLoop / 2); easing.type: Easing.InOutSine }
            }
            onScaleChanged: if (!AiService.busy && scale !== 1) scale = 1
            Text {
                anchors.centerIn: parent
                text: "󱙺"
                color: Theme.accentText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(18)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space2
            Text {
                Layout.fillWidth: true
                text: I18n.tr("AI assistant")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.typeTitleMedium
                font.bold: true
                elide: Text.ElideRight
            }
            // Selector rápido de modelo: cambiar de cerebro sin abrir la
            // config. El proveedor sale como detalle, a la derecha del valor.
            DropdownRow {
                Layout.fillWidth: true
                label: ""
                glyph: ""
                options: AiService.modelOptions
                current: AiService.model
                detailText: AiService.provider.label
                maxVisibleItems: 5
                onPicked: (v) => AiService.setModel(v)
            }
        }

        // Modo: Chat (solo conversación) ↔ Agente (herramientas con
        // aprobación). Tab en la entrada también lo conmuta, como el
        // plan/build de opencode.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            width: modeRow.implicitWidth + Theme.space10 * 2
            height: Theme.controlM
            radius: height / 2
            color: AiService.agentMode ? SettingsPalette.accentSoft
                                       : SettingsPalette.settingsControl
            border.width: Theme.hairline
            border.color: AiService.agentMode
                ? Theme.withAlpha(Theme.accent, 0.5) : SettingsPalette.settingsBorder
            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            RowLayout {
                id: modeRow
                anchors.centerIn: parent
                spacing: Theme.space4
                Text {
                    text: AiService.agentMode ? "󰚩" : "󰭹"
                    color: AiService.agentMode ? Theme.accentText : Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(13)
                }
                Text {
                    text: AiService.agentMode ? I18n.tr("Agent") : I18n.tr("Chat")
                    color: AiService.agentMode ? Theme.accentText : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.typeLabelSmall
                    font.bold: true
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Settings.aiMode = AiService.agentMode ? "chat" : "agent"
            }
        }

        // Historial de conversaciones.
        IconButton {
            Layout.alignment: Qt.AlignTop
            icon: "󰋚"
            diameter: Theme.controlM
            baseColor: panel.convOpen ? SettingsPalette.accentSoft : "transparent"
            iconColor: panel.convOpen ? Theme.accentText : Theme.fgDim
            onClicked: {
                panel.convOpen = !panel.convOpen
                if (panel.convOpen) panel.configOpen = false
            }
        }
        // Nueva conversación.
        IconButton {
            Layout.alignment: Qt.AlignTop
            icon: "󰐕"
            diameter: Theme.controlM
            baseColor: "transparent"
            visible: AiService.messages.count > 0
            onClicked: AiService.newConversation()
        }
        // Configuración de proveedores.
        IconButton {
            Layout.alignment: Qt.AlignTop
            icon: "󰒓"
            diameter: Theme.controlM
            baseColor: panel.configOpen ? SettingsPalette.accentSoft : "transparent"
            iconColor: panel.configOpen ? Theme.accentText : Theme.fgDim
            onClicked: {
                panel.configOpen = !panel.configOpen
                if (panel.configOpen) panel.convOpen = false
            }
        }
    }

    // Filete bajo la cabecera + medidor de contexto: la línea se va tiñendo
    // de acento según se llena el presupuesto que viaja al modelo, y avisa en
    // rojo cerca del tope — el momento de /compactar (el medidor de contexto
    // de Claude Code, reducido a un hilo de luz).
    Item {
        Layout.fillWidth: true
        implicitHeight: Theme.hairline * 2

        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.overlay, Theme.isDark ? 0.5 : 0.35)
        }
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * AiService.contextFill
            color: AiService.contextFill > 0.85 ? Theme.red
                 : Theme.withAlpha(Theme.accent, 0.8)
            Behavior on width { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Theme.animNormal } }
        }
    }

    // ── Conversaciones (lámina) ──────────────────────────────────────────────
    ExpandableDetail {
        open: panel.convOpen
        sourceComponent: convComp
    }

    Component {
        id: convComp
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: convCol.implicitHeight + Theme.space10 * 2
            radius: Theme.shapeMd
            color: SettingsPalette.groupFill

            ColumnLayout {
                id: convCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.space10
                spacing: Theme.space2

                // Acciones sobre la conversación ACTUAL: exportarla como
                // Markdown (entregable) o compactarla en un resumen.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.space6
                    spacing: Theme.space8
                    visible: AiService.messages.count > 0

                    SuggestChip {
                        label: "󰈝 " + I18n.tr("Export")
                        onDo: () => AiService.exportMarkdown()
                    }
                    SuggestChip {
                        label: "󰍃 " + I18n.tr("Compact")
                        enabled: !AiService.busy && !AiService.keyMissing
                        opacity: enabled ? 1 : 0.4
                        onDo: () => {
                            AiService.compact()
                            panel.convOpen = false
                        }
                    }
                    Item { Layout.fillWidth: true }
                    // Lo que lleva gastado esta conversación (estilo aider).
                    Text {
                        visible: AiService.convTokens > 0 || AiService.convMs > 0
                        text: (AiService.convTokens > 0 ? AiService.convTokens + " tok · " : "")
                              + (AiService.convMs / 1000).toFixed(0) + " s"
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.typeLabelSmall
                    }
                }

                EmptyNote {
                    visible: AiService.conversations.length === 0
                    text: I18n.tr("No conversations yet.")
                }

                Repeater {
                    model: AiService.conversations
                    delegate: Rectangle {
                        id: convRow
                        required property var modelData
                        readonly property bool current: modelData.id === AiService.currentId
                        Layout.fillWidth: true
                        implicitHeight: Theme.dp(42)
                        radius: Theme.shapeSm
                        color: current ? SettingsPalette.selectedTint
                             : convMa.containsMouse ? SettingsPalette.settingsHover
                             : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        // Debajo de la fila entera; el botón de borrar,
                        // declarado después, gana los clics que le caen.
                        MouseArea {
                            id: convMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                AiService.switchTo(convRow.modelData.id)
                                panel.convOpen = false
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space10
                            anchors.rightMargin: Theme.space6
                            spacing: Theme.space8

                            Text {
                                text: "󰭹"
                                color: convRow.current ? Theme.accentText : Theme.fgMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.sp(13)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: convRow.modelData.title
                                    color: convRow.current ? Theme.fg : Theme.fgDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.typeLabelLarge
                                    font.bold: convRow.current
                                    elide: Text.ElideRight
                                }
                                // Cuándo y cuánto: fecha del último mensaje y
                                // tamaño del hilo, para reconocerlo sin abrirlo.
                                Text {
                                    Layout.fillWidth: true
                                    text: new Date(convRow.modelData.updated)
                                              .toLocaleDateString(Qt.locale(), "d MMM")
                                          + " · " + convRow.modelData.entries.length
                                          + " msg"
                                    color: Theme.fgMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.typeLabelSmall
                                    elide: Text.ElideRight
                                }
                            }
                            IconButton {
                                icon: "󰩹"
                                diameter: Theme.dp(24)
                                iconPixelSize: Theme.sp(12)
                                baseColor: "transparent"
                                hoverColor: Theme.red
                                onClicked: AiService.deleteConversation(convRow.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Configuración (lámina) ───────────────────────────────────────────────
    ExpandableDetail {
        open: panel.configOpen
        sourceComponent: configComp
    }

    // La config en dos plantas (revelación progresiva): a la vista, SOLO lo
    // que hace falta para arrancar — proveedor y credencial; el modelo ya se
    // elige en la cabecera. Todo lo demás vive bajo "Ajustes avanzados",
    // plegado: sigue ahí entero, pero ya no es una pared de doce controles
    // para quien solo venía a pegar su clave.
    Component {
        id: configComp
        Rectangle {
            id: confRoot
            property bool advOpen: false
            Layout.fillWidth: true
            // Con los avanzados abiertos la lámina puede superar al panel:
            // tope de altura y DESPLAZA dentro, con su barra visible.
            implicitHeight: Math.min(confCol.implicitHeight + Theme.space12 * 2,
                                     Theme.dp(430))
            radius: Theme.shapeMd
            color: SettingsPalette.groupFill
            clip: true

            Flickable {
                id: confFlick
                anchors.fill: parent
                anchors.margins: Theme.space12
                contentWidth: width
                contentHeight: confCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height + 0.5

                ScrollBar.vertical: ThinScrollBar {
                    policy: confFlick.contentHeight > confFlick.height + 1
                        ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                    rightPadding: -Theme.space8
                    restOpacity: 0.35
                }

            ColumnLayout {
                id: confCol
                width: confFlick.width
                spacing: Theme.space10

                SegRow {
                    glyph: "󰚩"
                    label: I18n.tr("Provider")
                    options: [ { text: "Gemini", value: "gemini" },
                               { text: "OpenRouter", value: "openrouter" },
                               { text: "Ollama", value: "ollama" },
                               { text: "LLM", value: "custom" } ]
                    current: Settings.aiProvider
                    onPicked: (v) => Settings.aiProvider = v
                }

                TextField {
                    shown: AiService.provider.needsKey || Settings.aiProvider === "custom"
                    label: I18n.tr("API key")
                    leftIcon: "󰌆"
                    password: true
                    placeholder: Settings.aiProvider === "gemini" ? "AIza…"
                               : Settings.aiProvider === "custom" ? I18n.tr("optional")
                               : "sk-or-…"
                    value: AiService.apiKey
                    onEdited: (t) => AiService.setKey(Settings.aiProvider, t)
                }

                TextField {
                    shown: Settings.aiProvider === "ollama" || Settings.aiProvider === "custom"
                    label: I18n.tr("Server URL")
                    leftIcon: "󰒋"
                    placeholder: Settings.aiProvider === "custom"
                        ? "http://127.0.0.1:8080/v1" : "http://127.0.0.1:11434"
                    value: Settings.aiProvider === "custom"
                        ? Settings.aiCustomUrl : Settings.aiOllamaUrl
                    onEdited: (t) => {
                        if (Settings.aiProvider === "custom")
                            Settings.aiCustomUrl = t.trim()
                        else
                            Settings.aiOllamaUrl = t.trim()
                    }
                }

                Hint {
                    Layout.leftMargin: 0
                    text: Settings.aiProvider === "gemini"
                        ? I18n.tr("Free tier with a Google AI Studio key — good for quick questions.")
                        : Settings.aiProvider === "openrouter"
                        ? I18n.tr("One key, many models. The :free ids (Qwen, etc.) change over time — adjust the model if one vanishes.")
                        : Settings.aiProvider === "custom"
                        ? I18n.tr("Any OpenAI-compatible /v1 server: llama.cpp, LM Studio, vLLM… Key only if yours asks for one.")
                        : I18n.tr("Local and private, no key. Run Qwen or Meta's Muse Glimmer with 'ollama pull'.")
                }
                Hint {
                    Layout.leftMargin: 0
                    shown: AiService.haveKeyring && AiService.provider.needsKey
                    text: I18n.tr("Keys are stored in the system keyring, not in settings.json.")
                }

                // La puerta a la otra planta.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.dp(34)
                    radius: Theme.shapeSm
                    color: advMa.containsMouse ? SettingsPalette.settingsHover
                                               : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space8
                        anchors.rightMargin: Theme.space8
                        spacing: Theme.space8
                        Text {
                            text: "󰢻"
                            color: confRoot.advOpen ? Theme.accentText : Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.sp(14)
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Advanced settings")
                            color: confRoot.advOpen ? Theme.fg : Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.typeLabelLarge
                            font.weight: Font.Medium
                        }
                        Text {
                            text: "󰅀"
                            rotation: confRoot.advOpen ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.sp(13)
                        }
                    }
                    MouseArea {
                        id: advMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: confRoot.advOpen = !confRoot.advOpen
                    }
                }

                ExpandableDetail {
                    open: confRoot.advOpen
                    sourceComponent: advComp
                }
            }
            }
        }
    }

    // La planta avanzada: estilo, creatividad, compactación, instrucciones,
    // políticas de herramientas y memoria. Nada se fue — solo bajó al sótano.
    Component {
        id: advComp
        ColumnLayout {
            spacing: Theme.space10

            // Estilo de respuesta (persona): un ajuste, no un prompt a mano.
            SegRow {
                glyph: "󰚈"
                label: I18n.tr("Style")
                options: [ { text: I18n.tr("Normal"), value: "normal" },
                           { text: I18n.tr("Concise"), value: "concise" },
                           { text: I18n.tr("Teacher"), value: "teacher" },
                           { text: I18n.tr("Reviewer"), value: "reviewer" } ]
                current: Settings.aiPersona
                onPicked: (v) => Settings.aiPersona = v
            }

            // Modelo a mano (ids exóticos, sintaxis proveedor:modelo); el día
            // a día se elige en el desplegable de la cabecera.
            TextField {
                label: I18n.tr("Model")
                leftIcon: "󰍜"
                value: AiService.model
                onEdited: (t) => AiService.setModel(t)
            }

            // Temperatura: el mando universal de creatividad del contrato.
            SliderRow {
                label: I18n.tr("Creativity"); glyph: "󰔄"
                from: 0.0; to: 1.5; value: Settings.aiTemperature
                valueText: Settings.aiTemperature.toFixed(1)
                onMoved: (v) => Settings.aiTemperature = Math.round(v * 10) / 10
            }

            // Instrucciones extra: se añaden al prompt de sistema.
            TextField {
                label: I18n.tr("Extra instructions")
                leftIcon: "󰚈"
                placeholder: I18n.tr("e.g. answer always in Spanish, prefer fish over bash…")
                value: Settings.aiCustomPrompt
                onEdited: (t) => Settings.aiCustomPrompt = t
            }

            // Compactación: cuándo se resume el contexto y qué sobrevive.
            SegRow {
                glyph: "󰍃"
                label: I18n.tr("Compact context")
                options: [ { text: I18n.tr("Manual"), value: "manual" },
                           { text: I18n.tr("Warn"), value: "warn" },
                           { text: "Auto", value: "auto" } ]
                current: Settings.aiAutoCompact
                onPicked: (v) => Settings.aiAutoCompact = v
            }
            SegRow {
                glyph: "󰆓"
                label: I18n.tr("Keep on compact")
                options: [ { text: I18n.tr("Nothing"), value: 0 },
                           { text: I18n.tr("1 turn"), value: 1 },
                           { text: I18n.tr("2 turns"), value: 2 } ]
                current: Settings.aiCompactKeep
                onPicked: (v) => Settings.aiCompactKeep = v
            }
            Hint {
                Layout.leftMargin: 0
                text: I18n.tr("At 85% of the context: Warn suggests /compact; Auto does it by itself.")
            }

            // Política por herramienta (las listas de aprobación de
            // aisuite): Preguntar (defecto) · Auto · No. "No" la borra
            // del vocabulario del modelo; "Auto" ejecuta sin tarjeta,
            // siempre bajo el tope de pasos.
            Text {
                Layout.topMargin: Theme.space4
                text: I18n.tr("Tool policies")
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.typeLabelMedium
                font.weight: Font.Medium
            }
            Repeater {
                model: ["run_command", "write_file", "open_url",
                        "read_file", "list_dir", "remember"]
                delegate: SegRow {
                    required property string modelData
                    label: modelData
                    options: [ { text: I18n.tr("Ask"), value: "ask" },
                               { text: "Auto", value: "auto" },
                               { text: I18n.tr("Off"), value: "off" } ]
                    current: (Settings.aiToolPolicies || {})[modelData] || "ask"
                    onPicked: (v) => {
                        const p = Object.assign({}, Settings.aiToolPolicies)
                        p[modelData] = v
                        Settings.aiToolPolicies = p
                    }
                }
            }

            // Memoria persistente: lo que el asistente guardó (con tu
            // aprobación) y se inyecta en cada conversación.
            Text {
                Layout.topMargin: Theme.space4
                text: I18n.tr("Memory")
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.typeLabelMedium
                font.weight: Font.Medium
            }
            EmptyNote {
                visible: AiService.memoryList.length === 0
                text: I18n.tr("No saved notes.")
            }
            Repeater {
                model: AiService.memoryList
                delegate: RowLayout {
                    id: memRow
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: Theme.space8
                    Text {
                        text: "󰍩"
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.sp(12)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: memRow.modelData
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.typeBodySmall
                        elide: Text.ElideRight
                    }
                    IconButton {
                        icon: "󰩹"
                        diameter: Theme.dp(22)
                        iconPixelSize: Theme.sp(11)
                        baseColor: "transparent"
                        hoverColor: Theme.red
                        onClicked: AiService.removeMemory(memRow.index)
                    }
                }
            }

        }
    }

    // ── Conversación ─────────────────────────────────────────────────────────
    ListView {
        id: chat
        Layout.fillWidth: true
        // Alto ADAPTATIVO: se ciñe a la conversación y crece con ella hasta
        // el tope, donde empieza a desplazar.
        Layout.preferredHeight: Math.max(Theme.dp(250),
            Math.min(Theme.dp(460), contentHeight + Theme.space8))
        clip: true
        spacing: Theme.space12
        model: AiService.messages
        boundsBehavior: Flickable.StopAtBounds

        // Visible en reposo (no solo al usarla): con conversación larga, la
        // barra dice de un vistazo cuánto hay por encima.
        ScrollBar.vertical: ThinScrollBar {
            policy: chat.contentHeight > chat.height + 1
                ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            rightPadding: 0
            restOpacity: 0.35
        }

        // Sigue lo nuevo SOLO si ya estabas abajo; el botón flotante
        // re-engancha.
        property bool follow: true
        readonly property bool atBottom: contentY >= contentHeight - height - Theme.dp(48)
        onContentHeightChanged: if (follow && contentHeight > height)
            contentY = contentHeight - height
        onMovementEnded: follow = atBottom

        // ── Estado vacío: la invitación ──────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: AiService.messages.count === 0 && !AiService.busy

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width, Theme.dp(340))
                spacing: Theme.space12

                // Saludo según la hora: un panel que sabe si es de día.
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        const h = new Date().getHours()
                        return h < 7 ? I18n.tr("Good night") : h < 14 ? I18n.tr("Good morning")
                             : h < 21 ? I18n.tr("Good afternoon") : I18n.tr("Good night")
                    }
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.typeTitleMedium
                    font.weight: Font.Medium
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󱙺"
                    color: Theme.withAlpha(Theme.accent, 0.55)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(52)
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: AiService.keyMissing
                        ? I18n.tr("Pick a provider and add its key to start.")
                        : I18n.tr("Ask anything. Attach your clipboard or screen for context.")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.typeBodyMedium
                    wrapMode: Text.WordWrap
                }

                // Arranques que enseñan lo que el panel sabe hacer.
                Flow {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    spacing: Theme.space8
                    visible: !AiService.keyMissing

                    SuggestChip {
                        label: I18n.tr("Summarize my clipboard")
                        onDo: () => {
                            AiService.attachClipboard()
                            input.text = I18n.tr("Summarize this:")
                            input.forceActiveFocus()
                        }
                    }
                    SuggestChip {
                        label: I18n.tr("What's on my screen?")
                        onDo: () => {
                            input.text = I18n.tr("What's on my screen?")
                            AiService.draft = input.text
                            AiService.attachScreenshot()
                        }
                    }
                    SuggestChip {
                        label: I18n.tr("Explain this command:")
                        onDo: () => {
                            input.text = I18n.tr("Explain this command:") + " "
                            input.cursorPosition = input.length
                            input.forceActiveFocus()
                        }
                    }
                }
            }
        }

        // Se puentea por 'model.*' explícitamente: las propiedades propias de
        // MessageBubble taparían los roles inyectados del ListModel.
        delegate: MessageBubble {
            width: ListView.view.width
            role: model.role
            content: model.content
            reasoning: model.reasoning
            modelName: model.modelName
            ms: model.ms
            tokens: model.tokens
            toolName: model.toolName
            toolArgs: model.toolArgs
            toolResult: model.toolResult
            toolStatus: model.toolStatus
            attachNote: model.attachNote
            ts: model.ts
            msgIndex: model.index
            isLast: model.index === chat.count - 1
        }

        // Burbuja EN VIVO en el footer: no reconstruye la lista por token.
        footer: Item {
            width: chat.width
            height: AiService.busy ? liveCol.implicitHeight + Theme.space12 : 0

            ColumnLayout {
                id: liveCol
                width: parent.width
                visible: AiService.busy
                spacing: Theme.space6

                MessageBubble {
                    Layout.fillWidth: true
                    visible: AiService.liveText !== ""
                    live: true
                    role: "assistant"
                    content: AiService.liveText
                    modelName: AiService.model
                }

                // Razonamiento EN VIVO, atenuado: se ve pensar sin robar
                // protagonismo.
                RowLayout {
                    visible: AiService.liveText === "" && AiService.liveThink !== ""
                    Layout.leftMargin: Theme.dp(36)
                    Layout.rightMargin: Theme.space8
                    spacing: Theme.space8

                    Rectangle {
                        Layout.fillHeight: true
                        Layout.topMargin: Theme.space2
                        Layout.bottomMargin: Theme.space2
                        implicitWidth: Theme.dp(2)
                        radius: width / 2
                        color: Theme.withAlpha(Theme.accent, 0.5)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: AiService.liveThink.slice(-280)
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.typeBodySmall
                        font.italic: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                        elide: Text.ElideLeft
                    }
                }

                // Paso del agente y cola de mensajes: el estado del harness,
                // dicho en voz baja bajo la burbuja viva.
                RowLayout {
                    Layout.leftMargin: Theme.dp(36)
                    spacing: Theme.space10
                    visible: (AiService.agentMode && AiService.toolRounds > 0)
                             || AiService.sendQueue.length > 0
                    Text {
                        visible: AiService.agentMode && AiService.toolRounds > 0
                        text: I18n.tr("Step %1 of %2")
                            .arg(AiService.toolRounds).arg(AiService.maxToolRounds)
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.typeLabelSmall
                    }
                    Text {
                        visible: AiService.sendQueue.length > 0
                        text: I18n.tr("Queued: %1").arg(AiService.sendQueue.length)
                        color: Theme.accentText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.typeLabelSmall
                        font.bold: true
                    }
                }

                // Tres puntos respirando mientras aún no ha dicho nada.
                RowLayout {
                    visible: AiService.liveText === "" && AiService.liveThink === ""
                    spacing: Theme.space4
                    Layout.leftMargin: Theme.dp(36)
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: Theme.dp(7); height: width; radius: width / 2
                            color: Theme.accent
                            opacity: 0.25
                            SequentialAnimation on opacity {
                                running: AiService.busy
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * Math.round(Theme.animLoop / 9) }
                                NumberAnimation { to: 0.9; duration: Math.round(Theme.animLoop / 3) }
                                NumberAnimation { to: 0.25; duration: Math.round(Theme.animLoop / 3) }
                            }
                        }
                    }
                }
            }
        }

        // Botón de "volver abajo".
        IconButton {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.space8
            icon: "󰅀"
            diameter: Theme.dp(30)
            baseColor: SettingsPalette.accentSoft
            iconColor: Theme.accentText
            visible: !chat.atBottom && chat.contentHeight > chat.height
            onClicked: {
                chat.follow = true
                chat.contentY = chat.contentHeight - chat.height
            }
        }
    }

    // ── Adjuntos: acciones + chips de lo pendiente ───────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8

        AttachButton { icon: "󰅍"; onDo: () => AiService.attachClipboard() }
        AttachButton { icon: "󰒉"; onDo: () => AiService.attachSelection() }
        AttachButton {
            icon: "󰹑"
            onDo: () => {
                AiService.draft = input.text     // sobrevive al cierre del panel
                AiService.attachScreenshot()
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.space6

            Repeater {
                model: AiService.pendingAtts
                delegate: Rectangle {
                    id: attChip
                    required property var modelData
                    required property int index
                    width: attRow.implicitWidth + Theme.space10 * 2
                    height: Theme.dp(26)
                    radius: height / 2
                    color: SettingsPalette.accentSoft

                    RowLayout {
                        id: attRow
                        anchors.centerIn: parent
                        spacing: Theme.space4
                        Text {
                            text: attChip.modelData.kind === "image" ? "󰋩" : "󰈙"
                            color: Theme.accentText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.sp(12)
                        }
                        Text {
                            text: attChip.modelData.label
                            color: Theme.accentText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.typeLabelSmall
                            font.bold: true
                        }
                        Text {
                            text: "󰅖"
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.sp(11)
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -Theme.space4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: AiService.removeAttachment(attChip.index)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Entrada ──────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(Theme.dp(42),
                Math.min(input.implicitHeight + Theme.space10 * 2, Theme.dp(120)))
            radius: Theme.shapeLg
            color: SettingsPalette.settingsControl
            border.width: input.activeFocus ? Theme.focusWidth : Theme.hairline
            border.color: input.activeFocus ? Theme.accent : SettingsPalette.settingsBorder
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

            Flickable {
                anchors.fill: parent
                anchors.leftMargin: Theme.space12
                anchors.rightMargin: Theme.space12
                anchors.topMargin: Theme.space10
                anchors.bottomMargin: Theme.space10
                contentWidth: width
                contentHeight: input.implicitHeight
                clip: true
                interactive: contentHeight > height

                TextEdit {
                    id: input
                    width: parent.width
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    selectionColor: Theme.accent
                    // Enter envía; Shift+Enter, línea nueva; ↑ en vacío, edita
                    // tu último mensaje (como recuperar la orden en un shell).
                    Keys.onReturnPressed: (e) => {
                        if (e.modifiers & Qt.ShiftModifier) {
                            e.accepted = false
                            return
                        }
                        panel.submit()
                    }
                    Keys.onUpPressed: (e) => {
                        if (input.text === "" && !AiService.busy)
                            AiService.editLast()
                        else
                            e.accepted = false
                    }
                    // Tab conmuta Chat ↔ Agente, como en opencode.
                    Keys.onTabPressed: Settings.aiMode =
                        AiService.agentMode ? "chat" : "agent"
                    onTextChanged: AiService.draft = text
                    Component.onCompleted: {
                        text = AiService.draft
                        cursorPosition = length
                        forceActiveFocus()
                    }

                    Text {
                        anchors.top: parent.top
                        visible: input.text === ""
                        text: I18n.tr("Ask anything…")
                        color: Theme.fgMuted
                        font: input.font
                    }
                }
            }
        }

        // Enviar / Detener: mismo botón, dos papeles. Late suave mientras
        // trabaja, a juego con el avatar.
        IconButton {
            icon: AiService.busy ? "󰓛" : "󰒊"
            diameter: Theme.dp(42)
            SequentialAnimation on scale {
                running: AiService.busy
                loops: Animation.Infinite
                NumberAnimation { to: 1.07; duration: Math.round(Theme.animLoop / 2); easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: Math.round(Theme.animLoop / 2); easing.type: Easing.InOutSine }
            }
            onScaleChanged: if (!AiService.busy && scale !== 1) scale = 1
            baseColor: AiService.busy
                ? Theme.withAlpha(Theme.red, 0.16)
                : SettingsPalette.accentSoft
            hoverColor: AiService.busy ? Theme.red : Theme.accent
            iconColor: AiService.busy ? Theme.red : Theme.accentText
            onClicked: AiService.busy ? AiService.stop() : panel.submit()
        }
    }

    function submit() {
        const t = input.text.trim()
        if (t.startsWith("/")) {
            handleSlash(t)
            input.text = ""
            AiService.draft = ""
            return
        }
        if (t === "" && AiService.pendingAtts.length === 0)
            return
        // Ocupado incluido: el servicio lo encola y sale al terminar.
        AiService.send(t)
        input.text = ""
        AiService.draft = ""
    }

    // Comandos slash, al estilo opencode: acciones de sesión sin soltar el
    // teclado. La entrada los intercepta ANTES de enviar nada al modelo.
    function handleSlash(t) {
        const parts = t.split(/\s+/)
        switch (parts[0].toLowerCase()) {
        case "/nueva": case "/new":
            AiService.newConversation(); break
        case "/compactar": case "/compact":
            AiService.compact(); break
        case "/exportar": case "/export":
            AiService.exportMarkdown(); break
        case "/modelo": case "/model":
            if (parts[1]) AiService.setModel(parts[1]); break
        case "/agente": case "/agent":
            Settings.aiMode = "agent"; break
        case "/chat":
            Settings.aiMode = "chat"; break
        default:
            AiService.pushInfo(I18n.tr("Commands: /new · /compact · /export · /model <id> · /agent · /chat"))
        }
    }

    // Botón pequeño de adjuntar.
    component AttachButton: IconButton {
        property var onDo: null
        diameter: Theme.dp(30)
        iconPixelSize: Theme.sp(14)
        baseColor: "transparent"
        iconColor: Theme.fgMuted
        hoverColor: SettingsPalette.accentSoft
        hoverIconColor: Theme.accentText
        onClicked: if (onDo) onDo()
    }

    // Chip de arranque del estado vacío.
    component SuggestChip: Rectangle {
        id: chip
        property string label: ""
        property var onDo: null
        width: chipText.implicitWidth + Theme.space12 * 2
        height: Theme.dp(30)
        radius: height / 2
        color: chipHov.containsMouse ? SettingsPalette.accentSoft
                                     : SettingsPalette.settingsControl
        border.width: Theme.hairline
        border.color: SettingsPalette.settingsBorder
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chipHov.containsMouse ? Theme.accentText : Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.typeLabelMedium
        }
        MouseArea {
            id: chipHov
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (chip.onDo) chip.onDo()
        }
    }
}
