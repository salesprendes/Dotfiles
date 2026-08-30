import QtQuick

// El motor de movimiento de la isla: un muelle amortiguado que integra la FORMA
// entera —ancho, alto y los dos radios— hacia un objetivo.
//
// POR QUÉ UN MUELLE Y NO `Behavior on width`. Una transición con curva tiene
// una duración fija: le da igual de dónde venga. Si la isla está a medio
// expandirse y llega una notificación, la curva reinicia y el movimiento se
// parte por la mitad — se ve como un tirón. Un muelle no se reinicia nunca:
// conserva la VELOCIDAD que ya llevaba, así que un cambio de objetivo a mitad
// de camino se curva y sigue. Es lo que hace que la isla parezca una sola cosa
// que se mueve, en vez de varias animaciones peleándose.
//
// Y va SUBAMORTIGUADO a propósito. Con k=560 y m=1 el amortiguamiento crítico
// serían 47,3; aquí es 34. O sea que se pasa un pelín del destino y vuelve.
// Ese rebote de un par de píxeles es toda la diferencia entre "una caja que
// cambia de tamaño" y la sensación de isla.
//
// CUATRO DIMENSIONES, no ocho. La referencia (DankMaterialShell) integra
// además dos desplazamientos y los cuatro radios por separado. Aquí la isla
// siempre está centrada y pegada a su borde, así que los desplazamientos son
// constantes, y las esquinas son simétricas a izquierda y derecha: bastan un
// radio "cerca" (el lado del borde de pantalla) y otro "lejos". Importa porque
// este shell arranca con el JIT de QV4 apagado (ver shell.qml) y esto se
// integra en cada fotograma: la mitad de dimensiones es la mitad de trabajo en
// un intérprete, a 144 Hz.
QtObject {
    id: root

    // ── Parámetros del muelle ────────────────────────────────────────────────
    property real stiffness: 560
    property real damping: 34
    property real mass: 1

    // Sin animaciones (Ajustes ▸ Tema ▸ Velocidad = ninguna): el muelle se
    // salta y la forma salta al destino. No se apaga el componente entero
    // porque la forma la sigue publicando él.
    property bool reducedMotion: false

    // ── Estado ───────────────────────────────────────────────────────────────
    property real width: 200
    property real height: 36
    property real radiusNear: 18
    property real radiusFar: 18

    property real targetWidth: width
    property real targetHeight: height
    property real targetRadiusNear: radiusNear
    property real targetRadiusFar: radiusFar

    property real velocityWidth: 0
    property real velocityHeight: 0
    property real velocityRadiusNear: 0
    property real velocityRadiusFar: 0

    property bool running: false

    // Umbrales de reposo. Por debajo de un tercio de píxel no se ve nada y en
    // cambio mantiene vivo un FrameAnimation a 144 Hz para siempre: el muelle
    // matemáticamente nunca llega, solo se acerca.
    readonly property real positionEpsilon: 0.3
    readonly property real velocityEpsilon: 0.3

    // Techo del paso de integración. Si el shell se queda atascado un segundo
    // (una recarga de configuración, un pico de CPU), el fotograma siguiente
    // trae un delta enorme y el muelle explota: la fuerza se integra contra un
    // tiempo que no existió. Acotándolo a 1/30 s, lo peor que pasa es que el
    // movimiento se ve a saltos.
    readonly property real maxFrameTime: 1 / 30
    // Subpaso fijo: la estabilidad de un integrador de Euler depende del paso,
    // no del fotograma. Sin esto, un muelle rígido a 60 Hz oscila y a 144 no.
    readonly property real integrationStep: 1 / 240

    function setTarget(w, h, rNear, rFar) {
        if (targetWidth === w && targetHeight === h
            && targetRadiusNear === rNear && targetRadiusFar === rFar)
            return
        targetWidth = w
        targetHeight = h
        targetRadiusNear = rNear
        targetRadiusFar = rFar
        if (reducedMotion) {
            snap()
            return
        }
        running = true
    }

    // Coloca la forma sin movimiento. Se usa al nacer (la isla no debe entrar
    // creciendo desde cero la primera vez) y sin animaciones.
    function snap() {
        width = targetWidth
        height = targetHeight
        radiusNear = targetRadiusNear
        radiusFar = targetRadiusFar
        velocityWidth = 0
        velocityHeight = 0
        velocityRadiusNear = 0
        velocityRadiusFar = 0
        running = false
    }

    function settled() {
        return Math.abs(targetWidth - width) <= positionEpsilon
            && Math.abs(targetHeight - height) <= positionEpsilon
            && Math.abs(targetRadiusNear - radiusNear) <= positionEpsilon
            && Math.abs(targetRadiusFar - radiusFar) <= positionEpsilon
            && Math.abs(velocityWidth) <= velocityEpsilon
            && Math.abs(velocityHeight) <= velocityEpsilon
            && Math.abs(velocityRadiusNear) <= velocityEpsilon
            && Math.abs(velocityRadiusFar) <= velocityEpsilon
    }

    // Euler semi-implícito: se actualiza la velocidad con la posición VIEJA y
    // la posición con la velocidad NUEVA. Es una línea de diferencia con el
    // Euler explícito y es la que hace que el sistema no gane energía sola —
    // con el explícito, un muelle rígido se va amplificando hasta reventar.
    function advance(frameTime) {
        if (!running || reducedMotion)
            return
        const dt = Math.min(Math.max(frameTime, 0), maxFrameTime)
        if (dt <= 0)
            return

        const steps = Math.max(1, Math.ceil(dt / integrationStep))
        const h = dt / steps
        const invMass = 1 / Math.max(0.001, mass)
        const k = stiffness
        const c = damping

        // Las cuatro dimensiones se leen a locales y se devuelven al final: en
        // QML cada escritura a una propiedad notifica a quien la observe, y
        // aquí hay hasta ocho subpasos por fotograma. Escribiendo dentro del
        // bucle, la forma se recalcularía ocho veces por fotograma para pintar
        // una.
        let w = root.width, vw = root.velocityWidth
        let ht = root.height, vh = root.velocityHeight
        let rn = root.radiusNear, vrn = root.velocityRadiusNear
        let rf = root.radiusFar, vrf = root.velocityRadiusFar
        const tw = root.targetWidth, th = root.targetHeight
        const trn = root.targetRadiusNear, trf = root.targetRadiusFar

        for (let i = 0; i < steps; i++) {
            vw += (k * (tw - w) - c * vw) * invMass * h
            vh += (k * (th - ht) - c * vh) * invMass * h
            vrn += (k * (trn - rn) - c * vrn) * invMass * h
            vrf += (k * (trf - rf) - c * vrf) * invMass * h
            w += vw * h
            ht += vh * h
            rn += vrn * h
            rf += vrf * h
        }

        root.width = w
        root.velocityWidth = vw
        root.height = ht
        root.velocityHeight = vh
        root.radiusNear = rn
        root.velocityRadiusNear = vrn
        root.radiusFar = rf
        root.velocityRadiusFar = vrf

        if (settled())
            snap()
    }

    onReducedMotionChanged: if (reducedMotion) snap()

    // FrameAnimation y no un Timer: se sincroniza con el repintado y da el
    // tiempo REAL entre fotogramas, que es lo que necesita el integrador. Un
    // Timer a 16 ms miente en cuanto el sistema va justo, y el muelle
    // integraría contra un tiempo que no ha pasado.
    readonly property FrameAnimation _clock: FrameAnimation {
        running: root.running && !root.reducedMotion
        onTriggered: root.advance(frameTime)
    }
}
