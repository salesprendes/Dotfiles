pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Reproductor activo, y la única respuesta del shell a "¿hay algo sonando?".
//
// EL PROBLEMA QUE RESUELVE. Un navegador registra su reproductor MPRIS
// mientras el NAVEGADOR viva, no mientras suene algo. Brave, con el navegador
// abierto y nada reproduciéndose, se presenta así:
//
//     identity="Brave"  playbackState=Stopped  isPlaying=false
//     trackTitle=""  trackArtist=""  canPlay=false  canTogglePlaying=false
//
// Es un reproductor fantasma: existe, pero no hay nada detrás. La barra y el
// Dashboard elegían con `si nadie está reproduciendo, coge players[0]`, así que
// se quedaban clavados en ese fantasma — la píldora del reproductor no se iba
// nunca y el Dashboard enseñaba una tarjeta «Sin título» permanente.
//
// LA REGLA. No se pregunta "¿hay un reproductor?" sino "¿hay algo que
// controlar?":
//
//   · Reproduciendo         → sí, aunque no traiga metadatos (algo suena y
//                             quieres el botón de pausa a mano).
//   · En pausa CON metadatos → sí (pausaste tú; querrás reanudar).
//   · Parado                → no, tenga los metadatos que tenga.
//   · En pausa sin metadatos → no. Es el fantasma del navegador.
//
// El "con metadatos" del caso en pausa es lo que distingue una pausa de verdad
// del fantasma: el fantasma nunca tiene ni título ni artista.
//
// Vive en un singleton y no en cada consumidor porque estaba escrito dos veces
// —Bar/MediaWidget.qml y Panels/Dashboard.qml— y las dos copias ya habían
// divergido: la barra exigía metadatos y el Dashboard se conformaba con que
// existiera un reproductor. Dos respuestas distintas a la misma pregunta.
Singleton {
    id: root

    // Todo lo que hay en el bus, fantasmas incluidos.
    readonly property var all: Mpris.players?.values ?? []

    // ¿Hay algo detrás de este reproductor? Ver la regla de arriba.
    function isLive(p) {
        if (!p)
            return false
        if (p.playbackState === MprisPlaybackState.Playing)
            return true
        if (p.playbackState !== MprisPlaybackState.Paused)
            return false
        return (p.trackTitle || "") !== "" || (p.trackArtist || "") !== ""
    }

    // Los que de verdad cuentan. Es esta lista —y no 'all'— la que ve el
    // selector de reproductores del Dashboard: ofrecer cambiar a un fantasma
    // sería ofrecer cambiar a nada.
    //
    // El filtro LEE playbackState, trackTitle y trackArtist de cada
    // reproductor, así que QML apunta esas propiedades como dependencia y la
    // lista se recalcula sola en cuanto uno empieza a sonar o se para. No hace
    // falta ninguna señal a mano.
    readonly property var players: {
        const out = []
        for (const p of root.all)
            if (root.isLive(p))
                out.push(p)
        return out
    }

    // El elegido: el que esté sonando; si ninguno suena, el primero en pausa.
    readonly property var active: {
        const live = root.players
        for (const p of live)
            if (p.isPlaying)
                return p
        return live.length > 0 ? live[0] : null
    }

    readonly property bool hasMedia: root.active !== null
    readonly property bool playing: root.active?.isPlaying ?? false
}
