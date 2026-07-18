import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Services

Popout {
    id: launcher
    ns: "qs-launcher"
    cardWidth: 380
    cardMinWidth: 300
    alignLeft: true
    shown: Globals.launcherOpen

    property string search: ""
    property var apps: []
    property int selectedIndex: 0
    // Acciones de sesión del pie + etiqueta de la que está bajo el cursor.
    property bool powerOpen: false
    property string hoverAction: ""

    function applySearch() {
        const q = search.trim().toLowerCase()
        const catalog = AppCatalog.entries
        apps = q === "" ? catalog : catalog.filter(a => a.searchText.includes(q))
        selectedIndex = apps.length > 0 ? Math.min(selectedIndex, apps.length - 1) : -1
        appList.currentIndex = selectedIndex
    }

    onShownChanged: {
        if (shown) {
            search = ""
            searchInput.text = ""
            powerOpen = false
            hoverAction = ""
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
