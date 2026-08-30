pragma Singleton

import QtQuick
import Quickshell
import qs.Config
import qs.Services

// Paleta compartida de Ajustes: colores derivados del tema. Singleton para
// no repetir las fórmulas en cada fichero.
Singleton {
    // La altura se dice subiendo de contenedor, no metiendo sombras. En esta
    // ventana el orden es:
    //
    //   ventana            el fondo translúcido
    //   surfaceContainer   las tarjetas de grupo y las cajas de la ventana
    //   ...High            los controles dentro de ellas: desplegables, campos,
    //                      segmentos. Un peldaño por encima de la tarjeta que los
    //                      contiene, que es lo que los hace leerse como algo que
    //                      se puede tocar.
    //
    // Opacos y no mezclas con alfa: con alfa, el tono depende de lo que haya
    // debajo, y el mismo desplegable se vería de un gris dentro de una tarjeta y
    // de otro sobre el fondo de la ventana.
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

    // Superficie plana: el grupo dice lo suyo con un tono y un borde, y nada
    // más. Acumular degradados, reflejos y filetes para decir "esto es un
    // bloque" hace que, apilados media docena de veces en una página, el ojo no
    // distinga un grupo de otro. El acento y el movimiento se gastan en las
    // filas, que es donde está el trabajo del usuario.
    // Contenedor de M3, opaco: con alfa, dos superficies superpuestas suman y el
    // mismo token saldría de un tono distinto según lo que hubiera detrás. Con
    // los tramos de esquina agrupada, una tarjeta es una pila de piezas y no una
    // sola superficie, así que ese caso es el normal.
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
