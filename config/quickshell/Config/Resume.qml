pragma Singleton

import QtQuick
import Quickshell

// ─────────────────────────────────────────────────────────────
//  Coordinador de suspensión/reanudación.
//
//  logind emite la señal Manager.PrepareForSleep(true) justo antes de
//  suspender y (false) al despertar. shell.qml la capta reutilizando el
//  monitor de D-Bus que YA escucha org.freedesktop.login1 (el mismo del
//  bloqueo de sesión) y llama aquí a notify(); así hay UN ÚNICO punto de
//  detección en lugar de un monitor por servicio.
//
//  Se re-emite como dos señales limpias a las que los servicios se
//  suscriben para recuperarse tras el resume (WiFi, clima, brillo,
//  monitor de sistema, pantallas…), sin acoplar shell.qml a cada uno:
//
//      Connections {
//          target: Resume
//          function onResumed() { ...refrescar... }
//      }
//
//  REINTENTOS: al despertar, kernel/drivers/servicios (NetworkManager,
//  DDC/CI, Hyprland…) pueden NO estar listos en el primer instante, así
//  que resumed() no se emite una sola vez, sino en varias OLEADAS
//  ("pulsos de recuperación"). Cada refresco de servicio es idempotente
//  o coalesce (un curl/proceso en curso no se duplica), de modo que si el
//  primer intento falla —p. ej. la red aún no reconectó— un pulso
//  posterior lo consigue. Los servicios que solo quieren actuar una vez
//  filtran por `recoveryPulse === 1`.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ¿Creemos que el sistema está dormido ahora mismo?
    property bool sleeping: false

    signal aboutToSleep()   // justo antes de suspender
    signal resumed()        // tras despertar (uno o varios pulsos de recuperación)

    // Nº del pulso de recuperación en curso (1 = primero, 0 = fuera de ventana).
    // Permite a un servicio distinguir el primer resumed() de los reintentos.
    property int recoveryPulse: 0

    // Retardos ENTRE pulsos (ms). Primer pulso pronto para respuesta rápida;
    // los siguientes, espaciados, por si el hardware tarda en volver.
    readonly property var _pulseGaps: [700, 2500, 4500]   // → ~0.7 s, ~3.2 s, ~7.7 s
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
