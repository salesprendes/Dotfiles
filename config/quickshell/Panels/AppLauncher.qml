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
    }

    onShownChanged: {
        if (shown) {
            search = ""
            searchInput.text = ""
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
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
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
                Keys.onEscapePressed: Globals.closeAll()
                Keys.onReturnPressed: launcher.launch(launcher.apps[0]?.entry)
                Keys.onEnterPressed: launcher.launch(launcher.apps[0]?.entry)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text === ""
                    text: I18n.tr("Search applications...")
                    color: Theme.fgMuted
                    font: searchInput.font
                }
            }
            Text {
                text: launcher.apps.length
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    // ── Lista de aplicaciones ────────────────────────────────
    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(Theme.dp(440), launcher.apps.length * (Theme.dp(44) + Theme.space2))
        clip: true
        spacing: Theme.space2
        model: launcher.apps
        reuseItems: true
        cacheBuffer: Theme.dp(360)
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            id: appRow
            required property var modelData
            required property int index
            width: ListView.view.width
            implicitHeight: Theme.dp(44)
            radius: Theme.pillRadius
            color: "transparent"

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
                opacity: rowMa.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutQuad } }
            }

            readonly property string iconSrc:
                (modelData.entry?.icon ?? "") !== "" ? Quickshell.iconPath(modelData.entry.icon, true) : ""

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space8
                anchors.rightMargin: Theme.space10
                spacing: Theme.space10

                // Icono de la app (o glifo genérico).
                Item {
                    implicitWidth: Theme.controlS; implicitHeight: Theme.controlS
                    Image {
                        anchors.fill: parent
                        visible: appRow.iconSrc !== ""
                        source: appRow.iconSrc
                        sourceSize.width: Theme.controlS; sourceSize.height: Theme.controlS
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
            }

            MouseArea {
                id: rowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: launcher.launch(modelData.entry)
            }
        }
    }
}
