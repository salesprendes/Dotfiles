pragma Singleton

import QtQuick
import Quickshell
import qs.Config
import qs.Services

// Paleta compartida de Ajustes: colores derivados del tema. Singleton para
// no repetir las fórmulas en cada fichero.
Singleton {
    // ── La escalera de contenedores de M3, aplicada a Ajustes ────────────────
    // M3 dice la altura subiendo de contenedor, no metiendo sombras. En esta
    // ventana el orden es:
    //
    //   ventana            el fondo translúcido (settingsBackdrop)
    //   surfaceContainer   las tarjetas de grupo y las cajas de la ventana
    //   ...High            los CONTROLES dentro de ellas: desplegables,
    //                      campos, segmentos. Un peldaño por encima de la
    //                      tarjeta que los contiene, que es lo que los hace
    //                      leerse como algo que se puede tocar.
    //
    // Eran mezclas con alfa sobre 'surface' (0,72 y 0,86). El problema del alfa
    // aquí no es el tono sino que DEPENDE DE LO QUE HAYA DEBAJO: el mismo
    // desplegable se veía de un gris dentro de una tarjeta y de otro sobre el
    // fondo de la ventana, y no había forma de decir cuál era el correcto.
    readonly property color settingsCard: Theme.surfaceContainer
    readonly property color settingsControl: Theme.surfaceContainerHigh
    // El tono de fila lo define el TEMA (Theme.rowHover): aquí solo se le da
    // el nombre con el que lo conocen las páginas de ajustes.
    readonly property color settingsHover: Theme.rowHover
    // Separador de bajo contraste: el rol 'outlineVariant' de M3.
    readonly property color settingsBorder: Theme.outlineVariant

    // Material de tarjeta con luz cenital: el degradado aclara el borde
    // superior y oscurece el inferior, de modo que la tarjeta se lee como una
    // superficie iluminada desde arriba en vez de como un rectángulo plano.
    // Es un gradiente muy corto a propósito — se nota, no se ve.
    readonly property color cardTop: Theme.withAlpha(Theme.surfaceHi, Theme.isDark ? 0.78 : 0.86)
    readonly property color cardBottom: Theme.withAlpha(Theme.surface, Theme.isDark ? 0.60 : 0.70)
    // Reflejo especular del canto superior (1 px), lo que da el "peso" de
    // cristal. Se difumina a los lados para no chocar con las esquinas.
    readonly property color cardSheen: Theme.withAlpha(Theme.fg, Theme.isDark ? 0.10 : 0.16)

    // ── Grupo de ajustes (SettingsCard) ──────────────────────────────────────
    // Superficie PLANA. Antes cada grupo llevaba degradado cenital + reflejo
    // especular + filete bajo la cabecera + insignia de icono con su propio
    // degradado y su propio borde: cinco recursos para decir «esto es un
    // bloque». Apilados seis veces en una página, el ojo no distinguía un
    // grupo de otro y la página entera se leía como relieve estampado.
    //
    // Ahora el grupo dice lo suyo con dos cosas: un tono y un borde. Todo lo
    // demás (el acento, el movimiento) se gasta en las FILAS, que es donde
    // está el trabajo del usuario.
    // Contenedor de M3, opaco. Era withAlpha(surfaceHi, 0.42), y el alfa tenía
    // un problema que no se ve hasta que muerde: dos superficies con alfa una
    // encima de otra SUMAN, así que el mismo token salía de un tono distinto
    // según lo que hubiera detrás. Con los tramos de esquina agrupada eso pasó
    // de ser teórico a ser el caso normal — una tarjeta es ahora una pila de
    // piezas, no una sola superficie.
    //
    // El tono resultante es casi el mismo (#1d2125 contra el #1b1f23 que salía
    // compuesto), así que no cambia el aspecto: cambia que ahora es predecible.
    readonly property color groupFill: Theme.surfaceContainer
    readonly property color groupBorder: Theme.outlineVariant
    // Fondo tintado de los distintivos (badges) de icono. En modo claro sube
    // el alfa para que el acento se lea sobre superficies claras.
    readonly property color accentSoft: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.16 : 0.24)

    // Tinte de "esto es lo elegido": lo comparten la píldora de la nav, la
    // ficha de cuenta seleccionada y el segmento activo de un SegRow. La misma
    // fórmula estaba calculada en dos ficheros; con dos copias, cambiar la
    // intensidad en uno habría dejado al otro diciendo lo mismo en otro tono.
    readonly property color selectedTint: Theme.rowSelected

    // Degradado acento→acento2 de los "distintivos": la pestaña activa de la
    // nav, la cabecera de cada tarjeta y el icono de la ventana lo comparten,
    // así se leen como un único sistema en vez de piezas sueltas.
    readonly property color tileGradA:  Theme.withAlpha(Theme.accent,  Theme.isDark ? 0.32 : 0.36)
    readonly property color tileGradB:  Theme.withAlpha(Theme.accent2, Theme.isDark ? 0.10 : 0.13)
    readonly property color tileBorder: Theme.withAlpha(Theme.accent,  Theme.isDark ? 0.40 : 0.34)

    // ¿Es un portátil? (para mostrar/ocultar la opción de batería)
    readonly property bool hasBattery: Battery.present
}
