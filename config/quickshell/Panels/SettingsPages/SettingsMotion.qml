pragma Singleton

import QtQuick
import Quickshell
import qs.Config

// Reloj de entrada de una página de Ajustes. Un ÚNICO escalar 0→1 que mueve la
// ventana (Panels/Settings.qml) al montar una página, y del que cada tarjeta
// deriva su propia entrada con un retardo según su orden.
//
// Va aquí y no en cada tarjeta porque una animación por tarjeta arrancaría
// cuando la tarjeta se construye, y el Loader de la página es ASÍNCRONO: las
// tarjetas nacen escalonadas por el incubador, antes de que la página se vea,
// así que la mitad del escalonamiento se habría consumido a oscuras. Con un
// reloj común, la posición de cada tarjeta es una FUNCIÓN del reloj: da igual
// cuándo se construyó, siempre entra en su turno.
Singleton {
    id: motion

    // 0 = página recién montada, 1 = página asentada. Lo escribe y anima
    // Panels/Settings.qml. Arranca en 1 para que una tarjeta creada fuera de
    // una transición (recarga en caliente, filtro) se vea sin más.
    property real pageEnter: 1

    // Retardo de cada tarjeta respecto a la anterior, en fracción del reloj.
    readonly property real stagger: 0.07
    // Cuánto del reloj dura la entrada de UNA tarjeta. stagger × maxDelayed +
    // ramp tiene que caber en 1: si no, la última tarjeta no llegaría a 1 y se
    // quedaría translúcida para siempre.
    readonly property real ramp: 0.62
    // A partir de aquí el retardo deja de crecer. Sin techo, una página de
    // ocho tarjetas repartiría el escalonamiento tan fino que las últimas
    // entrarían todas juntas de todos modos — y las primeras irían a tirones.
    readonly property int maxDelayed: 5

    // Entrada de la tarjeta número 'i': 0 (fuera) → 1 (colocada).
    // El escalonamiento NO es lineal: el smoothstep hace que cada tarjeta nazca
    // y aterrice suave, que es lo que separa un escalonamiento de una cascada
    // de cortes.
    function reveal(i) {
        const d = Math.min(Math.max(0, i), maxDelayed) * stagger
        const t = Math.max(0, Math.min(1, (pageEnter - d) / ramp))
        return t * t * (3 - 2 * t)
    }
}
