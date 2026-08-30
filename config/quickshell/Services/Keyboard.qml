pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Distribución de teclado activa en Hyprland, por dos vías porque ninguna basta
// sola: el evento `activelayout` avisa de cada cambio pero solo cuando ocurre, y
// `hyprctl devices -j` da el estado actual pero hay que pedirlo. Se consulta una
// vez al arrancar y a partir de ahí manda el evento.
Singleton {
    id: root

    // Nombre completo tal cual lo da Hyprland ("English (US)", "Spanish").
    property string layout: ""
    // Todas las distribuciones configuradas, para poder rotar entre ellas.
    property var layouts: []

    // "Hay algo que enseñar", que se sabe al poder leer el teclado. No se
    // pregunta por el socket de Hyprland, cuya API no está garantizada entre
    // versiones: sin Hyprland, 'hyprctl devices' falla y esto queda en false.
    readonly property bool available: layout !== ""
    readonly property bool multiple: layouts.length > 1

    // Etiqueta corta para la barra y el bloqueo. Hyprland da el nombre humano de
    // la distribución y no su código xkb, así que recortar dos letras da "SP"
    // para el español, que no es ningún código. La tabla cubre las habituales y
    // lo que no esté en ella cae al recorte, que sigue dando algo usable.
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
        // "English (US)" no está tal cual pero "english" sí, así que se prueba
        // también con lo que hay antes del paréntesis.
        const base = clave.split("(")[0].trim()
        if (root._codes[base])
            return root._codes[base]
        return root.layout.replace(/[^A-Za-zÀ-ÿ]/g, "").substring(0, 2).toUpperCase()
    }

    // Teclado principal: el primero que Hyprland marque como "main". Es al que
    // hay que dirigir el switchxkblayout, porque mandárselo a "all" conmuta
    // también ratones y otros dispositivos con teclas.
    property string mainDevice: ""

    // Se leen del LED en sysfs, que es la única vía fiable: Qt no expone el
    // estado de los modificadores fuera de un evento de tecla y `hyprctl
    // devices` no lo cuenta. Se leen todos los teclados y basta con que uno esté
    // encendido, porque con un teclado externo hay varios LED.
    //
    // Se sondea, y solo con la pantalla de bloqueo puesta: sysfs no avisa por
    // inotify de un cambio de brillo de LED, y fuera del bloqueo nadie lo mira.
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
        // 250 ms: por debajo no se gana nada perceptible y por encima el aviso
        // llega cuando ya se ha escrito mal.
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
        // El dispatch dispara 'activelayout', así que el refresco llega solo.
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
                    // 'layout' es la lista xkb separada por comas ("us,es") y
                    // no los nombres humanos: sirve para saber cuántas hay, que
                    // es lo único que necesita cycle().
                    const configured = String(main.layout || "")
                    root.layouts = configured === "" ? [] : configured.split(",").map(s => s.trim())
                } catch (e) {
                    console.warn("Keyboard: no se pudo leer 'hyprctl devices':", e)
                }
            }
        }
    }

    // activelayout>>NOMBRE_DEL_TECLADO,NOMBRE_DE_LA_DISTRIBUCIÓN. El nombre del
    // teclado puede llevar comas, así que se parte por la última.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Una recarga de config puede cambiar la lista de distribuciones y
            // 'activelayout' no lo cuenta: hay que volver a preguntar.
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
