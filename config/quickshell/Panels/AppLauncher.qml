import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Services

Popout {
    id: launcher
    ns: "qs-launcher"
    cardWidth: 470
    cardMinWidth: 360
    alignLeft: true
    shown: Globals.launcherOpen

    property string search: ""
    property var apps: []
    property int selectedIndex: 0
    // Filtro por categoría freedesktop ("" = todas). Cada chip agrupa las
    // categorías afines de la spec bajo un solo icono.
    property string selectedCat: ""
    readonly property var catDefs: [
        { key: "Music",       glyph: "\u{f075a}", match: ["Audio", "Music", "Player", "Midi", "Mixer"] },
        { key: "Video",       glyph: "\u{f0567}", match: ["Video", "AudioVideo", "TV", "VideoEditor", "Recorder"] },
        { key: "Web",         glyph: "\u{f059f}", match: ["WebBrowser", "Network"] },
        { key: "Chat",        glyph: "\u{f0361}", match: ["Chat", "InstantMessaging", "Email", "Messaging", "P2P", "IRCClient"] },
        { key: "Development", glyph: "\u{f018d}", match: ["Development", "IDE", "TextEditor", "TerminalEmulator"] },
        { key: "Graphics",    glyph: "\u{f02e9}", match: ["Graphics", "Photography", "Viewer", "2DGraphics", "RasterGraphics", "VectorGraphics"] },
        { key: "Game",        glyph: "\u{f0297}", match: ["Game", "Emulator"] },
        { key: "Office",      glyph: "\u{f0219}", match: ["Office", "WordProcessor", "Spreadsheet", "Presentation", "Documentation", "Calendar", "ContactManagement"] },
        { key: "Education",   glyph: "\u{f0474}", match: ["Education", "Languages"] },
        { key: "Science",     glyph: "\u{f0093}", match: ["Science", "Math", "Electronics", "Engineering", "Astronomy"] },
        { key: "System",      glyph: "\u{f0493}", match: ["System", "Settings", "Utility", "Monitor", "FileManager", "FileTools", "Archiving", "Security"] }
    ]

    function entryInCat(entry, def) {
        const cats = entry.categories ?? []
        for (let i = 0; i < cats.length; i++)
            if (def.match.indexOf(cats[i]) >= 0)
                return true
        return false
    }

    onSelectedCatChanged: applySearch()
    // Acciones de sesión del pie + etiqueta de la que está bajo el cursor.
    property bool powerOpen: false
    property string hoverAction: ""

    function applySearch() {
        const q = search.trim().toLowerCase()
        let base = AppCatalog.entries
        if (selectedCat !== "") {
            const def = catDefs.find(d => d.key === selectedCat)
            if (def)
                base = base.filter(a => entryInCat(a.entry, def))
        }
        apps = q === "" ? base : base.filter(a => a.searchText.includes(q))
        selectedIndex = apps.length > 0 ? Math.min(selectedIndex, apps.length - 1) : -1
        appList.currentIndex = selectedIndex
    }

    onShownChanged: {
        if (shown) {
            search = ""
            searchInput.text = ""
            powerOpen = false
            hoverAction = ""
            selectedCat = ""
            apps = AppCatalog.entries
            focusTimer.restart()
        }
    }

    onSearchChanged: searchTimer.restart()

    Connections {
        target: AppCatalog
        function onEntriesChanged() { launcher.applySearch() }
    }

    Timer {
        id: searchTimer
        interval: 80
        onTriggered: launcher.applySearch()
    }

    Timer {
        id: focusTimer
        interval: 60
        onTriggered: searchInput.input.forceActiveFocus()
    }

    function launch(entry) {
        if (!entry) return
        entry.execute()
        Globals.closeAll()
    }

    function moveSelection(delta) {
        if (apps.length <= 0)
            return
        selectedIndex = Math.max(0, Math.min(apps.length - 1, selectedIndex + delta))
        appList.currentIndex = selectedIndex
        appList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function launchSelected() {
        launch(apps[selectedIndex]?.entry)
    }

    // Buscador
    SearchField {
        id: searchInput
        Layout.fillWidth: true
        accentIconOnFocus: true
        input.focus: true
        placeholder: I18n.tr("Search applications...")
        onTextChanged: launcher.search = text
        // ESC pliega primero las acciones de sesión; si ya están plegadas,
        // el evento burbujea hasta la tarjeta, que cierra el lanzador.
        onEscapePressed: (event) => {
            if (launcher.powerOpen) {
                launcher.powerOpen = false
                event.accepted = true
            }
        }
        onAccepted: launcher.launchSelected()
        onDownPressed: launcher.moveSelection(1)
        onUpPressed: launcher.moveSelection(-1)
    }

    // Filtros por categoría dentro de su propio recuadro: chips cuadrados de
    // solo icono, con "todas" primero.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: chipRow.implicitHeight + Theme.space6 * 2
        radius: Theme.pillRadius
        color: Theme.withAlpha(Theme.surface, 0.45)
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.25)

        RowLayout {
            id: chipRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.space6
            anchors.rightMargin: Theme.space6
            // Reparte el hueco sobrante entre los chips para que la fila
            // llene el recuadro de lado a lado. Se calcula de los hijos
            // reales (suma de anchos y recuento), sin duplicar aquí ni el
            // tamaño del chip ni cuántos hay: añadir o quitar categorías, o
            // cambiar el tamaño en CatChip, reequilibra solo.
            spacing: {
                let total = 0, n = 0
                const kids = visibleChildren
                for (let i = 0; i < kids.length; i++) {
                    if (kids[i].implicitWidth > 0) {
                        total += kids[i].implicitWidth
                        n++
                    }
                }
                return n > 1 ? Math.max(Theme.space4, (width - total) / (n - 1)) : 0
            }

            CatChip { catKey: ""; glyph: "\u{f056e}" }
            Repeater {
                model: launcher.catDefs
                delegate: CatChip {
                    required property var modelData
                    catKey: modelData.key
                    glyph: modelData.glyph
                }
            }
        }
    }

    // Lista de aplicaciones
    ListView {
        id: appList
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(Theme.dp(440), launcher.apps.length * (Theme.dp(44) + Theme.space2))
        clip: true
        spacing: Theme.space2
        model: launcher.apps
        reuseItems: true
        cacheBuffer: Theme.dp(360)
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: launcher.selectedIndex

        delegate: Rectangle {
            id: appRow
            required property var modelData
            required property int index
            width: ListView.view.width
            implicitHeight: Theme.dp(44)
            radius: Theme.pillRadius
            color: "transparent"
            // selectedIndex manda: ratón (onEntered) y teclado (moveSelection)
            // comparten un único resaltado, sin animación doble.
            readonly property bool selected: appRow.index === launcher.selectedIndex

            // Capa de resalte que anima opacidad, no color: interpolar
            // "transparent" pasaría por negro y dejaría un rastro en la fila.
            // Tinte de acento + borde para que se vea también en modo claro.
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Theme.withAlpha(Theme.accent, 0.16)
                border.width: Math.max(1, Theme.hairline)
                border.color: Theme.withAlpha(Theme.accent, 0.5)
                opacity: appRow.selected ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutQuad } }
            }

            readonly property string iconSrc:
                (modelData.entry?.icon ?? "") !== "" ? Quickshell.iconPath(modelData.entry.icon, true) : ""

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space8
                anchors.rightMargin: Theme.space10
                spacing: Theme.space10

                // Icono de la app sobre una "ficha" suave (o glifo genérico).
                Rectangle {
                    implicitWidth: Theme.dp(34); implicitHeight: Theme.dp(34)
                    radius: Theme.dp(10)
                    color: Theme.withAlpha(Theme.surface, 0.6)
                    border.width: Theme.hairline
                    border.color: Theme.withAlpha(Theme.overlay, 0.25)
                    Image {
                        anchors.centerIn: parent
                        width: Theme.dp(24); height: Theme.dp(24)
                        visible: appRow.iconSrc !== ""
                        source: appRow.iconSrc
                        sourceSize.width: Theme.dp(24); sourceSize.height: Theme.dp(24)
                        fillMode: Image.PreserveAspectFit
                        smooth: false
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: appRow.iconSrc === ""
                        text: "󰣆"
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize + 2
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: modelData.entry?.name ?? ""
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        readonly property string desc: modelData.entry?.comment || modelData.entry?.genericName || ""
                        visible: desc !== ""
                        text: desc
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideRight
                    }
                }

                // Botón de "lanzar" en la fila seleccionada.
                Rectangle {
                    visible: appRow.selected
                    implicitWidth: Theme.dp(26)
                    implicitHeight: Theme.dp(26)
                    radius: Theme.dp(8)
                    color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "󰌑"
                        color: Theme.bg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }

            MouseArea {
                id: rowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: launcher.selectedIndex = index
                onClicked: launcher.launch(modelData.entry)
            }
        }
    }

    // Sin resultados
    ColumnLayout {
        visible: launcher.apps.length === 0
        Layout.fillWidth: true
        Layout.topMargin: Theme.space16
        Layout.bottomMargin: Theme.space16
        spacing: Theme.space8
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰍉"
            color: Theme.fgMuted
            opacity: 0.55
            font.family: Theme.fontFamily
            font.pixelSize: Theme.dp(34)
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: I18n.tr("No results")
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    // Pie: contador + acciones de sesión
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Math.max(1, Theme.hairline)
        color: Theme.withAlpha(Theme.overlay, 0.3)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8

        Text {
            Layout.fillWidth: true
            text: launcher.powerOpen
                  ? (launcher.hoverAction !== "" ? launcher.hoverAction : I18n.tr("Session"))
                  : I18n.tr("%1 apps").arg(launcher.apps.length)
            color: launcher.powerOpen && launcher.hoverAction !== "" ? Theme.fg : Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            elide: Text.ElideRight
        }

        // Bandeja de acciones: se despliega hacia la izquierda del botón
        // con cascada (la más cercana al botón aparece primero).
        Item {
            id: powerTray
            property real prog: launcher.powerOpen ? 1 : 0
            Behavior on prog { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            implicitHeight: Theme.controlM
            implicitWidth: actionsRow.implicitWidth * prog
            visible: prog > 0.01
            clip: true

            Row {
                id: actionsRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space6
                Repeater {
                    id: powerActions
                    // Modelo compartido con el centro de control
                    // (Config/PowerActions.qml).
                    model: PowerActions.model
                    delegate: Rectangle {
                        id: pbtn
                        required property var modelData
                        required property int index
                        readonly property real rp: Math.max(0, Math.min(1,
                            (powerTray.prog - (powerActions.count - 1 - index) * 0.1) / 0.6))
                        width: Theme.controlM; height: Theme.controlM
                        radius: width / 2
                        color: pbMa.containsMouse ? pbtn.modelData.col : Theme.surface
                        border.width: Theme.hairline
                        border.color: pbMa.containsMouse ? pbtn.modelData.col
                                    : Theme.withAlpha(Theme.overlay, 0.4)
                        opacity: rp
                        scale: 0.6 + 0.4 * rp
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text {
                            anchors.centerIn: parent
                            text: pbtn.modelData.ic
                            color: pbMa.containsMouse ? Theme.bg : pbtn.modelData.col
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.iconSize
                        }
                        MouseArea {
                            id: pbMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: launcher.hoverAction = pbtn.modelData.label
                            onExited: if (launcher.hoverAction === pbtn.modelData.label) launcher.hoverAction = ""
                            onClicked: Globals.runPowerAction(pbtn.modelData.action)
                        }
                    }
                }
            }
        }

        // Botón que pliega/despliega la bandeja.
        Rectangle {
            implicitWidth: Theme.controlM; implicitHeight: Theme.controlM
            radius: width / 2
            color: launcher.powerOpen ? Theme.withAlpha(Theme.red, 0.16)
                 : ptMa.containsMouse ? Theme.surfaceHi : Theme.surface
            border.width: Theme.hairline
            border.color: launcher.powerOpen ? Theme.withAlpha(Theme.red, 0.55)
                        : Theme.withAlpha(Theme.overlay, 0.4)
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
            Text {
                anchors.centerIn: parent
                text: launcher.powerOpen ? "󰅖" : "󰐥"
                color: launcher.powerOpen || ptMa.containsMouse ? Theme.red : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
                rotation: launcher.powerOpen ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }
            MouseArea {
                id: ptMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    launcher.powerOpen = !launcher.powerOpen
                    if (!launcher.powerOpen) launcher.hoverAction = ""
                }
            }
        }
    }

    // Chip de categoría: cuadrado redondeado de solo icono; el activo se tiñe
    // de acento. Pulsar el activo vuelve a "todas".
    component CatChip: Rectangle {
        id: chip
        property string catKey: ""
        property string glyph: ""
        readonly property bool sel: launcher.selectedCat === chip.catKey
        implicitWidth: Theme.dp(30)
        implicitHeight: Theme.dp(30)
        radius: Theme.dp(9)
        color: sel ? Theme.withAlpha(Theme.accent, Theme.isDark ? 0.24 : 0.3)
             : chipMa.containsMouse ? Theme.surfaceHi
             : Theme.withAlpha(Theme.surface, 0.6)
        border.width: Theme.hairline
        border.color: sel ? Theme.withAlpha(Theme.accent, 0.55)
                          : Theme.withAlpha(Theme.overlay, 0.25)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Text {
            anchors.centerIn: parent
            text: chip.glyph
            color: chip.sel ? Theme.accent : Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: launcher.selectedCat = chip.sel ? "" : chip.catKey
        }
    }
}

