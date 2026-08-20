import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// LA FILA DE UNA HABILIDAD. Existe porque la de interruptor genérica no le
// hacía justicia a esta lista concreta, y se notaba:
//
//   · TODAS las habilidades llevaban el MISMO glifo. La insignia de fila
//     existe para darle a cada fila una cabeza reconocible y convertir el
//     margen izquierdo en un riel por el que el ojo baja saltando; con diez
//     filas idénticas hacía justo lo contrario: una columna de círculos
//     iguales que no distingue nada. Aquí la cabeza es el MONOGRAMA de la
//     habilidad, que sí es distinto en cada una.
//   · Encendida, la fila no se resaltaba. Lo único que cambiaba era el tinte
//     del disco, al otro extremo de la mirada respecto del interruptor. Saber
//     qué hay activo obligaba a recorrer la lista dos veces. Ahora la fila
//     ENTERA se marca como elegida, con el mismo resaltado que usa el resto
//     del shell (Components/RowHighlight.qml), más un filo de acento a la
//     izquierda que se lee de un vistazo desde arriba.
//   · Las descripciones tienen largos muy distintos, así que las filas salían
//     de alturas dispares y la lista parecía un muro irregular. Se acotan a
//     dos líneas: la lista recupera su ritmo y la descripción larga sigue
//     entera en su SKILL.md, que es donde se lee de verdad.
SettingsRow {
    id: skill

    property string name: ""
    property string desc: ""
    property bool checked: false
    signal toggled()

    filterText: skill.name + " " + skill.desc
    // El suyo lo dibuja esta fila (con estado de elegida y onda de pulsación),
    // así que el de la base sobra.
    rowHighlight: false
    implicitHeight: Math.max(fila.implicitHeight + Theme.space8 * 2, Theme.dp(52))

    // El resaltado del shell, con sus cuatro estados: nada, encima, elegida, y
    // elegida y encima. Va el PRIMERO para quedar por debajo del contenido.
    RowHighlight {
        id: realce
        hovered: ma.containsMouse
        selected: skill.checked
        bleedX: Theme.space8
        bleedY: Theme.space2
        radius: Theme.shapeMd
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (m) => realce.press(m.x, m.y)
        onClicked: skill.toggled()
    }

    // El filo de acento de lo encendido. Es la señal que se lee de un vistazo
    // recorriendo la lista de arriba abajo, sin tener que mirar cada
    // interruptor al otro lado de la fila.
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: -Theme.space6
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.dp(3)
        height: skill.checked ? Math.round(parent.height * 0.56) : 0
        radius: width
        color: Theme.accent
        opacity: skill.checked ? 1 : 0
        Behavior on height {
            NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
        }
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
    }

    RowLayout {
        id: fila
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space10

        // EL MONOGRAMA. Dos letras del nombre: es lo que hace que la columna
        // izquierda distinga una habilidad de otra en vez de repetir el mismo
        // icono diez veces.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Theme.dp(30)
            implicitHeight: Theme.dp(30)
            radius: height / 2
            color: skill.checked
                ? Theme.withAlpha(Theme.accent, Theme.isDark ? 0.24 : 0.30)
                : Theme.withAlpha(Theme.fg, Theme.isDark ? 0.07 : 0.06)
            Behavior on color {
                ColorAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }

            ThemedText {
                anchors.centerIn: parent
                // Dos letras si el nombre las da; una si no. En mayúsculas
                // porque un monograma en minúsculas se lee como una palabra
                // cortada, no como una marca.
                text: {
                    const n = String(skill.name).trim()
                    if (n === "")
                        return "?"
                    const partes = n.split(/[\s_-]+/).filter(p => p.length > 0)
                    return (partes.length > 1
                        ? partes[0].charAt(0) + partes[1].charAt(0)
                        : n.slice(0, 2)).toUpperCase()
                }
                color: skill.checked ? Theme.accentText : Theme.fgDim
                font.pixelSize: Theme.typeLabelMedium
                font.weight: Font.DemiBold
                Behavior on color {
                    ColorAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            ThemedText {
                Layout.fillWidth: true
                text: skill.name
                color: Theme.fg
                // Encendida pesa un punto más: la lista dice qué está en uso
                // también con la forma de la letra, no solo con el color (que
                // es lo único que ve alguien que no distingue bien el acento).
                font.weight: skill.checked ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
            ThemedText {
                Layout.fillWidth: true
                visible: skill.desc !== ""
                text: skill.desc
                color: Theme.fgMuted
                font.pixelSize: Theme.typeBodySmall
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        Switch {
            Layout.alignment: Qt.AlignVCenter
            checked: skill.checked
            offColor: SettingsPalette.settingsControl
            offBorderColor: SettingsPalette.settingsBorder
            onToggled: skill.toggled()
        }
    }
}
