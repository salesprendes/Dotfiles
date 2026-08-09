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
    border.width: Theme.hairline
    border.color: SettingsPalette.settingsBorder
    // Luz cenital: aclara arriba, oscurece abajo (ver SettingsPalette.cardTop).
    gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0.0; color: SettingsPalette.cardTop }
        GradientStop { position: 1.0; color: SettingsPalette.cardBottom }
    }

    // Reflejo del canto superior. Va metido hacia dentro el radio de la
    // esquina para que muera antes de doblarla, y se desvanece a los lados:
    // una línea recta a todo lo ancho delataría el truco.
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: Theme.hairline
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: cardRoot.radius
        anchors.rightMargin: cardRoot.radius
        implicitHeight: Theme.hairline
        height: Theme.hairline
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: "transparent" }
            GradientStop { position: 0.35; color: SettingsPalette.cardSheen }
            GradientStop { position: 0.65; color: SettingsPalette.cardSheen }
            GradientStop { position: 1.0;  color: "transparent" }
        }
    }

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
                font.pixelSize: Theme.fontSize + 2
                font.bold: true
                // Un pelo de tracking negativo: a cuerpo grande y en negrita,
                // la monoespaciada se abre demasiado y el título pierde bloque.
                font.letterSpacing: -Theme.dp(0.3)
                elide: Text.ElideRight
            }
        }

        // Filete que separa la cabecera de los controles. Nace bajo la
        // insignia y se disuelve hacia la derecha: marca el sentido de lectura
        // en vez de cerrar la cabecera con una línea de formulario.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: -Theme.space4
            visible: cardRoot.title !== ""
            implicitHeight: Theme.hairline
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.withAlpha(Theme.overlay, 0.42) }
                GradientStop { position: 0.7; color: Theme.withAlpha(Theme.overlay, 0.10) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }
}
