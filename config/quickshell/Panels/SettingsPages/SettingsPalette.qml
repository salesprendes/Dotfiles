pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Config

// Paleta compartida de Ajustes: colores derivados del tema. Singleton para
// no repetir las fórmulas en cada fichero.
Singleton {
    // Fondo translúcido, como el resto de paneles.
    readonly property color settingsBase: Theme.popupBg
    readonly property color settingsCard: Theme.withAlpha(Theme.surface, 0.72)
    readonly property color settingsControl: Theme.withAlpha(Theme.surface, 0.86)
    readonly property color settingsHover: Theme.withAlpha(Theme.surfaceHi, 0.74)
    readonly property color settingsLine: Theme.withAlpha(Theme.overlay, 0.18)
    readonly property color settingsBorder: Theme.withAlpha(Theme.overlay, 0.28)
    // Fondo tintado de los distintivos (badges) de icono. En modo claro sube
    // el alfa para que el acento se lea sobre superficies claras.
    readonly property color accentSoft: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.16 : 0.24)

    // Degradado acento→acento2 de los "distintivos": la pestaña activa de la
    // nav, la cabecera de cada tarjeta y el icono de la ventana lo comparten,
    // así se leen como un único sistema en vez de piezas sueltas.
    readonly property color tileGradA:  Theme.withAlpha(Theme.accent,  Theme.isDark ? 0.24 : 0.30)
    readonly property color tileGradB:  Theme.withAlpha(Theme.accent2, Theme.isDark ? 0.05 : 0.08)
    readonly property color tileBorder: Theme.withAlpha(Theme.accent,  Theme.isDark ? 0.40 : 0.34)

    // ¿Es un portátil? (para mostrar/ocultar la opción de batería)
    readonly property bool hasBattery: UPower.displayDevice?.isLaptopBattery ?? false
}
