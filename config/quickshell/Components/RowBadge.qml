import QtQuick
import qs.Config

// Insignia circular que abre una fila de ajuste: un glifo dentro de un círculo, a
// la izquierda de la etiqueta.
//
// Sin ella, todas las filas de una página arrancan con texto en la misma vertical
// y la columna izquierda es una pared plana de palabras; la insignia le da a cada
// fila una cabeza reconocible y convierte el margen en un riel por el que el ojo
// baja saltando.
//
// En las filas con estado se enciende con él, así que la columna de insignias
// resume de un vistazo qué hay activo en la página. En las que solo eligen un
// valor se queda neutra: no hay un "encendido" que enseñar.
Rectangle {
    id: badge

    property string glyph: ""
    property bool active: false

    // Mismas fórmulas que SettingsPalette. Se repiten aquí (como ya hace
    // DropdownRow) porque este componente vive en Components y no debe
    // depender de un singleton de Panels.
    property color offColor: Theme.withAlpha(Theme.surface, 0.86)
    property color offBorderColor: Theme.withAlpha(Theme.overlay, 0.28)

    visible: glyph !== ""
    implicitWidth: Theme.dp(28)
    implicitHeight: Theme.dp(28)
    radius: height / 2

    // Disco tonal plano, sin filete: un contorno sería un tercer trazo por fila
    // —círculo, glifo y aro— que en una lista larga se lee como ruido. Encendida
    // sube el tinte de acento, que es lo único que tiene que decir.
    color: active ? Theme.withAlpha(Theme.accent, Theme.isDark ? 0.22 : 0.28)
                  : Theme.withAlpha(Theme.fg, Theme.isDark ? 0.07 : 0.06)
    border.width: 0

    Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }

    ThemedText {
        anchors.centerIn: parent
        text: badge.glyph
        color: badge.active ? Theme.accentText : Theme.fgDim
        font.pixelSize: Theme.iconSize - Theme.dp(1)
        Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecel } }
    }
}
