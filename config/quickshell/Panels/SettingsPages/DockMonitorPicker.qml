import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config

// En qué monitores sale el dock. Lista vacía = todos, que es el valor de
// fábrica y el que casi todo el mundo quiere.
//
// Se guarda por NOMBRE DE CONECTOR ("DP-1") y no por índice: los índices bailan
// al enchufar o desenchufar una pantalla, y un dock que se muda de monitor
// porque has conectado un proyector es un fallo que nadie sabría explicar.
SettingsRow {
    id: root

    // label y desc no vienen de SettingsRow: los declara cada derivado, y son
    // lo que SettingsSearchIndex busca al recorrer el árbol para construir el
    // índice. Sin ellos, este ajuste existiría y el buscador diría que no.
    property string label: I18n.tr("Monitors")
    property string desc: I18n.tr("Which screens get a dock")

    skey: "dockOnlyMonitors"
    filterText: root.label + " " + root.desc
    isSettingsRow: false
    rowHighlight: false

    implicitHeight: cuerpo.implicitHeight

    readonly property var elegidos: Settings.dockOnlyMonitors
    readonly property bool todos: !Array.isArray(root.elegidos)
                                  || root.elegidos.length === 0

    function alternar(nombre) {
        const actual = Array.isArray(root.elegidos) ? root.elegidos.slice() : []
        const i = actual.indexOf(nombre)
        if (i !== -1)
            actual.splice(i, 1)
        else
            actual.push(nombre)
        // Marcarlos TODOS equivale a no filtrar: se guarda la lista vacía en vez
        // de una lista con todos los conectores de hoy, que dejaría un monitor
        // nuevo fuera del dock sin que nadie lo haya pedido.
        Settings.dockOnlyMonitors =
            actual.length >= Quickshell.screens.length ? [] : actual
    }

    ColumnLayout {
        id: cuerpo
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.space8

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space10

            BarGlyph { text: "󰍹"; color: Theme.fgMuted }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                ThemedText {
                    Layout.fillWidth: true
                    text: root.label
                    color: Theme.fg
                    font.pixelSize: Theme.sp(13)
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: root.todos ? I18n.tr("All monitors") : root.desc
                    color: Theme.fgMuted
                    font.pixelSize: Theme.sp(11)
                    elide: Text.ElideRight
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.space6

            Repeater {
                model: Quickshell.screens
                delegate: Rectangle {
                    id: ficha
                    required property var modelData
                    readonly property string nombre: ficha.modelData
                        ? ficha.modelData.name : ""
                    readonly property bool puesto: root.todos
                        || root.elegidos.indexOf(ficha.nombre) !== -1

                    implicitWidth: etiqueta.implicitWidth + Theme.space12 * 2
                    implicitHeight: Theme.dp(30)
                    radius: height / 2
                    color: ficha.puesto ? Theme.withAlpha(Theme.accent, 0.20)
                                        : Theme.surfaceContainer
                    border.width: 1
                    border.color: ficha.puesto ? Theme.withAlpha(Theme.accent, 0.45)
                                               : Theme.outlineVariant
                    antialiasing: true

                    ThemedText {
                        id: etiqueta
                        anchors.centerIn: parent
                        text: ficha.nombre
                        color: ficha.puesto ? Theme.accent : Theme.fgMuted
                        font.pixelSize: Theme.sp(12)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.alternar(ficha.nombre)
                    }
                }
            }
        }
    }
}
