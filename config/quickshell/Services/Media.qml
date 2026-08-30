pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Reproductor activo, y la única respuesta del shell a "¿hay algo sonando?".
//
// Un navegador registra su reproductor MPRIS mientras viva el navegador, no
// mientras suene algo, así que deja un reproductor fantasma: existe, con estado
// Stopped y sin metadatos, pero no hay nada detrás. Elegir con "si nadie
// reproduce, coge el primero" se queda clavado en ese fantasma.
//
// La pregunta no es "¿hay un reproductor?" sino "¿hay algo que controlar?":
//
//   · Reproduciendo         → sí, aunque no traiga metadatos.
//   · En pausa CON metadatos → sí; la pausa es deliberada y se querrá reanudar.
//   · Parado                → no, tenga los metadatos que tenga.
//   · En pausa sin metadatos → no. Es el fantasma del navegador.
//
// Los metadatos son lo que distingue una pausa de verdad del fantasma, que
// nunca tiene ni título ni artista.
//
// Vive en un singleton para que la barra y el Dashboard no puedan dar dos
// respuestas distintas a la misma pregunta.
Singleton {
    id: root

    // Todo lo que hay en el bus, fantasmas incluidos.
    readonly property var all: Mpris.players?.values ?? []

    // ¿Hay algo detrás de este reproductor? Ver la regla de la cabecera.
    function isLive(p) {
        if (!p)
            return false
        if (p.playbackState === MprisPlaybackState.Playing)
            return true
        if (p.playbackState !== MprisPlaybackState.Paused)
            return false
        return (p.trackTitle || "") !== "" || (p.trackArtist || "") !== ""
    }

    // Los que de verdad cuentan, y la lista que ve el selector del Dashboard:
    // ofrecer cambiar a un fantasma sería ofrecer cambiar a nada.
    //
    // El filtro lee playbackState, trackTitle y trackArtist, así que QML los
    // apunta como dependencia y la lista se recalcula sola cuando uno empieza a
    // sonar o se para.
    readonly property var players: {
        const out = []
        for (const p of root.all)
            if (root.isLive(p))
                out.push(p)
        return out
    }

    // El elegido: el que esté sonando y, si ninguno suena, el primero en pausa.
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
