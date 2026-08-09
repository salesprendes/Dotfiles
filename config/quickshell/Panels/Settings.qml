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
    // Geometría de referencia: 1280×600. El mínimo es pequeño a propósito:
    // Hyprland puede acorralar la ventana en un mosaico, y antes que
    // recortarse la interfaz se compacta por tramos (ver headerCompact /
    // navCompact).
    implicitWidth: Theme.dp(1280)
    implicitHeight: Theme.dp(600)
    minimumSize: Qt.size(Theme.dp(600), Theme.dp(400))

    // Puntos de corte responsive, del más ancho al más estrecho:
    //  · headerCompact — la cabecera suelta el texto accesorio ("Solo
    //    modificados", el rótulo de Restablecer) y el contenido pierde
    //    margen; los controles quedan como iconos, el de cerrar incluido.
    //  · navCompact — la barra lateral pasa a riel de iconos: avatar solo
    //    y pestañas sin etiqueta (el buscador vive en la cabecera global).
    //  · headerTight / headerMicro — la cabecera suelta controles por orden
    //    de prioridad (primero el interruptor "solo modificados", después
    //    Restablecer), plegándose con animación en vez de desbordar por la
    //    derecha. El botón de cerrar es SIEMPRE el último que queda.
    readonly property bool headerCompact: width < Theme.dp(1000)
    readonly property bool navCompact: width < Theme.dp(860)
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
    // La que pulsas (cat) y la que está montada (shownCat) no son la misma
    // durante la transición: la nav se ilumina al instante, pero el contenido
    // espera a que la página vieja se haya ido.
    property string shownCat: "theme"

    // ── Resaltado de selección de la nav (una sola píldora para TODA la barra) ─
    // La pestaña seleccionada informa aquí de su posición (en el sistema de
    // coordenadas del contenido del Flickable) y una única píldora se DESLIZA
    // hasta ahí, cruzando de un grupo a otro sin desaparecer. navSelAnimate se
    // apaga al abrir para colocarla sin animar (si no, "viajaría" desde 0).
    property Item navContent: null
    property real navSelY: 0
    property real navSelH: controlHeightSm
    property bool navSelAnimate: false
    readonly property bool navSelShown: cat !== "about"

    // Píldora de HOVER: también única para toda la barra. Antes cada pestaña
    // fundía su propio resaltado y, al pasar rápido, varios parpadeaban a la
    // vez; ahora una sola píldora persigue al cursor deslizándose. Se cuenta
    // cuántas pestañas tienen el ratón encima (al cruzar de una a otra el
    // "salir" y el "entrar" no llegan en orden fijo) y la píldora se ve
    // mientras haya alguna.
    property real navHovY: 0
    property real navHovH: controlHeightSm
    property int  navHovCount: 0
    Timer { id: navSettle; interval: 60; onTriggered: cfg.navSelAnimate = true }
    onVisibleChanged: {
        if (visible) {
            pageOut.stop()
            pageIn.stop()
            const already = (shownCat === "theme")
            pageOpacity = 0
            pageOffset = Theme.dp(10)
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
            // La píldora de la nav se coloca sin animar al abrir; tras un
            // instante se habilita el deslizamiento para los clics siguientes.
            navSelAnimate = false
            navSettle.restart()
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
        NumberAnimation {
            target: cfg; property: "pageOpacity"
            to: 1; duration: 300; easing.type: Easing.OutCubic
        }
        // La página sube y se asienta con un ligero rebote (OutBack suave).
        NumberAnimation {
            target: cfg; property: "pageOffset"
            to: 0; duration: 420
            easing.type: Easing.OutBack; easing.overshoot: 1.1
        }
    }

    SequentialAnimation {
        id: pageOut
        ParallelAnimation {
            NumberAnimation {
                target: cfg; property: "pageOpacity"
                to: 0; duration: Theme.animFast; easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: cfg; property: "pageOffset"
                to: -Theme.dp(5); duration: Theme.animFast; easing.type: Easing.InCubic
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
        pageOffset = Theme.dp(10)
        pageIn.restart()
    }

    onCatChanged: {
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

            Text {
                text: I18n.tr("Settings")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(21)
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
                textPixelSize: Theme.sp(15)
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
                    NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutQuad }
                }
                RowLayout {
                    id: modOnlyRow
                    // Anclado a la derecha: al plegarse, la etiqueta
                    // desaparece primero bajo el recorte y el
                    // interruptor es lo último en irse.
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: cfg.spaceXs + Theme.dp(4)
                    Text {
                        visible: !cfg.headerCompact
                        text: I18n.tr("Modified only")
                        color: SettingsFilter.modifiedOnly ? Theme.fg : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.sp(14)
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
                    NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutQuad }
                }
                readonly property bool hot: resetMa.containsMouse || activeFocus
                activeFocusOnTab: shownBtn
                Keys.onReturnPressed: Settings.reset()
                Keys.onEnterPressed: Settings.reset()
                Keys.onSpacePressed: Settings.reset()
                color: resetMa.pressed ? Theme.withAlpha(Theme.red, 0.28)
                     : hot ? Theme.withAlpha(Theme.red, 0.16)
                     : cfg.settingsControl
                border.width: activeFocus ? Theme.focusWidth : Theme.hairline
                border.color: activeFocus ? Theme.focusRing
                            : hot ? Theme.withAlpha(Theme.red, 0.85) : cfg.settingsBorder
                scale: resetMa.pressed ? 0.95 : (hot ? 1.04 : 1.0)
                Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

                RowLayout {
                    id: resetRow
                    anchors.centerIn: parent
                    spacing: cfg.spaceXs + Theme.dp(2)
                    Text {
                        id: resetGlyph
                        text: "󰜉"; color: Theme.red
                        font.family: Theme.fontFamily; font.pixelSize: Theme.sp(16)
                        Behavior on rotation { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
                    }
                    Text {
                        visible: !cfg.headerCompact
                        text: I18n.tr("Reset")
                        color: resetBtn.hot ? Theme.red : Theme.fgDim
                        font.family: Theme.fontFamily; font.pixelSize: Theme.sp(14)
                        font.bold: true
                        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
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

            // Cerrar: círculo con el mismo lenguaje que Restablecer
            // (tinte, borde y escala fundidos); la cruz gira un cuarto
            // de vuelta al posarse.
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
                color: closeMa.pressed ? Theme.withAlpha(Theme.red, 0.30)
                     : hot ? Theme.withAlpha(Theme.red, 0.18)
                     : cfg.settingsControl
                border.width: activeFocus ? Theme.focusWidth : Theme.hairline
                border.color: activeFocus ? Theme.focusRing
                            : hot ? Theme.withAlpha(Theme.red, 0.85) : cfg.settingsBorder
                scale: closeMa.pressed ? 0.92 : (hot ? 1.06 : 1.0)
                Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    color: closeBtn.hot ? Theme.red : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(18)
                    rotation: closeBtn.hot ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                    Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
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
                anchors.margins: cfg.navCompact ? Theme.dp(6) : Theme.dp(10)    // padding de la nav
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
                        color: sel ? Theme.withAlpha(Theme.accent, Theme.isDark ? 0.20 : 0.24)
                                   : Theme.withAlpha(Theme.surfaceHi, Theme.isDark ? 0.45 : 0.55)
                        border.width: Theme.hairline
                        border.color: sel ? Theme.withAlpha(Theme.accent, 0.45)
                                          : Theme.withAlpha(Theme.overlay, 0.22)
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
                                NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutQuad }
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
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: !cfg.navCompact
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: cfg.userName
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.sp(16)
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: SysMon.hostname !== "" ? SysMon.hostname : SysMon.distroName
                                    color: profileTab.sel ? Theme.fgDim : Theme.fgMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.sp(12)
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                }
                            }

                            // Galón: la ficha abre una página, como las
                            // pestañas de abajo. Sin él no había nada que lo
                            // dijera y parecía una cabecera decorativa.
                            Text {
                                visible: !cfg.navCompact
                                text: "󰅂"
                                color: profileTab.sel ? Theme.accent : Theme.fgMuted
                                opacity: profileTab.sel || profileMa.containsMouse ? 1 : 0.4
                                font.family: Theme.fontFamily
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
                        ScrollBar.vertical: ScrollBar {
                            id: navScrollBar
                            policy: navFlick.scrollable ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: Theme.dp(5)
                                radius: width / 2
                                color: Theme.accent
                                opacity: navScrollBar.pressed ? 0.9 : (navScrollBar.active ? 0.65 : 0.4)
                                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                            }
                            background: Rectangle {
                                implicitWidth: Theme.dp(5)
                                radius: width / 2
                                color: Theme.sliderTrack
                                opacity: 0.35
                            }
                        }

                        // Píldora ÚNICA de selección (detrás de las pestañas):
                        // se desliza a la posición absoluta de la seleccionada,
                        // de un grupo a otro sin cortes. Declarada antes que
                        // navCol para quedar por debajo.
                        NavHighlight {
                            id: navSelPill
                            x: navCol.x
                            width: navCol.width
                            // 'py' es la posición animada. De lo que le queda
                            // por recorrer sale un estirón EN EL SENTIDO DE LA
                            // MARCHA, que se recompone al llegar: el resaltado
                            // se mueve como una gota, no como una caja que
                            // salta de sitio. No necesita animación propia —
                            // se deriva de 'py', que ya va animada.
                            property real leadY: cfg.navSelY
                            property real trailY: cfg.navSelY
                            y: Math.min(leadY, trailY)
                            height: Math.abs(trailY - leadY) + cfg.navSelH
                            opacity: cfg.navSelShown ? 1 : 0
                            Behavior on leadY {
                                enabled: cfg.navSelAnimate
                                NumberAnimation {
                                    duration: Math.max(1, Math.round(Theme.animNormal * 0.65))
                                    easing.type: Easing.OutSine
                                }
                            }
                            Behavior on trailY {
                                enabled: cfg.navSelAnimate
                                NumberAnimation {
                                    duration: Math.max(1, Math.round(Theme.animNormal * 1.9))
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                        }

                        // Píldora de HOVER (más tenue que la selección): sigue
                        // al cursor deslizándose de pestaña en pestaña. Cuando
                        // no se ve, la posición salta sin animar: al reaparecer
                        // debe nacer bajo el cursor, no "viajar" desde donde se
                        // quedó la última vez.
                        NavHighlight {
                            id: navHovPill
                            x: navCol.x
                            width: navCol.width
                            color: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.13 : 0.16)
                            opacity: cfg.navHovCount > 0 ? 1 : 0
                            // Mismo elástico de dos bordes que la selección,
                            // algo más rápido: el hover tiene que ir con el
                            // cursor. Antes iba con una curva de salida corta y
                            // fija (190 ms, ni siquiera salía de Ajustes), que
                            // la pegaba al ratón: arrancaba de golpe y frenaba
                            // en seco en cada pestaña.
                            property real leadY: cfg.navHovY
                            property real trailY: cfg.navHovY
                            y: Math.min(leadY, trailY)
                            height: Math.abs(trailY - leadY) + cfg.navHovH
                            // Sin animar mientras no se ve: al reaparecer debe
                            // nacer bajo el cursor, no viajar desde donde se
                            // quedó la última vez.
                            Behavior on leadY {
                                enabled: navHovPill.opacity > 0.01
                                NumberAnimation {
                                    duration: Math.max(1, Math.round(Theme.animNormal * 0.5))
                                    easing.type: Easing.OutSine
                                }
                            }
                            Behavior on trailY {
                                enabled: navHovPill.opacity > 0.01
                                NumberAnimation {
                                    duration: Math.max(1, Math.round(Theme.animNormal * 1.5))
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutQuad } }
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

                // Firma de la ventana: el glifo de la categoría activa, enorme
                // y casi invisible, sangrando por la esquina superior derecha.
                // Es gratis (ya tenemos cfg.catGlyph) y cambia con cada página:
                // no decora, identifica dónde estás sin competir con el texto.
                // Fuera en "Acerca de": esa página ya trae su propia tarjeta
                // ilustrada (avatar + logo) y la marca de agua le hacía sombra.
                Text {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -Theme.dp(28)
                    anchors.rightMargin: -Theme.dp(14)
                    visible: cfg.shownCat !== "about"
                    text: cfg.catGlyph
                    color: Theme.accent
                    opacity: cfg.pageOpacity * (Theme.isDark ? 0.07 : 0.05)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sp(150)
                }

                ColumnLayout {
                anchors.fill: parent
                anchors.margins: cfg.headerCompact ? cfg.spaceMd : cfg.spaceLg
                anchors.leftMargin: cfg.headerCompact ? cfg.spaceSm : cfg.spaceMd
                spacing: cfg.spaceSm

                // Cabecera de la página: título a la izquierda y acciones
                // globales ("solo modificados", Restablecer, cerrar) a la
                // derecha. Cuanto más estrecho el panel, más margen derecho:
                // así el grupo de acciones se rebaja hacia la izquierda en vez
                // de quedarse pegado al borde.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.rightMargin: cfg.navCompact ? Theme.dp(24)
                                      : cfg.headerCompact ? Theme.dp(12) : 0
                    spacing: cfg.headerCompact ? cfg.spaceXs : cfg.spaceSm

                    // Título de la página. Va con la que SE VE (shownCat), no
                    // con la pulsada: si no, cambiaría antes que el contenido.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        opacity: cfg.pageOpacity
                        Text {
                            Layout.fillWidth: true
                            text: cfg.catGroupLabel
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.sp(12)
                            font.bold: true
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: Theme.dp(1.2)
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: cfg.catLabel
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.sp(23)
                            font.bold: true
                            elide: Text.ElideRight
                        }
                    }

                }

                // Resultados del buscador en OTRAS categorías (ver
                // cfg.crossGroups, declarado junto a itemIndex/activeItem
                // más arriba). Aparece/desaparece con barrido + fundido, no
                // de golpe (ver Components/ExpandableDetail.qml).
                ExpandableDetail {
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

                            Text {
                                text: I18n.tr("Results in other sections")
                                color: Theme.fgMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.sp(11)
                                font.bold: true
                                font.capitalization: Font.AllUppercase
                                font.letterSpacing: Theme.dp(1)
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
                                                Text {
                                                    Layout.preferredWidth: Theme.dp(22)
                                                    horizontalAlignment: Text.AlignHCenter
                                                    text: crossGroup.modelData.info.glyph
                                                    color: Theme.fgDim
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.sp(15)
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 0
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: resultRow.modelData.label
                                                        color: Theme.fg
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: Theme.fontSize
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: crossGroup.modelData.info.label
                                                        color: Theme.fgMuted
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: Theme.fontSize - 4
                                                    }
                                                }
                                                Text {
                                                    text: "󰁔"
                                                    color: Theme.fgMuted
                                                    font.family: Theme.fontFamily
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

                Flickable {
                    id: flick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: (pageLoader.item ? pageLoader.item.implicitHeight : 0) + cfg.spaceSm * 2
                    boundsBehavior: Flickable.StopAtBounds

                    // Solo se instancia la página ACTIVA. Así los desplegables
                    // pesados (p. ej. options: Fonts.list.map(...)) se evalúan
                    // únicamente al entrar en su categoría.
                    Loader {
                        id: pageLoader
                        anchors { left: parent.left; right: parent.right; top: parent.top
                                  topMargin: cfg.spaceSm; rightMargin: cfg.spaceSm }
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
                    Text {
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
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.sp(13)
                    }
                }
                }   // fin ColumnLayout interna (título + Flickable)
            }   // fin Item "Contenido"
        }       // fin de la fila barra lateral | contenido
    }

    // Componentes de la ventana. Los bloques que reutilizan las páginas
    // (SettingsCard, SwitchRow, SegRow, ColorRow, Hint, MonitorCard,
    // MonitorArrangement) viven en Panels/SettingsPages/; aquí solo la nav lateral.

    // Distintivo de "aquí estás": píldora estadio con tinte de acento suave,
    // no un bloque sólido. Es la pieza que reutilizan tanto el indicador
    // deslizante de cada NavSection como el estado propio de una NavTab
    // suelta. Sin posición propia (ni anchors.fill ni x/y): cada sitio que la
    // usa la coloca a su manera, para poder tanto deslizarla como anclarla.
    component NavHighlight: Rectangle {
        radius: height / 2
        color: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.26 : 0.32)
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

        // Cuando esta pestaña es la seleccionada, informa a la píldora global
        // de su posición (en coordenadas del contenido del Flickable) para que
        // se deslice hasta aquí. Se reevalúa si cambia la selección o si el
        // layout mueve la pestaña (ancho, riel, reflujo).
        function reportSel() {
            if (!tab.sel || !cfg.navContent || tab.selfHighlight)
                return
            const p = tab.mapToItem(cfg.navContent, 0, 0)
            cfg.navSelY = p.y
            cfg.navSelH = tab.height
        }
        onSelChanged: reportSel()
        onYChanged: reportSel()
        onHeightChanged: reportSel()
        Component.onCompleted: reportSel()
        Connections {
            target: cfg
            function onNavContentChanged() { tab.reportSel() }
        }

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
            if (hovPaints && cfg.navContent) {
                const p = tab.mapToItem(cfg.navContent, 0, 0)
                cfg.navHovY = p.y
                cfg.navHovH = tab.height
            }
            cfg.navHovCount += hovPaints ? 1 : -1
        }

        // Capa de HOVER local SOLO para pestañas sueltas (selfHighlight), que
        // viven fuera del carril de la píldora.
        NavHighlight {
            anchors.fill: parent
            visible: tab.selfHighlight
            opacity: tab.selfHighlight && tab.hovered && !tab.sel ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutQuad } }
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
            Text {
                Layout.preferredWidth: Theme.dp(30)
                Layout.fillWidth: cfg.navCompact
                horizontalAlignment: Text.AlignHCenter
                text: tab.glyph
                color: tab.active ? Theme.accent : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(22)
                // El glifo de la pestaña activa crece un punto: en Material el
                // indicador no solo se pinta, el propio icono gana cuerpo.
                scale: tab.sel ? 1.06 : 1
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animNormal
                        easing.type: Easing.OutBack; easing.overshoot: 2.4
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: !cfg.navCompact
                text: tab.label
                // Acento donde está la píldora; la negrita marca la SELECCIÓN
                // (no el simple hover), para distinguirla del paso del ratón.
                color: tab.active ? Theme.accent : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(15)
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
