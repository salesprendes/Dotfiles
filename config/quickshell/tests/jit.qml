import QtQuick
import Quickshell
import qs.Config
import qs.Modules.Island
import qs.Services

// Prueba de esfuerzo del JIT. La lanza tests/jit.py; ver su cabecera para el
// porqué. Aquí solo se machacan los patrones donde el motor se caía con Qt
// 6.11.1, hasta pasar de largo el umbral a partir del cual el JIT decide
// compilar una función.
ShellRoot {
    id: suite

    readonly property int segundos: {
        const v = parseInt(Quickshell.env("QS_JIT_SECONDS") ?? "25", 10)
        return isFinite(v) && v > 0 ? v : 25
    }

    property int vueltas: 0
    property int checksum: 0

    // El muelle de la isla: es el bucle más caliente de todo el shell, porque
    // integra en CADA fotograma. Aquí se le hace avanzar a mano miles de veces
    // seguidas, que es como se llega al umbral del JIT en segundos en vez de
    // en horas de uso.
    readonly property IslandSpring muelle: IslandSpring {}

    // Los patrones que se caían: 'property var' con objetos dentro,
    // reevaluados una y otra vez.
    function vuelta() {
        // 1) Layout de barra: clonar, mover, sanear. Objetos y arrays nuevos
        //    en cada pasada, que es lo que hacía trabajar al recolector a la
        //    vez que el JIT — la combinación donde saltaba el fallo.
        let layout = BarCatalog.defaultLayout()
        layout = BarCatalog.move(layout, "right", 0, "left", 1)
        layout = BarCatalog.add(layout, "spacer", "right")
        layout = BarCatalog.sanitize(layout)
        suite.checksum += BarCatalog.entriesOf(layout, "left").length

        // 2) Migración de ajustes sobre un objeto crudo distinto cada vez.
        const viejo = { showTray: (suite.vueltas % 2) === 0, showAi: true }
        Settings.migrate(viejo)
        suite.checksum += BarCatalog.has(viejo.barLayout, "tray") ? 1 : 0

        // 3) Estado de la isla: cola de notificaciones (array de objetos que
        //    entra y sale) y niveles.
        IslandState.pushNotification({ urgency: suite.vueltas % 3,
                                       summary: "s" + suite.vueltas })
        IslandState.showLevel("volume", (suite.vueltas % 100) / 100, false)
        IslandState.dismissNotification()
        suite.checksum += IslandState.notifQueue.length

        // 4) El integrador del muelle, con objetivos que cambian: es lo que
        //    hará la isla de verdad, fotograma tras fotograma.
        suite.muelle.setTarget(200 + (suite.vueltas % 200), 32 + (suite.vueltas % 300), 16, 24)
        for (let i = 0; i < 12; i++)
            suite.muelle.advance(1 / 144)
        suite.checksum += Math.round(suite.muelle.width)

        // 5) El buscador de emojis: filtra 2.500 objetos contra una consulta
        //    distinta cada vez. Bucle largo sobre 'property var' = comida de JIT.
        if (suite.vueltas % 20 === 0) {
            Emoji.load()
            Emoji.query = "a" + (suite.vueltas % 7)
            suite.checksum += Emoji.filtered.length
        }

        suite.vueltas++
    }

    readonly property Timer _motor: Timer {
        interval: 1
        repeat: true
        running: true
        onTriggered: {
            // Tandas de 40: con una vuelta por disparo, el temporizador manda
            // más que el trabajo y no se llega al umbral del JIT en un tiempo
            // razonable.
            for (let i = 0; i < 40; i++)
                suite.vuelta()
        }
    }

    readonly property Timer _final: Timer {
        interval: suite.segundos * 1000
        running: true
        onTriggered: {
            suite._motor.running = false
            // Y ahora la medida de VELOCIDAD, que es distinta de la de
            // estabilidad: trabajo fijo, cronometrado. El bucle de arriba lo
            // marca el temporizador, así que su contador sale igual con JIT y
            // sin él — solo dice si el motor aguanta. Esto dice cuánto corre.
            const t0 = Date.now()
            let acc = 0
            for (let i = 0; i < 40000; i++) {
                suite.muelle.advance(1 / 144)
                acc += suite.muelle.width
                if ((i & 63) === 0)
                    suite.muelle.setTarget(120 + (i % 400), 32 + (i % 200), 16, 24)
            }
            const ms = Date.now() - t0

            // El mismo trabajo en JS puro, dentro de UNA sola llamada.
            //
            // Y aquí está el hallazgo, que no es el que uno esperaría: este
            // número NO cambia entre JIT e intérprete (142 ms contra 143). El
            // de arriba sí (67 contra 80). La razón es que QV4 compila POR
            // FUNCIÓN y según cuántas veces se ha LLAMADO, y no tiene
            // reemplazo en pila: un bucle de dos millones de vueltas metido en
            // una única llamada nunca llega a compilarse, porque cuando el
            // motor podría decidirlo ya está dentro. `advance()`, en cambio, se
            // llama cuarenta mil veces, cruza el umbral y se compila.
            //
            // O sea: el JIT no premia los bucles largos, premia las funciones
            // MUY LLAMADAS. Que es exactamente la forma del muelle de la isla
            // —una llamada por fotograma, para siempre— y por eso quitar el
            // pragma le viene bien justo a lo que se acaba de construir.
            const t1 = Date.now()
            let w = 200, vw = 0, acc2 = 0
            for (let i = 0; i < 2000000; i++) {
                const tw = 120 + (i & 255)
                vw += (560 * (tw - w) - 34 * vw) * (1 / 240)
                w += vw * (1 / 240)
                acc2 += w
            }
            console.warn("JIT BANCO JS PURO: 2000000 pasos en "
                         + (Date.now() - t1) + " ms (acc " + Math.round(acc2) + ")")
            console.warn("JIT BANCO: 40000 pasos de muelle en " + ms
                         + " ms (acc " + Math.round(acc) + ")")
            console.warn("JIT FIN: " + suite.vueltas + " vueltas, checksum "
                         + suite.checksum + ", el motor sigue en pie")
        }
    }

    Component.onCompleted: console.warn("JIT arrancando, "
                                        + suite.segundos + " s de machaque")
}
