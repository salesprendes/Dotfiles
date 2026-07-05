import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config

Popout {
    id: launcher
    ns: "qs-launcher"
    cardWidth: 380
    cardMinWidth: 300
    alignLeft: true
    keyboardExclusive: true
    shown: Globals.launcherOpen

    property string search: ""
    property var allEntries: []
    property var apps: []
    property int selectedIndex: 0
    // Desplegable de acciones de sesión (pie) y etiqueta de la acción
    // bajo el cursor, que se muestra en el lado izquierdo del pie.
    property bool powerOpen: false
    property string hoverAction: ""

    function rebuildApps() {
        allEntries = (DesktopEntries.applications?.values ?? [])
            .filter(a => !(a.noDisplay ?? false))
            .sort((x, y) => (x.name || "").localeCompare(y.name || ""))
            .map(a => ({ entry: a, searchText: searchableText(a) }))
        applySearch()
    }

    function searchableText(entry) {
        const kw = Array.isArray(entry.keywords) ? entry.keywords.join(" ")
                 : (typeof entry.keywords === "string" ? entry.keywords : "")
        return ((entry.name || "") + " " + (entry.genericName || "") + " "
              + (entry.comment || "") + " " + kw).toLowerCase()
    }

    function applySearch() {
        const q = search.trim().toLowerCase()
        apps = q === "" ? allEntries : allEntries.filter(a => a.searchText.includes(q))
        selectedIndex = apps.length > 0 ? Math.min(selectedIndex, apps.length - 1) : -1
        appList.currentIndex = selectedIndex
    }

    onShownChanged: {
        if (shown) {
            search = ""
            searchInput.text = ""
            powerOpen = false
            hoverAction = ""
            if (allEntries.length === 0)
                rebuildApps()
            else
                apps = allEntries
            focusTimer.restart()
        }
    }

    onSearchChanged: searchTimer.restart()

    Component.onCompleted: rebuildApps()

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { launcher.rebuildApps() }
    }

    Timer {
        id: searchTimer
        interval: 80
        onTriggered: launcher.applySearch()
    }

    Timer {
        id: focusTimer
        interval: 60
        onTriggered: searchInput.forceActiveFocus()
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

    // Mismas órdenes que el centro de control. La pausa del bloqueo deja
    // que el popout se cierre y SUELTE el teclado exclusivo antes de que
    // hyprlock tome el foco (si no, la pantalla de contraseña se "bugea").
    function runPowerAction(action) {
        Globals.closeAll()
        if (action === "lock")
            Quickshell.execDetached(["sh", "-c", "sleep 0.25; command -v hyprlock >/dev/null && hyprlock || loginctl lock-session"])
        else if (action === "suspend")
            Quickshell.execDetached(["systemctl", "suspend"])
        else if (action === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"])
        else if (action === "poweroff")
            Quickshell.execDetached(["systemctl", "poweroff"])
    }

    // ── Buscador ─────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.rowM
        radius: Theme.pillRadius
        color: Theme.surface
        border.width: Theme.hairline
        border.color: searchInput.activeFocus ? Theme.accent
                     : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space12
            anchors.rightMargin: Theme.space12
            spacing: Theme.space8

            Text {
                text: "󰍉"   // lupa
                color: searchInput.activeFocus ? Theme.accent : Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }
            TextInput {
                id: searchInput
                Layout.fillWidth: true
                clip: true
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                selectionColor: Theme.accent
                verticalAlignment: TextInput.AlignVCenter
                focus: true
                onTextChanged: launcher.search = text
                // ESC pliega primero las acciones de sesión; si ya están
                // plegadas, cierra el lanzador.
                Keys.onEscapePressed: {
                    if (launcher.powerOpen) launcher.powerOpen = false
                    else Globals.closeAll()
                }
                Keys.onReturnPressed: launcher.launchSelected()
                Keys.onEnterPressed: launcher.launchSelected()
                Keys.onDownPressed: launcher.moveSelection(1)
                Keys.onUpPressed: launcher.moveSelection(-1)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text === ""
                    text: I18n.tr("Search applications...")
                    color: Theme.fgMuted
                    font: searchInput.font
                }
            }
            // Borrar la búsqueda de un click.
            Rectangle {
                visible: searchInput.text !== ""
                implicitWidth: Theme.dp(22); implicitHeight: Theme.dp(22)
                radius: width / 2
                color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b,
                               clearMa.containsMouse ? 0.5 : 0)
                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    color: clearMa.containsMouse ? Theme.fg : Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                MouseArea {
                    id: clearMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: searchInput.text = ""
                }
            }
        }
    }

    // ── Lista de aplicaciones ────────────────────────────────
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
            // Selección = única fuente de verdad (selectedIndex). El ratón la
            // mueve en onEntered y el teclado en moveSelection, así hover y
            // teclado comparten UN solo resaltado (sin animación doble).
            readonly property bool selected: appRow.index === launcher.selectedIndex

            // Resaltado de hover/selección como capa aparte que anima su
            // OPACIDAD (no el color): nunca se interpola hacia el negro de
            // "transparent" → sin "parte negra" en la fila anterior. Usa tinte
            // de acento + borde (mismo estilo "seleccionado" que WiFi/audio/
            // desplegables) para que se vea bien también en modo claro.
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                border.width: Math.max(1, Theme.hairline)
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
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
                    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.6)
                    border.width: Theme.hairline
                    border.color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.25)
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
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: (modelData.entry?.genericName ?? "") !== ""
                        text: modelData.entry?.genericName ?? ""
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideRight
                    }
                }

                // Flecha de "lanzar" en la fila seleccionada.
                Text {
                    visible: appRow.selected
                    text: "󰌑"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
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

    // ── Sin resultados ───────────────────────────────────────
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

    // ── Pie: contador + acciones de sesión desplegables ──────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Math.max(1, Theme.hairline)
        color: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.3)
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
                    model: [
                        { ic: "󰍁", label: I18n.tr("Lock"),      action: "lock",     col: Theme.accent },
                        { ic: "󰤄", label: I18n.tr("Suspend"),   action: "suspend",  col: Theme.accent },
                        { ic: "󰜉", label: I18n.tr("Restart"),   action: "reboot",   col: Theme.accent },
                        { ic: "󰐥", label: I18n.tr("Shut down"), action: "poweroff", col: Theme.red }
                    ]
                    delegate: Rectangle {
                        id: pbtn
                        required property var modelData
                        required property int index
                        readonly property real rp: Math.max(0, Math.min(1,
                            (powerTray.prog - (3 - index) * 0.1) / 0.6))
                        width: Theme.controlM; height: Theme.controlM
                        radius: width / 2
                        color: pbMa.containsMouse ? pbtn.modelData.col : Theme.surface
                        border.width: Theme.hairline
                        border.color: pbMa.containsMouse ? pbtn.modelData.col
                                    : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)
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
                            onClicked: launcher.runPowerAction(pbtn.modelData.action)
                        }
                    }
                }
            }
        }

        // Botón que pliega/despliega la bandeja.
        Rectangle {
            implicitWidth: Theme.controlM; implicitHeight: Theme.controlM
            radius: width / 2
            color: launcher.powerOpen ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.16)
                 : ptMa.containsMouse ? Theme.surfaceHi : Theme.surface
            border.width: Theme.hairline
            border.color: launcher.powerOpen ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.55)
                        : Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.4)
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
}
