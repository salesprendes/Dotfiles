pragma Singleton

import QtQuick
import Quickshell
import qs.Config
import qs.Services

// Paleta compartida de Ajustes: colores derivados del tema. Singleton para
// no repetir las fórmulas en cada fichero.
Singleton {
    readonly property color settingsCard: Theme.withAlpha(Theme.surface, 0.72)
    readonly property color settingsControl: Theme.withAlpha(Theme.surface, 0.86)
    readonly property color settingsHover: Theme.withAlpha(Theme.surfaceHi, 0.74)
    readonly property color settingsBorder: Theme.withAlpha(Theme.overlay, 0.28)

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
    readonly property color groupFill: Theme.withAlpha(Theme.surfaceHi, Theme.isDark ? 0.42 : 0.62)
    readonly property color groupBorder: Theme.withAlpha(Theme.overlay, Theme.isDark ? 0.22 : 0.26)
    // Fondo tintado de los distintivos (badges) de icono. En modo claro sube
    // el alfa para que el acento se lea sobre superficies claras.
    readonly property color accentSoft: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.16 : 0.24)

    // Tinte de "esto es lo elegido": lo comparten la píldora de la nav, la
    // ficha de cuenta seleccionada y el segmento activo de un SegRow. La misma
    // fórmula estaba calculada en dos ficheros; con dos copias, cambiar la
    // intensidad en uno habría dejado al otro diciendo lo mismo en otro tono.
    readonly property color selectedTint: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.26 : 0.32)

    // Degradado acento→acento2 de los "distintivos": la pestaña activa de la
    // nav, la cabecera de cada tarjeta y el icono de la ventana lo comparten,
    // así se leen como un único sistema en vez de piezas sueltas.
    readonly property color tileGradA:  Theme.withAlpha(Theme.accent,  Theme.isDark ? 0.32 : 0.36)
    readonly property color tileGradB:  Theme.withAlpha(Theme.accent2, Theme.isDark ? 0.10 : 0.13)
    readonly property color tileBorder: Theme.withAlpha(Theme.accent,  Theme.isDark ? 0.40 : 0.34)

    // ¿Es un portátil? (para mostrar/ocultar la opción de batería)
    readonly property bool hasBattery: Battery.present
}
