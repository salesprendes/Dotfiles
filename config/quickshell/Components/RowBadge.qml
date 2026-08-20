import QtQuick
import qs.Config

// Insignia circular que abre una fila de ajuste: un glifo dentro de un
// círculo, a la izquierda de la etiqueta.
//
// Por qué existe: sin ella todas las filas de una página arrancan con texto
// en la misma vertical y la columna izquierda es una pared plana de palabras.
// La insignia le da a cada fila una cabeza reconocible y convierte el margen
// izquierdo en un riel de formas por el que el ojo baja saltando.
//
// Y no es solo decoración. En las filas que tienen estado (un interruptor)
// se enciende con él: encendida va teñida de acento, apagada queda neutra.
// Así la columna de insignias RESUME de un vistazo qué hay activo en la
// página, sin recorrer los interruptores uno a uno hasta el borde derecho.
// En las filas sin estado (elegir un valor) se queda siempre neutra: no hay
// un "encendido" que enseñar.
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

    // Disco tonal PLANO, sin filete. ChromeOS mete sus iconos de fila en un
    // contenedor de color sin contorno; el borde de antes era un tercer trazo
    // por fila (círculo + glifo + aro) que en una lista larga se lee como ruido.
    // Encendida sube el tinte de acento, que es lo único que tiene que decir.
    color: active ? Theme.withAlpha(Theme.accent, Theme.isDark ? 0.22 : 0.28)
                  : Theme.withAlpha(Theme.fg, Theme.isDark ? 0.07 : 0.06)
    border.width: 0

    Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

    ThemedText {
        anchors.centerIn: parent
        text: badge.glyph
        color: badge.active ? Theme.accentText : Theme.fgDim
        font.pixelSize: Theme.iconSize - Theme.dp(1)
        Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
    }
}
