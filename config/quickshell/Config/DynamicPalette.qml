import QtQuick

// Paleta dinámica: de los píxeles de un fondo de pantalla a una paleta
// completa. Funciones PURAS, sin estado ni efectos secundarios: quien llama
// decide qué hacer con el resultado (Settings lo cachea y lo guarda; el
// greeter lo aplica a su Theme).
//
// Sin dependencias de Settings a propósito, igual que Scale.qml: el greeter
// corre antes de la sesión, como usuario 'greeter', y no puede leer
// settings.json (el HOME del usuario es 0700). Compartir ESTE fichero es lo
// que permite que el login y la sesión deriven la misma paleta del mismo
// fondo en vez de mantener dos copias de la fórmula.
//
// NO es singleton adrede: los singletons (Settings, el Theme del greeter) lo
// instancian como hijo. Ver la nota de Scale.qml sobre singletons que se
// referencian entre sí durante el arranque del motor.
QtObject {
    // El color se trabaja en OKLCh (claridad · croma · tono), no en HSL. En HSL
    // la "L" NO es claridad percibida: un amarillo y un azul con la misma L se
    // ven con brillos muy distintos, así que una paleta a claridades fijas
    // salía luminosa con unos fondos y apagada con otros, y había que elegir
    // números de compromiso que no quedaban bien con ninguno. En OKLab la
    // claridad sí es perceptual: cada papel de la paleta (fondo, superficie,
    // texto, acento) conserva el MISMO peso visual salga el tono que salga.
    // Es lo que hacen los generadores tipo matugen con CAM16/HCT, en cuarenta
    // líneas y sin dependencias.

    function _srgbToLinear(v) {
        return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
    }
    function _linearToSrgb(v) {
        return v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055
    }

    // Pública: 'readableOn' de Settings decide el color de texto con esta L.
    function rgbToOklab(r, g, b) {
        const R = _srgbToLinear(r), G = _srgbToLinear(g), B = _srgbToLinear(b)
        const l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B)
        const m = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B)
        const s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B)
        return {
            L: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        }
    }

    function _oklabToRgb(L, a, b) {
        const l_ = L + 0.3963377774 * a + 0.2158037573 * b
        const m_ = L - 0.1055613458 * a - 0.0638541728 * b
        const s_ = L - 0.0894841775 * a - 1.2914855480 * b
        const l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return {
            r: _linearToSrgb( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            g: _linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            b: _linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        }
    }

    // OKLCh → "#rrggbb". Si el color pedido no cabe en sRGB se le baja el
    // croma (búsqueda binaria) hasta que quepa, en vez de recortar cada canal
    // por separado: recortar canales TUERCE el tono, y un acento que vira al
    // recortarse deja de armonizar con la paleta de la que salió.
    function _okHex(L, C, hueDeg) {
        const hr = hueDeg * Math.PI / 180
        const ca = Math.cos(hr), sa = Math.sin(hr)
        const fits = (c) => c.r >= -0.0005 && c.r <= 1.0005
                         && c.g >= -0.0005 && c.g <= 1.0005
                         && c.b >= -0.0005 && c.b <= 1.0005
        let rgb = _oklabToRgb(L, C * ca, C * sa)
        if (!fits(rgb)) {
            let lo = 0, hi = C
            for (let i = 0; i < 14; i++) {
                const mid = (lo + hi) / 2
                if (fits(_oklabToRgb(L, mid * ca, mid * sa))) lo = mid
                else hi = mid
            }
            rgb = _oklabToRgb(L, lo * ca, lo * sa)
        }
        const hx = (v) => Math.max(0, Math.min(255, Math.round(v * 255)))
            .toString(16).padStart(2, "0")
        return "#" + hx(rgb.r) + hx(rgb.g) + hx(rgb.b)
    }

    // Recibe los píxeles RGBA de una miniatura del fondo y saca de ella el tono
    // y el croma con los que se construye la paleta.
    function fromPixels(data) {
        const N = 36                       // cubos de 10°
        const vx = new Array(N).fill(0)    // componentes del voto circular
        const vy = new Array(N).fill(0)
        const vw = new Array(N).fill(0)
        let chromaSum = 0, weightSum = 0, colored = 0, total = 0

        for (let i = 0; i + 3 < data.length; i += 4) {
            if (data[i + 3] < 128)
                continue
            total++
            const lab = rgbToOklab(data[i] / 255, data[i + 1] / 255, data[i + 2] / 255)
            const C = Math.sqrt(lab.a * lab.a + lab.b * lab.b)
            if (C < 0.02)                  // gris: no tiene tono que votar
                continue
            colored++
            // Pesa por croma y por cercanía a la media luz: lo casi negro y lo
            // casi blanco apenas definen el carácter cromático de una imagen.
            const lw = Math.max(0, 1 - Math.pow((lab.L - 0.60) / 0.45, 2))
            const w = C * lw
            if (w <= 0)
                continue
            let h = Math.atan2(lab.b, lab.a) * 180 / Math.PI
            if (h < 0) h += 360
            const k = Math.floor(h / 10) % N
            const hr = h * Math.PI / 180
            vx[k] += Math.cos(hr) * w
            vy[k] += Math.sin(hr) * w
            vw[k] += w
            chromaSum += C * w
            weightSum += w
        }

        // Fondo sin color (blanco y negro, escala de grises): paleta sobria
        // en un azul frío neutro, en vez de inventarse un tono a partir del
        // ruido de compresión.
        if (weightSum <= 0) {
            return fromSeed(250, 0.02)
        }

        // El pico se busca sumando cada cubo con sus dos vecinos: un tono
        // repartido a caballo entre dos cubos perdía antes contra otro peor
        // pero mejor centrado, por puro azar de dónde cae la frontera.
        let best = 0, bestScore = -1
        for (let i = 0; i < N; i++) {
            const s = vw[(i + N - 1) % N] + vw[i] + vw[(i + 1) % N]
            if (s > bestScore) { bestScore = s; best = i }
        }
        // Media circular del pico y sus vecinos: precisión de grados, no de
        // cubo (antes se usaba el centro del cubo ganador, hasta 5° de error).
        let cx = 0, cy = 0
        for (let d = -1; d <= 1; d++) {
            const k = (best + d + N) % N
            cx += vx[k]; cy += vy[k]
        }
        let hue = Math.atan2(cy, cx) * 180 / Math.PI
        if (hue < 0) hue += 360

        // El croma sale del croma REAL de la imagen, no de una escalera de tres
        // peldaños: un fondo pastel da paleta pastel y uno saturado, paleta
        // viva. Si el color es solo una pincelada sobre una imagen casi gris
        // ('share' bajo), se rebaja para no teñir todo el shell por un detalle.
        const share = colored / Math.max(1, total)
        const imgC = chromaSum / weightSum
        return fromSeed(hue, imgC * (share < 0.12 ? 0.55 : 1.0))
    }

    // Deriva la paleta completa (oscura + variantes claras) del tono semilla.
    // Las claridades van en OKLab, así que son las mismas para cualquier tono.
    // 'cf' es lo colorido que es el fondo (croma medio de sus píxeles con
    // color). Las rectas de abajo están calibradas midiendo fondos reales: van
    // de ~0.02 (un tema desaturado tipo Nord) a ~0.13 (uno muy vivo tipo
    // Gruvbox), y reparten ese recorrido de verdad — con la escala anterior la
    // mayoría de los fondos topaba con el mínimo y acababa con el mismo acento
    // exacto, que era justo lo que la paleta dinámica debía evitar.
    function fromSeed(hue, cf) {
        const H = (x) => ((x % 360) + 360) % 360
        // Armoniza un tono fijo (rojo, verde…) acercándolo un 15% al semilla:
        // siguen siendo reconocibles, pero pertenecen a la misma familia que
        // el resto de la paleta.
        const harm = (h) => H(h + (((hue - h + 540) % 360) - 180) * 0.15)
        const k = (L, C, h) => _okHex(L, C, h === undefined ? hue : h)
        const ac = Math.max(0.085, Math.min(0.210, 0.060 + cf * 1.15))   // acentos
        const sc = Math.max(0.080, Math.min(0.170, 0.055 + cf * 0.95))   // semánticos
        const nc = Math.max(0.004, Math.min(0.020, cf * 0.14))           // neutros teñidos
        return {
            label: "Dinámico",
            bg:        k(0.185, nc),       bgAlt:     k(0.215, nc),
            surface:   k(0.255, nc * 1.1), surfaceHi: k(0.305, nc * 1.2),
            overlay:   k(0.440, nc * 1.6),
            fg:        k(0.955, nc * 0.5), fgDim:     k(0.790, nc * 0.9),
            fgMuted:   k(0.635, nc * 1.1),
            accent:    k(0.800, ac),
            accent2:   k(0.760, ac * 0.92, H(hue + 42)),
            cyan:      k(0.800, sc, harm(195)),       green:   k(0.790, sc, harm(145)),
            yellow:    k(0.850, sc, harm(105)),       orange:  k(0.780, sc, harm(60)),
            red:       k(0.690, sc * 1.1, harm(29)),  magenta: k(0.740, sc, harm(345)),
            lightBg:        k(0.965, nc * 0.8), lightBgAlt:     k(0.945, nc * 0.9),
            lightSurface:   k(0.905, nc * 1.1), lightSurfaceHi: k(0.865, nc * 1.2),
            lightOverlay:   k(0.735, nc * 1.6),
            lightFg:        k(0.255, nc * 1.4), lightFgDim:     k(0.420, nc * 1.3),
            // 0.540 y no más claro: es el punto donde el texto secundario
            // sobre fondo claro cruza el 4.5:1 de WCAG AA (a 0.560 se quedaba
            // en 4.21:1). En oscuro el equivalente ya iba sobrado.
            lightFgMuted:   k(0.540, nc * 1.2),
            lightAccent:    k(0.520, ac * 1.05),
            lightAccent2:   k(0.500, ac * 0.95, H(hue + 42)),
            lightCyan:      k(0.520, sc * 1.05, harm(195)), lightGreen:   k(0.510, sc * 1.05, harm(145)),
            lightYellow:    k(0.560, sc * 1.05, harm(105)), lightOrange:  k(0.540, sc * 1.05, harm(60)),
            lightRed:       k(0.480, sc * 1.15, harm(29)),  lightMagenta: k(0.500, sc * 1.05, harm(345)),
            hyprInactive: k(0.255, nc * 1.1), hyprShadow: k(0.130, nc * 0.8)
        }
    }
}
