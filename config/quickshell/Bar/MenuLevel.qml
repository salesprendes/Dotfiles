import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Config

// Contenido del menú del tray. Sin recursión de tipos (QML la prohíbe):
// los submenús se navegan "drill-in" cambiando el menú mostrado, con una
// fila "atrás" para volver. Profundidad ilimitada, un solo componente.
Column {
    id: level

    property var menuHandle: null
    signal requestClose()

    // Pila de navegación para entrar/salir de submenús.
    property var navStack: []
    property var currentMenu: menuHandle
    onMenuHandleChanged: level.reset()

    function reset() {
        level.navStack = []
        level.currentMenu = level.menuHandle
    }
    function openChild(entry) {
        level.navStack = level.navStack.concat([level.currentMenu])
        level.currentMenu = entry
    }
    function goBack() {
        if (level.navStack.length === 0)
            return
        const s = level.navStack.slice()
        const prev = s.pop()
        level.navStack = s
        level.currentMenu = prev
    }

    readonly property string backLabel: I18n.language === "ca" ? "Enrere"
                                      : I18n.language === "en" ? "Back"
                                      : "Atrás"

    spacing: Theme.space2

    QsMenuOpener {
        id: opener
        menu: level.currentMenu
    }

    // ── Fila "atrás" (solo dentro de un submenú) ─────────────
    Loader {
        width: parent.width
        active: level.navStack.length > 0
        visible: active
        sourceComponent: Rectangle {
            width: parent.width
            implicitWidth: backRow.implicitWidth + Theme.space8 * 2
            height: Theme.rowS
            radius: Theme.pillRadius
            color: backHover.containsMouse ? Theme.withAlpha(Theme.accent, 0.20) : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            RowLayout {
                id: backRow
                anchors.fill: parent
                anchors.leftMargin: Theme.space8
                anchors.rightMargin: Theme.space8
                spacing: Theme.space8
                Text {
                    text: "‹"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                Text {
                    Layout.fillWidth: true
                    text: level.backLabel
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            MouseArea {
                id: backHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: level.goBack()
            }
        }
    }

    // Separador bajo la fila "atrás".
    Rectangle {
        width: parent.width - Theme.space8 * 2
        x: Theme.space8
        height: Theme.hairline
        visible: level.navStack.length > 0
        color: Theme.withAlpha(Theme.overlay, 0.55)
    }

    // ── Entradas del nivel actual ────────────────────────────
    Repeater {
        model: opener.children

        delegate: Item {
            id: entry
            required property var modelData
            width: level.width
            implicitHeight: cell.implicitHeight

            Loader {
                id: cell
                width: parent.width
                active: !!entry.modelData
                sourceComponent: entry.modelData && entry.modelData.isSeparator ? sepComp : rowComp
            }

            // Separador.
            Component {
                id: sepComp
                Item {
                    implicitHeight: Theme.space8
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.space8
                        anchors.rightMargin: Theme.space8
                        height: Theme.hairline
                        color: Theme.withAlpha(Theme.overlay, 0.55)
                    }
                }
            }

            // Fila normal.
            Component {
                id: rowComp
                Rectangle {
                    implicitWidth: rowLayout.implicitWidth + Theme.space8 * 2
                    implicitHeight: Theme.rowS
                    radius: Theme.pillRadius
                    color: hover.containsMouse && entry.modelData.enabled
                           ? Theme.withAlpha(Theme.accent, 0.20)
                           : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    RowLayout {
                        id: rowLayout
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space8
                        anchors.rightMargin: Theme.space8
                        spacing: Theme.space8

                        // Check / radio.
                        Text {
                            Layout.preferredWidth: Theme.iconSize
                            horizontalAlignment: Text.AlignHCenter
                            visible: entry.modelData.buttonType !== QsMenuButtonType.None
                            text: entry.modelData.buttonType === QsMenuButtonType.RadioButton ? "●" : "✓"
                            opacity: entry.modelData.checkState === Qt.Checked ? 1 : 0
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        // Icono propio de la entrada.
                        Image {
                            Layout.preferredWidth: Theme.iconSize
                            Layout.preferredHeight: Theme.iconSize
                            visible: !!entry.modelData.icon && source != ""
                            source: entry.modelData.icon ?? ""
                            sourceSize.width: Theme.iconSize
                            sourceSize.height: Theme.iconSize
                            smooth: true
                        }

                        // Texto.
                        Text {
                            Layout.fillWidth: true
                            text: entry.modelData.text ?? ""
                            color: entry.modelData.enabled ? Theme.fg : Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        // Flecha de submenú.
                        Text {
                            visible: entry.modelData.hasChildren
                            text: "›"
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: entry.modelData.enabled
                        cursorShape: entry.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (entry.modelData.hasChildren) {
                                level.openChild(entry.modelData)
                            } else {
                                entry.modelData.triggered()
                                level.requestClose()
                            }
                        }
                    }
                }
            }
        }
    }
}
