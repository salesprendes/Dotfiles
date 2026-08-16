import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Grupo plegable de la configuración del asistente: una línea con icono,
// nombre y ESTADO a la derecha, y debajo su contenido cuando se abre.
//
// El estado es lo que hace que un acordeón valga: sin él hay que abrir los
// siete grupos para saber qué hay dentro, y entonces plegar no ahorra nada,
// solo esconde. Con él, la configuración entera se lee de un vistazo —
// «Permisos: Normal · Habilidades: 20 · Servidores: 2»— y solo se abre lo que
// de verdad se va a cambiar.
//
// El contenido va en un Component y solo se construye al abrirlo (lo hace
// ExpandableDetail con su Loader): treinta filas de excepciones no cuestan
// nada mientras nadie las mire.
ColumnLayout {
    id: fold

    property string glyph: ""
    property string title: ""
    property string summary: ""
    // Tinte de aviso en el estado (un modo que actúa sin preguntar, un
    // servidor caído): el color dice "mira aquí" sin desplegar nada.
    property bool warn: false
    property bool open: false
    property Component sourceComponent: null

    Layout.fillWidth: true
    spacing: 0

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Theme.rowL
        radius: Theme.shapeSm
        color: fold.open ? SettingsPalette.settingsControl
             : ma.containsMouse ? SettingsPalette.settingsHover
             : "transparent"
        // Entra casi instantáneo y sale con calma: el fondo sigue al
        // puntero, y los 100 ms de una transición normal se notan
        // como retraso (ver Theme.animHover).
        Behavior on color {
            ColorAnimation {
                duration: ma.containsMouse ? Theme.animHover
                                           : Theme.animHoverOut
                easing.type: ma.containsMouse ? Easing.OutCubic
                                              : Easing.InQuad
            }
        }
        clip: true

        Ripple { id: ripple }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space10
            anchors.rightMargin: Theme.space10
            spacing: Theme.space10

            RowBadge {
                Layout.alignment: Qt.AlignVCenter
                glyph: fold.glyph
                active: fold.open
            }
            Text {
                Layout.fillWidth: true
                text: fold.title
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
            }
            Text {
                text: fold.summary
                color: fold.warn ? Theme.red : Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.typeLabelMedium
                elide: Text.ElideRight
                Layout.maximumWidth: Theme.dp(150)
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }
            Text {
                text: "󰅀"
                rotation: fold.open ? 180 : 0
                color: fold.open ? Theme.accentText : Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(13)
                Behavior on rotation {
                    NumberAnimation {
                        duration: Theme.animNormal
                        easing.type: Theme.reflowEasing
                    }
                }
            }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: (e) => ripple.press(e.x, e.y)
            onClicked: fold.open = !fold.open
        }
    }

    ExpandableDetail {
        open: fold.open
        sourceComponent: fold.sourceComponent
    }
}
