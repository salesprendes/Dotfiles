pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Actualizaciones pendientes del sistema (Arch): paquetes de los repos y, si
// hay ayudante de AUR, también los del AUR.
Singleton {
    id: root

    // ── De dónde sale la cuenta ──────────────────────────────────────────────
    //
    // Dos fuentes, y se suman: una para los repos de pacman y otra para el AUR.
    //
    // REPOS. Dos comandos posibles, y la diferencia entre ellos es la FRESCURA,
    // no el riesgo:
    //   · `checkupdates` (paquete pacman-contrib) sincroniza contra una copia
    //     TEMPORAL de la base de datos, así que da la cuenta real del momento
    //     sin necesitar root y sin tocar /var/lib/pacman/sync.
    //   · `pacman -Qu` es una consulta puramente LOCAL: compara lo instalado
    //     contra la base de datos sincronizada que ya haya en el disco. No
    //     necesita root ni escribe nada — el comando peligroso es `pacman -Sy`,
    //     que sí toca la base de datos y deja el sistema "sincronizado a
    //     medias"; ese no se usa aquí ni con checkupdates ni sin él. Lo único
    //     que pasa sin checkupdates es que la cuenta puede ir vieja: si hace
    //     tres días que no sincronizas, cuenta lo de hace tres días.
    //
    // AUR. `paru`/`yay` con `-Qua`, que lista SOLO los del AUR. Se pide con la
    // 'a' a propósito: su `-Qu` a secas incluye también los repos y se sumaría
    // dos veces con la cuenta de arriba.
    //
    // Con esto el widget funciona en cualquier Arch sin instalar nada: pacman
    // siempre está. checkupdates y un ayudante de AUR solo lo afinan.
    readonly property bool hasCheckupdates: Deps.has("checkupdates")
    readonly property string aurHelper: Deps.has("paru") ? "paru"
                                      : Deps.has("yay") ? "yay" : ""
    readonly property bool available: Deps.has("pacman") || hasCheckupdates

    property int repoCount: 0
    property int aurCount: 0
    readonly property int count: repoCount + aurCount

    property bool checking: false
    property bool ready: false
    // Lista legible "paquete versión→versión", para el tooltip/panel.
    property var packages: []

    // Cada cuánto se mira, en minutos. Media hora: lo bastante para enterarse
    // el mismo día y lo bastante poco para no castigar la red ni el mirror.
    property int refreshMinutes: 30

    function refresh() {
        if (!available || repoProc.running || aurProc.running)
            return
        root.checking = true
        repoProc.running = true
    }

    // Abre el terminal preferido con la actualización en marcha. Con ayudante
    // de AUR se actualiza todo de una pasada; sin él, pacman a secas.
    function runUpdate() {
        const cmd = aurHelper !== "" ? (aurHelper + " -Syu") : "sudo pacman -Syu"
        const term = Settings.terminalApp !== "" ? Settings.terminalApp : "kitty"
        // `-e` es la bandera de "ejecuta esto" en kitty, alacritty, foot,
        // wezterm y ghostty. El `read` final deja la ventana abierta para ver
        // el resultado en vez de cerrarse en la cara del usuario.
        Quickshell.execDetached([term, "-e", "sh", "-c",
            cmd + "; printf '\\n[Enter] para cerrar '; read _"])
    }

    Process {
        id: repoProc
        // Los dos comandos salen con código != 0 cuando NO hay nada pendiente
        // (checkupdates con 2, pacman -Qu con 1). Eso no es un error, así que
        // el `true` final lo normaliza para que Process no lo trate como fallo.
        command: ["sh", "-c",
            (root.hasCheckupdates ? "checkupdates" : "pacman -Qu") + " 2>/dev/null; true"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const lines = String(this.text || "").split("\n")
                    .map(l => l.trim()).filter(l => l !== "")
                root.repoCount = lines.length
                root.packages = lines
                // Encadenado, no en paralelo: el ayudante de AUR toma el mismo
                // bloqueo de la base de datos, y lanzarlos a la vez hace que
                // uno de los dos espere o falle.
                if (root.aurHelper !== "") {
                    aurProc.running = true
                    return
                }
                root.aurCount = 0
                root.checking = false
                root.ready = true
            }
        }
        onExited: {
            // Si el proceso murió sin llegar a emitir stdout, se cierra el
            // estado igualmente para no dejar el widget girando para siempre.
            if (root.checking && root.aurHelper === "") {
                root.checking = false
                root.ready = true
            }
        }
    }

    Process {
        id: aurProc
        // -Qua: SOLO el AUR. Los repos ya los ha contado repoProc.
        command: ["sh", "-c",
            (root.aurHelper !== "" ? root.aurHelper : "true") + " -Qua 2>/dev/null; true"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const lines = String(this.text || "").split("\n")
                    .map(l => l.trim()).filter(l => l !== "")
                root.aurCount = lines.length
                root.packages = root.packages.concat(lines)
            }
        }
        onExited: {
            root.checking = false
            root.ready = true
        }
    }

    // Solo se sondea si el widget está puesto en la barra. Sin él, mirar
    // actualizaciones cada media hora es tráfico de red que nadie ve.
    readonly property bool wanted: BarCatalog.has(Settings.barLayout, "updates")

    Timer {
        interval: Math.max(5, root.refreshMinutes) * 60 * 1000
        running: root.wanted && root.available
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Tras el resume la red suele tardar; el primer pulso puede fallar y el
    // temporizador normal tardaría media hora en reintentarlo, así que se
    // aprovecha la última oleada de recuperación, cuando ya hay conectividad.
    Connections {
        target: Resume
        function onResumed() {
            if (Resume.recoveryPulse === 3 && root.wanted)
                root.refresh()
        }
    }
}
