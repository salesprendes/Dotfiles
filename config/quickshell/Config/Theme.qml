pragma Singleton

import QtQuick
import Quickshell
import qs.Config

// Tema "Solitude": paleta global, radios, espaciado y escala visual.
// Usa Theme.<prop> desde cualquier componente.
Singleton {
    id: theme

    // Conmutado por Settings.darkMode desde el Centro de control.
    // Todo lo demás deriva de estos colores para cambiar en bloque.
    readonly property bool isDark: Settings.darkMode

    readonly property var palette: Settings.currentPalette

    // Paleta base
    readonly property color bg:        isDark ? palette.bg        : palette.lightBg
    readonly property color bgAlt:     isDark ? palette.bgAlt     : palette.lightBgAlt
    readonly property color surface:   isDark ? palette.surface   : palette.lightSurface
    readonly property color surfaceHi: isDark ? palette.surfaceHi : palette.lightSurfaceHi
    readonly property color overlay:   isDark ? palette.overlay   : palette.lightOverlay

    readonly property color fg:        isDark ? palette.fg        : palette.lightFg
    readonly property color fgDim:     isDark ? palette.fgDim     : palette.lightFgDim
    readonly property color fgMuted:   isDark ? palette.fgMuted   : palette.lightFgMuted

    // Acentos
    readonly property color accent:    Settings.resolvedAccent
    // En modo claro usa la variante oscura del acento secundario (si existe)
    // para que iconos como el de Bluetooth contrasten sobre fondo claro.
    readonly property color accent2:   isDark ? palette.accent2
                                              : (palette.lightAccent2 || palette.accent2)
    // Colores semánticos: en modo claro usan su variante oscura (lightX) para
    // contrastar sobre fondo claro; en oscuro, el valor normal de la paleta.
    readonly property color cyan:      isDark ? palette.cyan    : (palette.lightCyan    || palette.cyan)
    readonly property color green:     isDark ? palette.green   : (palette.lightGreen   || palette.green)
    readonly property color yellow:    isDark ? palette.yellow  : (palette.lightYellow  || palette.yellow)
    readonly property color orange:    isDark ? palette.orange  : (palette.lightOrange  || palette.orange)
    readonly property color red:       isDark ? palette.red     : (palette.lightRed     || palette.red)
    readonly property color magenta:   isDark ? palette.magenta : (palette.lightMagenta || palette.magenta)

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // Opacidades efectivas (ver Settings.eff*): los sliders de Ajustes las editan.
    readonly property color barBg:      withAlpha(bg, Settings.effBarOpacity)
    readonly property color popupBg:    withAlpha(bg, Settings.effPopupOpacity)
    readonly property color pillBg:     withAlpha(surface, Settings.effWidgetOpacity)
    readonly property color panelBorder: withAlpha(overlay, 0.5)
    // Acento LEGIBLE para TEXTO. Sobre superficie clara —y sobre todo sobre un
    // tinte del propio acento, como la píldora de la barra o el segmento
    // elegido— el acento puro no tiene contraste: en modo claro, texto verde
    // sobre verde al 32 % es casi invisible. Es el equivalente al
    // 'on_primary_container' de Material 3, que nunca es el color base.
    readonly property color accentText: isDark ? accent : Qt.darker(accent, 1.85)
    readonly property color focusRing:  withAlpha(accent, 0.92)
    readonly property color focusBg:    withAlpha(accent, 0.14)

    // Carril de los sliders. OPACO a propósito: los paneles ya son translúcidos,
    // así que un carril con alfa dejaba ver el fondo de escritorio a través y se
    // leía como un hueco, no como un control. Usa 'overlay' (el Outline) y
    // no 'surface': el escalón sobre el fondo del panel tiene que
    // verse desde lejos, y las superficies quedan demasiado cerca del fondo.
    // Token único para que los tres sliders no vuelvan a divergir (había tres
    // colores distintos).
    readonly property color sliderTrack: overlay

    // densityScale se deriva de la resolución del monitor mayor (lado corto
    // relativo a 1080p). uiScale del usuario multiplica encima (1.0 = neutro):
    // escala = densityScale × uiScale.
    // Lado corto: 1080p→~1.00 · 1440p→~1.15 · 4K→~1.45
    readonly property real uiScale: Settings.uiScale
    // Densidad automática compartida con el greeter: fórmula en
    // Config/Scale.qml, instanciada aquí (ver el comentario de ese archivo).
    // El zoom automático se puede apagar (Ajustes → Tema): entonces la
    // densidad es neutra y manda solo la escala del usuario.
    readonly property Scale _densitySource: Scale {}
    readonly property real densityScale: Settings.autoDensity ? _densitySource.density : 1
    readonly property real scale: clamp(uiScale * densityScale, 0.7, 1.9)

    function dp(value) {
        return Math.round(value * scale)
    }

    function sp(value) {
        return Math.max(9, Math.round(value * scale * fontScale))
    }

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value))
    }

    function panelWidth(screen, desired, minValue, maxRatio) {
        const sw = screen ? screen.width : 1920
        const margin = barMargin * 2
        const maxByRatio = Math.round(sw * (maxRatio || 0.92))
        return Math.max(dp(minValue || 300), Math.min(dp(desired), maxByRatio, sw - margin))
    }

    // Geometría / espaciado (tokens derivados)
    readonly property int hairline: 1
    readonly property int focusWidth: Math.max(2, dp(2))
    readonly property int space2: dp(2)
    readonly property int space4: dp(4)
    readonly property int space6: dp(6)
    readonly property int space8: dp(8)
    readonly property int space10: dp(10)
    readonly property int space12: dp(12)
    readonly property int space14: dp(14)
    readonly property int space16: dp(16)
    readonly property int space18: dp(18)

    // ── Material 3 ───────────────────────────────────────────────────────────
    // Capas de estado: en M3 un control no cambia de color al interactuar,
    // sino que se le superpone una capa del color de su contenido con una
    // opacidad fija. Tenerlas como tokens es lo que hace que un interruptor,
    // un botón y una pestaña reaccionen con la MISMA intensidad — que es de
    // dónde sale la sensación de que todo pertenece al mismo sistema.
    readonly property real stateHover: 0.08
    readonly property real stateFocus: 0.10
    readonly property real statePressed: 0.12

    // Escala de formas de M3. No sustituye a pillRadius/barRadius (que siguen
    // el ajuste de redondeo del usuario): son los radios FIJOS de los
    // controles, que en M3 no dependen del tema sino de su tamaño.
    readonly property int shapeXs: dp(4)
    readonly property int shapeSm: dp(8)
    readonly property int shapeMd: dp(12)
    readonly property int shapeLg: dp(16)
    readonly property int shapeXl: dp(28)

    // Escala tipográfica de Material 3. Sustituye a los "fontSize − 3" que
    // había repartidos por el código: dos textos del mismo papel acababan con
    // tamaños distintos según quién los escribiera, y no había forma de saber
    // si una diferencia de 1 px era intencionada o un descuido.
    //
    // Los tres papeles de M3, de dentro afuera:
    //   label → texto DE un control (rótulos, pestañas, botones)
    //   body  → texto que se lee seguido (descripciones, ayudas)
    //   title → encabezados
    // Todos pasan por sp(), así que siguen el ajuste de tamaño de fuente.
    readonly property int typeLabelSmall:    sp(11)
    readonly property int typeLabelMedium:   sp(12)
    readonly property int typeLabelLarge:    sp(14)
    readonly property int typeBodySmall:     sp(12)
    readonly property int typeBodyMedium:    sp(14)
    readonly property int typeBodyLarge:     sp(16)
    readonly property int typeTitleSmall:    sp(14)
    readonly property int typeTitleMedium:   sp(16)
    readonly property int typeTitleLarge:    sp(22)
    readonly property int typeHeadlineSmall: sp(24)
    readonly property int typeHeadlineMedium: sp(28)
    // Tracking de las versalitas: a cuerpo pequeño y en mayúsculas, la
    // monoespaciada necesita aire para no leerse como un bloque macizo.
    readonly property real typeLabelTracking: dp(1.4)

    readonly property int controlXS: dp(22)
    readonly property int controlS: dp(26)
    readonly property int controlM: dp(30)
    readonly property int controlL: dp(38)
    readonly property int rowS: dp(34)
    readonly property int rowM: dp(38)
    readonly property int rowL: dp(48)
    readonly property int tileM: dp(54)
    readonly property int tileL: dp(64)

    readonly property int   barHeight:   dp(Math.round(36 * Settings.barScale))
    // barMargin controla el hueco lateral de la barra respecto al monitor.
    // barTopMargin controla únicamente la separación de la barra con su borde
    // (superior o inferior según Settings.barPosition). Con la barra pegada
    // (no flotante), ambos colapsan a 0: a sangre de borde a borde.
    readonly property int   barMargin:      Settings.barFloating ? dp(8) : 0
    readonly property int   barTopMargin:   Settings.barFloating ? dp(4) : 0
    // Alto de las píldoras de la barra: casi a sangre con la barra (deja un
    // respiro de space8 en total). Un alto propio en vez de derivarlo del
    // margen lateral hace las píldoras más presentes sin engordar la barra.
    readonly property int   barPillHeight:  barHeight - space8
    // Factor de redondeo amplificado: por debajo del 100% es lineal
    // (de casi-cuadrado a normal); por encima crece x2.2 para que subir
    // hasta el 160% se note claramente más redondeado (≈ doble de radio).
    readonly property real  cornerFactor: Settings.cornerScale <= 1.0
                                           ? Settings.cornerScale
                                           : 1.0 + (Settings.cornerScale - 1.0) * 2.2
    readonly property int   barRadius:   dp(Math.round(10 * cornerFactor))
    readonly property int   pillRadius:  dp(Math.round(8 * cornerFactor))
    readonly property int   gap:         space8       // entre grupos
    readonly property int   pad:         space10      // padding interno pill
    readonly property int   spacing:     space6       // entre items dentro de pill

    // Tipografía
    readonly property string fontFamily: Settings.fontFamily
    readonly property string monoFontFamily: Settings.monoFontFamily
    readonly property real   fontScale: Settings.fontScale
    readonly property int    fontSize:    sp(13)
    readonly property int    iconSize:    sp(15)
    // Iconos de la barra superior: más prominentes que iconSize general.
    // En la pill (Components/Pill.qml) quedaban perdidos con mucho hueco
    // alrededor sobre monitores grandes; un multiplicador fijo sobre iconSize
    // los hace notoriamente más grandes mientras siguen escalando con
    // 'scale' (resolución/densidad), en vez de quedar en un tamaño fijo.
    readonly property int    barIconSize: Math.round(iconSize * 1.4)

    readonly property int   animFast:   Settings.animFastMs
    readonly property int   animNormal: Settings.animNormalMs
    readonly property int   animSlow:   Settings.animSlowMs
    // Periodo de los indicadores CONTINUOS (spinners, latidos). Sigue la
    // velocidad de Ajustes como el resto, pero con un suelo: a diferencia de
    // una transición, un bucle no puede durar 0 — giraría sin avanzar,
    // repintando cada frame. Con la velocidad por defecto da los 1200 ms de
    // siempre.
    readonly property int   animLoop:   Math.max(900, animSlow * 3)

    // Todo lo que aparece entra con OutQuint y sale con InQuad, en
    // animNormal. No hay muelles ni curvas bezier: se anima un único
    // escalar 'reveal' 0→1 y se deriva de él la geometria (un barrido de
    // recorte desde el borde anclado, no un escalado) y la opacidad.
    // OutQuint (no OutCubic): cubre casi todo el recorrido enseguida y
    // dedica el resto a asentarse — misma duración, sensación más fluida.
    readonly property int enterEasing: Easing.OutQuint
    readonly property int exitEasing:  Easing.InQuad
    // Los popouts barren toda la altura de la tarjeta: OutQuint consumia ese
    // recorrido en los primeros frames y el despliegue parecia un corte.
    // OutCubic reparte el movimiento por toda la duracion — el barrido se VE
    // y aun asi aterriza suave.
    readonly property int popoutEnterEasing: Easing.OutCubic
    readonly property int popoutExitEasing:  Easing.InCubic
    // Reacomodos (pilas que se recolocan, cambios de pestaña). InOutCubic:
    // arranque y frenada más redondos que InOutQuad, sin cambiar el ritmo.
    readonly property int reflowEasing: Easing.InOutCubic

    // Opacidad del contenido en funcion del reveal: invisible hasta el 15%
    // y fundido en el resto — la tarjeta se abre primero y el contenido
    // aparece dentro, con retardo. La rampa es un smoothstep, no lineal:
    // el fundido nace y aterriza suave en vez de cortarse en los extremos.
    function revealOpacity(reveal) {
        const t = Math.max(0, Math.min(1, (reveal - 0.15) / 0.85))
        return t * t * (3 - 2 * t)
    }
}
