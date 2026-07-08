pragma Singleton

import QtQuick
import Quickshell

// Coordinador de suspensión/reanudación. shell.qml capta el
// PrepareForSleep de logind (reusando el monitor de D-Bus del bloqueo de
// sesión) y llama a notify(), así hay un único punto de detección.
// Reemite aboutToSleep()/resumed() y los servicios se suscriben para
// recuperarse tras el resume (WiFi, clima, brillo, sysmon, pantallas).
//
// Al despertar, drivers y servicios pueden no estar listos aún, así que
// resumed() se emite en varias oleadas (pulsos de recuperación) con
// retardos crecientes. Los refrescos son idempotentes/coalesce, de modo
// que si el primer intento falla (p. ej. la red aún no reconectó) un pulso
// posterior lo consigue. Para actuar una sola vez, filtra por
// recoveryPulse === 1.
Singleton {
    id: root

    // ¿Está dormido el sistema ahora mismo?
    property bool sleeping: false

    signal aboutToSleep()   // justo antes de suspender
    signal resumed()        // tras despertar (uno o varios pulsos de recuperación)

    // Nº del pulso de recuperación en curso (1 = primero, 0 = fuera de ventana).
    // Permite a un servicio distinguir el primer resumed() de los reintentos.
    property int recoveryPulse: 0

    // Retardos entre pulsos (ms). El primero pronto; los siguientes
    // espaciados, por si el hardware tarda en volver.
    readonly property var _pulseGaps: [700, 2500, 4500]   // acumulado ~0.7s, ~3.2s, ~7.7s
    property int _pulseIndex: 0

    // Punto de entrada llamado desde shell.qml con el booleano de PrepareForSleep.
    function notify(goingToSleep) {
        if (goingToSleep) {
            root.sleeping = true
            pulseTimer.stop()
            root._pulseIndex = 0
            root.recoveryPulse = 0
            root.aboutToSleep()
        } else if (root.sleeping) {
            // Solo tratamos como "resume" si de verdad veníamos de dormir, para
            // ignorar un (false) suelto o duplicado sin su (true) previo.
            root.sleeping = false
            root._pulseIndex = 0
            pulseTimer.interval = root._pulseGaps[0]
            pulseTimer.restart()
        }
    }

    Timer {
        id: pulseTimer
        repeat: false
        onTriggered: {
            root.recoveryPulse = root._pulseIndex + 1
            root.resumed()
            root._pulseIndex++
            if (root._pulseIndex < root._pulseGaps.length) {
                pulseTimer.interval = root._pulseGaps[root._pulseIndex]
                pulseTimer.restart()
            } else {
                root.recoveryPulse = 0   // fin de la ventana de recuperación
            }
        }
    }
}
