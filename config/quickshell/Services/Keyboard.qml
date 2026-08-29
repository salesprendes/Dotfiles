pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Distribución de teclado activa en Hyprland.
//
// Dos vías, porque ninguna basta sola:
//   · El evento `activelayout` de Hyprland avisa de CADA cambio, pero solo
//     cuando ocurre: al arrancar el shell no se ha emitido ninguno todavía.
//   · `hyprctl devices -j` da el estado actual, pero es una foto: hay que
//     pedirla, no llega sola.
// Así que se consulta una vez al arrancar y a partir de ahí manda el evento.
Singleton {
    id: root

    // Nombre completo tal cual lo da Hyprland ("English (US)", "Spanish").
    property string layout: ""
    // Todas las distribuciones configuradas, para poder rotar entre ellas.
    property var layouts: []

    // "Hay algo que enseñar": se sabe cuando se ha podido leer el teclado.
    // No se pregunta por el socket de Hyprland (API no garantizada entre
    // versiones); si no hay Hyprland, 'hyprctl devices' falla y esto se queda
    // en false, que es exactamente lo que hace falta.
    readonly property bool available: layout !== ""
    readonly property bool multiple: layouts.length > 1

    // Etiqueta corta para la barra y el bloqueo.
    //
    // Hyprland da el nombre HUMANO de la distribución ("Spanish", "English
    // (US)"), no su código xkb, y cortar las dos primeras letras da "SP" para
    // el español — que no es ningún código y confunde más que ayuda. Así que
    // hay una tabla de los nombres habituales, y solo lo que no esté en ella
    // cae al recorte de dos letras.
    //
    // La tabla no pretende ser completa —son cientos de distribuciones— sino
    // acertar en las que alguien de verdad va a tener configuradas a la vez.
    // Lo que no reconozca sigue dando una etiqueta usable, solo que menos
    // canónica.
    readonly property var _codes: ({
        "english": "EN", "english (us)": "EN", "english (uk)": "GB",
        "spanish": "ES", "spanish (latin american)": "LA",
        "catalan": "CA", "galician": "GL", "basque": "EU",
        "french": "FR", "french (canada)": "CA", "german": "DE",
        "italian": "IT", "portuguese": "PT", "portuguese (brazil)": "BR",
        "dutch": "NL", "swedish": "SE", "norwegian": "NO", "danish": "DK",
        "finnish": "FI", "polish": "PL", "czech": "CZ", "slovak": "SK",
        "hungarian": "HU", "romanian": "RO", "greek": "GR", "turkish": "TR",
        "russian": "RU", "ukrainian": "UA", "bulgarian": "BG",
        "arabic": "AR", "hebrew": "IL", "japanese": "JP", "korean": "KR",
        "chinese": "CN", "swiss": "CH", "belgian": "BE", "icelandic": "IS",
        "estonian": "EE", "latvian": "LV", "lithuanian": "LT",
        "croatian": "HR", "serbian": "RS", "slovenian": "SI"
    })

    readonly property string short: {
        if (root.layout === "")
            return ""
        const clave = root.layout.toLowerCase().trim()
        const exacto = root._codes[clave]
        if (exacto)
            return exacto
        // "English (US)" no está tal cual, pero "english" sí: se prueba también
        // con lo que hay antes del paréntesis.
        const base = clave.split("(")[0].trim()
        if (root._codes[base])
            return root._codes[base]
        return root.layout.replace(/[^A-Za-zÀ-ÿ]/g, "").substring(0, 2).toUpperCase()
    }

    // Teclado principal: el primero que Hyprland marque como "main". Es al que
    // hay que dirigir el switchxkblayout; mandárselo a "all" también conmuta
    // ratones y otros dispositivos con teclas, que no es lo que se quiere.
    property string mainDevice: ""

    // ── Bloq Mayús y Bloq Núm ────────────────────────────────────────────────
    // Se leen del LED en sysfs (/sys/class/leds/*::capslock/brightness). Es la
    // única vía fiable: Qt no expone el estado de los modificadores fuera de un
    // evento de tecla, y `hyprctl devices` no lo cuenta. Se leen TODOS los
    // teclados y basta con que uno esté encendido — con un teclado externo
    // enchufado hay varios LED y el estado es del que estés usando.
    //
    // Se SONDEA, y solo mientras la pantalla de bloqueo está puesta: sysfs no
    // avisa por inotify de un cambio de brillo de LED, así que no hay forma de
    // que llegue solo. Fuera del bloqueo nadie lo mira, y estar leyendo un
    // archivo cuatro veces por segundo toda la sesión para nada no tiene
    // ninguna gracia.
    property bool capsLock: false
    property bool numLock: false

    // Quien quiera el estado enciende esto. Hoy solo la pantalla de bloqueo.
    readonly property bool watchLocks: Lock.locked

    Process {
        id: ledProc
        command: ["sh", "-c",
            "grep -qs '[1-9]' /sys/class/leds/*::capslock/brightness && echo CAPS; "
            + "grep -qs '[1-9]' /sys/class/leds/*::numlock/brightness && echo NUM; true"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const out = String(this.text || "")
                root.capsLock = out.indexOf("CAPS") !== -1
                root.numLock = out.indexOf("NUM") !== -1
            }
        }
    }

    Timer {
        // 250 ms: por debajo de eso no se gana nada perceptible y por encima el
        // aviso llega tarde — pulsas Bloq Mayús, escribes, y el aviso aparece
        // cuando ya te has equivocado.
        interval: 250
        running: root.watchLocks
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!ledProc.running) ledProc.running = true
    }

    function cycle() {
        if (!multiple || mainDevice === "")
            return
        Hyprland.dispatch(Hyprland.usingLua
            ? "hl.dsp.switchxkblayout({ device = \"" + mainDevice + "\", cmd = \"next\" })"
            : "switchxkblayout " + mainDevice + " next")
        // El dispatch dispara 'activelayout', así que no hace falta refrescar
        // a mano: llegará solo.
    }

    function refresh() {
        if (!devicesProc.running)
            devicesProc.running = true
    }

    Process {
        id: devicesProc
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text || "{}")
                    const keyboards = Array.isArray(data.keyboards) ? data.keyboards : []
                    let main = null
                    for (const k of keyboards)
                        if (k && k.main === true) { main = k; break }
                    if (!main && keyboards.length > 0)
                        main = keyboards[0]
                    if (!main)
                        return
                    root.mainDevice = String(main.name || "")
                    root.layout = String(main.active_keymap || "")
                    // 'layout' del teclado es la lista xkb separada por comas
                    // ("us,es"), no los nombres humanos: sirve para saber
                    // CUÁNTAS hay, que es lo único que necesita cycle().
                    const configured = String(main.layout || "")
                    root.layouts = configured === "" ? [] : configured.split(",").map(s => s.trim())
                } catch (e) {
                    console.warn("Keyboard: no se pudo leer 'hyprctl devices':", e)
                }
            }
        }
    }

    // activelayout>>NOMBRE_DEL_TECLADO,NOMBRE_DE_LA_DISTRIBUCIÓN
    // El nombre del teclado puede llevar comas, así que se parte por la
    // ÚLTIMA: la distribución es lo que va detrás de la última coma.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Una recarga de config puede cambiar la lista de distribuciones,
            // y 'activelayout' no lo cuenta: hay que volver a preguntar.
            if (event.name === "configreloaded") {
                root.refresh()
                return
            }
            if (event.name !== "activelayout")
                return
            const data = String(event.data || "")
            const cut = data.lastIndexOf(",")
            if (cut === -1)
                return
            root.layout = data.substring(cut + 1)
            const device = data.substring(0, cut)
            if (root.mainDevice === "")
                root.mainDevice = device
        }

    }

    Component.onCompleted: refresh()
}
