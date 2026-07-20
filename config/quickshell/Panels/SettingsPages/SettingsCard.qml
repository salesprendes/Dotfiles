import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Panels.SettingsPages

// Tarjeta reutilizable con cabecera (icono + título). El contenido va dentro.
Rectangle {
    id: cardRoot
    property string title: ""
    property string glyph: ""
    // Condición propia de la página (p. ej. "solo si el terminal es configurable").
    // Va aparte de 'visible' para no pisar el binding del filtro.
    property bool shown: true
    default property alias content: cardCol.data
    Layout.fillWidth: true
    implicitHeight: cardCol.implicitHeight + Theme.space16 * 2
    radius: Theme.dp(12)                    // radiusXl
    color: SettingsPalette.settingsCard
    border.width: Theme.hairline
    border.color: SettingsPalette.settingsBorder

    // La tarjeta desaparece cuando el filtro ha escondido todas sus filas: si
    // no, quedarían cabeceras vacías flotando por la página.
    //
    // Se mira 'matches' (propiedad propia de la fila), NO 'visible': en QML
    // 'visible' es la visibilidad EFECTIVA e incluye la del padre, así que al
    // ocultar la tarjeta sus filas pasarían a reportar false y la tarjeta ya
    // nunca podría volver a mostrarse.
    readonly property bool anyMatch: {
        const kids = cardCol.children
        let filterable = false
        let any = false
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i]
            if (k && k.skey !== undefined && k.skey !== "") {
                filterable = true
                if (k.matches)
                    any = true
            }
        }
        // Tarjetas sin filas filtrables (Monitores, Acerca de…): se juzgan por
        // su propio título.
        return filterable ? any : SettingsFilter.acceptsCard(cardRoot.title)
    }
    visible: shown && anyMatch

    // El título de la tarjeta se busca también: al escribir "terminal" salen
    // sus filas aunque ninguna etiqueta contenga esa palabra.
    function pushTitle() {
        const kids = cardCol.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i] && kids[i].cardTitle !== undefined)
                kids[i].cardTitle = cardRoot.title
    }
    Component.onCompleted: pushTitle()
    onTitleChanged: pushTitle()

    ColumnLayout {
        id: cardCol
        anchors.fill: parent
        anchors.margins: Theme.space16
        spacing: Theme.space12

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space10
            visible: cardRoot.title !== ""
            Rectangle {
                visible: cardRoot.glyph !== ""
                implicitWidth: Theme.controlM
                implicitHeight: Theme.controlM
                radius: Theme.pillRadius
                border.width: Theme.hairline
                border.color: SettingsPalette.tileBorder
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: SettingsPalette.tileGradA }
                    GradientStop { position: 1.0; color: SettingsPalette.tileGradB }
                }
                Text {
                    anchors.centerIn: parent
                    text: cardRoot.glyph
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize
                }
            }
            Text {
                Layout.fillWidth: true
                text: cardRoot.title
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
            }
        }

        // Filete que separa la cabecera de los controles.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: -Theme.space4
            visible: cardRoot.title !== ""
            implicitHeight: Theme.hairline
            color: Theme.withAlpha(Theme.overlay, 0.22)
        }
    }
}
