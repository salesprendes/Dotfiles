import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import qs.Config

// Selector de imágenes con el lenguaje del panel de Ajustes (Material 3).
//
// Sustituye al diálogo genérico de Qt, que era una lista de nombres de fichero
// con tamaños y fechas: para elegir una FOTO, el nombre no dice nada — hay que
// VERLA. Por eso es una rejilla de miniaturas.
//
// La idea que lo separa de un explorador cualquiera: al elegir para un avatar,
// lo que se guarda no es la foto entera sino el CÍRCULO de dentro. Así que la
// marca de "elegida" ES ese círculo, dibujado sobre la miniatura, y el pie
// enseña el avatar de verdad al tamaño al que se va a ver. Elegir una foto cuya
// cara se sale del recorte es el error clásico de estos selectores; aquí se ve
// antes de confirmar.
//
// Se cuelga del contenido de su ventana (ver 'hoist'), no de quien lo declara:
// es una capa modal que tapa la ventana entera, y colgada de una fila de
// ajustes quedaría encerrada en su tarjeta — sin recibir el ratón fuera de
// ella, que es el fallo que arrastraban los desplegables.
Item {
    id: sheet

    // Ruta absoluta elegida. Se emite al confirmar, nunca al ir navegando.
    signal picked(string path)

    property bool shown: false
    // El destino recorta en círculo (avatar). Con false —un fondo de pantalla,
    // por ejemplo— la selección se marca con un marco y no se enseña el círculo,
    // que ahí sería mentira.
    property bool circularCrop: false
    // Carpeta visible. Es una URL porque FolderListModel trabaja con URLs; la
    // ruta plana se deriva para lo que se enseña y para lo que se devuelve.
    property url folder: ""
    property string selected: ""

    readonly property var places: [
        { name: I18n.tr("Pictures"), path: Settings.xdgPicturesDir, glyph: "󰉏" },
        { name: I18n.tr("Wallpapers"), path: Settings.wallpaperDirs[0] || "", glyph: "󰸉" },
        { name: I18n.tr("Downloads"), path: Settings.xdgDownloadDir, glyph: "󰉍" },
        { name: I18n.tr("Desktop"), path: Settings.xdgDesktopDir, glyph: "󰧨" },
        { name: I18n.tr("Home"), path: Settings.home, glyph: "󰋜" }
    ]

    function toPath(u) {
        const s = String(u || "")
        return s === "" ? "" : decodeURIComponent(s.replace(/^file:\/\//, ""))
    }
    function toUrl(p) {
        return p === "" ? "" : "file://" + p
    }

    readonly property string folderPath: sheet.toPath(sheet.folder)

    // Migas de pan. La ruta ES una jerarquía, así que se navega por ella en vez
    // de enseñarla como un rótulo muerto. La casa se abrevia a '~' y solo se
    // muestran los últimos tramos: el principio de una ruta larga no aporta nada
    // y empujaría el resto fuera. Nunca se enseña una URL — 'file://…' es ruido
    // de máquina en una cara visible.
    readonly property var crumbs: {
        const p = sheet.folderPath
        if (p === "")
            return []
        const h = Settings.home
        const out = []
        let base = ""
        let rest = p
        if (h !== "" && p.indexOf(h) === 0) {
            base = h
            rest = p.substring(h.length)
            out.push({ name: "~", path: h })
        } else {
            out.push({ name: "/", path: "/" })
        }
        const parts = rest.split("/").filter(x => x !== "")
        let acc = base
        for (let i = 0; i < parts.length; i++) {
            acc += "/" + parts[i]
            out.push({ name: parts[i], path: acc })
        }
        return out.length > 4 ? out.slice(out.length - 4) : out
    }

    // Cuántas imágenes hay aquí. Dicho en la cabecera, ahorra entrar en una
    // carpeta para descubrir que está vacía.
    property int imageCount: 0
    function recount() {
        let n = 0
        for (let i = 0; i < folderModel.count; i++)
            if (!folderModel.get(i, "fileIsDir"))
                n++
        sheet.imageCount = n
    }

    // Se cuelga del contenido de la ventana. Cuanto antes: declarado dentro de
    // una página de ajustes es hijo de un layout, y un layout coloca a todos sus
    // hijos — la capa modal no tiene nada que hacer en esa columna.
    function hoist() {
        const win = sheet.Window.window
        if (win && win.contentItem && sheet.parent !== win.contentItem)
            sheet.parent = win.contentItem
    }
    Component.onCompleted: sheet.hoist()

    // Abre en 'startAt'. Si viene una imagen ya elegida, abre en SU carpeta y
    // con ella marcada: volver a abrir y encontrarse donde lo dejaste es lo que
    // uno espera.
    function present(startAt) {
        sheet.hoist()
        const s = startAt || ""
        const cut = s.lastIndexOf("/")
        const isFile = cut > 0 && s.indexOf(".", cut) > cut
        sheet.selected = isFile ? s : ""
        const dir = isFile ? s.substring(0, cut)
                 : s !== "" ? s
                 : Settings.xdgPicturesDir
        sheet.folder = sheet.toUrl(dir)
        sheet.shown = true
        grid.forceActiveFocus()
    }
    function dismiss() {
        sheet.shown = false
    }
    function confirm() {
        if (sheet.selected === "")
            return
        sheet.picked(sheet.selected)
        sheet.dismiss()
    }
    function goTo(dir) {
        sheet.selected = ""
        sheet.folder = sheet.toUrl(dir)
        grid.currentIndex = 0
    }
    function goUp() {
        const p = sheet.folderPath
        const cut = p.lastIndexOf("/")
        if (cut > 0)
            sheet.goTo(p.substring(0, cut))
    }
    // Teclado: entra en la carpeta o marca la imagen bajo el cursor de la
    // rejilla; repetir sobre una ya marcada confirma.
    function activateCurrent() {
        const i = grid.currentIndex
        if (i < 0 || i >= folderModel.count)
            return
        const p = folderModel.get(i, "filePath")
        if (folderModel.get(i, "fileIsDir"))
            sheet.goTo(p)
        else if (sheet.selected === p)
            sheet.confirm()
        else
            sheet.selected = p
    }

    // Sin anclas: 'parent' cambia al colgarse de la ventana, y una ancla fijada
    // al padre de partida no la seguiría. Vinculado al tamaño del padre sí.
    x: 0
    y: 0
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    z: 900
    visible: opacity > 0.01
    opacity: sheet.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutQuad } }
    // Sin esto la capa oculta seguiría comiéndose los clics del panel.
    enabled: sheet.shown

    Keys.onEscapePressed: sheet.dismiss()

    // El aro del cursor de rejilla solo se enseña cuando se está navegando con
    // el teclado. Al abrir, la rejilla toma el foco para que las flechas
    // funcionen desde el primer momento, pero pintar entonces un aro sobre la
    // primera miniatura la haría parecer elegida sin serlo.
    property bool keyNav: false

    // Velo. Atenúa lo de detrás para que la atención caiga en la hoja, y recoge
    // el clic fuera como "cancelar", que es lo que espera todo el mundo.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.44)
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: sheet.dismiss()
            onWheel: (w) => w.accepted = true      // no desplazar el panel de detrás
        }
    }

    // Sombra de la hoja: tres anillos, como en el resto del shell (este equipo
    // no tiene el módulo de efectos gráficos de Qt, así que no hay desenfoque).
    Item {
        anchors.fill: card
        Repeater {
            model: 3
            delegate: Rectangle {
                required property int index
                readonly property int grow: (index + 1) * Theme.dp(3)
                anchors.fill: parent
                anchors.margins: -grow
                radius: Theme.shapeXl + grow
                color: "transparent"
                border.width: Theme.dp(2)
                border.color: Qt.rgba(0, 0, 0, 0.16 - index * 0.05)
            }
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(sheet.width - Theme.dp(56), Theme.dp(880))
        height: Math.min(sheet.height - Theme.dp(56), Theme.dp(640))
        radius: Theme.shapeXl
        color: Theme.surfaceHi
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.34)
        // Entra creciendo un pelín, no de golpe: es la transición estándar de M3
        // para un diálogo, y da el sentido de "esto sale de la nada".
        scale: sheet.shown ? 1 : 0.94
        Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutBack } }

        // Se traga los clics para que no lleguen al velo y lo cierren.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space16
            spacing: Theme.space12

            // ── Cabecera ──────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space10

                // Subir de carpeta. Se apaga en la raíz en vez de desaparecer:
                // un botón que va y viene mueve de sitio a los de al lado.
                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: Theme.dp(36)
                    implicitHeight: Theme.dp(36)
                    radius: height / 2
                    color: upMa.containsMouse && upMa.enabled
                        ? Theme.withAlpha(Theme.fg, Theme.stateHover) : "transparent"
                    opacity: upMa.enabled ? 1 : 0.38
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        anchors.centerIn: parent
                        text: "󰁝"
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                    }
                    MouseArea {
                        id: upMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: sheet.folderPath !== "/" && sheet.folderPath !== ""
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sheet.goUp()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.dp(2)

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Choose an image")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.typeTitleMedium
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    // Migas navegables + recuento.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space4

                        Repeater {
                            model: sheet.crumbs
                            delegate: RowLayout {
                                id: crumb
                                required property var modelData
                                required property int index
                                readonly property bool last: crumb.index === sheet.crumbs.length - 1
                                spacing: Theme.space4

                                Text {
                                    visible: crumb.index > 0
                                    text: "›"
                                    color: Theme.withAlpha(Theme.fgMuted, 0.7)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.typeBodySmall
                                }
                                Text {
                                    text: crumb.modelData.name
                                    color: crumb.last ? Theme.fgDim
                                         : crumbMa.containsMouse ? Theme.accent : Theme.fgMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.typeBodySmall
                                    font.underline: crumbMa.containsMouse && !crumb.last
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                    MouseArea {
                                        id: crumbMa
                                        anchors.fill: parent
                                        anchors.margins: -Theme.space2
                                        hoverEnabled: true
                                        enabled: !crumb.last
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: sheet.goTo(crumb.modelData.path)
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: sheet.imageCount === 1
                                ? I18n.tr("1 image")
                                : I18n.tr("%1 images").arg(sheet.imageCount)
                            visible: sheet.imageCount > 0
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.typeLabelSmall
                        }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: Theme.dp(36)
                    implicitHeight: Theme.dp(36)
                    radius: height / 2
                    color: closeMa.containsMouse
                        ? Theme.withAlpha(Theme.fg, Theme.stateHover) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sheet.dismiss()
                    }
                }
            }

            // ── Sitios + rejilla ──────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.space12

                ColumnLayout {
                    // fillWidth EXPLÍCITO a false: dentro de un RowLayout un hijo
                    // de tipo Layout lo trae puesto a true de fábrica, y esta
                    // columna se quedaba con todo el ancho dejando la rejilla en
                    // nada. En hoja estrecha se esconde entera: la rejilla vale
                    // más que un menú lateral cuando no hay ancho para los dos.
                    Layout.fillWidth: false
                    Layout.preferredWidth: Theme.dp(192)
                    Layout.alignment: Qt.AlignTop
                    spacing: Theme.space2
                    visible: card.width > Theme.dp(580)

                    // Rótulo en versalitas espaciadas, igual que las cabeceras de
                    // las tarjetas de ajustes: ata el selector al resto del panel.
                    Text {
                        Layout.leftMargin: Theme.space12
                        Layout.bottomMargin: Theme.space4
                        text: I18n.tr("Places")
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.typeLabelSmall
                        font.bold: true
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: Theme.typeLabelTracking
                    }

                    Repeater {
                        model: sheet.places
                        delegate: Rectangle {
                            id: place
                            required property var modelData
                            readonly property bool here: sheet.folderPath === place.modelData.path
                            Layout.fillWidth: true
                            visible: place.modelData.path !== ""
                            implicitHeight: Theme.dp(40)
                            radius: Theme.pillRadius
                            color: place.here ? Theme.withAlpha(Theme.accent, Theme.isDark ? 0.18 : 0.22)
                                 : placeMa.containsMouse ? Theme.withAlpha(Theme.fg, Theme.stateHover)
                                 : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.space12
                                anchors.rightMargin: Theme.space10
                                spacing: Theme.space10
                                Text {
                                    text: place.modelData.glyph
                                    color: place.here ? Theme.accent : Theme.fgDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.iconSize
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: place.modelData.name
                                    color: place.here ? Theme.fg : Theme.fgDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.typeBodyMedium
                                    font.bold: place.here
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                id: placeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sheet.goTo(place.modelData.path)
                            }
                        }
                    }
                }

                // Lienzo de la rejilla: un hueco hundido para que las miniaturas
                // se lean como contenido dentro de la hoja y no flotando.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: Theme.dp(240)
                    radius: Theme.shapeLg
                    color: Theme.withAlpha(Theme.bgAlt, 0.55)
                    border.width: Theme.hairline
                    border.color: Theme.withAlpha(Theme.overlay, 0.22)
                    clip: true

                    FolderListModel {
                        id: folderModel
                        folder: sheet.folder
                        showDirs: true
                        showDirsFirst: true
                        showDotAndDotDot: false
                        showHidden: false
                        sortField: FolderListModel.Name
                        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp", "*.gif"]
                        onCountChanged: sheet.recount()
                    }

                    GridView {
                        id: grid
                        anchors.fill: parent
                        anchors.margins: Theme.space10
                        clip: true
                        focus: true
                        model: folderModel
                        // Celdas repartidas a partes iguales: la última fila no
                        // queda con un hueco raro y las miniaturas mantienen la
                        // misma medida al cambiar de tamaño la hoja. Alto = ancho
                        // más la banda del nombre, así el área de imagen queda
                        // CUADRADA — que es lo que más se parece al círculo final.
                        readonly property int minCell: Theme.dp(112)
                        readonly property int cols: Math.max(1, Math.floor(width / minCell))
                        readonly property int nameBand: Theme.dp(20)
                        cellWidth: Math.floor(width / cols)
                        cellHeight: cellWidth + nameBand
                        boundsBehavior: Flickable.StopAtBounds
                        cacheBuffer: cellHeight * 3

                        Keys.onUpPressed: (e) => { sheet.keyNav = true; e.accepted = false }
                        Keys.onDownPressed: (e) => { sheet.keyNav = true; e.accepted = false }
                        Keys.onLeftPressed: (e) => { sheet.keyNav = true; e.accepted = false }
                        Keys.onRightPressed: (e) => { sheet.keyNav = true; e.accepted = false }
                        Keys.onReturnPressed: sheet.activateCurrent()
                        Keys.onEnterPressed: sheet.activateCurrent()
                        Keys.onSpacePressed: sheet.activateCurrent()

                        ScrollBar.vertical: ScrollBar {
                            id: gridBar
                            policy: grid.contentHeight > grid.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: Theme.dp(5)
                                radius: width / 2
                                color: Theme.accent
                                opacity: gridBar.pressed ? 0.9 : (gridBar.active ? 0.65 : 0.4)
                                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                            }
                            background: Rectangle {
                                implicitWidth: Theme.dp(5)
                                radius: width / 2
                                color: Theme.sliderTrack
                                opacity: 0.35
                            }
                        }

                        delegate: Item {
                            id: cell
                            required property string fileBaseName
                            required property string filePath
                            required property bool fileIsDir
                            required property int index
                            readonly property bool sel: !cell.fileIsDir && sheet.selected === cell.filePath
                            readonly property bool cursor: cell.GridView.isCurrentItem && grid.activeFocus && sheet.keyNav
                            width: grid.cellWidth
                            height: grid.cellHeight

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: Theme.dp(5)
                                radius: Theme.shapeMd
                                // La selección NO lleva marco: la marca es el
                                // círculo de recorte sobre la miniatura (abajo).
                                // Un marco además del círculo sería decir lo
                                // mismo dos veces.
                                color: cell.sel ? Theme.withAlpha(Theme.accent, 0.16)
                                     : cellMa.containsMouse ? Theme.withAlpha(Theme.fg, Theme.stateHover)
                                     : "transparent"
                                // El anillo de foco de teclado se calla en la elegida: ahí ya lo
                                // dice el círculo, y dos marcas para una cosa sobran.
                                border.width: cell.cursor && !cell.sel ? Theme.hairline : 0
                                border.color: Theme.withAlpha(Theme.accent, 0.55)
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.space6
                                    spacing: Theme.space2

                                    Item {
                                        id: thumbBox
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        // Carpeta: glifo tonal, no miniatura. Se
                                        // lee de un vistazo que es un sitio al
                                        // que entrar y no algo que elegir.
                                        Rectangle {
                                            anchors.fill: parent
                                            visible: cell.fileIsDir
                                            radius: Theme.shapeSm
                                            color: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.12 : 0.16)
                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰉋"
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Math.round(thumbBox.height * 0.40)
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: !cell.fileIsDir
                                            radius: Theme.shapeSm
                                            color: Theme.withAlpha(Theme.overlay, 0.20)
                                            clip: true

                                            Image {
                                                id: thumb
                                                anchors.fill: parent
                                                source: cell.fileIsDir ? "" : sheet.toUrl(cell.filePath)
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                cache: false
                                                // Se decodifica al tamaño de la
                                                // celda, no al de la foto: una
                                                // carpeta de fotos de 12 Mpx a
                                                // tamaño completo se come la
                                                // memoria y el arranque.
                                                sourceSize.width: Math.round(grid.cellWidth)
                                                sourceSize.height: Math.round(grid.cellWidth)
                                                // Entra al estar lista, no de
                                                // golpe: al desplazar, una rejilla
                                                // dando saltos de imagen se lee
                                                // como parpadeo.
                                                opacity: thumb.status === Image.Ready ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                                            }

                                            // Fichero que no carga (roto, o formato
                                            // que Qt no lee). Se dice, en vez de
                                            // dejar un cuadro vacío.
                                            Text {
                                                anchors.centerIn: parent
                                                visible: thumb.status === Image.Error
                                                text: "󰋔"
                                                color: Theme.fgMuted
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.iconSize * 2
                                            }
                                        }

                                        // ── La marca de elegida ───────────────
                                        // El círculo que de verdad se va a
                                        // recortar, encima de la miniatura. Ver
                                        // la nota de cabecera: es la razón de ser
                                        // de este selector frente a un explorador.
                                        Rectangle {
                                            anchors.centerIn: parent
                                            visible: cell.sel && sheet.circularCrop
                                            width: Math.min(thumbBox.width, thumbBox.height)
                                            height: width
                                            radius: width / 2
                                            color: "transparent"
                                            border.width: Theme.focusWidth
                                            border.color: Theme.accent
                                        }
                                        // Sin recorte circular (un fondo de
                                        // pantalla): marco, que es lo honesto.
                                        Rectangle {
                                            anchors.fill: parent
                                            visible: cell.sel && !sheet.circularCrop
                                            radius: Theme.shapeSm
                                            color: "transparent"
                                            border.width: Theme.focusWidth
                                            border.color: Theme.accent
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        // Sin extensión: a tres columnas
                                        // 'apple_gruvbox.jpg' se cortaba en
                                        // mitad del nombre, y el formato no
                                        // ayuda a elegir una foto. El pie
                                        // enseña el nombre entero.
                                        text: cell.fileBaseName
                                        horizontalAlignment: Text.AlignHCenter
                                        color: cell.sel ? Theme.fg : Theme.fgDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.typeLabelSmall
                                        font.bold: cell.sel
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }

                            MouseArea {
                                id: cellMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    sheet.keyNav = false
                                    grid.currentIndex = cell.index
                                    if (cell.fileIsDir)
                                        sheet.goTo(cell.filePath)
                                    else
                                        sheet.selected = cell.filePath
                                }
                                // Doble clic sobre una imagen = elegirla. Es el
                                // gesto que todo el mundo prueba en una rejilla.
                                onDoubleClicked: {
                                    if (!cell.fileIsDir) {
                                        sheet.selected = cell.filePath
                                        sheet.confirm()
                                    }
                                }
                            }
                        }
                    }

                    // Carpeta sin nada. Una pantalla vacía es una invitación a
                    // actuar, no un cartel de error: dice dónde seguir buscando.
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - Theme.dp(64)
                        spacing: Theme.space6
                        visible: folderModel.status === FolderListModel.Ready && folderModel.count === 0

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "󰋩"
                            color: Theme.withAlpha(Theme.fgMuted, 0.55)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.dp(40)
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("No images here. Try another folder.")
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.typeBodyMedium
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // ── Pie ───────────────────────────────────────────────────────────
            // Con algo elegido, el avatar DE VERDAD, al tamaño al que se va a
            // ver. El círculo de la rejilla dice qué trozo entra; esto dice cómo
            // queda. Es el mismo componente que lo pinta en el panel, así que no
            // puede mentir.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space10

                Avatar {
                    visible: sheet.circularCrop && sheet.selected !== ""
                    diameter: Theme.dp(40)
                    source: sheet.selected
                    initial: "?"
                }

                Text {
                    Layout.fillWidth: true
                    text: sheet.selected === "" ? "" : sheet.selected.split("/").pop()
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.typeBodySmall
                    elide: Text.ElideMiddle
                }
                TextButton {
                    text: I18n.tr("Cancel")
                    onClicked: sheet.dismiss()
                }
                TextButton {
                    text: I18n.tr("Choose")
                    primary: true
                    enabled: sheet.selected !== ""
                    onClicked: sheet.confirm()
                }
            }
        }
    }
}
