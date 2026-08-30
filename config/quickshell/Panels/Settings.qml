import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Hyprland
import qs.Components
import qs.Config
import qs.Panels.SettingsPages
import qs.Services

// Ventana de Ajustes: ventana XDG real (FloatingWindow), así que Hyprland la
// gestiona como un programa (mosaico, redimensionar, esquinas del compositor).
// Escribe en el singleton Settings. Cada categoría vive en Panels/SettingsPages/
// y solo se instancia la activa (un Loader).
FloatingWindow {
    id: cfg

    title: I18n.tr("Settings") + " · Quickshell"
    color: settingsBackdrop
    // ── Geometría de referencia ──────────────────────────────────────────────
    // 1100×800 y NUNCA más que la pantalla.
    //
    // Antes eran 1280×600 a pelo, sin tope, y las dos cosas estaban mal:
    //
    //   · Demasiado ancha para lo que cabe. La columna de contenido está
    //     acotada a 760 dp (ver contentCol.inset), así que pedir 1280 de ancho
    //     es reservar sitio que nada puede ocupar: quedaban ~227 px de canalón
    //     vacío a los lados. Y demasiado baja: con las tarjetas apiladas, 600
    //     de alto obliga a desplazarse en casi todas las páginas.
    //   · Sin tope de pantalla. En un portátil de 1024×768, dp(1280) pide 1114
    //     px de ancho sobre 1024 disponibles: la ventana nacía más grande que
    //     el monitor. Con Hyprland en mosaico no se nota porque él la recorta,
    //     pero flotando sí, y en pantallas pequeñas es donde más duele.
    //
    // Los factores (0,85 y 0,80) dejan ver que hay escritorio detrás, que es lo
    // que distingue una ventana de una pantalla completa.
    readonly property int _screenW: cfg.screen ? cfg.screen.width : 1920
    readonly property int _screenH: cfg.screen ? cfg.screen.height : 1080
    implicitWidth: Math.min(Theme.dp(1100), Math.round(cfg._screenW * 0.85))
    implicitHeight: Math.min(Theme.dp(800), Math.round(cfg._screenH * 0.80))
    // El mínimo es pequeño a propósito: Hyprland puede acorralar la ventana en
    // un mosaico, y antes que recortarse la interfaz se compacta por tramos
    // (ver headerCompact / navCompact). Y se acota también contra la pantalla,
    // porque un mínimo mayor que el monitor es un mínimo imposible de cumplir.
    minimumSize: Qt.size(Math.min(Theme.dp(600), cfg._screenW),
                         Math.min(Theme.dp(400), cfg._screenH))

    // Clases de tamaño de ventana de Material 3. Son los mismos cortes que usa
    // M3 para decidir la forma de la navegación, y le dan nombre a lo que
    // antes eran cuatro números sueltos:
    //
    //   compacta (<600)   una sola columna; la navegación se reduce al mínimo
    //   media   (600-839) riel de iconos
    //   expandida (840+)  riel con etiquetas
    //   grande  (1200+)   además, sitio de sobra en la cabecera
    readonly property int sizeClass: width < Theme.dp(600) ? 0
                                   : width < Theme.dp(840) ? 1
                                   : width < Theme.dp(1200) ? 2 : 3
    readonly property bool sizeCompact: sizeClass === 0
    readonly property bool sizeMedium: sizeClass <= 1

    // Cortes propios de la cabecera, escalonados por debajo de las clases:
    // suelta controles por orden de prioridad en vez de desbordar por la
    // derecha — primero el texto accesorio, luego el interruptor "solo
    // modificados", luego Restablecer. El botón de cerrar es SIEMPRE el
    // último que queda. navCompact pasa la barra lateral a riel de iconos.
    readonly property bool headerCompact: width < Theme.dp(1000)
    readonly property bool navCompact: sizeMedium
    readonly property bool headerTight: width < Theme.dp(720)
    readonly property bool headerMicro: width < Theme.dp(640)

    visible: Globals.settingsOpen

    // Tokens de espaciado/tamaño propios de esta ventana; el resto del
    // shell sigue con los suyos.
    readonly property int spaceXs: Theme.dp(4)
    readonly property int spaceSm: Theme.dp(8)
    readonly property int spaceMd: Theme.dp(12)
    readonly property int spaceLg: Theme.dp(16)
    readonly property int radiusMd: Theme.dp(6)
    // Radio de esquina de las tarjetas flotantes (barra lateral y contenido).
    // Fijo: no sigue el ajuste de redondeo de esquinas del shell.
    readonly property int radiusCard: Theme.dp(22)
    // Hueco alrededor y entre las tarjetas; deja ver el fondo de la ventana.
    readonly property int cardGap: Theme.dp(14)
    readonly property int controlHeightSm: Theme.dp(36)
    // Padding interno de la tarjeta de la barra lateral. Lo comparten la
    // columna de pestañas y su barra de desplazamiento, que necesita saberlo
    // para calcular cuánto le falta para librar la esquina redondeada.
    readonly property int navPad: navCompact ? Theme.dp(6) : Theme.dp(10)
    readonly property int sidebarWidth: navCompact ? Theme.dp(72)
        : width < Theme.dp(1080) ? Theme.dp(240) : Theme.dp(264)

    // Paleta compartida con las páginas (ver SettingsPages/SettingsPalette.qml).
    // Fondo de la ventana entre y alrededor de las tarjetas: más oscuro que
    // ellas para que el contraste las separe visualmente del fondo.
    readonly property color settingsBackdrop: Theme.withAlpha(Theme.bg, Theme.isDark ? 0.86 : 0.82)
    readonly property color settingsCard: SettingsPalette.settingsCard
    readonly property color settingsControl: SettingsPalette.settingsControl
    readonly property color settingsHover: SettingsPalette.settingsHover
    readonly property color settingsBorder: SettingsPalette.settingsBorder

    property string cat: "theme"

    // Salto directo desde Spotlight: Globals deja anotados la categoría y el
    // texto a filtrar, y esto los aplica — al construirse (primera apertura) y
    // cada vez que se vuelve a invocar la ventana ya existente.
    function applyPendingJump() {
        if (Globals.settingsPendingCat !== "") {
            cfg.cat = Globals.settingsPendingCat
            Globals.settingsPendingCat = ""
        }
        if (Globals.settingsPendingQuery !== "") {
            SettingsFilter.query = Globals.settingsPendingQuery
            Globals.settingsPendingQuery = ""
        }
    }
    Component.onCompleted: cfg.applyPendingJump()
    Connections {
        target: Globals
        function onSettingsResummon() { cfg.applyPendingJump() }
    }
    // La que pulsas (cat) y la que está montada (shownCat) no son la misma
    // durante la transición: la nav se ilumina al instante, pero el contenido
    // espera a que la página vieja se haya ido.
    property string shownCat: "theme"

    // ── Resaltado de selección de la nav (una sola píldora para TODA la barra) ─
    // La pestaña seleccionada informa aquí de su posición (en el sistema de
    // coordenadas del contenido del Flickable) y una única píldora se DESLIZA
    // hasta ahí, cruzando de un grupo a otro sin desaparecer. navSelAnimate se
    // apaga al abrir para colocarla sin animar (si no, "viajaría" desde 0).
    // Tinte de "estás aquí", en un solo sitio: lo comparten la píldora de la
    // barra y la ficha de cuenta, que es un destino más de la navegación.
    // Estaban en 0.26/0.32 y 0.20/0.24 respectivamente — el mismo significado
    // pintado con dos fuerzas, y ninguna razón para la diferencia.
    readonly property color navSelTint: SettingsPalette.selectedTint
    readonly property color navHovTint: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.13 : 0.16)
    property Item navContent: null
    // La pestaña seleccionada, NO sus coordenadas. Antes cada pestaña escribía
    // aquí su 'y' calculado con mapToItem al cambiar su propio alto o posición;
    // eso es una caché, y toda caché se queda vieja: al cambiar la resolución
    // (que mueve Theme.scale y con él CADA dp) el aviso saltaba con la
    // disposición a medio resolver, guardaba una posición intermedia y nadie
    // volvía a mirarla — el resaltado quedaba clavado a 90 px de su pestaña.
    // Guardando el elemento, la posición se DERIVA, y se recalcula sola ante
    // cualquier cambio de geometría: resolución, tamaño de ventana, escala de
    // interfaz, aparición de la barra desplazable o reflujo de la nav.
    property Item navSelItem: null
    // Suma de 'y' desde el elemento hasta el contenedor. Se recorre a mano en
    // vez de usar mapToItem porque QML apunta como dependencia cada propiedad
    // que se LEE al evaluar un vínculo: al leer 'y' de cada ancestro, este
    // vínculo se reevalúa solo cuando cualquiera de ellos se mueve. mapToItem
    // devuelve un número suelto y no crea dependencia de nada.
    function yWithin(item, root) {
        let acc = 0
        let it = item
        for (let d = 0; d < 24 && it && it !== root; d++) {
            acc += it.y
            it = it.parent
        }
        return acc
    }
    readonly property real navSelY: navSelItem && navContent
        ? yWithin(navSelItem, navContent) : 0
    readonly property real navSelH: navSelItem ? navSelItem.height : controlHeightSm
    // La píldora se DESLIZA solo cuando eliges otra pestaña. Ante un cambio de
    // geometría —resolución, tamaño de ventana, escala— tiene que aparecer ya
    // colocada: animar ahí se vería como si el resaltado se hubiera soltado y
    // fuera persiguiendo a su pestaña. Antes esto se apañaba con un plazo de
    // 60 ms al abrir; ahora la ventana de animación la abre el propio cambio de
    // categoría y se cierra al terminar el recorrido.
    property bool navSelAnimate: false
    Timer {
        id: navSelSettle
        interval: Math.round(Theme.animNormal * 1.9) + 60   // el borde más lento + margen
        onTriggered: cfg.navSelAnimate = false
    }
    readonly property bool navSelShown: cat !== "about"

    // Píldora de HOVER: también única para toda la barra. Antes cada pestaña
    // fundía su propio resaltado y, al pasar rápido, varios parpadeaban a la
    // vez; ahora una sola píldora persigue al cursor deslizándose. Se cuenta
    // cuántas pestañas tienen el ratón encima (al cruzar de una a otra el
    // "salir" y el "entrar" no llegan en orden fijo) y la píldora se ve
    // mientras haya alguna.
    property Item navHovItem: null
    readonly property real navHovY: navHovItem && navContent
        ? yWithin(navHovItem, navContent) : 0
    readonly property real navHovH: navHovItem ? navHovItem.height : controlHeightSm
    // Cuenta con suelo en 0: si una pestaña desaparece con el ratón encima
    // (filtro, reflujo, recarga) su "he salido" no llega nunca, y un contador
    // sin suelo se quedaba en positivo con la píldora de hover encendida sobre
    // una pestaña que ya no está.
    property int  navHovCount: 0
    function navHovEnter(tab) {
        cfg.navHovItem = tab
        cfg.navHovCount = cfg.navHovCount + 1
    }
    function navHovLeave() {
        cfg.navHovCount = Math.max(0, cfg.navHovCount - 1)
    }

    onVisibleChanged: {
        if (visible) {
            pageOut.stop()
            pageIn.stop()
            const already = (shownCat === "theme")
            pageOpacity = 0
            pageOffset = Theme.dp(6)
            SettingsMotion.pageEnter = 0
            swapping = true
            shownCat = "theme"
            cat = "theme"
            // Si no toca recargar nadie nos va a avisar: tiramos ya.
            if (already) pageReady()
            // El filtro no sobrevive al cierre: abrirla y encontrártela filtrada
            // de la última vez es desconcertante (parecen ajustes desaparecidos).
            search.clear()
            SettingsFilter.clear()
            // El campo recibe el foco al abrir, salvo en ventanas tan
            // estrechas que la cabecera ha soltado el buscador.
            if (!headerMicro) search.input.forceActiveFocus()
            // Al abrir, la píldora se coloca sin animar: 'cat' ya se ha puesto
            // en "theme" más arriba, así que se cancela la ventana que ese
            // cambio acaba de abrir.
            navSelSettle.stop()
            navSelAnimate = false
        }
        else if (Globals.settingsOpen) Globals.settingsOpen = false   // cerrada por Hyprland
    }

    // ── Cambio de página ─────────────────────────────────────────────────────
    // La vieja se desvanece subiendo un pelo. Cuando ya no se ve, pedimos la
    // nueva y el Loader la construye aparte: montarla aquí mismo congelaría el
    // hilo justo en el peor momento, y eso es el tirón que se notaba. La
    // entrada la dispara el Loader cuando la página ya existe de verdad.
    property real pageOpacity: 1
    property real pageOffset: 0
    property bool swapping: false      // hay una página en camino

    // Van sin 'from' a propósito: si cortas la transición a medias, se
    // reenganchan desde donde estaban en vez de saltar a cero.
    ParallelAnimation {
        id: pageIn
        // Duraciones derivadas de la velocidad de animación de Ajustes (nunca
        // fijas): a "Sin animación" valen 0 y la página aparece de golpe, que
        // es lo que ha pedido quien apaga las animaciones.
        NumberAnimation {
            target: cfg; property: "pageOpacity"
            to: 1; duration: Math.round(Theme.animSlow * 0.75); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel
        }
        // La página sube y se asienta. Sin rebote: el rebote lo ponían antes
        // estas dos líneas, y ahora lo pone el escalonamiento de las tarjetas
        // (ver abajo). Dos muelles a la vez no se leen como uno más rico, se
        // leen como un temblor.
        NumberAnimation {
            target: cfg; property: "pageOffset"
            to: 0; duration: Theme.animSlow; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel
        }
        // Reloj del escalonamiento de las tarjetas (ver SettingsMotion). Va
        // LINEAL a propósito: la curva la pone cada tarjeta en su smoothstep,
        // y encadenar dos suavizados deja el arranque plano. Dura más que el
        // resto porque tiene que repartir varias entradas dentro.
        NumberAnimation {
            target: SettingsMotion; property: "pageEnter"
            to: 1; duration: Math.round(Theme.animSlow * 1.7)
            easing.type: Easing.Linear
        }
    }

    SequentialAnimation {
        id: pageOut
        ParallelAnimation {
            NumberAnimation {
                target: cfg; property: "pageOpacity"
                to: 0; duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedAccel
            }
            NumberAnimation {
                target: cfg; property: "pageOffset"
                to: -Theme.dp(5); duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedAccel
            }
        }
        ScriptAction {
            script: {
                cfg.swapping = true
                cfg.shownCat = cfg.cat
                flick.contentY = 0
            }
        }
    }

    // Nos llama el Loader cuando la página nueva ya está en pantalla.
    function pageReady() {
        if (!swapping) return
        swapping = false
        pageOpacity = 0
        pageOffset = Theme.dp(6)
        SettingsMotion.pageEnter = 0
        pageIn.restart()
    }

    onCatChanged: {
        // Ventana de animación de la píldora de la nav (ver navSelAnimate).
        cfg.navSelAnimate = true
        navSelSettle.restart()

        if (cat === shownCat) {
            // Has vuelto a la página que aún se estaba yendo: la traemos de
            // vuelta. Si ya hay una en camino, que siga su curso.
            if (pageOut.running && !swapping) {
                pageOut.stop()
                pageIn.restart()
            }
            return
        }
        pageIn.stop()                       // pulsas rápido: corta lo que hubiera
        pageOut.restart()
    }

    Connections {
        target: Globals
        function onSettingsResummon() { cfg.summonOrClose() }
    }

    // Busca el toplevel de Hyprland de ESTA ventana por su título (que
    // conocemos aquí mismo, así no depende del idioma de la interfaz).
    function settingsToplevel() {
        const list = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].title === cfg.title) return list[i]
        return null
    }

    // Reabrir cuando ya está abierta (llamado desde onSettingsResummon, que
    // dispara Globals.toggleSettings() si la ventana ya existe): si está en
    // este workspace se cierra (toggle); si está en otro, se trae al actual
    // y se enfoca en vez de cerrarla. Como el destino es el workspace
    // activo, el "seguir la ventana" no cambia la vista y deja la ventana
    // enfocada. Este Hyprland está en modo Lua, así que la sintaxis clásica
    // de dispatchers NO vale: hay que usar la API Lua.
    function summonOrClose() {
        const tl = settingsToplevel()
        const ws = Hyprland.focusedWorkspace
        const here = tl && ws && tl.workspace && tl.workspace.id === ws.id
        if (!tl || here) {
            Globals.settingsOpen = false
            return
        }
        let addr = String(tl.address)
        if (addr.indexOf("0x") !== 0) addr = "0x" + addr
        if (Hyprland.usingLua) {
            Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + ws.id
                + ', window = "address:' + addr + '" })')
        } else {
            Hyprland.dispatch("movetoworkspace " + ws.id + ",address:" + addr)
            Hyprland.dispatch("focuswindow address:" + addr)
        }
    }

    readonly property string userName: Quickshell.env("USER") || "usuario"

    // Salta a una categoría (pestañas, perfil, resultados de búsqueda).
    function goCat(key) {
        if (key === cat)
            return
        cat = key
    }

    // Glifos nf-md de Nerd Font (redondeados, trazo uniforme), planos y sin
    // contenedor de color.
    readonly property var groups: [
        { label: I18n.tr("Personalization"), items: [
            { key: "theme",     glyph: "󰏘", label: I18n.tr("Theme") },
            { key: "font",      glyph: "󰛖", label: I18n.tr("Typography") },
            // La pestaña Terminal solo aparece si hay kitty/alacritty/foot instalado.
            ...(Terminal.available.length > 0
                ? [{ key: "terminal", glyph: "󰆍", label: I18n.tr("Terminal") }]
                : []),
            { key: "wallpaper", glyph: "󰋩", label: I18n.tr("Wallpaper") }
        ] },
        { label: I18n.tr("Bar and widgets"), items: [
            { key: "bar",   glyph: "󰕰", label: I18n.tr("Widgets") },
            { key: "dock",  glyph: "󰇘", label: I18n.tr("Dock") },
            { key: "clock", glyph: "󰒓", label: I18n.tr("Shell") }
        ] },
        { label: I18n.tr("System"), items: [
            { key: "displays", glyph: "󰍹", label: I18n.tr("Displays") },
            { key: "network",  glyph: "󰖩", label: I18n.tr("Network") },
            { key: "notif",    glyph: "󰂚", label: I18n.tr("Notifications") }
        ] }
    ]
    // Índice plano key → { label, glyph, group }. Se construye UNA vez
    // (se recalcula solo si cambian los grupos: idioma o terminales). Las
    // props de la categoría activa son ya búsquedas O(1), sin bucles anidados.
    readonly property var itemIndex: {
        const idx = ({})
        for (let g = 0; g < groups.length; g++)
            for (let i = 0; i < groups[g].items.length; i++) {
                const it = groups[g].items[i]
                idx[it.key] = { label: it.label, glyph: it.glyph, group: groups[g].label }
            }
        // About va suelta, sin grupo, así que se lo inventamos.
        idx["about"] = { label: I18n.tr("About"), glyph: "󰋽", group: "Quickshell" }
        return idx
    }
    // Va con la página que se ve, no con la que has pulsado: si no, el título
    // cambiaría antes que el contenido.
    readonly property var activeItem: itemIndex[shownCat] || ({ label: "", glyph: "󰒓", group: "" })
    readonly property string catLabel:      activeItem.label
    readonly property string catGroupLabel: activeItem.group

    // ── Secciones de la página actual ────────────────────────────────────────
    // Se leen del árbol REAL de la página montada, no de un índice aparte. Es
    // la diferencia que importa: al filtrar, una tarjeta cuyas filas no casan
    // se esconde, y esta lista se encoge con ella sin que haya que avisarle de
    // nada — porque lee 'visible' de cada tarjeta y QML apunta la dependencia.
    //
    // Un índice paralelo habría que mantenerlo sincronizado a mano, que es
    // justo el problema que ya tiene la referencia de la que viene esta idea:
    // su registro exige apuntar cada archivo nuevo y lo avisa en su cabecera.
    readonly property var pageSections: {
        const it = pageLoader.item
        if (!it)
            return []
        const out = []
        const kids = it.children || []
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i]
            if (k && k.isSettingsCard === true && k.visible && k.title !== "")
                out.push({ title: k.title, card: k })
        }
        return out
    }

    function jumpToSection(i) {
        const s = cfg.pageSections[i]
        if (!s || !s.card)
            return
        const tope = Math.max(0, flick.contentHeight - flick.height)
        jumpAnim.to = Math.max(0, Math.min(tope, s.card.y))
        jumpAnim.restart()
    }

    // Se DESPLAZA, no salta. Un salto instantáneo en una página larga deja sin
    // saber si te has movido dos secciones o siete.
    NumberAnimation {
        id: jumpAnim
        target: flick
        property: "contentY"
        duration: Math.max(1, Theme.animNormal)
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel
    }
    readonly property string catGlyph:      activeItem.glyph

    // Resultados del buscador en OTRAS categorías, agrupados — la que se ve
    // ya se filtra sola (SettingsFilter, dentro de la página cargada); esto
    // cubre lo que esa página no puede mostrar por no ser la activa.
    readonly property var crossResults: SettingsFilter.searching
        ? SettingsSearchIndex.search(SettingsFilter.query, cfg.shownCat) : []
    readonly property var crossGroups: {
        const byCat = ({})
        const order = []
        for (let i = 0; i < crossResults.length; i++) {
            const e = crossResults[i]
            if (!byCat[e.cat]) { byCat[e.cat] = []; order.push(e.cat) }
            byCat[e.cat].push(e)
        }
        return order.map(c => ({ cat: c, info: itemIndex[c] || { label: c, glyph: "" }, items: byCat[c] }))
    }

    // Dos tarjetas flotantes (barra lateral | contenido) sobre el fondo de la
    // ventana, con esquinas redondeadas y un hueco que deja ver el fondo entre
    // y alrededor de ellas. Sin cabecera de ventana propia: el título lo pone
    // Hyprland y el cierre vive en la cabecera del contenido.
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: cfg.cardGap
        spacing: cfg.cardGap

        // ── Cabecera global ──────────────────────────────────────────────────
        // Cruza TODO el ancho de la ventana, por encima de las dos tarjetas:
        // el buscador busca en todas las secciones y cerrar cierra la ventana
        // entera, así que ninguno de los dos pertenece a una tarjeta concreta.
        // Antes el buscador vivía dentro de la barra lateral (parecía filtrar
        // solo la navegación) y el aspa colgaba de la tarjeta de contenido,
        // que empieza pasada la barra: no llegaba al vértice de la ventana.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: cfg.spaceSm
            Layout.rightMargin: cfg.spaceXs
            spacing: cfg.spaceMd

            ThemedText {
                text: I18n.tr("Settings")
                color: Theme.fg
                font.pixelSize: Theme.typeTitleLarge
                font.bold: true
                font.letterSpacing: -Theme.dp(0.3)
                visible: !cfg.headerTight
            }

            Item { Layout.fillWidth: true }

            // Buscador en cabecera de la barra lateral: busca sobre
            // todas las páginas (la activa se filtra en vivo; el resto
            // sale en "Resultados en otras secciones").
            SearchField {
                id: search
                // En la cabecera global sí hay sitio aunque la barra lateral
                // se haya plegado a riel; solo desaparece cuando la ventana es
                // tan estrecha que la cabecera va soltando controles.
                visible: !cfg.headerMicro
                // Ancho propio (no fillWidth): entre los dos huecos elásticos
                // queda centrada en la ventana, como en la referencia. Con
                // fillWidth se repartía el sobrante a tres bandas y su tamaño
                // dependía de cuántas acciones hubiera visibles a la derecha.
                Layout.preferredWidth: Math.min(Theme.dp(380), cfg.width * 0.32)
                Layout.preferredHeight: cfg.controlHeightSm
                Layout.alignment: Qt.AlignVCenter
                placeholder: I18n.tr("Search settings…")
                textPixelSize: Theme.typeBodyLarge
                accentIconOnFocus: true
                // Un solo sentido (campo → filtro). Enlazar también el
                // sentido contrario haría un bucle de bindings.
                onTextChanged: SettingsFilter.query = text
                // Enter: si la página visible se quedó sin coincidencias
                // pero hay resultados en otra sección, salta a la primera.
                onAccepted: {
                    const pageEmpty = pageLoader.item
                        && pageLoader.item.implicitHeight < Theme.dp(8)
                    if (pageEmpty && cfg.crossGroups.length > 0)
                        cfg.goCat(cfg.crossGroups[0].cat)
                }
                onEscapePressed: (e) => {
                    if (search.text !== "") {
                        search.clear()
                        e.accepted = true
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // "Solo modificados": mismo lenguaje que "Activar
            // plantillas" (etiqueta + interruptor deslizante). En
            // estrecho se queda solo el interruptor; en muy estrecho
            // (headerTight) se pliega entero deslizándose bajo el
            // recorte, en vez de empujar a los botones fuera.
            Item {
                id: modOnlyWrap
                readonly property bool shownCtl: !cfg.headerTight
                Layout.preferredWidth: shownCtl ? modOnlyRow.implicitWidth : 0
                implicitHeight: modOnlyRow.implicitHeight
                opacity: shownCtl ? 1 : 0
                visible: opacity > 0.01 || Layout.preferredWidth > 0.5
                clip: true
                Behavior on Layout.preferredWidth {
                    NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel }
                }
                RowLayout {
                    id: modOnlyRow
                    // Anclado a la derecha: al plegarse, la etiqueta
                    // desaparece primero bajo el recorte y el
                    // interruptor es lo último en irse.
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: cfg.spaceXs + Theme.dp(4)
                    ThemedText {
                        visible: !cfg.headerCompact
                        text: I18n.tr("Modified only")
                        color: SettingsFilter.modifiedOnly ? Theme.fg : Theme.fgDim
                        font.pixelSize: Theme.typeLabelLarge
                        font.bold: SettingsFilter.modifiedOnly
                    }
                    Switch {
                        enabled: modOnlyWrap.shownCtl
                        checked: SettingsFilter.modifiedOnly
                        offColor: cfg.settingsControl
                        offBorderColor: cfg.settingsBorder
                        onToggled: SettingsFilter.modifiedOnly = !SettingsFilter.modifiedOnly
                    }
                }
            }

            // Restablecer TODO: sin sentido si no hay nada que
            // restablecer. En estrecho colapsa a solo el icono (botón
            // cuadrado), como el resto de la cabecera.
            // Resaltado en pareja con el botón de cerrar: tinte rojo
            // suave que funde (fondo, borde y texto a la vez), leve
            // crecida al posarse y encogida al pulsar; la flecha de
            // reinicio da una vuelta completa al entrar el puntero.
            Rectangle {
                id: resetBtn
                // En headerMicro se pliega también: por prioridad, el
                // último superviviente de la cabecera es Cerrar.
                readonly property bool shownBtn: Settings.anyModified && !cfg.headerMicro
                visible: opacity > 0.01 || implicitWidth > 0.5
                implicitWidth: !shownBtn ? 0
                             : cfg.headerCompact ? cfg.controlHeightSm
                                                 : resetRow.implicitWidth + cfg.spaceMd * 2
                implicitHeight: cfg.controlHeightSm
                radius: cfg.radiusMd
                clip: true
                opacity: shownBtn ? 1 : 0
                Behavior on implicitWidth {
                    NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel }
                }
                readonly property bool hot: resetMa.containsMouse || activeFocus
                activeFocusOnTab: shownBtn
                Keys.onReturnPressed: Settings.reset()
                Keys.onEnterPressed: Settings.reset()
                Keys.onSpacePressed: Settings.reset()
                // Restablecer CONSERVA el rojo: destruye lo que hayas
                // configurado, y el color es la advertencia. Pero el fondo ya
                // no se recolorea a mano en tres estados: lleva la capa de
                // estado de M3, con la misma intensidad que el resto.
                color: cfg.settingsControl
                border.width: activeFocus ? Theme.focusWidth : Theme.hairline
                border.color: activeFocus ? Theme.focusRing
                            : hot ? Theme.withAlpha(Theme.red, 0.85) : cfg.settingsBorder
                scale: resetMa.pressed ? 0.95 : 1.0
                Behavior on border.color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Theme.red
                    opacity: resetMa.pressed ? Theme.statePressed * 1.6
                           : resetBtn.hot ? Theme.stateHover * 1.6 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                }

                RowLayout {
                    id: resetRow
                    anchors.centerIn: parent
                    spacing: cfg.spaceXs + Theme.dp(2)
                    Text {
                        id: resetGlyph
                        text: "󰜉"; color: Theme.red
                        font.family: Theme.fontFamily; font.pixelSize: Theme.sp(16)
                        Behavior on rotation { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
                    }
                    Text {
                        visible: !cfg.headerCompact
                        text: I18n.tr("Reset")
                        color: resetBtn.hot ? Theme.red : Theme.fgDim
                        font.family: Theme.fontFamily; font.pixelSize: Theme.typeLabelLarge
                        font.bold: true
                        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
                    }
                }
                MouseArea {
                    id: resetMa
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Giro anti-horario: el mismo sentido que "deshacer".
                    onEntered: resetGlyph.rotation -= 360
                    onClicked: Settings.reset()
                }
            }

            // Cerrar: botón de icono de M3. NEUTRO, no rojo.
            //
            // Iba en rojo, a juego con Restablecer, y eso era un error de
            // vocabulario: el rojo promete "esto destruye algo". Restablecer
            // sí borra tu configuración; cerrar una ventana no pierde nada.
            // Pintarlos igual enseñaba a desconfiar del aspa — o, peor, a
            // perderle el miedo al botón que sí es peligroso.
            Rectangle {
                id: closeBtn
                implicitWidth: cfg.controlHeightSm
                implicitHeight: cfg.controlHeightSm
                radius: height / 2
                readonly property bool hot: closeMa.containsMouse || activeFocus
                activeFocusOnTab: true
                Keys.onReturnPressed: Globals.settingsOpen = false
                Keys.onEnterPressed: Globals.settingsOpen = false
                Keys.onSpacePressed: Globals.settingsOpen = false
                color: cfg.settingsControl
                border.width: activeFocus ? Theme.focusWidth : Theme.hairline
                border.color: activeFocus ? Theme.focusRing
                            : hot ? Theme.withAlpha(Theme.fg, 0.45) : cfg.settingsBorder
                scale: closeMa.pressed ? 0.92 : 1.0
                Behavior on border.color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }

                // Capa de estado neutra (ver Theme.stateHover).
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Theme.fg
                    opacity: closeMa.pressed ? Theme.statePressed
                           : closeBtn.hot ? Theme.stateHover : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                }

                ThemedText {
                    anchors.centerIn: parent
                    text: "󰅖"
                    color: closeBtn.hot ? Theme.fg : Theme.fgDim
                    font.pixelSize: Theme.sp(18)
                    rotation: closeBtn.hot ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSpatial; easing.overshoot: 1.6 } }
                    Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
                }
                MouseArea {
                    id: closeMa
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Globals.settingsOpen = false
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: cfg.cardGap

        // ── Barra lateral (tarjeta) ──────────────────────────────────────────
        Rectangle {
            Layout.preferredWidth: cfg.sidebarWidth
            Layout.fillHeight: true
            radius: cfg.radiusCard
            clip: true
            color: cfg.settingsCard
            border.width: Theme.hairline
            border.color: cfg.settingsBorder
            // El cambio de tramo desliza, no salta.
            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: Theme.animNormal; easing.type: Theme.enterEasing }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: cfg.navPad    // padding de la nav
                spacing: Theme.dp(2)             // gap entre pestañas

                    // Tarjeta de perfil (avatar + usuario + equipo): es la
                    // puerta a "Acerca de", que por eso ya no necesita pestaña
                    // abajo.
                    Rectangle {
                        id: profileTab
                        readonly property bool sel: cfg.cat === "about"
                        Layout.fillWidth: true
                        Layout.bottomMargin: cfg.spaceSm
                        implicitHeight: profileRow.implicitHeight + Theme.dp(16)
                        radius: Theme.dp(14)
                        // Tarjeta de cuenta con superficie propia, no un bloque
                        // de acento: el acento dice "estás aquí" en la barra, y
                        // teñir de acento media barra solo por pasar el ratón
                        // hacía que la ficha gritara más que la navegación. Al
                        // seleccionarse sí se tiñe (es una página más) y se
                        // enmarca; el hover va aparte, en capa de estado.
                        color: sel ? cfg.navSelTint
                                   : Theme.withAlpha(Theme.surfaceHi, Theme.isDark ? 0.45 : 0.55)
                        border.width: Theme.hairline
                        border.color: sel ? Theme.withAlpha(Theme.accent, 0.45)
                                          : Theme.outlineVariant
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        // Capa de estado (Material): el hover no cambia el color
                        // de la ficha, le superpone un velo tenue. Así el mismo
                        // gesto se lee igual sobre la ficha teñida y sobre la
                        // ficha en reposo.
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: Theme.withAlpha(Theme.fg, Theme.isDark ? 0.07 : 0.05)
                            opacity: profileMa.containsMouse ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel }
                            }
                        }

                        // Reflejo del canto superior, igual que las tarjetas de
                        // la derecha: barra y contenido hablan el mismo idioma.
                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: Theme.hairline
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: parent.radius
                            anchors.rightMargin: parent.radius
                            height: Theme.hairline
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.5; color: SettingsPalette.cardSheen }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }

                        RowLayout {
                            id: profileRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.dp(8)
                            anchors.rightMargin: Theme.dp(8)
                            spacing: cfg.navCompact ? 0 : Theme.dp(10)

                            // En riel, un hueco elástico a cada lado centra el
                            // avatar (que se queda solo al ocultarse el texto).
                            Item { Layout.fillWidth: cfg.navCompact; visible: cfg.navCompact }

                            // Avatar: inicial del usuario en círculo tonal de
                            // acento, como los avatares de letra de Google
                            // (no hay ~/.face en este equipo).
                            Avatar {
                                Layout.alignment: Qt.AlignVCenter
                                diameter: Theme.dp(40)
                                source: Settings.avatarPath
                                initial: cfg.userName.charAt(0).toUpperCase()
                                initialPixelSize: Theme.sp(18)
                                tint: Theme.accent
                                fontFamily: Theme.fontFamily
                                isDark: Theme.isDark
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: !cfg.navCompact
                                spacing: 0
                                ThemedText {
                                    Layout.fillWidth: true
                                    text: cfg.userName
                                    color: Theme.fg
                                    font.pixelSize: Theme.typeTitleMedium
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                ThemedText {
                                    Layout.fillWidth: true
                                    text: SysMon.hostname !== "" ? SysMon.hostname : SysMon.distroName
                                    color: profileTab.sel ? Theme.fgDim : Theme.fgMuted
                                    font.pixelSize: Theme.typeLabelMedium
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                }
                            }

                            // Galón: la ficha abre una página, como las
                            // pestañas de abajo. Sin él no había nada que lo
                            // dijera y parecía una cabecera decorativa.
                            ThemedText {
                                visible: !cfg.navCompact
                                text: "󰅂"
                                color: profileTab.sel ? Theme.accentText : Theme.fgMuted
                                opacity: profileTab.sel || profileMa.containsMouse ? 1 : 0.4
                                font.pixelSize: Theme.iconSize
                                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            }

                            // Hueco elástico derecho: cierra el centrado del
                            // avatar en riel.
                            Item { Layout.fillWidth: cfg.navCompact; visible: cfg.navCompact }
                        }
                        Ripple {
                            id: profileRipple
                            color: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.18 : 0.15)
                        }

                        MouseArea {
                            id: profileMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: (m) => profileRipple.press(m.x, m.y)
                            onClicked: cfg.goCat("about")
                        }
                    }


                    Flickable {
                        id: navFlick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: navCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        // El sistema de coordenadas donde vive la píldora y al
                        // que las pestañas mapean su posición.
                        Component.onCompleted: cfg.navContent = contentItem
                        // ¿Sobra contenido para lo que cabe? Solo entonces hay
                        // barra (y las pestañas dejan un carril para ella).
                        readonly property bool scrollable: contentHeight > height + 1
                        readonly property real scrollGutter: scrollable ? Theme.dp(8) : 0

                        // Barra deslizable fina, del mismo lenguaje que la de
                        // los desplegables (ver Components/DropdownRow.qml):
                        // solo aparece cuando hace falta.
                        ScrollBar.vertical: ThinScrollBar {
                            policy: navFlick.scrollable ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                            // Separada del canto y, abajo, retranqueada JUSTO
                            // lo que le falta para librar el redondeo de la
                            // esquina de la tarjeta: en los extremos del
                            // recorrido el tirador se metía en la curva, donde
                            // ya no hay superficie, y parecía colgar fuera.
                            // Sale de la resta (radio − padding de la nav), no
                            // de un número a ojo. Arriba no hace falta tanto:
                            // ahí no hay esquina, está la ficha de cuenta.
                            rightPadding: Theme.dp(3)
                            topPadding: Theme.dp(2)
                            bottomPadding: Math.max(Theme.dp(2), cfg.radiusCard - cfg.navPad)
                        }

                        // Píldora ÚNICA de selección (detrás de las pestañas):
                        // se desliza a la posición absoluta de la seleccionada,
                        // de un grupo a otro sin cortes. Declarada antes que
                        // navCol para quedar por debajo.
                        //
                        // No se anima mientras no se ve. Al pasar por la ficha
                        // de cuenta la píldora se apaga, y si el trayecto
                        // siguiera corriendo por debajo, al volver a una
                        // categoría reaparecería a medio vuelo. Debe nacer ya
                        // puesta en su pestaña.
                        ElasticPill {
                            id: navSelPill
                            targetY: cfg.navSelY
                            targetH: cfg.navSelH
                            animate: cfg.navSelAnimate && cfg.navSelShown
                            opacity: cfg.navSelShown ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                        }

                        // Píldora de HOVER (más tenue que la selección): sigue
                        // al cursor deslizándose de pestaña en pestaña, con el
                        // mismo elástico algo más rápido — tiene que ir con el
                        // cursor. Cuando no se ve, la posición salta sin
                        // animar: al reaparecer debe nacer bajo el cursor, no
                        // "viajar" desde donde se quedó la última vez.
                        ElasticPill {
                            id: navHovPill
                            color: cfg.navHovTint
                            targetY: cfg.navHovY
                            targetH: cfg.navHovH
                            animate: navHovPill.opacity > 0.01
                            leadFactor: 0.5
                            trailFactor: 1.5
                            opacity: cfg.navHovCount > 0 ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
                        }

                        ColumnLayout {
                            id: navCol
                            // Deja un carril para la barra cuando la hay, para
                            // que no se solape con las pestañas.
                            width: navFlick.width - navFlick.scrollGutter
                            spacing: Theme.dp(2)
                            Repeater {
                                model: cfg.groups
                                delegate: NavSection {
                                    required property var modelData
                                    items: modelData.items
                                }
                            }
                        }
                    }

                }
            }

            // Contenido: la otra tarjeta flotante. El hueco de la fila
            // (cardGap) hace de separador, así que ya no hace falta filete.
            // Rectangle (no Item) para pintar el fondo de tarjeta y redondear;
            // clip recorta la marca de agua y la página a las esquinas.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: cfg.radiusCard
                clip: true
                color: cfg.settingsCard
                border.width: Theme.hairline
                border.color: cfg.settingsBorder

                // Luz que entra por el canto superior de la tarjeta: un halo
                // radial muy tenue del color de acento, centrado arriba y
                // apagándose hacia abajo. Es lo que hace que la tarjeta se lea
                // como una superficie iluminada y no como un rectángulo de
                // color plano — y es el único sitio de la ventana donde el
                // acento aparece como LUZ en vez de como tinta.
                //
                // Va en Canvas y no en un Gradient de Rectangle porque QML
                // solo sabe hacer degradados lineales de forma declarativa;
                // el contexto 2D sí tiene createRadialGradient. Se repinta
                // solo cuando cambia el tamaño o el acento, no por fotograma.
                Canvas {
                    id: bloom
                    anchors.fill: parent
                    // El acento se lee aquí (y no dentro de onPaint) para que
                    // el cambio de tema dispare el repintado.
                    property color tint: Theme.accent
                    onTintChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        if (width <= 0 || height <= 0)
                            return
                        const cx = width * 0.5
                        const cy = -height * 0.04
                        const r = width * 0.62
                        const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
                        const peak = Theme.isDark ? 0.13 : 0.10
                        g.addColorStop(0.0, Qt.rgba(tint.r, tint.g, tint.b, peak))
                        g.addColorStop(0.5, Qt.rgba(tint.r, tint.g, tint.b, peak * 0.30))
                        g.addColorStop(1.0, Qt.rgba(tint.r, tint.g, tint.b, 0))
                        ctx.fillStyle = g
                        ctx.fillRect(0, 0, width, height)
                    }
                }

                // Firma de la ventana: el glifo de la categoría activa, enorme
                // y casi invisible, sangrando por la esquina superior derecha.
                // Es gratis (ya tenemos cfg.catGlyph) y cambia con cada página:
                // no decora, identifica dónde estás sin competir con el texto.
                // Fuera en "Acerca de": esa página ya trae su propia tarjeta
                // ilustrada (avatar + logo) y la marca de agua le hacía sombra.
                ThemedText {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -Theme.dp(28)
                    anchors.rightMargin: -Theme.dp(14)
                    visible: cfg.shownCat !== "about"
                    text: cfg.catGlyph
                    color: Theme.accent
                    opacity: cfg.pageOpacity * (Theme.isDark ? 0.07 : 0.05)
                    font.pixelSize: Theme.sp(150)
                    // Paralaje: al desplazar la página, la marca de agua se va
                    // más despacio que el contenido. Es lo que le da a la
                    // tarjeta una segunda profundidad — la marca deja de ser un
                    // dibujo pegado al cristal y pasa a estar detrás. Acotada:
                    // pasado un punto ya se ha ido y seguir moviéndola solo
                    // gastaría repintados.
                    transform: Translate {
                        y: -Math.min(Math.max(0, flick.contentY) * 0.14, Theme.dp(56))
                    }
                }

                ColumnLayout {
                id: contentCol
                anchors.fill: parent
                anchors.margins: cfg.headerCompact ? cfg.spaceMd : cfg.spaceLg
                anchors.leftMargin: cfg.headerCompact ? cfg.spaceSm : cfg.spaceMd
                // Margen derecho corto a propósito: es el carril por el que
                // baja la barra de desplazamiento de la página, y una barra de
                // página va pegada al canto. La columna de texto no se descentra
                // por esto — va centrada por 'inset', que absorbe la diferencia.
                anchors.rightMargin: cfg.spaceSm
                spacing: cfg.spaceSm

                // Medida de la columna de contenido. Un ajuste es una línea de
                // texto seguida de su control: pasado cierto ancho, estirarla
                // no añade nada y sí separa la etiqueta de lo que gobierna.
                // Con la ventana maximizada en un monitor de 2560 px la fila
                // llegaba a medir metro y medio de vacío.
                //
                // El tope solo entra en juego en pantalla grande: al tamaño de
                // referencia (1280 px) la tarjeta ya mide menos que esto, así
                // que la vista normal no cambia — lo que cambia es que
                // maximizar deja de estropear la lectura.
                readonly property int inset:
                    Math.max(0, Math.round((width - Theme.dp(760)) / 2))

                // Cabecera de la página: título a la izquierda y acciones
                // globales ("solo modificados", Restablecer, cerrar) a la
                // derecha. Cuanto más estrecho el panel, más margen derecho:
                // así el grupo de acciones se rebaja hacia la izquierda en vez
                // de quedarse pegado al borde.
                RowLayout {
                    Layout.fillWidth: true
                    // Mismo eje que las tarjetas de ajustes de debajo: el
                    // título y la primera fila de la primera tarjeta arrancan
                    // de la misma vertical.
                    Layout.leftMargin: contentCol.inset
                    Layout.rightMargin: contentCol.inset
                    // En compacto la cabecera respiraba menos justo cuando
                    // menos sitio hay alrededor: un punto MÁS de aire, no menos
                    // — es lo que separa "compacto" de "apretado".
                    Layout.topMargin: cfg.headerCompact ? cfg.spaceXs : 0
                    Layout.bottomMargin: cfg.spaceSm
                    spacing: cfg.headerCompact ? cfg.spaceXs : cfg.spaceSm

                    // Título de la página. Va con la que SE VE (shownCat), no
                    // con la pulsada: si no, cambiaría antes que el contenido.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space2
                        opacity: cfg.pageOpacity
                        // Baja mientras las tarjetas suben. El movimiento
                        // contrario hace que la página se lea como algo que se
                        // ABRE por el medio; con todo yendo en el mismo sentido
                        // solo se ve un bloque deslizándose.
                        transform: Translate {
                            y: -Math.round((1 - SettingsMotion.reveal(0)) * Theme.dp(8))
                        }

                        // Miga del grupo ("Personalización", "Sistema"). SOLO
                        // cuando la barra se ha plegado a riel de iconos: con
                        // las etiquetas de la nav a la vista repetirlo era
                        // ruido (por eso se quitó el antetítulo), pero el riel
                        // las esconde — y entonces la miga es la única pista
                        // de en qué grupo estás.
                        ThemedText {
                            visible: cfg.navCompact && cfg.catGroupLabel !== ""
                            text: cfg.catGroupLabel
                            color: Theme.fgMuted
                            font.pixelSize: Theme.typeLabelMedium
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space10

                            // El glifo de la sección, plano y de acento, como
                            // los de la nav: ancla la identidad de la página
                            // sin contenedor. La marca de agua ya lo insinúa
                            // arriba a la derecha, pero casi invisible y
                            // sangrada fuera — esto es lo que se LEE.
                            //
                            // Crece con el reloj de entrada de la página: nace
                            // pequeño y se asienta con las tarjetas, sin
                            // animación propia.
                            ThemedText {
                                text: cfg.catGlyph
                                color: Theme.accentText
                                font.pixelSize: cfg.headerCompact ? Theme.sp(22) : Theme.sp(26)
                                scale: 0.6 + 0.4 * SettingsMotion.reveal(0)
                            }
                            // Un paso más grande que antes (headline medium):
                            // el título es la única pieza de texto grande de la
                            // página y se quedaba corto frente a las tarjetas.
                            // En compacto baja un escalón para no comerse el
                            // ancho.
                            ThemedText {
                                Layout.fillWidth: true
                                text: cfg.catLabel
                                color: Theme.fg
                                font.pixelSize: cfg.headerCompact
                                    ? Theme.typeHeadlineSmall : Theme.typeHeadlineMedium
                                font.weight: Font.Medium
                                font.letterSpacing: -Theme.dp(0.4)
                                elide: Text.ElideRight
                            }
                        }
                    }

                }

                // Resultados del buscador en OTRAS categorías (ver
                // cfg.crossGroups, declarado junto a itemIndex/activeItem
                // más arriba). Aparece/desaparece con barrido + fundido, no
                // de golpe (ver Components/ExpandableDetail.qml).
                ExpandableDetail {
                    Layout.leftMargin: contentCol.inset
                    Layout.rightMargin: contentCol.inset
                    open: cfg.crossGroups.length > 0
                    sourceComponent: crossResultsComp
                }

                Component {
                    id: crossResultsComp
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: crossCol.implicitHeight + cfg.spaceMd * 2
                        radius: cfg.radiusMd
                        color: cfg.settingsCard
                        border.width: Theme.hairline
                        border.color: cfg.settingsBorder

                        ColumnLayout {
                            id: crossCol
                            anchors.fill: parent
                            anchors.margins: cfg.spaceMd
                            spacing: cfg.spaceXs

                            ThemedText {
                                text: I18n.tr("Results in other sections")
                                color: Theme.fgMuted
                                font.pixelSize: Theme.typeLabelSmall
                                font.bold: true
                                font.capitalization: Font.AllUppercase
                                font.letterSpacing: Theme.typeLabelTracking
                            }

                            Repeater {
                                model: cfg.crossGroups
                                delegate: ColumnLayout {
                                    id: crossGroup
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: cfg.spaceXs

                                    Repeater {
                                        model: crossGroup.modelData.items
                                        delegate: Rectangle {
                                            id: resultRow
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: rowLay.implicitHeight + cfg.spaceSm * 2
                                            radius: cfg.radiusMd - Theme.space2
                                            color: resultMa.containsMouse ? cfg.settingsHover : "transparent"
                                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                            RowLayout {
                                                id: rowLay
                                                anchors.fill: parent
                                                anchors.margins: cfg.spaceSm
                                                spacing: cfg.spaceSm
                                                // Glifo plano de la categoría
                                                // destino, igual que en la nav:
                                                // se ve a dónde te lleva el
                                                // resultado antes de leerlo.
                                                ThemedText {
                                                    Layout.preferredWidth: Theme.dp(22)
                                                    horizontalAlignment: Text.AlignHCenter
                                                    text: crossGroup.modelData.info.glyph
                                                    color: Theme.fgDim
                                                    font.pixelSize: Theme.sp(15)
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 0
                                                    ThemedText {
                                                        Layout.fillWidth: true
                                                        text: resultRow.modelData.label
                                                        color: Theme.fg
                                                        elide: Text.ElideRight
                                                    }
                                                    ThemedText {
                                                        Layout.fillWidth: true
                                                        text: crossGroup.modelData.info.label
                                                        color: Theme.fgMuted
                                                        font.pixelSize: Theme.fontSize - 4
                                                    }
                                                }
                                                ThemedText {
                                                    text: "󰁔"
                                                    color: Theme.fgMuted
                                                    font.pixelSize: Theme.iconSize - 2
                                                }
                                            }
                                            MouseArea {
                                                id: resultMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: cfg.goCat(resultRow.modelData.cat)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Saltar a una sección ─────────────────────────────────
                // Las páginas largas —Tema son ocho tarjetas— solo se recorrían
                // a rueda, y desde arriba no había forma de saber qué hay
                // abajo. Esta tira hace las dos cosas: dice de qué va la página
                // de un vistazo y lleva a cada sitio.
                //
                // Va bajo la cabecera y no en una columna propia a la izquierda
                // (que es donde la pone la referencia) por una razón de sitio:
                // con la barra lateral y la columna de lectura acotada a 760 dp
                // no queda ancho para un tercer carril sin robárselo al texto,
                // que es lo que menos conviene estrechar. En horizontal no
                // cuesta ancho a nadie.
                //
                // Desde tres secciones: con dos, la lista es más trabajo de
                // leer que bajar la rueda.
                Item {
                    id: jumpBar
                    Layout.fillWidth: true
                    Layout.leftMargin: contentCol.inset
                    Layout.rightMargin: contentCol.inset
                    Layout.bottomMargin: visible ? cfg.spaceXs : 0
                    visible: cfg.pageSections.length >= 3
                    implicitHeight: visible ? jumpRow.implicitHeight : 0
                    opacity: cfg.pageOpacity

                    Flickable {
                        anchors.fill: parent
                        contentWidth: jumpRow.implicitWidth
                        contentHeight: height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.HorizontalFlick

                        Row {
                            id: jumpRow
                            spacing: cfg.spaceXs

                            Repeater {
                                model: cfg.pageSections
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    implicitWidth: chipText.implicitWidth + cfg.spaceMd * 2
                                    implicitHeight: Theme.dp(26)
                                    radius: height / 2
                                    color: chipMa.containsMouse ? SettingsPalette.settingsHover
                                                                : SettingsPalette.settingsControl
                                    border.width: Theme.hairline
                                    border.color: SettingsPalette.settingsBorder
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                    ThemedText {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: modelData.title
                                        color: Theme.fgDim
                                        font.pixelSize: Theme.typeLabelMedium
                                    }

                                    MouseArea {
                                        id: chipMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: cfg.jumpToSection(index)
                                    }
                                }
                            }
                        }
                    }
                }

                Flickable {
                    id: flick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: (pageLoader.item ? pageLoader.item.implicitHeight : 0) + cfg.spaceSm * 2
                    boundsBehavior: Flickable.StopAtBounds

                    // Barra de desplazamiento del contenido. La barra lateral
                    // tenía la suya y el contenido —que es lo que de verdad se
                    // desplaza— no tenía ninguna: en una página larga no había
                    // forma de saber cuánto quedaba.
                    //
                    // Va como capa SOBRE el contenido y solo mientras se usa,
                    // que es como la pinta ChromeOS: una barra permanente le
                    // robaría un carril a la columna de lectura, que ya está
                    // acotada a propósito (ver contentCol.inset).
                    ScrollBar.vertical: ThinScrollBar {
                        policy: flick.contentHeight > flick.height + 1
                            ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        // A ras del canto derecho: esta es la barra que baja
                        // TODA la página, y ese es el sitio donde se busca sin
                        // pensar. Solo se ve mientras se usa (restOpacity 0):
                        // permanente robaría un carril a la columna de lectura.
                        rightPadding: 0
                        // Vertical sí: abajo está la esquina redondeada de la
                        // tarjeta de contenido (misma cuenta que en la nav).
                        topPadding: Theme.dp(2)
                        bottomPadding: Math.max(Theme.dp(2), cfg.radiusCard - cfg.spaceSm)
                        restOpacity: 0
                    }

                    // Solo se instancia la página ACTIVA. Así los desplegables
                    // pesados (p. ej. options: Fonts.list.map(...)) se evalúan
                    // únicamente al entrar en su categoría.
                    Loader {
                        id: pageLoader
                        // Columna centrada de medida acotada (ver
                        // contentCol.inset). Nada de anclarse a los dos
                        // bordes: en pantalla ancha las filas se estiraban
                        // hasta romper la relación etiqueta ↔ control.
                        width: Math.max(Theme.dp(200), flick.width - contentCol.inset * 2)
                        x: Math.round((flick.width - width) / 2)
                        anchors.top: parent.top
                        anchors.topMargin: cfg.spaceSm
                        // Sin esto, montar la página congela el hilo justo cuando
                        // está corriendo la animación y se nota el tirón.
                        asynchronous: true
                        opacity: cfg.pageOpacity
                        transform: Translate { y: cfg.pageOffset }
                        // Ya está montada (o ha petado): que entre.
                        onStatusChanged: if (status === Loader.Ready || status === Loader.Error) cfg.pageReady()
                        source: {
                            switch (cfg.shownCat) {
                            case "font":      return "SettingsPages/FontPage.qml"
                            case "terminal":  return "SettingsPages/TerminalPage.qml"
                            case "wallpaper": return "SettingsPages/WallpaperPage.qml"
                            case "bar":       return "SettingsPages/BarPage.qml"
                            case "dock":      return "SettingsPages/DockPage.qml"
                            case "clock":     return "SettingsPages/ShellPage.qml"
                            case "displays":  return "SettingsPages/DisplaysPage.qml"
                            case "network":   return "SettingsPages/NetworkPage.qml"
                            case "notif":     return "SettingsPages/NotifPage.qml"
                            case "about":     return "SettingsPages/AboutPage.qml"
                            default:          return "SettingsPages/ThemePage.qml"
                            }
                        }
                    }

                    // El filtro ha escondido toda la página. Se ancla al ancho
                    // del Flickable (no a su contentItem, que es tan alto como
                    // la página y descolocaba el centrado).
                    ThemedText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: Theme.dp(64)
                        horizontalAlignment: Text.AlignHCenter
                        visible: SettingsFilter.active && pageLoader.status === Loader.Ready
                                 && pageLoader.item && pageLoader.item.implicitHeight < Theme.dp(8)
                        text: SettingsFilter.modifiedOnly && !SettingsFilter.searching
                            ? I18n.tr("Nothing modified on this page")
                            : I18n.tr("No settings match your search")
                        color: Theme.fgMuted
                        font.pixelSize: Theme.typeBodyMedium
                    }
                }
                }   // fin ColumnLayout interna (título + Flickable)

                // Filete de desplazamiento bajo la cabecera. Aparece en cuanto
                // el contenido deja de estar arriba del todo y dice lo único
                // que el borde superior no puede decir por sí solo: que hay
                // algo por encima de lo que se ve. Es un detalle de ChromeOS —
                // y de casi cualquier lista con cabecera fija— que aquí faltaba:
                // al desplazar, las tarjetas se cortaban a media altura contra
                // el título sin nada que marcara el corte.
                //
                // Se coloca por coordenadas (no por anclas) porque el Flickable
                // vive dentro de contentCol y no es hermano de esta capa; las
                // anclas de QML solo llegan al padre y a los hermanos.
                Item {
                    id: headerScrim
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: contentCol.y + flick.y
                    height: Theme.dp(10)
                    // Un umbral, no una rampa sobre contentY: así el fundido lo
                    // hace la animación (con la duración de Ajustes) y no el
                    // dedo, fotograma a fotograma.
                    opacity: flick.contentY > Theme.dp(2) ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: Theme.hairline
                        color: Theme.withAlpha(Theme.overlay, Theme.isDark ? 0.7 : 0.45)
                    }
                    // Caída de sombra muy corta bajo el filete: sin ella el
                    // filete parece un separador dibujado, no un borde por
                    // debajo del cual pasa el contenido.
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: Theme.hairline
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: Qt.rgba(0, 0, 0, Theme.isDark ? 0.22 : 0.08)
                            }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                }
            }   // fin Item "Contenido"
        }       // fin de la fila barra lateral | contenido
    }

    // Componentes de la ventana. Los bloques que reutilizan las páginas
    // (SettingsCard, SwitchRow, SegRow, Hint, MonitorCard,
    // MonitorArrangement) viven en Panels/SettingsPages/; aquí solo la nav lateral.

    // Distintivo de "aquí estás": píldora estadio con tinte de acento suave,
    // no un bloque sólido. Es la pieza que reutilizan tanto el indicador
    // deslizante de cada NavSection como el estado propio de una NavTab
    // suelta. Sin posición propia (ni anchors.fill ni x/y): cada sitio que la
    // usa la coloca a su manera, para poder tanto deslizarla como anclarla.
    component NavHighlight: Rectangle {
        radius: height / 2
        color: cfg.navSelTint
    }

    // Píldora elástica de la nav: persigue 'targetY' con dos bordes a
    // velocidades distintas. La misma pieza pinta la selección y el hover
    // (antes eran dos copias de esta lógica, una por píldora).
    //
    // El borde que va delante corre (leadFactor) y la cola remolonea
    // (trailFactor): de la diferencia entre ambos sale un estirón EN EL
    // SENTIDO DE LA MARCHA que se recompone al llegar — el resaltado se mueve
    // como una gota, no como una caja que salta de sitio.
    //
    // El estirón se ACOTA a un 90 % del alto de una pestaña. Sin tope, saltar
    // de la primera a la última estiraba la píldora ocho pestañas: deja de
    // leerse como una gota y pasa a ser un borrón que cruza la barra.
    component ElasticPill: NavHighlight {
        id: pill
        property real targetY: 0
        property real targetH: cfg.controlHeightSm
        property bool animate: false
        // Duración de cada borde, en múltiplos de animNormal.
        property real leadFactor: 0.65
        property real trailFactor: 1.9

        property real leadY: pill.targetY
        property real trailY: pill.targetY
        readonly property real stretch:
            Math.min(Math.abs(trailY - leadY), pill.targetH * 0.9)

        x: navCol.x
        width: navCol.width
        // El borde que va DELANTE manda: la cola es la que se recorta al
        // llegar al tope.
        y: leadY >= trailY ? leadY - stretch : leadY
        height: stretch + pill.targetH

        Behavior on leadY {
            enabled: pill.animate
            NumberAnimation {
                duration: Math.max(1, Math.round(Theme.animNormal * pill.leadFactor))
                easing.type: Easing.OutSine
            }
        }
        Behavior on trailY {
            enabled: pill.animate
            NumberAnimation {
                duration: Math.max(1, Math.round(Theme.animNormal * pill.trailFactor))
                easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel
            }
        }
    }

    // Sección de la nav: solo sus pestañas, sin cabecera de grupo. Como ya no
    // hay cabeceras desplegables, tampoco hay hueco extra entre grupos: todas
    // las pestañas quedan a la misma distancia (una lista continua y uniforme).
    // La SELECCIÓN la pinta una única píldora global (ver el Flickable) que se
    // desliza cruzando de un grupo a otro; aquí solo van las pestañas.
    component NavSection: Item {
        id: sec
        property var items: []
        Layout.fillWidth: true
        implicitHeight: tabsCol.implicitHeight

        ColumnLayout {
            id: tabsCol
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Theme.dp(2)
            Repeater {
                model: sec.items
                delegate: NavTab {
                    required property var modelData
                    Layout.fillWidth: true
                    itemKey: modelData.key
                    glyph: modelData.glyph
                    label: modelData.label
                    selfHighlight: false   // la píldora global pinta la selección
                }
            }
        }
    }

    // Pestaña de la nav. Alto 32, glifo 18, etiqueta 13 en negrita,
    // alineada a la izquierda.
    // 'selfHighlight' true = dibuja su propio NavHighlight al seleccionarse
    // (pestañas sueltas, como Acerca de); false = la selección la pinta la
    // píldora global de la barra, que se coloca donde esta pestaña informa.
    component NavTab: Item {
        id: tab
        property string itemKey: ""
        property string glyph: ""
        property string label: ""
        property bool selfHighlight: true
        readonly property bool sel: cfg.cat === tab.itemKey
        readonly property bool hovered: tabMa.containsMouse
        // Texto teñido de acento donde hay resaltado: la selección (fija) o el
        // hover (pasajero). Ambos se pintan igual.
        readonly property bool active: sel || hovered

        // Alto de destino táctil del NavigationRail de Material. Cabe desde
        // que Plantillas y Clima se fusionaron en Tema y Widgets: con las doce
        // secciones de antes, 48 obligaba a desplazar la barra en la altura
        // por defecto de la ventana; con nueve, entra entero.
        implicitHeight: Theme.dp(48)

        // Al seleccionarse, la pestaña se ENTREGA a la píldora global. Solo eso:
        // la posición la deriva cfg.navSelY de la jerarquía viva, así que no
        // hay nada que volver a informar cuando el layout se mueve.
        function claimSel() {
            if (tab.sel && !tab.selfHighlight)
                cfg.navSelItem = tab
        }
        onSelChanged: claimSel()
        Component.onCompleted: claimSel()

        // Distintivo de SELECCIÓN propio SOLO para pestañas sueltas
        // (selfHighlight); las de sección las pinta la píldora global.
        NavHighlight {
            anchors.fill: parent
            visible: tab.selfHighlight && tab.sel
        }

        // HOVER: las pestañas del carril global no pintan nada propio — avisan
        // a la píldora deslizante de dónde está el cursor. No se pinta sobre la
        // seleccionada (ahí ya está su píldora), para no doblar el tono.
        // hovPaints centraliza la condición: el contador global se mantiene
        // equilibrado ante cualquier cambio (hover, selección, clic en caliente).
        readonly property bool hovPaints: !tab.selfHighlight && tab.hovered && !tab.sel
        onHovPaintsChanged: {
            if (hovPaints)
                cfg.navHovEnter(tab)
            else
                cfg.navHovLeave()
        }
        // Red de seguridad: al desaparecer con el ratón encima, devuelve su
        // cuenta. Sin esto la píldora de hover se quedaba encendida.
        Component.onDestruction: if (tab.hovPaints) cfg.navHovLeave()

        // Capa de HOVER local SOLO para pestañas sueltas (selfHighlight), que
        // viven fuera del carril de la píldora.
        NavHighlight {
            anchors.fill: parent
            visible: tab.selfHighlight
            opacity: tab.selfHighlight && tab.hovered && !tab.sel ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
        }

        RowLayout {
            anchors.fill: parent
            // En riel no hay etiqueta: el glifo se centra en toda la pastilla.
            anchors.leftMargin: cfg.navCompact ? 0 : Theme.dp(8)     // paddingH
            anchors.rightMargin: cfg.navCompact ? 0 : Theme.dp(10)
            spacing: cfg.navCompact ? 0 : Theme.dp(8)                // gap tesela↔etiqueta

            // Glifo plano, sin contenedor: monocromo en reposo y teñido de
            // acento allí donde está la píldora. Ancho fijo para que las
            // etiquetas queden alineadas aunque el glifo varíe; en riel se
            // estira para centrarse.
            ThemedText {
                Layout.preferredWidth: Theme.dp(30)
                Layout.fillWidth: cfg.navCompact
                horizontalAlignment: Text.AlignHCenter
                text: tab.glyph
                color: tab.active ? Theme.accentText : Theme.fgDim
                font.pixelSize: Theme.sp(22)
                // El glifo de la pestaña activa crece un punto: en Material el
                // indicador no solo se pinta, el propio icono gana cuerpo.
                scale: tab.sel ? 1.06 : 1
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animNormal
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSpatial; easing.overshoot: 2.4
                    }
                }
            }
            ThemedText {
                Layout.fillWidth: true
                visible: !cfg.navCompact
                text: tab.label
                // Acento donde está la píldora; la negrita marca la SELECCIÓN
                // (no el simple hover), para distinguirla del paso del ratón.
                color: tab.active ? Theme.accentText : Theme.fg
                font.pixelSize: Theme.typeLabelLarge
                font.bold: tab.sel
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }
        }

        // Onda de pulsación, por encima del contenido y recortada a la píldora.
        Ripple {
            id: tabRipple
            color: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.20 : 0.16)
        }

        MouseArea {
            id: tabMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: (m) => tabRipple.press(m.x, m.y)
            onClicked: cfg.goCat(tab.itemKey)
        }
    }
}
