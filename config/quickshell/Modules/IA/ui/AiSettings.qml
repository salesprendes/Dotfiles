import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages
import qs.Modules.IA.core

// La configuración del asistente, en dos plantas.
//
// A la vista solo lo que hace falta para hablar: proveedor, dirección, clave y si
// contesta. Lo demás vive en grupos plegados que dicen su estado en la propia
// línea —«Permisos: Normal», «Habilidades: 20»—, así que la lámina se lee en ocho
// renglones y solo se abre lo que se va a tocar.
//
// La correa del agente es un control de tres opciones y no una decisión por
// herramienta: las excepciones son eso, excepciones, plegadas y con contador.
Rectangle {
    id: root

    Layout.fillWidth: true
    // Sin conversación aún, la lámina puede permitirse más alto: es lo único que
    // hay en pantalla y quien la abre viene a configurar.
    implicitHeight: Math.min(col.implicitHeight + Theme.space12 * 2,
                             Theme.dp(AiService.messages.count === 0 ? 540 : 430))
    radius: Theme.shapeMd
    color: SettingsPalette.groupFill
    clip: true

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: Theme.space12
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height + 0.5

        ScrollBar.vertical: ThinScrollBar {
            policy: flick.contentHeight > flick.height + 1
                ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            rightPadding: -Theme.space8
            restOpacity: 0.35
        }

        ColumnLayout {
            id: col
            width: flick.width
            spacing: Theme.space8

            // Planta baja: poder hablar
            SegRow {
                glyph: "󰚩"
                label: I18n.tr("Provider")
                options: [ { text: "Gemini", value: "gemini" },
                           { text: "OpenRouter", value: "openrouter" },
                           { text: "Ollama", value: "ollama" },
                           { text: I18n.tr("Server"), value: "custom" } ]
                current: Settings.aiProvider
                onPicked: (v) => Settings.aiProvider = v
            }

            // La URL va primero en los proveedores de servidor propio: sin
            // dirección, la credencial no tiene adónde ir. Se admite cualquier forma
            // razonable —host a secas, con o sin /v1, o el endpoint entero— porque
            // el servicio la normaliza y debajo se enseña la dirección real.
            TextField {
                shown: AiService.provider.userUrl
                label: I18n.tr("Server URL")
                leftIcon: "󰒋"
                placeholder: Settings.aiProvider === "custom"
                    ? "https://ia.tu-servidor.com/v1"
                    : "https://ollama.tu-servidor.com"
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
                shown: AiService.provider.userUrl && AiService.endpoint !== ""
                text: "󰁔  " + AiService.endpoint
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

            // Con un servidor remoto la mitad de los problemas son de red y no del
            // modelo: aquí se ve si contesta, cuánto tarda y cuántos modelos publica
            // antes de escribir la primera pregunta. La sonda salta sola al cambiar
            // URL o clave.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.max(Theme.dp(40),
                                         connCol.implicitHeight + Theme.space8 * 2)
                radius: Theme.shapeSm
                color: AiService.connState === "fail"
                         ? Theme.withAlpha(Theme.red, 0.10)
                     : AiService.connState === "ok"
                         ? Theme.withAlpha(Theme.green, 0.10)
                         : SettingsPalette.settingsControl
                Behavior on color { ColorAnimation { duration: Theme.animNormal } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space10
                    anchors.rightMargin: Theme.space6
                    spacing: Theme.space10

                    // El semáforo: late mientras sondea.
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: Theme.dp(9)
                        implicitHeight: Theme.dp(9)
                        radius: width / 2
                        color: AiService.connState === "ok" ? Theme.green
                             : AiService.connState === "fail" ? Theme.red
                             : AiService.connState === "probing" ? Theme.accent
                             : Theme.fgMuted
                        Behavior on color { ColorAnimation { duration: Theme.animNormal } }
                        SequentialAnimation on opacity {
                            running: AiService.connState === "probing"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: Math.round(Theme.animLoop / 3) }
                            NumberAnimation { to: 1.0; duration: Math.round(Theme.animLoop / 3) }
                        }
                        onOpacityChanged: if (AiService.connState !== "probing" && opacity !== 1)
                            opacity = 1
                    }

                    ColumnLayout {
                        id: connCol
                        Layout.fillWidth: true
                        spacing: 0
                        ThemedText {
                            Layout.fillWidth: true
                            text: AiService.connState === "ok"
                                    ? I18n.tr("Connected · %1 ms · %2 models")
                                          .arg(AiService.connMs).arg(AiService.connModels)
                                : AiService.connState === "probing"
                                    ? I18n.tr("Checking…")
                                : AiService.connState === "fail"
                                    ? I18n.tr("No connection")
                                : AiService.urlMissing
                                    ? I18n.tr("Enter your server's address")
                                : AiService.keyMissing
                                    ? I18n.tr("Enter the API key")
                                    : I18n.tr("Not checked yet")
                            color: AiService.connState === "fail" ? Theme.red
                                 : AiService.connState === "ok" ? Theme.fg : Theme.fgDim
                            font.pixelSize: Theme.typeLabelLarge
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        ThemedText {
                            Layout.fillWidth: true
                            visible: AiService.connDetail !== ""
                            text: AiService.connDetail
                            color: Theme.fgMuted
                            font.pixelSize: Theme.typeLabelSmall
                            wrapMode: Text.WordWrap
                        }
                    }

                    TextButton {
                        text: I18n.tr("Test")
                        outlined: true
                        enabled: AiService.modelsUrl !== ""
                        opacity: enabled ? 1 : 0.4
                        onClicked: AiService.testConnection()
                    }
                }
            }

            Hint {
                Layout.leftMargin: 0
                text: Settings.aiProvider === "gemini"
                    ? I18n.tr("Free tier with a Google AI Studio key — good for quick questions.")
                    : Settings.aiProvider === "openrouter"
                    ? I18n.tr("One key, many models. The :free ids (Qwen, etc.) change over time — adjust the model if one vanishes.")
                    : Settings.aiProvider === "custom"
                    ? I18n.tr("Your own remote server speaking OpenAI: vLLM, TGI, LiteLLM, LM Studio… Paste its /v1 address and, if it asks for one, its key.")
                    : I18n.tr("An Ollama, here or on another machine: paste its address (it must listen beyond localhost).")
            }
            Hint {
                Layout.leftMargin: 0
                shown: AiService.haveKeyring && AiService.keyringWarn === ""
                       && (AiService.provider.needsKey || Settings.aiProvider === "custom")
                text: I18n.tr("Keys are stored in the system keyring, not in settings.json.")
            }
            // Si el llavero ha fallado, la clave no se ha perdido: se ha quedado en
            // los ajustes. Hay que decirlo, porque la promesa de la línea de arriba
            // deja de ser cierta.
            Hint {
                Layout.leftMargin: 0
                shown: AiService.keyringWarn !== ""
                color: Theme.yellow
                text: AiService.keyringWarn
            }

            // Planta de arriba: los grupos
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space4
                Layout.bottomMargin: Theme.space2
                implicitHeight: Theme.hairline
                color: SettingsPalette.settingsBorder
            }

            Fold {
                glyph: "󰦝"
                title: I18n.tr("Connection details")
                summary: Settings.aiInsecureTls ? I18n.tr("Untrusted TLS") : ""
                warn: Settings.aiInsecureTls
                visible: AiService.provider.userUrl
                sourceComponent: Component {
                    ColumnLayout {
                        spacing: Theme.space8
                        // Extras de un servidor tras una pasarela: su propia
                        // cabecera y su certificado.
                        TextField {
                            label: I18n.tr("Extra header")
                            leftIcon: "󰐕"
                            placeholder: "X-Api-Key: …"
                            value: Settings.aiCustomHeader
                            onEdited: (t) => Settings.aiCustomHeader = t.trim()
                        }
                        SwitchRow {
                            glyph: "󰦝"
                            label: I18n.tr("Accept untrusted certificate")
                            desc: I18n.tr("Only for your own server with a self-signed certificate")
                            checked: Settings.aiInsecureTls
                            onToggled: Settings.aiInsecureTls = !Settings.aiInsecureTls
                        }
                    }
                }
            }

            Fold {
                glyph: "󰚈"
                title: I18n.tr("Answers")
                summary: {
                    const p = Settings.aiPersona
                    return p === "concise" ? I18n.tr("Concise")
                         : p === "teacher" ? I18n.tr("Teacher")
                         : p === "reviewer" ? I18n.tr("Reviewer")
                                            : I18n.tr("Normal")
                }
                sourceComponent: Component {
                    ColumnLayout {
                        spacing: Theme.space8

                        // Estilo de respuesta (persona): un ajuste, no un
                        // prompt escrito a mano.
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

                        // Interruptor suave de razonamiento. Con un modelo local,
                        // apagar el pensamiento es la mayor mejora de latencia que
                        // existe, y encenderlo, la de calidad.
                        SegRow {
                            glyph: "󰟃"
                            // Con un modelo reconocido es la palanca de ese modelo,
                            // se llame como se llame por dentro.
                            label: AiService.profileLabel !== ""
                                ? I18n.tr("Reasoning") : I18n.tr("Reasoning (Qwen)")
                            options: [ { text: "Auto", value: "auto" },
                                       { text: I18n.tr("Always"), value: "think" },
                                       { text: I18n.tr("Off"), value: "no_think" } ]
                            current: Settings.aiThink
                            onPicked: (v) => Settings.aiThink = v
                        }
                        Hint {
                            Layout.leftMargin: 0
                            // Cada familia enciende el pensamiento por un sitio
                            // distinto, y decirlo evita buscar un interruptor que en
                            // ese modelo no existe.
                            text: AiService.profile.softSwitch
                                ? I18n.tr("Qwen3 soft switch: adds /think or /no_think to your message. Other models ignore it.")
                                : AiService.profile.thinking === "always"
                                ? I18n.tr("%1 always thinks: it cannot be turned off, only turned down.").arg(AiService.profileLabel)
                                : AiService.profile.thinkVia === "systoken"
                                ? I18n.tr("%1 switches it with a mark at the start of the system prompt — the harness puts it there.").arg(AiService.profileLabel)
                                : I18n.tr("%1 has its own flag: the switch travels in the request, not inside your message.").arg(AiService.profileLabel)
                        }

                        // Con cualquier otro modelo esta parte no aparece: no
                        // tiene sentido ofrecer palancas que nadie va a leer al
                        // otro lado.
                        SegRow {
                            shown: AiService.profile.efforts.length > 0
                            glyph: "󰓅"
                            label: I18n.tr("Reasoning effort")
                            options: [ { text: "Auto", value: "auto" },
                                       { text: I18n.tr("Low"), value: "low" },
                                       { text: I18n.tr("Balanced"), value: "medium" },
                                       { text: I18n.tr("Max"), value: "xhigh" } ]
                            current: AiService.effortSetting
                            onPicked: (v) => Settings.aiEffort = v
                        }
                        Hint {
                            shown: AiService.profile.efforts.length > 0
                            Layout.leftMargin: 0
                            text: AiService.effortSetting === "auto"
                                ? I18n.tr("Auto spends thinking where decisions are made (the first turn of a task, code review) and goes light where the work is mechanical (tool rounds, compacting, supervising).")
                                : I18n.tr("Fixed for everything — including compacting and supervising, which do not need it.")
                        }

                        SwitchRow {
                            shown: AiService.profile.sampling !== null
                            glyph: "󰘵"
                            label: I18n.tr("Model's recommended settings")
                            checked: Settings.aiModelTuning
                            onToggled: Settings.aiModelTuning = !Settings.aiModelTuning
                        }
                        Hint {
                            shown: AiService.profile.sampling !== null
                            Layout.leftMargin: 0
                            text: I18n.tr("Uses the sampling values its authors recommend (they differ between thinking and not thinking). With a Qwen this is not a detail: the wrong temperature turns solving the task into rambling. While it is on, the Creativity slider does not travel.")
                        }

                        SwitchRow {
                            shown: AiService.profile.preserveThinking
                            glyph: "󰑖"
                            label: I18n.tr("Give its reasoning back")
                            checked: Settings.aiKeepThinking
                            onToggled: Settings.aiKeepThinking = !Settings.aiKeepThinking
                        }
                        Hint {
                            shown: AiService.profile.preserveThinking
                            Layout.leftMargin: 0
                            text: I18n.tr("Sends back its own reasoning from the last two turns, which this model knows how to reuse: it picks a long task up where it left it instead of reasoning it out again.")
                        }

                        SliderRow {
                            label: I18n.tr("Creativity"); glyph: "󰔄"
                            enabled: !(AiService.profile.sampling !== null
                                       && Settings.aiModelTuning)
                            opacity: enabled ? 1 : 0.45
                            from: 0.0; to: 1.5; value: Settings.aiTemperature
                            valueText: Settings.aiTemperature.toFixed(1)
                            onMoved: (v) => Settings.aiTemperature = Math.round(v * 10) / 10
                        }

                        TextField {
                            label: I18n.tr("Extra instructions")
                            leftIcon: "󰚈"
                            placeholder: I18n.tr("e.g. answer always in Spanish, prefer fish over bash…")
                            value: Settings.aiCustomPrompt
                            onEdited: (t) => Settings.aiCustomPrompt = t
                        }
                    }
                }
            }

            // Hasta ahora solo se podía elegir desde el botón de la cabecera, y
            // en Ajustes —donde uno viene precisamente a configurar el
            // servidor— no había forma. Es la misma lámina, con su buscador y
            // su catálogo: lo que publique el servidor, con la variante al lado
            // para distinguir el de 27B del de 32B, y la fila "Otro" para
            // escribir un id que el catálogo no liste.
            Fold {
                glyph: "󰧑"
                title: I18n.tr("Model")
                summary: AiService.model === "" ? I18n.tr("choose one")
                                                : AiService.modelLabel(AiService.model)
                warn: AiService.model === ""
                sourceComponent: Component { ModelSheet { autoFocus: false } }
            }

            // Que se vea que el harness ha reconocido el modelo: si no, el
            // usuario no tiene forma de saber por qué la ventana pasó de 32k a
            // 262k ni de dónde salen las palancas nuevas.
            Hint {
                shown: AiService.profileLabel !== ""
                Layout.leftMargin: 0
                text: "󰄬  " + I18n.tr("Recognised model: %1").arg(AiService.profileLabel)
                      + "  ·  " + Math.round(AiService.contextTokens / 1000) + "k"
                      + (AiService.profile.vision ? "  ·  " + I18n.tr("sees images") : "")
                color: Theme.green
            }

            Fold {
                glyph: "󰍛"
                title: I18n.tr("Context")
                summary: Math.round(AiService.contextTokens / 1000) + "k"
                sourceComponent: Component {
                    ColumnLayout {
                        spacing: Theme.space8

                        // Ventana del modelo: de aquí sale todo el reparto del
                        // contexto. Con un modelo local pequeño es el ajuste
                        // que más se nota.
                        TextField {
                            label: I18n.tr("Context window (tokens)")
                            leftIcon: "󰍛"
                            placeholder: I18n.tr("automatic")
                            value: Settings.aiContextTokens > 0
                                ? String(Settings.aiContextTokens) : ""
                            onEdited: (t) => Settings.aiContextTokens = parseInt(t) || 0
                        }
                        Hint {
                            Layout.leftMargin: 0
                            text: I18n.tr("Now: %1 tokens · %2 chars of history · %3 per tool result.")
                                .arg(AiService.contextTokens)
                                .arg(AiService.charBudget)
                                .arg(AiService.toolResultCap)
                        }

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
                            text: I18n.tr("At 85% of the context: Warn suggests /compact; Auto does it by itself, also mid-turn, and rescues the turn if the context overflows.")
                        }
                    }
                }
            }

            // Permisos
            Fold {
                glyph: "󰒃"
                title: I18n.tr("Permissions")
                summary: root.approvalLabel(AiService.approvalMode)
                         + (AiService.toolOverrides > 0
                            ? " · " + AiService.toolOverrides : "")
                warn: AiService.approvalMode === "auto"
                sourceComponent: Component {
                    ColumnLayout {
                        spacing: Theme.space8

                        SegRow {
                            glyph: "󰒃"
                            label: I18n.tr("Approval")
                            options: [ { text: I18n.tr("Careful"), value: "careful" },
                                       { text: I18n.tr("Normal"), value: "normal" },
                                       { text: I18n.tr("Autonomous"), value: "auto" } ]
                            current: AiService.approvalMode
                            onPicked: (v) => Settings.aiApproval = v
                        }
                        Hint {
                            Layout.leftMargin: 0
                            text: AiService.approvalMode === "careful"
                                ? I18n.tr("Asks before anything, even reading a file.")
                                : AiService.approvalMode === "auto"
                                ? I18n.tr("Acts without asking — writes, runs commands and reaches the network on its own.")
                                : I18n.tr("Reads and queries on its own. Writing, running and reaching out ask first.")
                            color: AiService.approvalMode === "auto" ? Theme.red
                                                                     : Theme.fgMuted
                        }

                        // El supervisor va aquí y no en su propia sección: es
                        // una decisión de permisos, no una comodidad. Y vive
                        // pegado al modo porque lo que hace es corregirlo —
                        // sostener una correa suelta con un segundo par de ojos.
                        SegRow {
                            glyph: "󰭎"
                            label: I18n.tr("Supervisor")
                            options: [ { text: I18n.tr("Off"), value: "off" },
                                       { text: I18n.tr("Risky only"), value: "risky" },
                                       { text: I18n.tr("Everything"), value: "all" } ]
                            current: AiService.supervisorMode
                            onPicked: (v) => Settings.aiSupervisor = v
                        }
                        Hint {
                            Layout.leftMargin: 0
                            text: AiService.supervisorMode === "off"
                                ? I18n.tr("Nobody double-checks the agent.")
                                : AiService.supervisorMode === "all"
                                ? I18n.tr("A second model reviews every call — one extra request each. Only worth it with a fast model.")
                                : I18n.tr("A second model reviews what can do damage (writing, running, destructive commands) before you decide. It can only stop things, never approve them.")
                        }
                        TextField {
                            shown: AiService.supervisorMode !== "off"
                            label: I18n.tr("Supervisor model")
                            leftIcon: "󰭎"
                            placeholder: I18n.tr("the same one as the agent")
                            value: Settings.aiSupervisorModel
                            onEdited: (t) => Settings.aiSupervisorModel = t.trim()
                        }
                        Hint {
                            visible: AiService.supervisorMode !== "off"
                            Layout.leftMargin: 0
                            text: I18n.tr("Another model on the SAME server — a small fast one watching a big one is the useful combination. Not another provider: that would mean sending pieces of your files to a third company for an opinion.")
                        }

                        // Las excepciones son eso: excepciones. Plegadas, con
                        // contador, y solo se construyen al abrirlas.
                        Fold {
                            glyph: "󰙨"
                                        title: I18n.tr("Per-tool exceptions")
                            summary: AiService.toolOverrides > 0
                                ? String(AiService.toolOverrides)
                                : I18n.tr("none")
                            sourceComponent: Component { ToolPolicyList {} }
                        }
                    }
                }
            }

            // Habilidades
            Fold {
                glyph: "󰠮"
                title: I18n.tr("Skills")
                summary: AiService.skills.length === 0 ? I18n.tr("none")
                    : root.skillsOn + "/" + AiService.skills.length
                sourceComponent: Component {
                    ColumnLayout {
                        spacing: Theme.space6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space8
                            SearchField {
                                id: skillQ
                                Layout.fillWidth: true
                                visible: AiService.skills.length > 6
                                placeholder: I18n.tr("Filter skills…")
                            }
                            Chip {
                                label: "󰑐 " + I18n.tr("Refresh")
                                onDo: () => AiService.rescanSkills()
                            }
                        }
                        EmptyNote {
                            visible: AiService.skills.length === 0
                            text: I18n.tr("No skills installed.")
                        }
                        Repeater {
                            model: AiService.skills
                            delegate: SkillRow {
                                required property var modelData
                                name: modelData.name
                                desc: modelData.description
                                shown: skillQ.text.trim() === ""
                                    || (modelData.name + " " + modelData.description)
                                        .toLowerCase()
                                        .indexOf(skillQ.text.trim().toLowerCase()) !== -1
                                checked: AiService.skillEnabled(modelData.id)
                                onToggled: AiService.setSkillEnabled(modelData.id,
                                    !AiService.skillEnabled(modelData.id))
                            }
                        }
                        Hint {
                            Layout.leftMargin: 0
                            text: I18n.tr("One folder per skill in %1, each with its SKILL.md (YAML front matter + Markdown).")
                                .arg("Modules/IA/skills")
                        }
                    }
                }
            }

            // Herramientas externas
            Fold {
                glyph: "󱁤"
                title: I18n.tr("External tools")
                summary: {
                    const n = (Settings.aiMcpServers || []).length
                    return n === 0 ? I18n.tr("none")
                                   : n + " · " + AiService.mcpTools.length
                }
                sourceComponent: Component {
                    ColumnLayout {
                        spacing: Theme.space6

                        // Procesos que publican herramientas por el Model
                        // Context Protocol (stdio). Cada fila: estado, nombre y
                        // cuántas herramientas aporta.
                        EmptyNote {
                            visible: (Settings.aiMcpServers || []).length === 0
                            text: I18n.tr("No MCP servers configured.")
                        }
                        Repeater {
                            model: Settings.aiMcpServers
                            delegate: RowLayout {
                                id: mcpRow
                                required property var modelData
                                required property int index
                                readonly property string st:
                                    (AiService.mcpStatus[modelData.name] || "starting")
                                Layout.fillWidth: true
                                spacing: Theme.space8
                                Rectangle {
                                    implicitWidth: Theme.dp(8)
                                    implicitHeight: Theme.dp(8)
                                    radius: width / 2
                                    color: mcpRow.st === "ok" ? Theme.green
                                         : mcpRow.st.startsWith("error") ? Theme.red
                                         : Theme.fgMuted
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    ThemedText {
                                        Layout.fillWidth: true
                                        text: mcpRow.modelData.name
                                              + (mcpRow.st === "ok"
                                                 ? "  ·  " + AiService.mcpTools
                                                       .filter(t => t.server === mcpRow.modelData.name).length
                                                       + " " + I18n.tr("tools")
                                                 : "")
                                        color: Theme.fgDim
                                        font.pixelSize: Theme.typeLabelMedium
                                        elide: Text.ElideRight
                                    }
                                    ThemedText {
                                        Layout.fillWidth: true
                                        visible: mcpRow.st.startsWith("error")
                                        text: mcpRow.st
                                        color: Theme.red
                                        font.pixelSize: Theme.typeLabelSmall
                                        elide: Text.ElideRight
                                    }
                                }
                                RowDelete {
                                    onClicked: {
                                        const l = (Settings.aiMcpServers || []).slice()
                                        l.splice(mcpRow.index, 1)
                                        Settings.aiMcpServers = l
                                    }
                                }
                            }
                        }
                        // Alta: nombre corto + comando que arranca el servidor.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space8
                            DraftField {
                                id: mcpName
                                Layout.preferredWidth: Theme.dp(110)
                                placeholder: I18n.tr("name")
                            }
                            DraftField {
                                id: mcpCmd
                                Layout.fillWidth: true
                                placeholder: "npx -y @modelcontextprotocol/server-filesystem ~/docs"
                            }
                            TextButton {
                                text: I18n.tr("Add")
                                outlined: true
                                onClicked: {
                                    const n = mcpName.draft.trim().replace(/[^A-Za-z0-9_-]/g, "")
                                    const c = mcpCmd.draft.trim()
                                    if (n === "" || c === "")
                                        return
                                    Settings.aiMcpServers = (Settings.aiMcpServers || [])
                                        .filter(s => s.name !== n)
                                        .concat([{ name: n, command: c }])
                                    mcpName.reset()
                                    mcpCmd.reset()
                                }
                            }
                        }
                        Hint {
                            Layout.leftMargin: 0
                            text: I18n.tr("Its tools appear to the model as mcp__name__tool and run only after your approval.")
                        }
                    }
                }
            }

            // Tenía media línea escondida dentro del grupo de MCP, y era
            // engañosa: decía "opcional, sin esto el asistente busca igual". Ya
            // no es verdad, y esa mentira salía cara — las instancias públicas
            // de SearXNG dejaron de servir su API JSON a clientes sin navegador,
            // y DuckDuckGo y Mojeek responden con un captcha, así que la
            // herramienta fallaba SIEMPRE. Como el fallo llegaba al modelo como
            // un error cualquiera, este reformulaba la consulta y lo reintentaba
            // hasta agotar el turno: por fuera se veía como si se quedara
            // pensando.
            Fold {
                glyph: "󰖟"
                title: I18n.tr("Web search")
                // Ya no es "configurado o no": siempre hay al menos DuckDuckGo,
                // así que lo que importa es a CUÁNTAS voces se pregunta.
                summary: AiService.searchSources.join(" + ")
                sourceComponent: Component {
                    ColumnLayout {
                        spacing: Theme.space8
                        // Abrir esta sección vuelve a mirar si hay un SearXNG en
                        // la máquina: si acabas de levantarlo, lo normal es que
                        // vengas aquí a comprobarlo.
                        Component.onCompleted: AiService.probeSearchLocal()

                        Hint {
                            Layout.leftMargin: 0
                            text: I18n.tr("Asks every source at once and merges the answers: what several agree on rises to the top. Three need nothing at all and are always asked — DuckDuckGo, Brave and Mojeek, with three different indexes — so there is consensus out of the box.")
                        }

                        DropdownRow {
                            glyph: "󰍉"
                            label: I18n.tr("Preferred source")
                            options: [ { text: "DuckDuckGo", value: "ddg" },
                                       { text: "Brave Search", value: "brave" },
                                       { text: "Mojeek", value: "mojeek" },
                                       { text: "SearXNG", value: "searxng" },
                                       { text: I18n.tr("Tavily (needs a key)"), value: "tavily" },
                                       { text: I18n.tr("Exa (needs a key)"), value: "exa" },
                                       { text: I18n.tr("Kagi (needs a key)"), value: "kagi" } ]
                            current: Settings.aiSearchBackend
                            onPicked: (v) => Settings.aiSearchBackend = v
                        }
                        Hint {
                            Layout.leftMargin: 0
                            text: I18n.tr("Only breaks ties: with the same number of sources agreeing, this one wins. The one with a key, if you set one, is this one.")
                        }

                        // La dirección y la clave se enseñan siempre: no
                        // compiten entre sí, se suman.
                        TextField {
                            label: I18n.tr("Your SearXNG")
                            leftIcon: "󰇧"
                            placeholder: "http://localhost:8080"
                            value: Settings.aiSearchUrl
                            onEdited: (t) => Settings.aiSearchUrl = t.trim()
                        }
                        Hint {
                            Layout.leftMargin: 0
                            color: AiService.searchLocal !== "" ? Theme.green : Theme.fgMuted
                            text: AiService.searchLocal !== ""
                                ? I18n.tr("Found one here: %1 — it works with no further setup.")
                                      .arg(AiService.searchLocal)
                                : I18n.tr("Needs formats: [json] in its settings.yml. One running on localhost:8080 is found on its own.")
                        }

                        // La clave es UNA y es la de la fuente preferida. Por
                        // eso el campo desaparece cuando la elegida no lleva
                        // clave: enseñar una casilla que no va a ningún sitio es
                        // peor que no enseñarla.
                        TextField {
                            visible: AiService.searchTakesKey
                            label: I18n.tr("%1 key").arg(AiService.searchBackendLabel)
                            leftIcon: "󰌆"
                            password: true
                            placeholder: Settings.aiSearchBackend === "tavily" ? "tvly-…"
                                       : Settings.aiSearchBackend === "brave" ? "BSA…"
                                       : ""
                            value: AiService.searchKey
                            onEdited: (t) => AiService.setKey("search", t)
                        }
                        Hint {
                            Layout.leftMargin: 0
                            visible: AiService.searchTakesKey
                            text: Settings.aiSearchBackend === "brave"
                                ? I18n.tr("Optional: without a key Brave is read from its public page, which already works. With one it answers through its API, with dates and no markup surprises.")
                                : AiService.haveKeyring
                                  ? I18n.tr("Free tier is enough for everyday use. Stored in the system keyring.")
                                  : I18n.tr("Free tier is enough for everyday use.")
                        }

                        // El estado, dicho sin rodeos: es la diferencia entre
                        // "no encuentro nada" y "no puedo buscar".
                        Hint {
                            Layout.leftMargin: 0
                            visible: AiService.searchBroken
                            color: Theme.red
                            text: I18n.tr("The last search failed in every source. Change something here and it will try again.")
                        }
                    }
                }
            }

            // Servidores remotos
            Fold {
                glyph: "󰒋"
                title: I18n.tr("Remote servers (SSH)")
                summary: (Settings.aiSshHosts || []).length === 0
                    ? I18n.tr("none") : String((Settings.aiSshHosts || []).length)
                sourceComponent: Component {
                    ColumnLayout {
                        spacing: Theme.space6

                        // Lista blanca: el modelo solo se conecta a lo que se
                        // registre aquí, por nombre. Las contraseñas van al
                        // llavero, no a settings.json.
                        EmptyNote {
                            visible: (Settings.aiSshHosts || []).length === 0
                            text: I18n.tr("No servers registered.")
                        }
                        Repeater {
                            model: Settings.aiSshHosts
                            delegate: RowLayout {
                                id: sshRow
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: Theme.space8
                                ThemedText {
                                    text: (AiService.sshPass[sshRow.modelData.name] ? "󰌾" : "󰷖")
                                    color: Theme.fgMuted
                                    font.pixelSize: Theme.sp(13)
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    ThemedText {
                                        Layout.fillWidth: true
                                        text: sshRow.modelData.name
                                        color: Theme.fgDim
                                        font.pixelSize: Theme.typeLabelMedium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: (sshRow.modelData.user || "root")
                                              + "@" + sshRow.modelData.host
                                              + ":" + (sshRow.modelData.port || 22)
                                        color: Theme.fgMuted
                                        font.family: Theme.monoFontFamily
                                        font.pixelSize: Theme.typeLabelSmall
                                        elide: Text.ElideMiddle
                                    }
                                }
                                RowDelete {
                                    onClicked: {
                                        AiService.setSshPassword(sshRow.modelData.name, "")
                                        const l = (Settings.aiSshHosts || []).slice()
                                        l.splice(sshRow.index, 1)
                                        Settings.aiSshHosts = l
                                    }
                                }
                            }
                        }
                        // Alta: alias y el destino EN PIEZAS — usuario, host y
                        // puerto por separado. El campo combinado "root@1.2.3.4"
                        // se quedaba vacío sin que se notara cuál faltaba, y
                        // cada campo con su etiqueta encima no necesita
                        // explicación. Pegar "usuario@ip" entero en el host
                        // sigue valiendo: el alta lo reparte.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space8
                            DraftField {
                                id: sshName
                                Layout.preferredWidth: Theme.dp(110)
                                label: I18n.tr("name")
                                placeholder: "servidor-ia"
                            }
                            DraftField {
                                id: sshUser
                                Layout.preferredWidth: Theme.dp(110)
                                label: I18n.tr("user")
                                placeholder: "root"
                            }
                            DraftField {
                                id: sshHost
                                Layout.fillWidth: true
                                label: I18n.tr("host or IP")
                                placeholder: "192.168.1.10"
                            }
                            DraftField {
                                id: sshPort
                                Layout.preferredWidth: Theme.dp(64)
                                label: I18n.tr("port")
                                placeholder: "22"
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space8
                            DraftField {
                                id: sshPw
                                Layout.fillWidth: true
                                password: true
                                placeholder: I18n.tr("password (blank if key)")
                            }
                            TextButton {
                                text: I18n.tr("Add")
                                outlined: true
                                onClicked: {
                                    const n = sshName.draft.trim().replace(/[^A-Za-z0-9_.-]/g, "")
                                    let host = sshHost.draft.trim()
                                    let user = sshUser.draft.trim()
                                    // Tolerancia con la forma vieja: si el host
                                    // trae "usuario@ip" entero, se reparte (el
                                    // usuario tecleado aparte manda).
                                    const at = host.indexOf("@")
                                    if (at > 0) {
                                        if (user === "")
                                            user = host.slice(0, at)
                                        host = host.slice(at + 1)
                                    }
                                    if (user === "")
                                        user = "root"
                                    console.log("[ssh-alta] name='" + n + "' user='"
                                                + user + "' host='" + host + "'")
                                    // Un campo vacío retornaba EN SILENCIO:
                                    // "le doy a añadir y no pasa nada". El
                                    // culpable se enciende en rojo (y se apaga
                                    // al volver a teclear en él). Ojo: el
                                    // nombre puede quedar vacío tras el saneo
                                    // (solo letras, números y _ . -).
                                    sshName.invalid = (n === "")
                                    sshHost.invalid = (host === "")
                                    if (n === "" || host === "")
                                        return
                                    const port = parseInt(sshPort.draft) || 22
                                    Settings.aiSshHosts = (Settings.aiSshHosts || [])
                                        .filter(h => h.name !== n)
                                        .concat([{ name: n, host: host, user: user, port: port }])
                                    if (sshPw.draft.trim() !== "")
                                        AiService.setSshPassword(n, sshPw.draft.trim())
                                    sshName.reset(); sshUser.reset(); sshHost.reset()
                                    sshPort.reset(); sshPw.reset()
                                }
                            }
                        }
                        Hint {
                            Layout.leftMargin: 0
                            shown: AiService.haveKeyring
                            text: I18n.tr("Optional: saved servers let you say \"web1\" instead of repeating credentials. You can always give host and password in the message. Passwords go to the system keyring; password login needs 'sshpass'.")
                        }
                        // Sin llavero la promesa de arriba es falsa: las
                        // contraseñas caen en claro a settings.json (respaldo
                        // de KeyStore.setSshPassword). Decirlo aquí, en
                        // amarillo, es la diferencia entre una decisión del
                        // usuario y una sorpresa al abrir el archivo.
                        Hint {
                            Layout.leftMargin: 0
                            shown: !AiService.haveKeyring
                            color: Theme.yellow
                            text: I18n.tr("Optional: saved servers let you say \"web1\" instead of repeating credentials. No system keyring found: passwords are stored as plain text in settings.json. Password login needs 'sshpass'.")
                        }
                    }
                }
            }

            // Memoria
            Fold {
                glyph: "󰍩"
                title: I18n.tr("Memory")
                summary: (AiService.memoryList.length + AiService.instinctList.length) === 0
                    ? I18n.tr("none")
                    : (AiService.memoryList.length + " · " + AiService.instinctList.length)
                sourceComponent: Component {
                    ColumnLayout {
                        spacing: Theme.space6

                        // Lo que el asistente guardó (con aprobación) y se
                        // inyecta en cada conversación.
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
                                ThemedText {
                                    text: "󰍩"
                                    color: Theme.fgMuted
                                    font.pixelSize: Theme.sp(12)
                                }
                                ThemedText {
                                    Layout.fillWidth: true
                                    text: memRow.modelData
                                    color: Theme.fgDim
                                    font.pixelSize: Theme.typeBodySmall
                                    elide: Text.ElideRight
                                }
                                RowDelete { onClicked: AiService.removeMemory(memRow.index) }
                            }
                        }

                        // Instintos: lo aprendido de este equipo. El número es
                        // cuántas veces se lo ha vuelto a encontrar — cuanto
                        // más alto, antes entra en el contexto.
                        ThemedText {
                            Layout.topMargin: Theme.space4
                            visible: AiService.instinctList.length > 0
                            text: I18n.tr("Learned about this machine")
                            color: Theme.fgDim
                            font.pixelSize: Theme.typeLabelMedium
                            font.weight: Font.Medium
                        }
                        Repeater {
                            model: AiService.instinctList
                            delegate: RowLayout {
                                id: instRow
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: Theme.space8
                                ThemedText {
                                    text: "󱐋"
                                    color: Theme.accentText
                                    font.pixelSize: Theme.sp(12)
                                }
                                ThemedText {
                                    Layout.fillWidth: true
                                    text: instRow.modelData.text
                                    color: Theme.fgDim
                                    font.pixelSize: Theme.typeBodySmall
                                    elide: Text.ElideRight
                                }
                                ThemedText {
                                    text: "×" + (instRow.modelData.confidence || 1)
                                    color: Theme.fgMuted
                                    font.pixelSize: Theme.typeLabelSmall
                                }
                                RowDelete { onClicked: AiService.removeInstinct(instRow.index) }
                            }
                        }
                    }
                }
            }
        }
    }

    // Cuántas habilidades hay encendidas: el estado del grupo plegado.
    readonly property int skillsOn: {
        let n = 0
        const s = AiService.skills
        for (let i = 0; i < s.length; i++)
            if (AiService.skillEnabled(s[i].id))
                n++
        return n
    }

    function approvalLabel(m) {
        return m === "careful" ? I18n.tr("Careful")
             : m === "auto" ? I18n.tr("Autonomous")
                            : I18n.tr("Normal")
    }

    // Campo de alta: guarda lo tecleado en 'draft' y sabe vaciarse. El valor no
    // puede leerse del TextField (su TextInput interno no lo publica), así que
    // cada alta llevaba su propia propiedad y su propio par de líneas para
    // limpiarse.
    component DraftField: TextField {
        property string draft: ""
        label: ""
        onEdited: (t) => { draft = t; invalid = false }
        function reset() { draft = ""; invalid = false; clear() }
    }
}
