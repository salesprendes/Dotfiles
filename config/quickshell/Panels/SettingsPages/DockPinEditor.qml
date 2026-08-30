import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Services

// Las apps fijadas del dock: la lista en su orden, arrastrable, y un buscador para
// añadir.
//
// Mismo patrón que BarLayoutEditor y por la misma razón: la ficha que se arrastra
// no se reparenta, se queda en su sitio atenuada haciendo de hueco de origen, y lo
// que sigue al ratón es un fantasma dibujado aparte. Reparentar el delegate de un
// Repeater funciona hasta que el modelo cambia, y entonces el Repeater reclama a
// su hijo, se lo encuentra con otro padre, y la ficha desaparece a mitad del gesto
// o se queda pegada a la capa de arrastre. Aquí el modelo cambia más que en la
// barra, así que el patrón no es opcional.
//
// Este editor es el segundo sitio que escribe Settings.dockPinned; el otro es
// arrastrar dentro del propio dock. Los dos llaman a las mismas funciones del
// catálogo y ninguno toca el array a mano.
SettingsRow {
    id: root

    property string label: I18n.tr("Pinned apps")
    property string desc: I18n.tr("Drag to reorder")

    skey: "dockPinned"
    filterText: root.label + " " + root.desc + " " + I18n.tr("Add app")
    aliases: ["fijar", "anclar", "pin", "favoritas"]
    isSettingsRow: false
    rowHighlight: false

    implicitHeight: cuerpo.implicitHeight

    readonly property var fijadas: Settings.dockPinned

    // Estado del arrastre
    property int arrastrando: -1     // índice que se arrastra, -1 = ninguno
    property int destino: -1         // hueco resaltado
    property real fantasmaX: 0
    property real fantasmaY: 0

    function soltar() {
        if (root.arrastrando !== -1 && root.destino !== -1
            && root.destino !== root.arrastrando) {
            // El hueco de suelta 'destino' se cuenta sobre la lista CON el
            // elemento todavía dentro; move() lo interpreta sobre la lista ya
            // sin él, así que un salto hacia la derecha se pasa por uno.
            const hasta = root.destino > root.arrastrando ? root.destino - 1
                                                          : root.destino
            Dock.reordenar(root.arrastrando, hasta)
        }
        root.arrastrando = -1
        root.destino = -1
    }

    ColumnLayout {
        id: cuerpo
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.space10

        // La lista
        ThemedText {
            Layout.fillWidth: true
            visible: root.fijadas.length === 0
            text: I18n.tr("No pinned apps yet.")
            color: Theme.fgMuted
            font.pixelSize: Theme.sp(12)
        }

        Flow {
            id: carril
            Layout.fillWidth: true
            spacing: Theme.space6
            visible: root.fijadas.length > 0

            Repeater {
                model: root.fijadas
                delegate: Row {
                    id: celda
                    required property var modelData
                    required property int index
                    spacing: 0

                    // Hueco de suelta ANTES de esta ficha.
                    DockPinDropGap {
                        editor: root
                        indice: celda.index
                        alto: ficha.height
                    }

                    DockPinChip {
                        id: ficha
                        editor: root
                        appId: celda.modelData
                        indice: celda.index
                    }
                }
            }

            // Y el hueco del final, que es el que falta si solo se ponen antes.
            DockPinDropGap {
                editor: root
                indice: root.fijadas.length
                alto: Theme.dp(34)
            }
        }

        // Añadir
        SearchField {
            id: busca
            Layout.fillWidth: true
            placeholder: I18n.tr("Add app")
        }

        readonly property var candidatas: {
            const q = SettingsFilter.fold(busca.text.trim())
            if (q === "")
                return []
            const out = []
            for (const c of AppCatalog.entries) {
                if (c.searchText.indexOf(q) === -1)
                    continue
                const id = DockCatalog.normalizeId(c.entry.id)
                if (DockCatalog.has(root.fijadas, id))
                    continue
                out.push(c.entry)
                if (out.length >= 6)
                    break
            }
            return out
        }

        Repeater {
            model: cuerpo.candidatas
            delegate: Rectangle {
                id: sugerencia
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Theme.dp(34)
                radius: Theme.shapeSm
                color: zonaSug.containsMouse ? Theme.withAlpha(Theme.accent, 0.14)
                                             : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space8
                    anchors.rightMargin: Theme.space8
                    spacing: Theme.space8

                    Image {
                        Layout.preferredWidth: Theme.dp(20)
                        Layout.preferredHeight: Theme.dp(20)
                        source: Quickshell.iconPath(sugerencia.modelData.icon ?? "", true)
                        sourceSize.width: Theme.dp(20)
                        sourceSize.height: Theme.dp(20)
                        fillMode: Image.PreserveAspectFit
                    }
                    ThemedText {
                        Layout.fillWidth: true
                        text: sugerencia.modelData.name ?? ""
                        color: Theme.fg
                        font.pixelSize: Theme.sp(12)
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: zonaSug
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Dock.fijar(sugerencia.modelData.id)
                        busca.text = ""
                    }
                }
            }
        }
    }

    // Fuera de todo layout y por encima de todo, porque tiene que poder
    // dibujarse sobre cualquier parte del editor sin que ningún positioner le
    // reclame el sitio.
    Rectangle {
        visible: root.arrastrando !== -1
        z: 100
        x: root.fantasmaX
        y: root.fantasmaY
        width: Theme.dp(34)
        height: Theme.dp(34)
        radius: Theme.shapeSm
        color: Theme.withAlpha(Theme.accent, 0.22)
        border.width: 1
        border.color: Theme.accent
        antialiasing: true

        Image {
            anchors.centerIn: parent
            width: Theme.dp(22)
            height: Theme.dp(22)
            source: root.arrastrando !== -1
                    ? Dock.iconoDe(root.fijadas[root.arrastrando]) : ""
            sourceSize.width: Theme.dp(22)
            sourceSize.height: Theme.dp(22)
            fillMode: Image.PreserveAspectFit
        }
    }
}
