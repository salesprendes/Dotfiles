import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Components
import qs.Config
import qs.Services

// Monitor de sistema como aplicación: ventana XDG real, no un popout.
//
// No sustituye a Panels/SystemMonitor.qml, y esa es la idea: el popout es un
// vistazo que se abre sobre lo que se está haciendo y se cierra, sin historia ni
// pestañas porque no hay tiempo de leerlas; la aplicación es sentarse a mirar,
// vive en su ventana, la gestiona el compositor como a cualquier programa y tiene
// un minuto de historia, porque cuando algo va mal lo que importa no es el número
// de ahora sino cómo llegó ahí.
//
// Cerrada no cuesta nada: el muestreo por segundo, la lista de procesos y el
// histórico están atados a Globals.sysMonAppOpen.
FloatingWindow {
    id: app

    title: I18n.tr("System monitor") + " · Quickshell"
    color: Theme.bg
    visible: Globals.sysMonAppOpen

    // Nunca más grande que la pantalla: una ventana que nace más ancha que el
    // monitor solo se salva porque el compositor la recorta.
    readonly property int _screenW: app.screen ? app.screen.width : 1920
    readonly property int _screenH: app.screen ? app.screen.height : 1080
    implicitWidth: Math.min(Theme.dp(1080), Math.round(app._screenW * 0.85))
    implicitHeight: Math.min(Theme.dp(720), Math.round(app._screenH * 0.80))
    minimumSize: Qt.size(Math.min(Theme.dp(560), app._screenW),
                         Math.min(Theme.dp(400), app._screenH))

    // Reabrir con la ventana ya abierta la cierra. Ajustes sabe además traerse la
    // suya desde otro escritorio, pero eso son treinta líneas de la API Lua de
    // Hyprland y aquí no compensan.
    Connections {
        target: Globals
        function onSysMonAppResummon() { Globals.sysMonAppOpen = false }
    }

    // La batería solo si la hay: una pestaña vacía en un sobremesa es una promesa
    // incumplida.
    property string page: "perf"
    readonly property var pages: {
        const out = [{ key: "perf", glyph: "󰕒", label: I18n.tr("Performance") }]
        if (Battery.present)
            out.push({ key: "batt", glyph: "󰁹", label: I18n.tr("Battery") })
        out.push({ key: "proc", glyph: "󰋙", label: I18n.tr("Processes") })
        return out
    }
    onPagesChanged: {
        // Si desaparece la página en la que se estaba, no dejarla en blanco.
        for (let i = 0; i < app.pages.length; i++)
            if (app.pages[i].key === app.page)
                return
        app.page = "perf"
    }

    // Sub-pestañas de Rendimiento: 'over' enseña todo junto y las demás son la
    // misma vista de detalle parametrizada por métrica. Cambia el dato, no la
    // forma.
    property string metric: "over"
    readonly property bool hasGpu: SysMon.gpuBusy >= 0 || SysMon.gpuTemp > 0
    readonly property var metrics: {
        const out = [
            { key: "over", glyph: "󰕮", label: I18n.tr("Overview") },
            { key: "cpu",  glyph: "󰻠", label: "CPU" }
        ]
        if (app.hasGpu)
            out.push({ key: "gpu", glyph: "󰢮", label: "GPU" })
        out.push({ key: "mem",  glyph: "󰍛", label: I18n.tr("Memory") })
        out.push({ key: "net",  glyph: "󰛳", label: I18n.tr("Network") })
        out.push({ key: "disk", glyph: "󰋊", label: I18n.tr("Disk") })
        return out
    }
    onMetricsChanged: {
        for (let i = 0; i < app.metrics.length; i++)
            if (app.metrics[i].key === app.metric)
                return
        app.metric = "over"
    }

    function fmtKB(kb) {
        if (kb >= 1024)
            return (kb / 1024).toFixed(2) + " MB/s"
        return Math.round(kb) + " KB/s"
    }

    function fmtSecs(sec) {
        if (!sec || sec <= 0)
            return "—"
        const h = Math.floor(sec / 3600)
        const m = Math.floor((sec % 3600) / 60)
        return h > 0 ? h + " h " + m + " min" : m + " min"
    }

    // Todo lo de cada métrica en un sitio: la rejilla del resumen y la vista de
    // detalle leen de aquí, así que una no puede enseñar algo distinto de la otra.
    function metricInfo(k) {
        if (k === "gpu")
            return { title: I18n.tr("GPU usage"),
                     sub: SysMon.gpuTemp > 0 ? Math.round(SysMon.gpuTemp) + "°C" : I18n.tr("No sensor"),
                     value: SysMon.gpuBusy >= 0 ? Math.round(SysMon.gpuBusy) + "%" : "—",
                     series: SysMon.gpuHistory, series2: null,
                     max: 100, color: Theme.magenta }
        if (k === "mem")
            return { title: I18n.tr("Memory"),
                     sub: SysMon.memUsedGB.toFixed(1) + " / " + SysMon.memTotalGB.toFixed(1) + " GB"
                          + (SysMon.swapTotalGB > 0
                             ? "  ·  " + I18n.tr("Swap") + " " + SysMon.swapUsedGB.toFixed(1) + " GB" : ""),
                     value: Math.round(SysMon.memPercent) + "%",
                     series: SysMon.memHistory, series2: null,
                     max: 100, color: Theme.cyan }
        if (k === "net")
            return { title: I18n.tr("Network"),
                     sub: "↓ " + app.fmtKB(SysMon.netDownKB) + "   ↑ " + app.fmtKB(SysMon.netUpKB),
                     value: app.fmtKB(SysMon.netDownKB + SysMon.netUpKB),
                     series: SysMon.netDownHistory, series2: SysMon.netUpHistory,
                     max: 0, color: Theme.green }
        if (k === "disk")
            return { title: I18n.tr("Disk I/O"),
                     sub: "R " + app.fmtKB(SysMon.diskReadKB) + "   W " + app.fmtKB(SysMon.diskWriteKB)
                          + "  ·  " + Math.round(SysMon.diskPercent) + "% "
                          + I18n.tr("of %1 GB").arg(SysMon.diskTotalGB.toFixed(0)),
                     value: app.fmtKB(SysMon.diskReadKB + SysMon.diskWriteKB),
                     series: SysMon.diskIoHistory, series2: null,
                     max: 0, color: Theme.orange }
        return { title: I18n.tr("CPU usage"),
                 sub: (SysMon.cpuTemp > 0 ? Math.round(SysMon.cpuTemp) + "°C  ·  " : "")
                      + I18n.tr("%1 threads").arg(SysMon.cpuThreads),
                 value: Math.round(SysMon.cpu) + "%",
                 series: SysMon.cpuHistory, series2: null,
                 max: 100, color: Theme.accent }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Cabecera
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Theme.space16
            Layout.bottomMargin: Theme.space10
            spacing: Theme.space12

            ThemedText {
                Layout.fillWidth: true
                text: I18n.tr("System monitor")
                color: Theme.fg
                font.pixelSize: Theme.sp(19)
                font.weight: Font.Medium
            }

            IconButton {
                icon: "󰅖"
                diameter: Theme.controlM
                baseColor: "transparent"
                hoverColor: Theme.red
                onClicked: Globals.sysMonAppOpen = false
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Theme.space16
            Layout.rightMargin: Theme.space16
            Layout.bottomMargin: Theme.space16
            spacing: Theme.space16

            // Carril
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: Theme.dp(184)
                // Explícito, y no sobra: en un RowLayout 'fillWidth' vale false por
                // defecto para un ítem cualquiera pero true para un layout, así que
                // este carril se quedaría con todo el ancho y empujaría el contenido
                // fuera de la ventana. El preferredWidth no lo sujeta: es lo que
                // pide, no un tope.
                Layout.fillWidth: false
                spacing: Theme.space2

                Repeater {
                    model: app.pages
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool activa: app.page === modelData.key

                        Layout.fillWidth: true
                        implicitHeight: Theme.dp(44)
                        radius: Theme.pillRadius
                        color: activa ? Theme.withAlpha(Theme.accent, 0.20)
                             : (railMa.containsMouse ? Theme.withAlpha(Theme.fg, 0.06) : "transparent")
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space14
                            anchors.rightMargin: Theme.space12
                            spacing: Theme.space12
                            ThemedText {
                                text: modelData.glyph
                                color: activa ? Theme.accent : Theme.fgDim
                                font.pixelSize: Theme.iconSize
                            }
                            ThemedText {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: activa ? Theme.fg : Theme.fgDim
                                font.pixelSize: Theme.fontSize
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: railMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.page = modelData.key
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // Ficha del equipo al pie: quién eres y desde cuándo está en pie.
                // Sigue a la vista mires la pestaña que mires.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.space6
                    spacing: Theme.space10

                    Rectangle {
                        implicitWidth: Theme.dp(34)
                        implicitHeight: Theme.dp(34)
                        radius: width / 2
                        color: Theme.withAlpha(Theme.accent, 0.18)
                        clip: true

                        // La inicial se queda debajo del retrato en vez de
                        // alternarse con él, así el avatar puede tardar en cargar —o
                        // no existir— sin dejar un hueco vacío.
                        ThemedText {
                            anchors.centerIn: parent
                            text: (SysMon.hostname || "?").charAt(0).toUpperCase()
                            color: Theme.accent
                            font.pixelSize: Theme.sp(15)
                            font.bold: true
                        }
                        Image {
                            anchors.fill: parent
                            source: Settings.avatarPath
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: status === Image.Ready
                            sourceSize.width: Theme.dp(34) * 2
                            sourceSize.height: Theme.dp(34) * 2
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        ThemedText {
                            Layout.fillWidth: true
                            text: SysMon.hostname || "—"
                            color: Theme.fg
                            font.pixelSize: Theme.typeBodySmall
                            elide: Text.ElideRight
                        }
                        ThemedText {
                            Layout.fillWidth: true
                            text: I18n.tr("Uptime %1").arg(SysMon.uptime || "—")
                            color: Theme.fgMuted
                            font.pixelSize: Theme.typeLabelSmall
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Contenido
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.shapeLg
                // Contenedor de M3: la caja donde vive el contenido.
                color: Theme.surfaceContainerLow

                // Rendimiento
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.space16
                    visible: app.page === "perf"
                    spacing: Theme.space14

                    // Sub-pestañas, desplazables en horizontal: en una ventana
                    // estrecha no caben, y cortarlas sin poder llegar a la última es
                    // peor que hacerlas arrastrables.
                    Flickable {
                        id: tabFlick
                        Layout.fillWidth: true
                        implicitHeight: tabRow.implicitHeight
                        contentWidth: tabRow.width
                        contentHeight: height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.HorizontalFlick

                        // Las fichas se reparten el ancho hasta el canto derecho en
                        // vez de amontonarse a la izquierda: son la navegación de
                        // esta página, y una barra que ocupa un tercio de la fila
                        // deja el resto como un vacío que no dice nada. El ancho es
                        // el mayor entre lo que piden y lo que hay:
                        RowLayout {
                            id: tabRow
                            width: Math.max(implicitWidth, tabFlick.width)
                            height: tabFlick.height
                            spacing: Theme.space6

                            Repeater {
                                model: app.metrics
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool activa: app.metric === modelData.key

                                    Layout.fillWidth: true
                                    // El mínimo es su contenido más el aire:
                                    // por debajo de eso el texto se cortaría, y
                                    // una ficha que no se puede leer no sirve
                                    // de navegación.
                                    Layout.minimumWidth: tabIn.implicitWidth + Theme.space12 * 2
                                    implicitHeight: Theme.dp(34)
                                    radius: height / 2
                                    color: activa ? Theme.withAlpha(Theme.accent, 0.22)
                                         : (tabMa.containsMouse ? Theme.withAlpha(Theme.fg, 0.07)
                                                                : Theme.withAlpha(Theme.overlay, 0.30))
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                    RowLayout {
                                        id: tabIn
                                        anchors.centerIn: parent
                                        spacing: Theme.space6
                                        ThemedText {
                                            text: modelData.glyph
                                            color: activa ? Theme.accent : Theme.fgMuted
                                            font.pixelSize: Theme.iconSize - 2
                                        }
                                        ThemedText {
                                            text: modelData.label
                                            color: activa ? Theme.fg : Theme.fgDim
                                            font.pixelSize: Theme.typeBodySmall
                                        }
                                    }

                                    MouseArea {
                                        id: tabMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: app.metric = modelData.key
                                    }
                                }
                            }
                        }
                    }

                    // Cabecera del resumen: título a la izquierda y las tres
                    // cifras que NO son una serie temporal a la derecha. Van
                    // aquí y no en tarjetas porque una gráfica de "374
                    // procesos" no dice nada que el número no diga ya.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: app.metric === "over"
                        spacing: Theme.space18

                        ThemedText {
                            Layout.fillWidth: true
                            text: I18n.tr("System overview")
                            color: Theme.fg
                            font.pixelSize: Theme.sp(17)
                            font.weight: Font.Medium
                        }

                        Repeater {
                            model: [
                                { k: I18n.tr("Uptime"),    v: SysMon.uptime || "—" },
                                { k: I18n.tr("Load avg"),  v: SysMon.loadAvg || "—" },
                                { k: I18n.tr("Processes"),
                                  // Procesos Y tareas: son cosas distintas y el
                                  // monitor se contradecía enseñando solo una.
                                  v: SysMon.taskCount > 0
                                     ? I18n.tr("%1 (%2 threads)").arg(SysMon.procCount).arg(SysMon.taskCount)
                                     : String(SysMon.procCount) }
                            ]
                            delegate: ColumnLayout {
                                required property var modelData
                                spacing: 0
                                ThemedText {
                                    text: modelData.k
                                    color: Theme.fgMuted
                                    font.pixelSize: Theme.typeLabelSmall
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: Theme.typeLabelTracking
                                }
                                ThemedText {
                                    text: modelData.v
                                    color: Theme.fg
                                    font.pixelSize: Theme.typeBodySmall
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }

                    // Resumen: rejilla de dos columnas y el disco a lo ancho.
                    // Dos columnas y no una porque estas medidas se leen
                    // COMPARÁNDOLAS —si sube la CPU, ¿sube también el disco?— y
                    // eso pide tenerlas a la vez delante, no una debajo de otra
                    // a un scroll de distancia.
                    GridLayout {
                        Layout.fillWidth: true
                        // Se ciñe a su contenido y NO llena el alto. Es el mismo
                        // sitio donde ya tropecé con el carril: en un layout,
                        // 'fillHeight' vale true por defecto. Llenando, la
                        // rejilla se quedaba con todo el alto de la ventana y
                        // CENTRABA sus filas — dejando un palmo de vacío entre
                        // la cabecera y la primera tarjeta.
                        Layout.fillHeight: false
                        visible: app.metric === "over"
                        columns: 2
                        columnSpacing: Theme.space12
                        rowSpacing: Theme.space12

                        Repeater {
                            model: app.hasGpu ? ["cpu", "gpu", "mem", "net"]
                                              : ["cpu", "mem", "net"]
                            delegate: GraphCard {
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                info: app.metricInfo(modelData)
                            }
                        }

                        GraphCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            // Sin GPU quedan tres tarjetas y el disco cierra la
                            // fila impar; con GPU son cuatro y el disco ocupa
                            // los dos huecos de abajo.
                            Layout.columnSpan: app.hasGpu ? 2 : 1
                            info: app.metricInfo("disk")
                        }
                    }

                    // El hueco sobrante, al final. Sin esto lo repartiría la
                    // rejilla y volvería a centrarse.
                    Item {
                        Layout.fillHeight: true
                        visible: app.metric === "over"
                    }

                    // Detalle de una métrica: la misma tarjeta, a toda la caja.
                    GraphCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: app.metric !== "over"
                        info: app.metricInfo(app.metric)
                    }
                }

                // Procesos
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.space16
                    visible: app.page === "proc"
                    spacing: Theme.space12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space12

                        ColumnLayout {
                            spacing: 0
                            ThemedText {
                                text: I18n.tr("Processes")
                                color: Theme.fg
                                font.pixelSize: Theme.sp(17)
                                font.weight: Font.Medium
                            }
                            ThemedText {
                                text: I18n.tr("%1 running processes").arg(app.procFiltered.length)
                                color: Theme.fgMuted
                                font.pixelSize: Theme.typeBodySmall
                            }
                        }

                        // Espaciador explícito para empujar el buscador al
                        // canto derecho. El fillWidth del bloque del título
                        // debería bastar, pero con un layout anidado dentro de
                        // otro el reparto no llegaba a estirarlo, y un hueco
                        // declarado no depende de cómo se reparta nada.
                        Item { Layout.fillWidth: true }

                        TextField {
                            Layout.preferredWidth: Theme.dp(260)
                            // TERCERA VEZ que hace falta decirlo en este
                            // archivo: 'fillWidth' vale true por defecto para un
                            // LAYOUT, y TextField es un ColumnLayout. Sin esto
                            // el buscador se comía la fila y dejaba el título
                            // apretado contra el borde izquierdo.
                            Layout.fillWidth: false
                            leftIcon: "󰍉"
                            placeholder: I18n.tr("Search process...")
                            value: app.procSearch
                            onEdited: (t) => app.procSearch = t
                        }
                    }

                    // Cabecera de columnas. Los anchos se declaran UNA vez
                    // (app.colPid y compañía) y los reusa cada fila: con los
                    // números repetidos en dos sitios, tocar uno desalinea la
                    // tabla y no se nota hasta mirarla de cerca.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.space12
                        Layout.rightMargin: Theme.space12
                        spacing: Theme.space12

                        ColHead { headText: "PID"; fixedWidth: app.colPid }
                        // Hueco del glifo, para que NOMBRE caiga sobre su columna.
                        Item { Layout.preferredWidth: Theme.iconSize }
                        ColHead {
                            headText: I18n.tr("Name"); fill: true
                            sortable: true; colKey: "name"
                        }
                        ColHead {
                            headText: "CPU"; fixedWidth: app.colCpu; rightAlign: true
                            sortable: true; colKey: "cpu"
                        }
                        ColHead {
                            headText: I18n.tr("Memory"); fixedWidth: app.colMem; rightAlign: true
                            sortable: true; colKey: "mem"
                        }
                        ColHead { headText: I18n.tr("User"); fixedWidth: app.colUser }
                        Item { Layout.preferredWidth: Theme.dp(22) }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: app.procFiltered
                        boundsBehavior: Flickable.StopAtBounds
                        // Recicla los delegados: con 340 procesos, crear uno por
                        // fila al desplazarse es lo que convierte una lista en
                        // un tirón.
                        reuseItems: true
                        cacheBuffer: Theme.dp(400)

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            width: ListView.view.width
                            implicitHeight: Theme.dp(40)
                            radius: Theme.shapeXs
                            // Bandas alternas: con filas de un solo alto y
                            // cinco columnas, seguir una de punta a punta sin
                            // guía es donde se pierde el ojo.
                            color: filaMa.containsMouse ? Theme.withAlpha(Theme.fg, 0.07)
                                 : (index % 2 === 0 ? "transparent"
                                                    : Theme.withAlpha(Theme.overlay, 0.22))

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.space12
                                anchors.rightMargin: Theme.space12
                                spacing: Theme.space12

                                ThemedText {
                                    Layout.preferredWidth: app.colPid
                                    text: modelData.pid
                                    color: Theme.fgMuted
                                    font.pixelSize: Theme.typeBodySmall
                                }
                                // Glifo por familia de proceso (navegador,
                                // terminal, música, hilo de núcleo…). Ya lo
                                // resolvía SysMon.processIcon para la lista del
                                // popout; al rehacer la tabla se me quedó fuera,
                                // y sin él trescientas filas de texto plano son
                                // un muro donde no se distingue nada.
                                ThemedText {
                                    Layout.preferredWidth: Theme.iconSize
                                    text: SysMon.processIcon(modelData.name)
                                    color: Theme.accent
                                    opacity: 0.9
                                    font.pixelSize: Theme.iconSize - 2
                                }
                                ThemedText {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: Theme.fg
                                    font.pixelSize: Theme.typeBodySmall
                                    elide: Text.ElideRight
                                }
                                ThemedText {
                                    Layout.preferredWidth: app.colCpu
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.cpu.toFixed(1) + "%"
                                    // Se enciende lo que de verdad está
                                    // gastando: con trescientas filas al 0,0 %
                                    // todas del mismo color, la que importa no
                                    // se ve.
                                    color: modelData.cpu >= 5 ? Theme.accent : Theme.fgDim
                                    font.pixelSize: Theme.typeBodySmall
                                }
                                ThemedText {
                                    Layout.preferredWidth: app.colMem
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.memMB >= 1
                                          ? modelData.memMB.toFixed(1) + " MB"
                                          : Math.round(modelData.memKB) + " KB"
                                    color: Theme.fgDim
                                    font.pixelSize: Theme.typeBodySmall
                                }
                                ThemedText {
                                    Layout.preferredWidth: app.colUser
                                    text: modelData.user || "—"
                                    color: Theme.fgMuted
                                    font.pixelSize: Theme.typeBodySmall
                                    elide: Text.ElideRight
                                }
                                IconButton {
                                    icon: "󰅖"
                                    diameter: Theme.dp(22)
                                    iconPixelSize: Theme.iconSize - 4
                                    baseColor: "transparent"
                                    hoverColor: Theme.red
                                    // Solo al pasar por encima: un aspa por fila
                                    // en trescientas filas es una invitación a
                                    // matar algo sin querer.
                                    opacity: filaMa.containsMouse ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                                    onClicked: SysMon.killProcess(modelData.pid)
                                }
                            }

                            // Solo escucha el puntero; NoButton para no comerse
                            // el clic del aspa que tiene encima.
                            MouseArea {
                                id: filaMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }
                    }
                }

                // Batería
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.space16
                    visible: app.page === "batt"
                    spacing: Theme.space12

                    ThemedText {
                        text: I18n.tr("Battery")
                        color: Theme.fg
                        font.pixelSize: Theme.sp(17)
                        font.weight: Font.Medium
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space12

                        StatCard {
                            glyph: Battery.charging ? "󰂄" : "󰁹"
                            title: I18n.tr("Charge")
                            value: Battery.percent + "%"
                            ratio: Battery.percent / 100
                            caption: {
                                const d = Battery.device
                                if (!d)
                                    return ""
                                if (Battery.charging)
                                    return I18n.tr("Full in %1").arg(app.fmtSecs(d.timeToFull))
                                if (Battery.discharging)
                                    return I18n.tr("%1 left").arg(app.fmtSecs(d.timeToEmpty))
                                return I18n.tr("Plugged in")
                            }
                        }

                        StatCard {
                            readonly property var dev: Battery.device
                            visible: dev && dev.healthSupported
                            glyph: "󰗐"
                            title: I18n.tr("Health")
                            value: dev ? Math.round(dev.healthPercentage) + "%" : "—"
                            caption: dev && dev.model ? dev.model : ""
                            ratio: dev ? dev.healthPercentage / 100 : 0
                        }

                        StatCard {
                            readonly property var dev: Battery.device
                            glyph: "󰚥"
                            title: I18n.tr("Rate")
                            // changeRate va en vatios y es lo que de verdad dice
                            // si algo se está comiendo la batería AHORA.
                            value: dev ? Math.abs(dev.changeRate).toFixed(1) + " W" : "—"
                            caption: Battery.charging ? I18n.tr("Charging") : I18n.tr("Draining")
                            ratio: 0
                        }

                        StatCard {
                            readonly property var dev: Battery.device
                            glyph: "󰂁"
                            title: I18n.tr("Capacity")
                            value: dev ? dev.energy.toFixed(1) + " Wh" : "—"
                            caption: dev ? I18n.tr("of %1 Wh").arg(dev.energyCapacity.toFixed(1)) : ""
                            ratio: dev && dev.energyCapacity > 0 ? dev.energy / dev.energyCapacity : 0
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    // Procesos: anchos, filtro y orden
    readonly property int colPid: Theme.dp(64)
    readonly property int colCpu: Theme.dp(62)
    readonly property int colMem: Theme.dp(86)
    readonly property int colUser: Theme.dp(96)

    // Estado propio: el popout de la barra puede estar abierto a la vez y no
    // deben pisarse el orden ni la búsqueda.
    property string procSearch: ""
    property string procSortKey: "cpu"
    property bool procDesc: true

    function sortBy(k) {
        if (app.procSortKey === k) {
            app.procDesc = !app.procDesc
            return
        }
        app.procSortKey = k
        // Al cambiar de columna se empieza por lo que se quiere ver: los que
        // más gastan primero, pero los nombres de la A a la Z.
        app.procDesc = k !== "name"
    }

    readonly property var procFiltered: {
        const q = app.procSearch.trim().toLowerCase()
        const src = SysMon.processes || []
        // La búsqueda mira nombre, PID y usuario: "1234" y "root" son formas
        // legítimas de buscar un proceso, y exigir el nombre obligaría a
        // saberlo antes de encontrarlo.
        const out = q === "" ? src.slice()
                             : src.filter(p => (p.name || "").toLowerCase().indexOf(q) !== -1
                                            || String(p.pid).indexOf(q) !== -1
                                            || (p.user || "").toLowerCase().indexOf(q) !== -1)
        const dir = app.procDesc ? 1 : -1
        if (app.procSortKey === "name")
            out.sort((a, b) => dir * String(b.name).localeCompare(a.name))
        else if (app.procSortKey === "mem")
            out.sort((a, b) => dir * (b.mem - a.mem))
        else
            out.sort((a, b) => dir * (b.cpu - a.cpu))
        return out
    }

    // Cabecera de columna, con orden opcional. Los nombres de propiedad llevan
    // prefijo (headText, colKey) a propósito: 'text' y 'sortKey' chocarían con
    // los del propio Item y con los de la ventana.
    component ColHead: Item {
        property string headText: ""
        property int fixedWidth: 0
        property bool rightAlign: false
        property bool fill: false
        property bool sortable: false
        property string colKey: ""
        readonly property bool activa: sortable && app.procSortKey === colKey

        Layout.fillWidth: fill
        Layout.preferredWidth: fill ? 0 : fixedWidth
        implicitHeight: headRow.implicitHeight

        RowLayout {
            id: headRow
            anchors.fill: parent
            layoutDirection: rightAlign ? Qt.RightToLeft : Qt.LeftToRight
            spacing: Theme.space4

            ThemedText {
                text: headText
                color: activa ? Theme.accent : Theme.fgMuted
                font.pixelSize: Theme.typeLabelSmall
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Theme.typeLabelTracking
            }
            ThemedText {
                visible: activa
                text: app.procDesc ? "󰁅" : "󰁝"
                color: Theme.accent
                font.pixelSize: Theme.typeLabelSmall
            }
            Item { Layout.fillWidth: true }
        }

        MouseArea {
            anchors.fill: parent
            enabled: sortable
            cursorShape: sortable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: app.sortBy(colKey)
        }
    }

    // Tarjeta con gráfica. TODO entra por 'info' (ver app.metricInfo) para que
    // el resumen y el detalle no puedan divergir: cambiar una etiqueta ahí las
    // cambia en los dos sitios, y no hay forma de que digan cosas distintas.
    component GraphCard: Rectangle {
        property var info: ({})

        implicitHeight: Theme.dp(150)
        radius: Theme.shapeMd
        // Un peldaño POR ENCIMA de la caja que las contiene: en M3 la altura
        // se dice subiendo de contenedor, no metiendo una sombra.
        color: Theme.surfaceContainerHigh
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.40)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space14
            spacing: Theme.space6

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    ThemedText {
                        Layout.fillWidth: true
                        text: info.title || ""
                        color: Theme.fg
                        font.pixelSize: Theme.fontSize + 1
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    ThemedText {
                        Layout.fillWidth: true
                        text: info.sub || ""
                        color: Theme.fgMuted
                        font.pixelSize: Theme.typeLabelSmall
                        elide: Text.ElideRight
                    }
                }

                ThemedText {
                    text: info.value || ""
                    color: Theme.fg
                    font.pixelSize: Theme.sp(19)
                    font.weight: Font.DemiBold
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Theme.dp(52)

                // Techo COMPARTIDO por las dos series, o una subida de 20 KB
                // parecería tan alta como una bajada de 2 MB.
                readonly property real techo: {
                    if ((info.max || 0) > 0)
                        return info.max
                    let m = 0
                    for (const arr of [info.series || [], info.series2 || []])
                        for (let i = 0; i < arr.length; i++)
                            if (arr[i] > m) m = arr[i]
                    return m > 0 ? m * 1.15 : 1
                }

                // La segunda serie (la subida) va detrás y con menos peso: la
                // primera es la que se mira.
                Sparkline {
                    anchors.fill: parent
                    visible: (info.series2 || null) !== null
                    values: info.series2 || []
                    maxValue: parent.techo
                    lineColor: Theme.fgMuted
                    fillOpacity: 0.06
                    gridLines: 0
                }
                Sparkline {
                    anchors.fill: parent
                    values: info.series || []
                    maxValue: parent.techo
                    lineColor: info.color || Theme.accent
                }
            }
        }
    }

    // Tarjeta compacta para lo que no necesita historia.
    component StatCard: Rectangle {
        property string title: ""
        property string glyph: ""
        property string value: ""
        property string caption: ""
        property real ratio: 0

        Layout.fillWidth: true
        Layout.preferredWidth: 0
        implicitHeight: scCol.implicitHeight + Theme.space12 * 2
        radius: Theme.shapeMd
        // Un peldaño POR ENCIMA de la caja que las contiene: en M3 la altura
        // se dice subiendo de contenedor, no metiendo una sombra.
        color: Theme.surfaceContainerHigh
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.40)

        ColumnLayout {
            id: scCol
            anchors.fill: parent
            anchors.margins: Theme.space12
            spacing: Theme.space6

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                ThemedText { text: glyph; color: Theme.accent; font.pixelSize: Theme.iconSize }
                ThemedText {
                    Layout.fillWidth: true
                    text: title
                    color: Theme.fgDim
                    font.pixelSize: Theme.typeBodySmall
                    elide: Text.ElideRight
                }
                ThemedText {
                    text: value
                    color: Theme.fg
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                // Se esconde con opacidad, no con 'visible': una tarjeta sin
                // barra medía un elemento menos que sus vecinas y la fila la
                // centraba a otra altura.
                opacity: ratio > 0 ? 1 : 0
                implicitHeight: Theme.dp(6)
                radius: height / 2
                color: Theme.withAlpha(Theme.overlay, 0.35)
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: parent.width * Math.max(0, Math.min(1, ratio))
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
                }
            }

            ThemedText {
                Layout.fillWidth: true
                visible: text !== ""
                text: caption
                color: Theme.fgMuted
                font.pixelSize: Theme.typeLabelSmall
                elide: Text.ElideRight
            }
        }
    }
}
