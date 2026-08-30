import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Fila con etiqueta (y descripción opcional) + interruptor a la derecha. La
// fila ENTERA es el área de toque (clic en cualquier punto la activa, no solo
// la bolita) y se resalta sutilmente al pasar el ratón: el panel entero
// comparte así el mismo lenguaje táctil que la nav.
//
// Root es un Item (SettingsRow), no un RowLayout: así puede haber un fondo de
// hover DETRÁS del contenido sin que la fila intente gestionarlo como si fuera
// otro campo de la columna. El filtro del buscador y la marca de fila los pone
// la base (ver Components/SettingsRow.qml); aquí solo se declara qué texto ve
// el buscador.
SettingsRow {
    id: sr
    // Esta fila lleva el suyo, con onda de pulsación: aquí la fila ENTERA es
    // pulsable (pulsar en cualquier sitio conmuta), y eso pide onda. El de la
    // base solo escucha el ratón, que es lo que necesitan las filas cuyo
    // control se maneja solo.
    rowHighlight: false
    property string label: ""
    property string desc: ""
    // Glifo de la insignia que abre la fila. Sin él no se dibuja nada, así
    // que el componente sigue sirviendo fuera de una tarjeta de ajustes.
    property string glyph: ""
    property bool checked: false
    signal toggled()

    filterText: sr.label + " " + sr.desc
    // Alto de fila holgado: una lista de ajustes respira mejor que a 36.
    implicitHeight: Math.max(row.implicitHeight, Theme.dp(46))

    // El resaltado de fila del shell, entero (banda + onda). Estaba escrito
    // aquí dentro, y por eso las listas del panel de IA se resaltaban de otra
    // manera; ahora es Components/RowHighlight.qml y lo comparten todas. Va
    // ANTES del contenido para quedar por debajo: en Material la onda corre por
    // la superficie, no por encima del texto.
    //
    // La banda sangra fuera de la fila para que la franja respire; menos por
    // arriba y abajo que por los lados, que es donde hay sitio (el hueco entre
    // filas es de Theme.space12).
    RowHighlight {
        id: realce
        hovered: rowMa.containsMouse
        bleedX: Theme.space8
        bleedY: Theme.space4
    }

    // Área de toque de la fila entera. Va ANTES del contenido (más abajo en
    // el orden de apilado): el interruptor, dibujado después, sigue captando
    // sus propios clics con prioridad; el resto de la fila cae aquí.
    MouseArea {
        id: rowMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (m) => realce.press(m.x, m.y)
        onClicked: sr.toggled()
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space10

        // Se enciende con el interruptor (ver Components/RowBadge.qml).
        RowBadge {
            Layout.alignment: Qt.AlignVCenter
            glyph: sr.glyph
            active: sr.checked
            offColor: SettingsPalette.settingsControl
            offBorderColor: SettingsPalette.settingsBorder
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: sr.label; color: Theme.fg
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: sr.desc !== ""
                text: sr.desc; color: Theme.fgMuted
                font.family: Theme.fontFamily; font.pixelSize: Theme.typeBodySmall
                wrapMode: Text.WordWrap
            }
        }

        Switch {
            Layout.alignment: Qt.AlignVCenter
            checked: sr.checked
            offColor: SettingsPalette.settingsControl
            offBorderColor: SettingsPalette.settingsBorder
            onToggled: sr.toggled()
        }
    }
}
