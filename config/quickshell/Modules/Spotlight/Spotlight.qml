import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Components
import qs.Config
import qs.Services
import "Search.js" as Search

// Spotlight: buscar en todo, desde el centro de la pantalla.
//
// ── EN QUÉ SE DIFERENCIA DEL LANZADOR ───────────────────────────────────────
// El lanzador (Panels/AppLauncher.qml) sigue existiendo y sigue en Super+Space:
// es una rejilla de aplicaciones por categorías, para cuando sabes que quieres
// una app y te apetece mirar. Esto es lo otro: escribes y sale lo que sea — una
// app, una cuenta resuelta, un ajuste, un emoji, algo del portapapeles.
//
// Y no cuelga de la barra: va centrado, porque no es "un panel de la barra"
// sino algo que se pone delante de todo mientras lo usas.
//
// ── LO QUE LO HACE ÚTIL ES EL ORDEN ─────────────────────────────────────────
// Toda la inteligencia está en Modules/Spotlight/Search.js, que es JS puro y
// tiene su propia batería (tests/t_busqueda.js): escalera de coincidencia,
// acentos normalizados y frecencia con memoria del cuándo. Aquí solo se pinta.
PanelWindow {
    id: win

    property var modelData
    screen: modelData

    // Solo en el monitor donde se pidió, como el resto de paneles: dos
    // buscadores compitiendo por el teclado es el problema de siempre.
    readonly property bool showsHere: Globals.openedOnMonitor === "" || !win.screen
                                      || win.screen.name === Globals.openedOnMonitor
    readonly property bool shown: Globals.spotlightOpen && win.showsHere

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-spotlight"
    // Teclado en exclusiva: aquí se escribe, y es lo único que importa mientras
    // está abierto.
    WlrLayershell.keyboardFocus: win.shown ? WlrKeyboardFocus.Exclusive
                                           : WlrKeyboardFocus.None

    visible: win.shown || win.progress > 0.001

    // ── Apertura ─────────────────────────────────────────────────────────────
    // Un solo escalar gobierna velo, escala y opacidad, como en Popout: dos
    // animaciones sueltas acaban desincronizándose en cuanto una se interrumpe.
    property real progress: 0
    NumberAnimation {
        id: openAnim
        target: win; property: "progress"; to: 1
        duration: Math.max(1, Theme.animNormal)
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel
    }
    NumberAnimation {
        id: closeAnim
        target: win; property: "progress"; to: 0
        duration: Math.max(1, Math.round(Theme.animNormal * 0.6))
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedAccel
    }
    onShownChanged: {
        if (win.shown) {
            win.reset()
            openAnim.restart()
            focusTimer.start()
        } else {
            closeAnim.restart()
        }
    }

    // El foco se pide con un pulso: al abrir, la superficie aún no lo tiene del
    // compositor y un forceActiveFocus() inmediato se pierde. Mismo patrón que
    // el resto de paneles con buscador.
    FocusPulse {
        id: focusTimer
        target: input
        // Atado a la visibilidad: al cerrar el panel deja de
        // insistir solo, sin tener que acordarse de pararlo.
        active: win.shown
    }

    // ── Estado de la búsqueda ────────────────────────────────────────────────
    property string text: ""
    property int selected: 0

    readonly property var parsed: Search.parseQuery(win.text)
    readonly property string mode: win.parsed.mode
    readonly property string query: win.parsed.text

    // Los candidatos, CACHEADOS. Antes esto se reconstruía dentro del binding
    // de resultados, o sea en cada pulsación de tecla: cuatrocientos objetos
    // nuevos por letra tecleada, y el recolector detrás recogiendo los de la
    // letra anterior. Ahora la lista solo se rehace cuando cambia el MODO (que
    // es lo que decide de dónde salen) o cuando cambia el catálogo de apps.
    //
    // La consulta no entra en esta dependencia a propósito: filtrar y ordenar
    // sí depende de lo que escribes, reunir los candidatos no.
    readonly property var candidates: {
        if (!win.shown && win.progress <= 0.001)
            return []
        // Se leen para que QML las apunte como dependencia y la lista se rehaga
        // sola cuando aparece o desaparece una app.
        const _ = AppCatalog.entries.length
        const __ = SettingsSearchIndex.built
        // El modo 'calc' y 'command' SÍ dependen del texto: no son listas que
        // se filtran, son un resultado que se construye con lo escrito.
        return Sources.gather(win.mode, win.mode === "calc" || win.mode === "command"
                                        ? win.query : "")
    }

    readonly property var results: {
        // La cuenta se resuelve fuera de la caché porque depende del texto: en
        // modo general, teclear "45*1.21" tiene que dar 54,45 sin prefijo.
        const extra = win.mode === "" && win.query !== ""
                      ? Sources.calc(win.query) : []
        // Y los ARCHIVOS por lo mismo: dependen del texto, así que no pueden
        // vivir en la caché por modo. Con "/" van sin tope —quien escribe la
        // barra sabe que busca un archivo, y ahí una lista larga ayuda—; en el
        // modo general con tope, para que su rastro no eche de la lista a los
        // ajustes y las acciones.
        const archivos = win.mode === "file"
                       ? Sources.files(win.query, 0)
                       : (win.mode === "" ? Sources.files(win.query,
                                            Sources.topeArchivosGeneral) : [])
        let pool = win.candidates
        if (extra.length > 0)
            pool = extra.concat(pool)
        if (archivos.length > 0)
            pool = pool.concat(archivos)
        if (pool.length === 0)
            return []
        const ranked = Search.rank(pool, win.query,
                                   id => Frecency.statsFor(id), Date.now(), 40)
        return ranked.map(r => r.item)
    }

    // ── Secciones ────────────────────────────────────────────────────────────
    // El primer resultado va DESTACADO y aparte, y el resto agrupado por tipo.
    // Es lo que hace Spotlight de macOS, y no es adorno: en cuanto los archivos
    // entran sin prefijo, una lista plana mezcla tres o cuatro clases de cosa y
    // deja de poder recorrerse con la vista.
    //
    // 'filas' es la lista que se dibuja: encabezados y resultados intercalados.
    // 'results' sigue siendo la lista PLANA y es la que manda para el teclado y
    // para activar — así la navegación no tiene que saber nada de secciones.
    readonly property var filas: {
        const rs = win.results
        if (rs.length === 0)
            return []
        const out = []
        // El primero, suelto y sin encabezado: es la apuesta del buscador.
        out.push({ fila: "top", item: rs[0], idx: 0 })
        let ultimo = ""
        for (let i = 1; i < rs.length; i++) {
            const t = rs[i].type || ""
            if (t !== ultimo) {
                out.push({ fila: "cabecera", texto: Sources.label(t) })
                ultimo = t
            }
            out.push({ fila: "item", item: rs[i], idx: i })
        }
        return out
    }

    function reset() {
        win.text = ""
        win.selected = 0
        Frecency.load()
        // Al cerrar y volver a abrir, soltar lo del prefijo "/": un recorrido
        // del disco que sigue vivo después de cerrar es trabajo para nadie, y
        // la lista de la vez anterior no es lo que se acaba de pedir.
        // Reconstruye el índice si está rancio. Son 12 ms: se paga en cada
        // apertura y a cambio un archivo creado hace un minuto ya aparece.
        FileSearch.build()
    }

    function move(delta) {
        const n = win.results.length
        if (n === 0)
            return
        // Circular: llegar al final y no poder seguir obliga a recordar dónde
        // estás en una lista que acabas de generar.
        win.selected = (win.selected + delta + n) % n
        list.positionViewAtIndex(win.filaDe(win.selected), ListView.Contain)
    }

    // Dónde está dibujado el resultado número 'i'. Las flechas se mueven por la
    // lista PLANA ('results'), que es la que manda; esto solo traduce a la fila
    // de la vista para poder desplazarla. Así la navegación no sabe nada de
    // secciones y no puede pararse en un encabezado.
    function filaDe(i) {
        const f = win.filas
        for (let k = 0; k < f.length; k++)
            if (f[k].idx === i)
                return k
        return 0
    }

    function activate(index) {
        const it = win.results[index === undefined ? win.selected : index]
        if (!it)
            return
        Frecency.remember(it.id)
        Globals.closeAll()
        // Después de cerrar: si la acción abre una ventana (Ajustes, un
        // terminal), hacerlo con el buscador todavía tomando el teclado en
        // exclusiva le roba el foco a lo que acaba de abrirse.
        Qt.callLater(function () {
            try {
                it.run()
            } catch (e) {
                console.warn("Spotlight: falló la acción de " + it.id + ":", e)
            }
        })
    }

    // Los archivos ya no son una fuente asíncrona: el índice está en memoria y
    // filtrarlo es una pasada de indexOf sobre tres mil cadenas. No hay nada
    // que avisar al teclear — el binding de 'results' llama a Sources.files()
    // y ya está.
    onTextChanged: win.selected = 0

    // ── Velo ─────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.35 * win.progress
    }
    MouseArea {
        anchors.fill: parent
        enabled: win.progress > 0.9
        onClicked: Globals.closeAll()
    }

    // ── La tarjeta ───────────────────────────────────────────────────────────
    Rectangle {
        id: card

        width: Theme.panelWidth(win.screen, 620, 380, 0.9)
        height: Math.min(win.height * 0.7, col.implicitHeight + Theme.space16 * 2)
        anchors.horizontalCenter: parent.horizontalCenter
        // Un punto por encima del centro óptico: centrado exacto, un cuadro de
        // diálogo se ve caído. Es la regla de toda la vida del cine y los
        // carteles, y aquí funciona igual.
        y: Math.round((win.height - height) * 0.36)

        radius: Theme.shapeLg
        color: Theme.popupBg
        border.width: Theme.hairline
        border.color: Theme.panelBorder
        antialiasing: true
        clip: true

        opacity: win.progress
        // Entra creciendo un pelín desde abajo. Muy poco: es un buscador que se
        // usa cien veces al día, y una animación lucida acaba cansando.
        scale: 0.97 + 0.03 * win.progress
        transform: Translate { y: (1 - win.progress) * Theme.dp(10) }

        // Absorbe los clics para que no cierre.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.space16
            spacing: Theme.space12

            // ── Campo ────────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space10

                ThemedText {
                    text: win.mode === "calc" ? "󰃬"
                        : win.mode === "command" ? "󰆍"
                        : win.mode === "emoji" ? "󰞅"
                        : win.mode === "clipboard" ? "󰅍"
                        : win.mode === "file" ? "󰉋"
                                              : "󰍉"
                    color: win.mode !== "" ? Theme.accent : Theme.fgMuted
                    font.pixelSize: Theme.sp(18)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }

                TextInput {
                    id: input
                    Layout.fillWidth: true
                    text: win.text
                    onTextChanged: win.text = text
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(18)
                    selectByMouse: true
                    selectionColor: Theme.withAlpha(Theme.accent, 0.45)
                    focus: true

                    Keys.onDownPressed: win.move(1)
                    Keys.onUpPressed: win.move(-1)
                    Keys.onReturnPressed: win.activate()
                    Keys.onEnterPressed: win.activate()
                    Keys.onEscapePressed: Globals.closeAll()
                    // Tab también baja: es el gesto que espera quien viene de
                    // un navegador, y no colisiona con nada aquí.
                    Keys.onTabPressed: win.move(1)
                    Keys.onBacktabPressed: win.move(-1)

                    ThemedText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        visible: input.text === ""
                        // Corto, como el de macOS. Aquí vivía la lista entera
                        // de los seis prefijos: ochenta y tres caracteres que
                        // ni siquiera cabían —salían cortados por la derecha—,
                        // así que no enseñaban los prefijos, solo ensuciaban el
                        // campo. Un aviso que no se lee entero no avisa.
                        //
                        // La clave va en inglés como todas: mezclar castellano
                        // dentro de una cadena que luego se traduce deja una
                        // entrada que ningún idioma puede traducir entera.
                        text: I18n.tr("Spotlight Search")
                        color: Theme.fgMuted
                        font.pixelSize: Theme.typeBodySmall
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                ThemedText {
                    visible: win.results.length > 0
                    text: win.results.length + (win.results.length === 40 ? "+" : "")
                    color: Theme.fgMuted
                    font.pixelSize: Theme.typeLabelSmall
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.hairline
                color: Theme.withAlpha(Theme.overlay, 0.45)
            }

            // ── Vacío ────────────────────────────────────────────────────────
            ThemedText {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space12
                Layout.bottomMargin: Theme.space12
                visible: win.results.length === 0
                horizontalAlignment: Text.AlignHCenter
                // Los archivos son la única fuente que TARDA, así que es la
                // única donde una lista vacía puede querer decir dos cosas
                // distintas. Decir "no hay nada" mientras se está recorriendo
                // el disco es mentir durante medio segundo, y quien lo lee ya
                // ha empezado a borrar para probar otra cosa.
                text: win.mode === "file" && FileSearch.running
                          ? I18n.tr("Searching…")
                    // Contra la consulta YA limpia del servicio, no contra
                    // win.query: esa lleva la barra del prefijo puesta, así
                    // que compararla con el mínimo acierta por un desfase de
                    // uno que nadie va a recordar la próxima vez.
                    : win.mode === "file" && FileSearch.query.length < FileSearch.minChars
                          ? I18n.tr("Type at least %1 letters.").arg(FileSearch.minChars)
                    : win.text === "" ? I18n.tr("Type to search")
                                      : I18n.tr("Nothing matches “%1”.").arg(win.text)
                color: Theme.fgMuted
                font.pixelSize: Theme.typeBodySmall
                wrapMode: Text.WordWrap
            }

            // ── Resultados ───────────────────────────────────────────────────
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(Theme.dp(420), contentHeight)
                visible: win.results.length > 0
                clip: true
                model: win.filas
                currentIndex: win.filaDe(win.selected)
                spacing: Theme.space2
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                cacheBuffer: Theme.dp(400)

                delegate: Item {
                    id: celda
                    required property var modelData

                    readonly property bool esCabecera: celda.modelData.fila === "cabecera"

                    width: ListView.view.width
                    implicitHeight: celda.esCabecera ? Theme.dp(26) : Theme.dp(46)

                    // El encabezado de sección. En versalitas pequeñas y
                    // apagadas: tiene que poder saltarse con la vista, no
                    // competir con los resultados que rotula.
                    ThemedText {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: Theme.space10
                        anchors.bottomMargin: Theme.space4
                        visible: celda.esCabecera
                        text: celda.modelData.texto ?? ""
                        color: Theme.fgMuted
                        font.pixelSize: Theme.typeLabelSmall
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: Theme.typeLabelTracking
                    }

                Rectangle {
                    id: row
                    visible: !celda.esCabecera
                    anchors.fill: parent

                    readonly property var item: celda.modelData.item ?? ({})
                    readonly property int idx: celda.modelData.idx ?? -1
                    // El primer resultado va suelto y sin encabezado encima: es
                    // la apuesta del buscador, y se marca con un filete de
                    // acento a la izquierda para que se vea que no es una fila
                    // más de una sección.
                    readonly property bool esTop: celda.modelData.fila === "top"

                    radius: Theme.shapeSm
                    readonly property bool current: row.idx === win.selected

                    // Filete de acento a la izquierda del destacado.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.space2
                        width: Theme.dp(3)
                        height: parent.height * 0.55
                        radius: width / 2
                        color: Theme.accent
                        visible: row.esTop
                        antialiasing: true
                    }
                    color: "transparent"

                    // El resaltado de fila del shell, el mismo que las listas
                    // de Ajustes. Aquí se fundía el color a pelo con UN solo
                    // Behavior de 100 ms para la selección Y el hover, que son
                    // dos señales con presupuestos de latencia distintos:
                    //
                    //   · el hover persigue al puntero y puede permitirse una
                    //     entrada suave
                    //   · la SELECCIÓN la mueven las flechas, y con cualquier
                    //     fundido de por medio hay dos filas medio encendidas a
                    //     la vez todo el rato mientras bajas por la lista
                    //
                    // De ahí selectMs: 0 — el resaltado va bajo el dedo y no
                    // detrás. Y por opacidad y no por color, que es lo que
                    // evita el punto turbio a mitad de camino (ver la cabecera
                    // de Components/RowHighlight.qml).
                    RowHighlight {
                        id: realce
                        selected: row.current
                        hovered: rowMa.containsMouse
                        radius: Theme.shapeSm
                        selectMs: 0
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space10
                        anchors.rightMargin: Theme.space10
                        spacing: Theme.space10

                        // Icono de app cuando lo hay; glifo si no. El respaldo
                        // importa: un hueco al principio de la fila se lee como
                        // que algo ha fallado.
                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: Theme.dp(24)
                            implicitHeight: Theme.dp(24)

                            IconImage {
                                id: appIcon
                                anchors.fill: parent
                                visible: status === Image.Ready
                                asynchronous: true
                                source: row.item.icon
                                        ? Quickshell.iconPath(row.item.icon, true) : ""
                            }
                            ThemedText {
                                anchors.centerIn: parent
                                visible: !appIcon.visible
                                text: row.item.glyph ?? "󰘳"
                                color: row.current ? Theme.accent : Theme.fgDim
                                // Un emoji se pinta con la fuente del sistema,
                                // no con la del shell: la Nerd Font los trae en
                                // blanco y negro cuando los trae.
                                font.family: row.item.type === "emoji"
                                             ? undefined : Theme.fontFamily
                                font.pixelSize: Theme.sp(16)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            ThemedText {
                                Layout.fillWidth: true
                                text: row.item.name ?? ""
                                color: Theme.fg
                                font.pixelSize: Theme.fontSize
                                elide: Text.ElideRight
                            }
                            ThemedText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: row.item.subtitle ?? ""
                                color: Theme.fgMuted
                                font.pixelSize: Theme.typeLabelSmall
                                elide: Text.ElideRight
                            }
                        }

                        // De qué fuente viene. SOLO en el destacado: el resto
                        // de filas ya lo dicen con el encabezado de su sección,
                        // y repetirlo en cada una es la misma palabra veinte
                        // veces en la misma columna.
                        Rectangle {
                            visible: row.esTop
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: kind.implicitWidth + Theme.space8
                            implicitHeight: Theme.dp(18)
                            radius: height / 2
                            color: Theme.withAlpha(Theme.overlay, 0.35)
                            ThemedText {
                                id: kind
                                anchors.centerIn: parent
                                text: Sources.label(row.item.type)
                                color: Theme.fgMuted
                                font.pixelSize: Theme.typeLabelSmall
                            }
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Filtrado, como en el resto de listas del shell: al
                        // teclear, las filas cruzan bajo un cursor parado y sin
                        // esto la selección salta a lo que quede encima.
                        onPositionChanged: (m) => {
                            if (hoverGate.moved(rowMa, m))
                                win.selected = row.idx
                        }
                        // La onda de pulsación venía dentro de RowHighlight y
                        // no la disparaba nadie: la fila no acusaba recibo del
                        // clic, solo se abría el resultado.
                        onPressed: (m) => realce.press(m.x, m.y)
                        onClicked: win.activate(row.idx)
                    }
                }
                }
            }
        }
    }

    PointerMoveGate {
        id: hoverGate
        referenceItem: list
    }

    onResultsChanged: hoverGate.reset()
}
