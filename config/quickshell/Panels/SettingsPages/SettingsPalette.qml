pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Config

// Paleta compartida de Ajustes: colores derivados del tema. Singleton para
// no repetir las fórmulas en cada fichero.
Singleton {
    // Fondo translúcido como el resto de paneles. En liquid-glass se vuelve
    // cristal esmerilado con el blur del compositor, no una losa opaca que
    // "brilla" en modo claro.
    readonly property color settingsBase: Theme.popupBg
    readonly property color settingsCard: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72)
    readonly property color settingsControl: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.86)
    readonly property color settingsHover: Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.74)
    readonly property color settingsLine: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.18)
    readonly property color settingsBorder: Qt.rgba(Theme.overlay.r, Theme.overlay.g, Theme.overlay.b, 0.28)
    // Fondo tintado de los distintivos (badges) de icono. En modo claro sube
    // el alfa para que el acento se lea sobre superficies claras.
    readonly property color accentSoft: Theme.withAlpha(Theme.accent, Theme.isDark ? 0.16 : 0.24)

    // ¿Es un portátil? (para mostrar/ocultar la opción de batería)
    readonly property bool hasBattery: UPower.displayDevice?.isLaptopBattery ?? false
}
