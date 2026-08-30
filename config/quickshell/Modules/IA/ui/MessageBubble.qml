import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Components
import qs.Config
import qs.Panels.SettingsPages
import qs.Modules.IA.core

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
    // El motivo por el que esta llamada concreta se considera peligrosa, o "" si
    // no lo es. Solo se pregunta mientras la tarjeta espera decisión.
    readonly property string dangerWhy:
        toolStatus === "pending" ? AiService.dangerOf(msgIndex) : ""
    property string toolArgs: ""
    property string toolResult: ""
    property string toolStatus: ""
    property string attachNote: ""
    property string ts: ""
    // Copia de seguridad de una edición: si la hay, se puede deshacer.
    property string undoPath: ""
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

    // Con el panel en su ancho mínimo, la tarjeta de herramienta se queda con
    // poco para el contenido y lo que sobra son sus propios márgenes. Por debajo
    // de este umbral todo se ciñe: márgenes, separaciones y avatar. Se mide el
    // ancho de esta burbuja y no el de la ventana, porque es el sitio que tiene
    // delante lo que decide si cabe.
    readonly property bool angosto: bubble.width > 0 && bubble.width < Theme.dp(420)
    readonly property int pad: angosto ? Theme.space8 : Theme.space12
    readonly property int hueco: angosto ? Theme.space6 : Theme.space10

    // Entre aprobar y ver el resultado, sin esto la tarjeta no cambia nada: los
    // botones siguen puestos, no hay reloj, y desde fuera no se distingue "el
    // comando está corriendo" de "el modelo está pensando" o de "se ha colgado".
    //
    // El estado no vive en el mensaje sino en el ejecutor: al recargar una
    // conversación no hay nada ejecutándose, y guardarlo dejaría tarjetas
    // eternamente en curso de procesos que ya no existen.
    readonly property bool toolRunning:
        isTool && AiService.toolRunningIndex === msgIndex
    // El reloj solo late mientras hay algo corriendo, y solo en ESTA tarjeta:
    // como mucho hay una a la vez.
    property double _ahora: 0
    readonly property int _corriendoS:
        Math.max(0, Math.round((_ahora - AiService.toolRunningSince) / 1000))
    Timer {
        running: bubble.toolRunning
        interval: 500
        repeat: true
        triggeredOnStart: true
        onTriggered: bubble._ahora = Date.now()
    }

    // Lo que pide la herramienta, ya legible.
    readonly property var _args: {
        if (!isTool) return ({})
        try { return JSON.parse(toolArgs) } catch (e) { return ({ raw: toolArgs }) }
    }

    // El veredicto llega después de que la tarjeta esté en pantalla —la crea el
    // streaming y el segundo modelo tarda—, así que esto pasa de "mirando" a un
    // juicio sin que el usuario espere.
    readonly property bool _supWatching:
        isTool && AiService.supervisorWatching === msgIndex
    readonly property var _sup: isTool ? AiService.supervisorOf(msgIndex) : null
    readonly property color _supColor:
        _supWatching ? Theme.fgMuted
      : !_sup ? Theme.fgMuted
      : _sup.fallo ? Theme.orange
      : _sup.veredicto === "dudo" ? Theme.orange
      : _sup.veredicto === "bloqueo" ? Theme.red
                                     : Theme.green
    readonly property string _supText: {
        if (_supWatching)
            return I18n.tr("The supervisor is looking at this…")
        if (!_sup)
            return ""
        if (_sup.fallo)
            return I18n.tr("The supervisor did not answer — decide yourself.")
        if (_sup.veredicto === "ok")
            return I18n.tr("The supervisor sees nothing worrying.")
        let t = I18n.tr("The supervisor is not sure — %1").arg(
            _sup.riesgo !== "" ? _sup.riesgo : I18n.tr("it did not say why"))
        if (String(_sup.irreversible || "").trim() !== "")
            t += "  ·  " + I18n.tr("no way back: %1").arg(_sup.irreversible)
        if (String(_sup.ajuste || "") !== "")
            t += "  (" + _sup.ajuste + ")"
        return t
    }

    // Lo que se le concede al subagente, dicho en la tarjeta donde se aprueba: una
    // que diga "delega una tarea" y se calle que va a escribir no es una
    // aprobación informada, y este permiso es el único que habrá para todo lo que
    // el subagente haga después.
    readonly property string _subGrant: {
        if (toolName !== "subagent")
            return ""
        const nombres = ({ read: I18n.tr("reads"), net: I18n.tr("web"),
                           write: I18n.tr("writes in its own workshop") })
        const g = AiService.subagentGrantFor(bubble._args)
        const papel = String(bubble._args.role || "research")
        return papel + "  ·  "
             + AiService.grantCaps(g).map(c => nombres[c] || c).join(" · ")
    }

    // Una tabla con una línea por herramienta, en vez de cuatro cadenas de
    // ternarios en paralelo donde añadir una obligaría a acertar en las cuatro y
    // olvidarse de alguna daría una tarjeta a medio pintar. Lo que una herramienta
    // no diga cae en el genérico.
    //   ico   glifo de la tarjeta
    //   di    titular ("El asistente quiere…"), ya traducido
    //   res   resumen de una línea, en la lápida de código
    //   ver   lo que se va a cambiar, para leerlo antes de aprobar
    //
    // 'a' es un accesor a los argumentos: a("path"). No es el objeto pelado a
    // propósito, porque un campo que el modelo no mandó saldría como "undefined"
    // pintado en la tarjeta.
    readonly property var _toolCards: ({
        open_url:      { ico: "󰖟", di: I18n.tr("The assistant wants to open:"),
                         res: a => a("url") },
        run_command:   { ico: "󰆍", di: I18n.tr("The assistant wants to run:"),
                         res: a => a("command") },
        read_file:     { ico: "󰈙", di: I18n.tr("The assistant wants to read:"),
                         res: a => a("path") },
        read_files:    { ico: "󰈢", di: I18n.tr("The assistant wants to read files:"),
                         res: a => Array.isArray(a("paths"))
                                   ? a("paths").length + " archivos" : "",
                         ver: a => (a("paths") || []).join("\n") },
        list_dir:      { ico: "󰉋", di: I18n.tr("The assistant wants to list:"),
                         res: a => a("path") },
        write_file:    { ico: "󰷈", di: I18n.tr("The assistant wants to write:"),
                         res: a => a("path"), ver: a => a("content") },
        edit_file:     { ico: "󰏫", di: I18n.tr("The assistant wants to edit:"),
                         res: a => a("path"),
                         // El trozo saliente con - y el entrante con +, como un
                         // diff.
                         ver: a => ("- " + String(a("old_string")).split("\n").join("\n- ")).slice(0, 600)
                                 + "\n" + ("+ " + String(a("new_string")).split("\n").join("\n+ ")).slice(0, 600) },
        edit_patch:    { ico: "󱇧", di: I18n.tr("The assistant wants to patch (hash-anchored):"),
                         res: a => a("path") + "  ·  "
                                   + (Array.isArray(a("hunks")) ? a("hunks").length : "?")
                                   + " cambios"
                                   + (a("dry_run") ? "  (ensayo)" : ""),
                         // Cada hunk como "op ancla → texto": se ve dónde toca y
                         // con qué, sin abrir el archivo.
                         ver: a => (a("hunks") || []).map(k =>
                                (k.op || "replace") + "  " + (k.at || "?")
                                + (k.to ? ".." + k.to : "")
                                + (k.text !== undefined && k.text !== ""
                                   ? "\n" + String(k.text).split("\n")
                                       .map(l => "+ " + l).join("\n") : ""))
                             .join("\n\n") },
        edit_lines:    { ico: "󰗀", di: I18n.tr("The assistant wants to replace lines:"),
                         res: a => a("path") + "  ·  líneas "
                                   + (a("start") || "?") + "-" + (a("end") || "?"),
                         ver: a => a("text") },
        grep_files:    { ico: "󰱼", di: I18n.tr("The assistant wants to search:"),
                         res: a => a("pattern") + "  ·  " + a("path") },
        glob_files:    { ico: "󰱽", di: I18n.tr("The assistant wants to find files:"),
                         res: a => a("pattern") + "  ·  " + a("path") },
        fetch_url:     { ico: "󰇧", di: I18n.tr("The assistant wants to fetch:"),
                         res: a => a("url") },
        web_search:    { ico: "󰖟", di: I18n.tr("The assistant wants to search the web:"),
                         res: a => a("query") },
        notify_user:   { ico: "󰂚", di: I18n.tr("The assistant sends a notification:"),
                         res: a => a("title") },
        use_skill:     { ico: "󰠮", di: I18n.tr("The assistant is reading the skill:"),
                         res: a => a("name") },
        remember:      { ico: "󰍩", di: I18n.tr("The assistant wants to remember:"),
                         res: a => a("note") },
        learn:         { ico: "󱐋", di: I18n.tr("The assistant learns:"),
                         res: a => a("lesson") },
        memory_update: { ico: "󰏫", di: I18n.tr("The assistant corrects a memory:"),
                         res: a => "[#" + (a("id") || "?") + "]  " + a("note") },
        memory_forget: { ico: "󰩹", di: I18n.tr("The assistant drops a memory:"),
                         res: a => "[#" + (a("id") || "?") + "]" },
        todo_write:    { ico: "󰝖", di: I18n.tr("The assistant updates its plan:"),
                         res: a => Array.isArray(a("todos")) ? a("todos").length + " pasos" : "",
                         ver: a => (a("todos") || []).map(t =>
                                (t.status === "completed" ? "󰄲 "
                                 : t.status === "in_progress" ? "󰥔 " : "󰄱 ") + t.content)
                                .join("\n") },
        propose_plan:  { ico: "󰗀", di: I18n.tr("The assistant proposes a plan:"),
                         res: () => "", ver: a => a("plan") },
        ask_user:      { ico: "󰘥", di: I18n.tr("The assistant asks you:"),
                         res: a => a("question") },
        subagent:      { ico: "󰳆", di: I18n.tr("The assistant delegates to a subagent:"),
                         res: a => (a("label") || String(a("task")).slice(0, 60))
                                   + "  ·  " + bubble._subGrant,
                         ver: a => a("task") },
        list_mcp_resources: { ico: "󰐱", di: I18n.tr("The assistant wants to list resources (MCP):"),
                         res: a => a("server") },
        read_mcp_resource:  { ico: "󰐱", di: I18n.tr("The assistant wants to read a resource (MCP):"),
                         res: a => a("server") + "  ·  " + a("uri") },
        // Desarrollo: LSP, AST, depurador y la celda de Python.
        lsp:           { ico: "󰿘", di: I18n.tr("The assistant asks the language server:"),
                         res: a => a("op") + "  ·  " + a("path")
                                   + (a("line") ? ":" + a("line") : "") },
        lsp_rename:    { ico: "󰑕", di: I18n.tr("The assistant wants to rename a symbol:"),
                         res: a => a("path") + ":" + (a("line") || "?")
                                   + "  →  " + a("new_name") },
        ast_search:    { ico: "󱁉", di: I18n.tr("The assistant searches the syntax tree:"),
                         res: a => a("pattern") + "  ·  " + a("path") },
        ast_edit:      { ico: "󱁊", di: I18n.tr("The assistant wants to rewrite structurally:"),
                         res: a => a("path"),
                         ver: a => "- " + a("pattern") + "\n+ " + a("rewrite") },
        python_exec:   { ico: "󰌠", di: I18n.tr("The assistant runs a Python cell:"),
                         res: a => String(a("code")).split("\n")[0].slice(0, 80),
                         ver: a => a("code") },
        debug_start:   { ico: "󰃤", di: I18n.tr("The assistant wants to debug:"),
                         res: a => a("program"),
                         ver: a => (a("breakpoints") || []).join("\n") },
        debug_ctl:     { ico: "󰐊", di: I18n.tr("The assistant steps the debugger:"),
                         res: a => a("action")
                                   + (a("file") ? "  ·  " + a("file") + ":" + a("line") : "") },
        debug_view:    { ico: "󰈈", di: I18n.tr("The assistant inspects the debugger:"),
                         res: a => a("what")
                                   + (a("frame") !== undefined && a("frame") !== ""
                                      ? "  ·  marco " + a("frame") : "") },
        debug_eval:    { ico: "󰊕", di: I18n.tr("The assistant evaluates in the paused frame:"),
                         res: a => a("expression") },
        lsp_fix:       { ico: "󰁨", di: I18n.tr("The assistant applies a quick fix:"),
                         res: a => a("path") + ":" + (a("line") || "?")
                                   + "  ·  #" + (a("index") || 0) },
        lsp_raw:       { ico: "󰘦", di: I18n.tr("The assistant sends a raw LSP request:"),
                         res: a => a("method") + "  ·  " + a("path") },
        // Trabajos en segundo plano.
        job_start:     { ico: "󱜯", di: I18n.tr("The assistant wants to run in the background:"),
                         res: a => (a("pty") ? "[pty] " : "") + a("command"),
                         ver: a => a("command") },
        job_list:      { ico: "󰋙", di: I18n.tr("The assistant lists background jobs"),
                         res: () => "" },
        job_view:      { ico: "󰈈", di: I18n.tr("The assistant checks a job:"),
                         res: a => "#" + (a("id") || "?") },
        job_input:     { ico: "󰌌", di: I18n.tr("The assistant types into a job:"),
                         res: a => "#" + (a("id") || "?") + "  ⌨  "
                                   + (a("eof") ? "(fin de entrada)" : a("text")) },
        job_ctl:       { ico: "󰚌", di: I18n.tr("The assistant wants to stop a job:"),
                         res: a => a("action") + (a("id") ? "  ·  #" + a("id") : "")
                                   + (a("signal") ? "  ·  " + a("signal") : "") },
        // Administración local.
        system_status: { ico: "󰄨", di: I18n.tr("The assistant checks the system"),
                         res: () => "" },
        journal_query: { ico: "󰌱", di: I18n.tr("The assistant reads the journal:"),
                         res: a => [a("unit"), a("priority"), a("since"), a("grep")]
                                   .filter(x => x).join("  ·  ") },
        service_query: { ico: "󰒓", di: I18n.tr("The assistant queries a service:"),
                         res: a => a("name") || a("list") },
        service_ctl:   { ico: "󰑓", di: I18n.tr("The assistant wants to control a service:"),
                         res: a => a("action") + "  ·  " + a("unit")
                                   + (a("user") ? "  (usuario)" : "") },
        process_query: { ico: "󰓅", di: I18n.tr("The assistant lists processes:"),
                         res: a => a("filter") || a("sort") || "cpu" },
        kill_process:  { ico: "󰚌", di: I18n.tr("The assistant wants to signal a process:"),
                         res: a => "PID " + (a("pid") || "?") + "  ·  " + (a("signal") || "TERM") },
        network_query: { ico: "󰛳", di: I18n.tr("The assistant inspects the network:"),
                         res: a => a("kind") + (a("host") ? "  ·  " + a("host") : "") },
        disk_query:    { ico: "󰋊", di: I18n.tr("The assistant checks the disks:"),
                         res: a => a("path") },
        package_query: { ico: "󰏖", di: I18n.tr("The assistant queries packages:"),
                         res: a => a("op") + (a("name") ? "  ·  " + a("name") : "") },
        // Servidores remotos.
        server_status: { ico: "󰒋", di: I18n.tr("The assistant checks a remote server:"),
                         res: a => a("host") },
        server_logs:   { ico: "󰋊", di: I18n.tr("The assistant reads remote logs:"),
                         res: a => a("host") + (a("path") ? "  ·  " + a("path")
                                                : a("unit") ? "  ·  " + a("unit") : "") },
        sftp_ls:       { ico: "󰉖", di: I18n.tr("The assistant lists a remote folder:"),
                         res: a => a("host") + "  ·  " + (a("path") || ".") },
        hosting_query: { ico: "󰌷", di: I18n.tr("The assistant queries the hosting panel:"),
                         res: a => a("host") + "  ·  " + a("panel") + " " + a("op")
                                   + (a("name") ? " " + a("name") : "") },
        ssh_exec:      { ico: "󰣀", di: I18n.tr("The assistant wants to run on a server:"),
                         res: a => a("host") + "  $  " + a("command"),
                         ver: a => a("command") },
        sftp_get:      { ico: "󰇚", di: I18n.tr("The assistant wants to download from a server:"),
                         res: a => a("host") + ":" + a("remote_path")
                                   + "  →  " + a("local_path") },
        sftp_put:      { ico: "󰕒", di: I18n.tr("The assistant wants to upload to a server:"),
                         res: a => a("local_path") + "  →  " + a("host")
                                   + ":" + a("remote_path") }
    })

    // La ficha de esta tarjeta. Las herramientas MCP no están en la tabla —nacen
    // del servidor que las publica—, así que llevan la suya al vuelo, y un nombre
    // desconocido cae en la genérica en vez de dejar la tarjeta muda.
    readonly property var _card:
        _toolCards[toolName] ? _toolCards[toolName]
      : toolName.startsWith("mcp__")
            ? ({ ico: "󰐱", di: I18n.tr("The assistant wants to use (MCP):"),
                 res: () => toolName.split("__").slice(1).join(" · ") })
            : _toolCards.run_command

    function _field(fn, cap) {
        if (!fn) return ""
        const get = (k) => bubble._args[k] === undefined ? "" : bubble._args[k]
        return String(fn(get) || "").trim().slice(0, cap)
    }

    readonly property string toolGlyph: isTool ? _card.ico : ""
    readonly property string toolHeadline: isTool ? _card.di : ""
    readonly property string toolPretty:
        isTool ? (_field(_card.res, 2000) || String(_args.raw || "")) : ""
    // Lo que va a cambiar, previsualizado antes de aprobar: nadie firma un archivo
    // sin verlo.
    readonly property string toolPreview: isTool ? _field(_card.ver, 2000) : ""

    // El Markdown de Qt pinta los bloques ``` sin fondo ni forma de copiarlos, así
    // que el contenido se trocea en [{code, lang, text}…] y cada trozo de código se
    // pinta aparte. Vale también para la burbuja en vivo: una valla sin cerrar
    // cuenta como código hasta el final.
    readonly property var segments: {
        if (!isAssistant) return []
        let all = content
        // En vivo, una fila de tabla a medias se retiene hasta su salto de línea:
        // con la fila cortada a mitad de celda, el parser de Markdown deja de ver
        // la tabla como tabla y la descompone en texto suelto, en cada token. Solo
        // filas de tabla y solo fuera de un cercado abierto —un "|" dentro de ```
        // es una tubería de shell—, porque retener prosa normal haría la escritura
        // a saltos de línea en vez de fluida.
        if (live) {
            const nl = all.lastIndexOf("\n")
            const cola = all.slice(nl + 1)
            const enCodigo = (all.match(/```/g) || []).length % 2 === 1
            if (!enCodigo && cola.startsWith("|"))
                all = nl === -1 ? "" : all.slice(0, nl + 1)
        }
        const out = []
        let rest = all
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

    // 'segments' se recalcula entero en cada token y devuelve un array nuevo. Un
    // Repeater con un array por modelo no compara nada: si la identidad del array
    // cambia, destruye todos sus delegates y los vuelve a crear, o sea una
    // reconstrucción completa por token.
    //
    // Con prosa se nota poco; con una tabla se ve, porque cada reconstrucción tira
    // el TextEdit —y con él el documento ya analizado, con sus columnas medidas— y
    // vuelve a interpretar el Markdown desde cero. Además el alto de la burbuja
    // daría tumbos en cada token, que es lo que hace saltar el desplazamiento.
    //
    // Aquí el modelo se sincroniza en el sitio: mientras la estructura no cambie
    // —mismo número de trozos, mismo tipo, mismo lenguaje— solo se actualiza el
    // texto y el TextEdit sigue vivo. Reconstruir se reserva para cuando aparece un
    // trozo nuevo.
    readonly property ListModel segModel: ListModel {}

    function _sincronizaSegs() {
        const s = bubble.segments
        let igual = segModel.count === s.length
        if (igual)
            for (let i = 0; i < s.length; i++) {
                const v = segModel.get(i)
                if (v.code !== s[i].code || v.lang !== s[i].lang) {
                    igual = false
                    break
                }
            }
        if (!igual) {
            segModel.clear()
            for (let i = 0; i < s.length; i++)
                segModel.append({ code: s[i].code, lang: s[i].lang,
                                  text: s[i].text })
            return
        }
        for (let i = 0; i < s.length; i++)
            if (segModel.get(i).text !== s[i].text)
                segModel.setProperty(i, "text", s[i].text)
    }
    onSegmentsChanged: bubble._sincronizaSegs()

    implicitHeight: isUser ? userCol.implicitHeight
                  : isError ? errBox.height
                  : isTool ? toolBox.height
                  : isInfo ? infoText.implicitHeight
                  : aiRow.implicitHeight

    // Nota del sistema (exportado, compactado…): centrada y apagada.
    ThemedText {
        id: infoText
        visible: bubble.isInfo
        anchors.left: parent.left
        anchors.right: parent.right
        horizontalAlignment: Text.AlignHCenter
        text: bubble.isInfo ? bubble.content : ""
        color: Theme.fgMuted
        font.pixelSize: Theme.typeLabelSmall
        wrapMode: Text.WordWrap
    }

    // La entrada la anima el ListView y no la burbuja: un segundo fundido aquí
    // pelearía con aquel —dos curvas escribiendo la misma opacity— y además se
    // re-ejecutaría cada vez que el ListView recreara el delegate al desplazar, así
    // que los mensajes parpadearían al hacer scroll y no solo al llegar.
    //
    // Y el modelo de segmentos se puebla en diferido: Component.onCompleted de un
    // delegate corre dentro del pase de disposición del ListView, y sincronizar ahí
    // instanciaría los TextEdit y parsearía el Markdown de cada mensaje en pleno
    // layout. Un tick después, fuera del pase, cuesta lo mismo y no bloquea.
    Component.onCompleted: Qt.callLater(bubble._sincronizaSegs)

    // Usuario
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
            // La esquina de arriba a la derecha, cerrada: es el espejo de la
            // del asistente. Las dos apuntan hacia fuera, hacia quien habla, y
            // esa asimetría es lo que hace que la conversación se lea como dos
            // voces y no como una lista de cajas iguales.
            topRightRadius: Theme.shapeXs
            color: SettingsPalette.selectedTint
            border.width: Theme.hairline
            border.color: Theme.withAlpha(Theme.accent, 0.22)

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

        // Pie del mensaje propio: adjuntos que llevaba más Editar y Eliminar. Flow
        // por lo mismo que el del asistente: una fila no se envuelve, y con la
        // etiqueta de un adjunto larga se saldría.
        Flow {
            id: pieUsuario
            Layout.fillWidth: true
            layoutDirection: Qt.RightToLeft
            spacing: Theme.space10
            visible: !bubble.live

            ThemedText {
                visible: bubble.ts !== ""
                text: bubble.ts
                color: Theme.fgMuted
                font.pixelSize: Theme.typeLabelSmall
            }
            ThemedText {
                visible: bubble.attachNote !== ""
                // La etiqueta del adjunto es lo único que puede crecer aquí.
                width: Math.max(0, Math.min(implicitWidth, pieUsuario.width))
                elide: Text.ElideRight
                text: "󰏢 " + bubble.attachNote
                color: Theme.fgMuted
                font.pixelSize: Theme.typeLabelSmall
            }
            Row {
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

    // Asistente
    RowLayout {
        id: aiRow
        visible: bubble.isAssistant
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: bubble.hueco

        // El avatar, con anillo: un disco plano se lee como una mancha, y el aro lo
        // convierte en una pieza separada del fondo del panel, que es translúcido y
        // cambia con el fondo de escritorio.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Theme.space6
            implicitWidth: bubble.angosto ? Theme.dp(22) : Theme.dp(28)
            implicitHeight: implicitWidth
            radius: width / 2
            color: SettingsPalette.accentSoft
            border.width: Theme.hairline
            border.color: Theme.withAlpha(Theme.accent, bubble.live ? 0.55 : 0.28)
            Behavior on border.color { ColorAnimation { duration: Theme.animNormal } }

            ThemedText {
                anchors.centerIn: parent
                text: "󱙺"
                color: Theme.accentText
                font.pixelSize: Theme.sp(13)
            }
            // Mientras escribe, el aro respira: es la única señal de "sigue
            // trabajando" que no ocupa sitio ni mueve lo ya escrito.
            SequentialAnimation on scale {
                running: bubble.live
                loops: Animation.Infinite
                NumberAnimation { to: 1.06; duration: Math.round(Theme.animLoop / 2)
                                  easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: Math.round(Theme.animLoop / 2)
                                  easing.type: Easing.InOutSine }
            }
        }

        // La superficie de la respuesta. Sin ella, con el mensaje del usuario en
        // una píldora teñida y el del asistente como texto suelto sobre un fondo
        // translúcido con escritorio detrás, la respuesta —que es lo que se
        // viene a leer— sería lo único sin sitio propio.
        //
        // La esquina de arriba a la izquierda va más cerrada que las demás:
        // es la que mira al avatar, y esa asimetría es lo que hace que un
        // rectángulo se lea como un bocadillo y no como una caja.
        Rectangle {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            implicitHeight: aiCol.implicitHeight + (bubble.angosto ? Theme.space8 : Theme.space10) * 2
            radius: Theme.shapeLg
            topLeftRadius: Theme.shapeXs
            color: SettingsPalette.settingsCard
            border.width: Theme.hairline
            border.color: SettingsPalette.settingsBorder

            // Mientras escribe, un filo recorre el borde izquierdo en vez de un
            // punto que parpadea: un parpadeo dice "hay algo" y un recorrido dice
            // "está pasando ahora". Va por el borde, fuera del texto, así que no
            // compite con lo que se está leyendo.
            //
            // El carril tenue queda de fondo para que el filo no aparezca de la nada
            // en cada vuelta: se ve el camino que recorre.
            Rectangle {
                id: carril
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: Theme.space6
                width: Theme.dp(2)
                radius: width
                color: Theme.withAlpha(Theme.accent, 0.18)
                opacity: bubble.live ? 1 : 0
                clip: true
                Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

                Rectangle {
                    id: viajero
                    width: parent.width
                    // Un tercio del alto, con un mínimo: en una respuesta corta un
                    // tercio serían unos pocos píxeles y no se vería viajar.
                    height: Math.max(Theme.dp(18), Math.round(carril.height * 0.34))
                    radius: width
                    color: Theme.accent
                    // Se anima un escalar 0→1 y la 'y' sale por vínculo: una
                    // NumberAnimation captura from y to al arrancar y los bucles no
                    // los reevalúan, así que animando 'y' directamente el recorrido
                    // se quedaría congelado en el alto del primer token mientras el
                    // carril real crece.
                    property real t: 0
                    y: Math.round((carril.height + height) * t) - height

                    SequentialAnimation on t {
                        running: bubble.live && carril.height > 0
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0
                            to: 1
                            duration: Theme.animLoop
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

        ColumnLayout {
            id: aiCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: bubble.pad
            anchors.rightMargin: bubble.pad
            anchors.topMargin: bubble.angosto ? Theme.space8 : Theme.space10
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
                    ThemedText {
                        text: "󰟃"
                        color: bubble.showReasoning ? Theme.accentText : Theme.fgMuted
                        font.pixelSize: Theme.sp(12)
                    }
                    ThemedText {
                        text: I18n.tr("Reasoning")
                        color: bubble.showReasoning ? Theme.accentText : Theme.fgMuted
                        font.pixelSize: Theme.typeLabelSmall
                        font.bold: bubble.showReasoning
                    }
                    ThemedText {
                        text: bubble.showReasoning ? "󰅀" : "󰅂"
                        color: Theme.fgMuted
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
                model: bubble.segModel
                delegate: Loader {
                    id: seg
                    // Del modelo vivo, por roles: así cambiar el texto no cambia
                    // 'sourceComponent' y el TextEdit de dentro sobrevive al token
                    // siguiente con su tabla ya medida.
                    required property bool code
                    required property string lang
                    required property string text
                    Layout.fillWidth: true
                    // El Loader pide poco a propósito. Sin esto, el ancho que le
                    // pide a la columna es el implicitWidth de su hijo, y el de un
                    // TextEdit es el que tendría sin ajustar: una ruta larga o una
                    // palabra sin espacios pediría miles de píxeles, la columna se
                    // los daría y el texto se saldría por la derecha. Pidiendo uno,
                    // manda el sitio disponible y el hijo se ata al ancho resuelto.
                    Layout.preferredWidth: 1
                    sourceComponent: code ? codeComp : proseComp

                    Component {
                        id: proseComp
                        TextEdit {
                            // Atado al ancho ya resuelto del Loader: es lo que hace
                            // que el ajuste tenga contra qué ajustar.
                            width: seg.width
                            text: seg.text
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
                            width: seg.width
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
                                    ThemedText {
                                        Layout.fillWidth: true
                                        text: seg.lang !== "" ? seg.lang : "code"
                                        color: Theme.fgMuted
                                        font.pixelSize: Theme.typeLabelSmall
                                        font.bold: true
                                    }
                                    FootAction {
                                        label: codeCopied.running ? I18n.tr("Copied") : I18n.tr("Copy")
                                        onDo: () => {
                                            Quickshell.execDetached(["wl-copy", seg.text])
                                            codeCopied.restart()
                                        }
                                    }
                                    Timer { id: codeCopied; interval: 1500 }
                                }
                                TextEdit {
                                    Layout.fillWidth: true
                                    text: seg.text
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

            // Pie con la metainformación y las acciones, al posarse. Flow y no
            // RowLayout: una fila no se envuelve, así que con el panel estrecho
            // todo junto sumaría más ancho que la tarjeta. Envolviendo, lo que no
            // cabe baja de línea, y la metainformación —lo único que puede crecer—
            // se recorta antes de empujar a nadie.
            Flow {
                id: pieIA
                Layout.fillWidth: true
                visible: !bubble.live
                spacing: Theme.space10
                opacity: aiHov.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                ThemedText {
                    // Nunca negativo: con un ancho negativo el elide no recorta
                    // nada y el texto se pinta entero.
                    width: Math.max(0, Math.min(implicitWidth, pieIA.width))
                    elide: Text.ElideRight
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
    }
    MouseArea {
        id: aiHov
        anchors.fill: aiRow
        visible: aiRow.visible
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // Herramienta: la tarjeta de aprobación
    Rectangle {
        id: toolBox
        visible: bubble.isTool
        anchors.left: parent.left
        anchors.right: parent.right
        height: toolCol.implicitHeight + bubble.pad * 2
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
            anchors.margins: bubble.pad
            spacing: Theme.space8

            // Si el modelo dijo algo antes de proponer, se enseña.
            ThemedText {
                Layout.fillWidth: true
                visible: bubble.content !== ""
                text: bubble.content
                color: Theme.fg
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                ThemedText {
                    text: bubble.toolGlyph
                    color: Theme.accentText
                    font.pixelSize: Theme.iconSize
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: bubble.toolHeadline
                    // Se ajusta: un titular largo no cabe en el panel estrecho, y
                    // sin esto se saldría de la tarjeta en vez de pasar de línea.
                    wrapMode: Text.WordWrap
                    color: Theme.fgDim
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

            // Comando destructivo: el guardarraíl por encima de la política. No se
            // prohíbe —a veces borrar es justo lo que toca— pero se dice qué se ha
            // visto, y esta llamada nunca se auto-aprueba.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space6
                visible: bubble.dangerWhy !== ""
                ThemedText {
                    text: "󰀪"
                    color: Theme.red
                    font.pixelSize: Theme.sp(13)
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: I18n.tr("Careful — %1").arg(bubble.dangerWhy)
                    color: Theme.red
                    font.pixelSize: Theme.typeLabelSmall
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                }
            }

            // El supervisor, con banda propia y separada del aviso destructivo,
            // porque dicen cosas distintas: aquel es una regla local sobre el
            // comando y esto la opinión de un segundo modelo sobre esta llamada.
            // Mientras piensa se dice que está pensando: un supervisor callado no
            // puede parecer conforme.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space6
                visible: bubble.toolStatus === "pending"
                         && (bubble._supWatching || bubble._sup !== null)
                ThemedText {
                    text: bubble._supWatching ? "󰛐" : "󰭎"
                    color: bubble._supColor
                    font.pixelSize: Theme.sp(13)
                    opacity: bubble._supWatching ? 0.6 : 1
                    SequentialAnimation on opacity {
                        running: bubble._supWatching
                        loops: Animation.Infinite
                        NumberAnimation { to: 1; duration: Theme.animSlow }
                        NumberAnimation { to: 0.45; duration: Theme.animSlow }
                    }
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: bubble._supText
                    color: bubble._supColor
                    font.pixelSize: Theme.typeLabelSmall
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                }
            }

            // Un enlace simbólico que sale de la carpeta personal: se dice adónde
            // apunta de verdad. No se prohíbe, porque se perderían rutas legítimas,
            // pero esta llamada no se auto-aprueba nunca.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space6
                visible: AiService.realPathFor(bubble.msgIndex) !== ""
                ThemedText {
                    text: "󰌷"
                    color: Theme.orange
                    font.pixelSize: Theme.sp(12)
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Symlink — really points to: %1")
                        .arg(AiService.realPathFor(bubble.msgIndex))
                    color: Theme.fgDim
                    font.family: Theme.monoFontFamily
                    font.pixelSize: Theme.typeLabelSmall
                    wrapMode: Text.WrapAnywhere
                }
            }

            // write_file: el contenido que se va a escribir, previsualizado.
            QuoteBlock {
                visible: bubble.toolPreview !== ""
                Layout.fillWidth: true
                mono: true
                text: bubble.toolPreview
            }

            // write_file sobre un archivo existente: diff real contra lo que hay
            // en disco, a un clic y antes de aprobar. Con archivo nuevo lo dice
            // y ya.
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

            // No es aprobar una acción sino dar el visto bueno a un rumbo: aprobar
            // saca del solo-lectura y rechazar devuelve la crítica.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                visible: bubble.toolName === "propose_plan" && bubble.toolStatus === "pending"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space8
                    TextField {
                        id: planFeedback
                        property string draft: ""
                        Layout.fillWidth: true
                        label: ""
                        placeholder: I18n.tr("what would you change?")
                        onEdited: (t) => draft = t
                    }
                    TextButton {
                        text: I18n.tr("Revise")
                        onClicked: {
                            AiService.rejectPlan(bubble.msgIndex, planFeedback.draft)
                            planFeedback.draft = ""; planFeedback.clear()
                        }
                    }
                    TextButton {
                        text: I18n.tr("Start")
                        primary: true
                        onClicked: AiService.approvePlan(bubble.msgIndex)
                    }
                }
            }

            // No hay nada que aprobar sino algo que contestar: opciones como chips
            // y, siempre, la puerta del texto libre.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                visible: bubble.toolName === "ask_user" && bubble.toolStatus === "pending"

                Flow {
                    id: opciones
                    Layout.fillWidth: true
                    spacing: Theme.space6
                    Repeater {
                        model: Array.isArray(bubble._args.options) ? bubble._args.options : []
                        delegate: Rectangle {
                            id: optChip
                            required property var modelData
                            // Con tope: sin él la píldora se hace tan ancha como su
                            // texto, y una opción larga se sale de la tarjeta. El
                            // Flow no ayuda, porque envuelve entre hijos pero no
                            // encoge a uno que ya no cabe. Si no cabe, el texto
                            // elide; el valor que se contesta es el entero.
                            readonly property real natural:
                                optText.implicitWidth + Theme.space12 * 2
                            // El tope solo cuando el Flow ya tiene ancho: en el
                            // primer pase de disposición vale 0, y un Math.min
                            // contra 0 deja la píldora en nada y el hueco del texto
                            // en negativo, con lo que el elide no recorta y pinta la
                            // frase entera fuera de la píldora.
                            width: opciones.width > 0
                                   ? Math.min(natural, opciones.width) : natural
                            height: Theme.dp(30)
                            radius: height / 2
                            color: optMa.containsMouse ? SettingsPalette.accentSoft
                                                       : SettingsPalette.settingsControl
                            border.width: Theme.hairline
                            border.color: SettingsPalette.settingsBorder
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            ThemedText {
                                id: optText
                                anchors.centerIn: parent
                                // Nunca negativo, por el mismo motivo.
                                width: Math.max(0, Math.min(implicitWidth,
                                    optChip.width - Theme.space12 * 2))
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                text: String(optChip.modelData)
                                color: optMa.containsMouse ? Theme.accentText : Theme.fg
                                font.pixelSize: Theme.typeLabelMedium
                            }
                            MouseArea {
                                id: optMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: AiService.answerQuestion(bubble.msgIndex,
                                                                    String(optChip.modelData))
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space8
                    TextField {
                        id: freeAnswer
                        property string draft: ""
                        Layout.fillWidth: true
                        label: ""
                        placeholder: I18n.tr("or answer here…")
                        onEdited: (t) => draft = t
                        onAccepted: {
                            AiService.answerQuestion(bubble.msgIndex, draft)
                            draft = ""; clear()
                        }
                    }
                    TextButton {
                        text: I18n.tr("Answer")
                        primary: true
                        onClicked: {
                            AiService.answerQuestion(bubble.msgIndex, freeAnswer.draft)
                            freeAnswer.draft = ""; freeAnswer.clear()
                        }
                    }
                }
            }

            // En curso: ocupa el sitio de los botones, que desaparecen en cuanto
            // algo empieza a correr, y dice lo único que hace falta saber mientras
            // se espera. Los segundos convierten "se ha colgado" en "lleva cuatro
            // segundos".
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space6
                visible: bubble.toolRunning
                ThemedText {
                    text: "󰑮"
                    color: Theme.accentText
                    font.pixelSize: Theme.sp(13)
                    // Late en vez de girar: una rotación continua pide la mirada
                    // todo el rato, y esto pasa dentro de una conversación que se
                    // está leyendo.
                    SequentialAnimation on opacity {
                        running: bubble.toolRunning
                        loops: Animation.Infinite
                        NumberAnimation { to: 1; duration: Theme.animSlow }
                        NumberAnimation { to: 0.45; duration: Theme.animSlow }
                    }
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: bubble._corriendoS < 1
                        ? I18n.tr("Running…")
                        : I18n.tr("Running… %1 s").arg(bubble._corriendoS)
                    color: Theme.fgDim
                    font.pixelSize: Theme.typeLabelSmall
                }
            }

            // Pendiente, las dos decisiones; resuelta, el veredicto y la salida.
            //
            // Flow y no RowLayout: un RowLayout no se envuelve y, al estrecharse el
            // panel, aprieta a sus hijos por debajo de su ancho natural, cortando
            // las etiquetas de los tres botones que hay que poder leer antes de
            // pulsar uno. De derecha a izquierda, para que "Aprobar" siga siendo el
            // de la esquina.
            Flow {
                Layout.fillWidth: true
                spacing: Theme.space8
                layoutDirection: Qt.RightToLeft
                visible: bubble.toolStatus === "pending" && !bubble.toolRunning
                         && bubble.toolName !== "ask_user"
                         && bubble.toolName !== "propose_plan"

                TextButton {
                    text: I18n.tr("Approve")
                    primary: true
                    onClicked: AiService.approveToolByUser(bubble.msgIndex)
                }
                // "Siempre", para esta conversación: solo donde se puede permitir
                // en firme. Lo que ejecuta o escribe no lo ofrece.
                TextButton {
                    visible: AiService.canStandingAllow(bubble.toolName)
                    text: I18n.tr("Always")
                    onClicked: AiService.approveToolAlways(bubble.msgIndex)
                }
                // La ráfaga: un diagnóstico son decenas de comandos de mirar contra
                // la misma máquina. Solo aparece cuando esta llamada es de solo
                // lectura reconocida, y vale para las iguales de este turno.
                TextButton {
                    visible: AiService.canBurstCall(bubble.toolName, bubble.toolArgs)
                             && !AiService.canStandingAllow(bubble.toolName)
                    text: I18n.tr("Allow reads")
                    onClicked: AiService.approveToolBurst(bubble.msgIndex)
                }
                TextButton {
                    text: I18n.tr("Reject")
                    onClicked: AiService.rejectTool(bubble.msgIndex)
                }
            }

            // El veredicto y sus acciones. Flow por lo mismo que los pies: en un
            // panel estrecho, una fila rígida se sale por la derecha.
            Flow {
                Layout.fillWidth: true
                visible: bubble.toolStatus !== "pending" && bubble.toolStatus !== ""
                spacing: Theme.space6
                ThemedText {
                    text: bubble.toolStatus === "rejected" ? "󰜺" : "󰄬"
                    color: bubble.toolStatus === "rejected" ? Theme.red : Theme.green
                    font.pixelSize: Theme.sp(12)
                }
                ThemedText {
                    text: bubble.toolStatus === "rejected"
                        ? I18n.tr("Rejected") : I18n.tr("Executed")
                    color: Theme.fgMuted
                    font.pixelSize: Theme.typeLabelSmall
                }
                FootAction {
                    visible: bubble.toolStatus === "done" && bubble.toolResult !== ""
                    label: bubble.showToolOut ? I18n.tr("Hide output") : I18n.tr("Show output")
                    onDo: () => bubble.showToolOut = !bubble.showToolOut
                }
                // Volver el archivo a como estaba antes de esta edición.
                FootAction {
                    visible: bubble.toolStatus === "done" && bubble.undoPath !== ""
                    label: I18n.tr("Undo")
                    onDo: () => AiService.undoEdit(bubble.msgIndex)
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

    // Error
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

            ThemedText {
                text: "󰀪"
                color: Theme.red
                font.pixelSize: Theme.iconSize
            }
            ThemedText {
                Layout.fillWidth: true
                text: bubble.isError ? bubble.content : ""
                color: Theme.fg
                font.pixelSize: Theme.typeBodySmall
                wrapMode: Text.WordWrap
            }
            TextButton {
                text: I18n.tr("Retry")
                onClicked: AiService.retry()
            }
        }
    }

    // Piezas

    // Acción de pie: texto pequeño que se enciende al pasar. 'onDo' es una función
    // que se ejecuta al pulsar.
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

    // Nota al margen: texto atenuado con filete de acento al costado. La usan el
    // razonamiento desplegado y la salida de una herramienta.
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
