import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Services

Popout {
    id: panel
    ns: "qs-clipboard"
    cardWidth: 420
    cardMinWidth: 320
    shown: Globals.clipboardOpen
    property int selectedIndex: 0

    // Estado y animación del vaciado (alto del cuerpo incluido), compartidos
    // con el centro de notificaciones.
    ClearableListState {
        id: clearState
        itemCount: () => Clipboard.filteredEntries.length
        clearAll: () => Clipboard.clear()
        body: historyBody
        list: historyList
        emptyBodyHeight: 120
        // Tope fijo del cuerpo: el panel nunca pasa de este alto. Con más
        // contenido, la lista desplaza dentro (con barra de scroll) y al
        // borrar una entrada las filas de debajo suben a ocupar el hueco;
        // el panel solo encoge cuando lo que queda ya cabe bajo el tope.
        maxContentHeight: Theme.dp(430)
    }

    function moveSelection(delta) {
        const count = Clipboard.filteredEntries.length
        if (count <= 0)
            return
        selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta))
        historyList.currentIndex = selectedIndex
        historyList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function copySelected() {
        Clipboard.copy(Clipboard.filteredEntries[selectedIndex])
    }

    onShownChanged: {
        if (shown) {
            Clipboard.search = ""
            searchInput.text = ""
            selectedIndex = 0
            Clipboard.refresh()
            clearState.refreshBodyHeight()
            focusTimer.restart()
        }
    }

    Connections {
        target: Clipboard
        function onFilteredEntriesChanged() {
            panel.selectedIndex = Clipboard.filteredEntries.length > 0
                ? Math.min(panel.selectedIndex, Clipboard.filteredEntries.length - 1)
                : -1
            historyList.currentIndex = panel.selectedIndex
            clearState.refreshBodyHeight()
            // Remedida cuando la transición de recolocación ha asentado: con
            // ella en marcha, contentHeight puede no ser aún el definitivo.
            settleRefresh.restart()
        }
    }

    Timer {
        id: settleRefresh
        interval: Theme.animNormal + 80
        onTriggered: clearState.refreshBodyHeight()
    }

    Timer {
        id: focusTimer
        interval: 60
        onTriggered: searchInput.input.forceActiveFocus()
    }

    // Debounce del filtrado: agrupa la ráfaga de teclas antes de filtrar.
    Timer {
        id: searchDebounce
        interval: 80
        onTriggered: Clipboard.search = searchInput.text
    }

    Component.onCompleted: clearState.refreshBodyHeight()

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: I18n.tr("Clipboard")
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }

        Rectangle {
            implicitWidth: Theme.controlM
            implicitHeight: Theme.controlM
            radius: height / 2
            color: refreshMa.containsMouse ? Theme.surfaceHi : Theme.surface
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Text {
                anchors.centerIn: parent
                text: Clipboard.loading ? "󰑓" : "󰑐"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
                RotationAnimation on rotation {
                    running: Clipboard.loading
                    loops: Animation.Infinite
                    from: 0; to: 360
                    duration: 900
                }
            }
            MouseArea {
                id: refreshMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Clipboard.refresh()
            }
        }

        IconButton {
            visible: Clipboard.filteredEntries.length > 0 && !clearState.clearing
            icon: "󰆴"
            iconColor: Theme.red
            hoverIconColor: Theme.red
            hoverColor: Theme.withAlpha(Theme.red, 0.22)
            onClicked: clearState.clearAnimated()
        }
    }

    SearchField {
        id: searchInput
        Layout.fillWidth: true
        showClear: false
        input.focus: true
        placeholder: I18n.tr("Search history...")
        onTextChanged: searchDebounce.restart()
        // ESC no se maneja aquí: burbujea hasta la tarjeta, que cierra.
        onAccepted: panel.copySelected()
        onDownPressed: panel.moveSelection(1)
        onUpPressed: panel.moveSelection(-1)

        // Contador de resultados en el lado derecho del campo.
        Text {
            text: Clipboard.filteredEntries.length
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: !Clipboard.available
        implicitHeight: Theme.dp(58)
        radius: Theme.pillRadius
        color: Theme.withAlpha(Theme.orange, 0.12)
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.orange, 0.35)

        Text {
            anchors.fill: parent
            anchors.margins: Theme.space12
            text: I18n.tr("Install %1 to use history").arg(Clipboard.missingTools)
            color: Theme.yellow
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
        }
    }

    Item {
        id: historyBody

        Layout.fillWidth: true
        Layout.preferredHeight: clearState.bodyHeight
        clip: true

        Text {
            anchors.centerIn: parent
            visible: Clipboard.available && (Clipboard.filteredEntries.length === 0 || clearState.showingClearedState) && clearState.emptyMessageReady
            opacity: visible ? 1 : 0
            text: Clipboard.search === "" ? I18n.tr("No history yet") : I18n.tr("No results")
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize

            Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        }

        ListView {
            id: historyList
            anchors.fill: parent
            visible: (Clipboard.filteredEntries.length > 0 || clearState.clearing) && !clearState.showingClearedState
            enabled: !clearState.clearing
            clip: true
            spacing: Theme.space4
            reuseItems: true
            cacheBuffer: 320
            // ScriptModel (no el array a pelo): calcula el diff entre listas y
            // emite altas/bajas puntuales, así borrar UNA entrada dispara las
            // transiciones de recolocación en vez de reconstruir la lista
            // entera (que además reseteaba el scroll). Las entradas se
            // identifican por 'raw' (línea única de cliphist) — por valor,
            // no por identidad: ver el aviso en Clipboard.remove().
            model: ScriptModel { values: Clipboard.filteredEntries; objectProp: "raw" }
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: panel.selectedIndex
            opacity: clearState.listClearOpacity
            transform: Translate { y: clearState.listClearOffset }
            onContentHeightChanged: clearState.refreshBodyHeight()

            // ¿Hay más contenido del que el cuerpo puede llegar a mostrar?
            // Se compara contra el TOPE de alto (no contra 'height', que va
            // animándose al remedirse y daría falsos positivos transitorios).
            readonly property bool scrollable: contentHeight > clearState.maxContentHeight + 1
            // Carril para la barra: las filas acaban un poco antes de donde
            // empieza el hilo, y solo cuando la barra existe — sin ella,
            // ocupan el ancho completo.
            readonly property real scrollGutter: scrollable ? Theme.dp(10) : 0

            // Barra en modo overlay: un hilo fino SIN pista que flota sobre el
            // borde derecho, separado un pelo del filo. A diferencia de las
            // listas planas de Ajustes/desplegables, aquí las filas son
            // tarjetas con borde: una pista a toda altura leía como una
            // segunda línea pegada a ellas, y reservarle un carril dejaba las
            // filas más estrechas que el buscador. Solo existe cuando sobra
            // contenido, y se atenúa cuando no se usa.
            ScrollBar.vertical: ScrollBar {
                id: histScrollBar
                policy: historyList.scrollable ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                rightPadding: Theme.space2
                topPadding: Theme.space2
                bottomPadding: Theme.space2
                background: null
                contentItem: Rectangle {
                    implicitWidth: Theme.dp(4)
                    radius: width / 2
                    color: Theme.accent
                    opacity: histScrollBar.pressed ? 0.9 : (histScrollBar.active ? 0.6 : 0.35)
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                }
            }

            // Al borrar (o filtrar) una entrada, las filas recolocadas se
            // deslizan a su nuevo sitio en vez de dar un salto seco.
            displaced: Transition {
                NumberAnimation { properties: "y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }
            removeDisplaced: Transition {
                NumberAnimation { properties: "y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index

                width: ListView.view.width - ListView.view.scrollGutter
                implicitHeight: Math.max(Theme.rowL, preview.implicitHeight + Theme.controlXS)
                x: deleting ? Theme.dp(28) : 0
                opacity: deleting ? 0 : 1
                scale: deleting ? 0.94 : 1
                radius: Theme.pillRadius
                readonly property bool selected: ListView.isCurrentItem
                color: rowMa.containsMouse || selected ? Theme.surfaceHi : Theme.surface
                border.width: selected ? Theme.focusWidth : Theme.hairline
                border.color: selected ? Theme.focusRing : Theme.withAlpha(Theme.overlay, 0.28)
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                Behavior on x { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

                property bool deleting: false

                // Con reuseItems, un delegate reciclado podría heredar el
                // estado 'deleting' de la fila anterior: se resetea al reusar.
                ListView.onReused: {
                    deleteAnim.stop()
                    deleting = false
                }

                // Salida: desliza+desvanece y borra la entrada casi al
                // terminar — un pelo antes, para que el cierre del hueco
                // (removeDisplaced) solape con el final del fundido en vez de
                // ir por turnos. Ligada a animNormal para respetar la
                // velocidad de animación del usuario.
                SequentialAnimation {
                    id: deleteAnim
                    ScriptAction { script: row.deleting = true }
                    PauseAnimation { duration: Math.max(0, Theme.animNormal - 40) }
                    ScriptAction { script: Clipboard.remove(row.modelData) }
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    enabled: !row.deleting && !clearState.clearing
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onEntered: panel.selectedIndex = index
                    onClicked: Clipboard.copy(modelData)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space10
                    anchors.rightMargin: Theme.space8
                    spacing: Theme.space10

                    Rectangle {
                        implicitWidth: Theme.controlM
                        implicitHeight: Theme.controlM
                        radius: height / 2
                        color: modelData.type === "image"
                            ? Theme.withAlpha(Theme.magenta, 0.20)
                            : Theme.withAlpha(Theme.accent, 0.16)
                        Text {
                            anchors.centerIn: parent
                            text: modelData.type === "image" ? "󰋩" : "󰉿"
                            color: modelData.type === "image" ? Theme.magenta : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.iconSize
                        }
                    }

                    Text {
                        id: preview
                        Layout.fillWidth: true
                        text: modelData.preview
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        implicitWidth: Theme.controlS
                        implicitHeight: Theme.controlS
                        radius: height / 2
                        color: deleteMa.containsMouse ? Theme.withAlpha(Theme.red, 0.22) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "󰆴"
                            color: deleteMa.containsMouse ? Theme.red : Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.iconSize - 1
                        }
                        MouseArea {
                            id: deleteMa
                            anchors.fill: parent
                            enabled: !row.deleting && !clearState.clearing
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: deleteAnim.restart()
                        }
                    }
                }
            }
        }
    }
}
