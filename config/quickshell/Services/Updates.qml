pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Actualizaciones pendientes del sistema: paquetes de los repos y, si hay
// ayudante de AUR, también los del AUR.
Singleton {
    id: root

    // Dos fuentes que se suman: los repos de pacman y el AUR.
    //
    // En los repos la diferencia entre los dos comandos posibles es la frescura,
    // no el riesgo. `checkupdates` sincroniza contra una copia temporal de la
    // base de datos, así que da la cuenta del momento sin root y sin tocar
    // /var/lib/pacman/sync. `pacman -Qu` es una consulta puramente local contra
    // la base ya sincronizada en disco: tampoco necesita root ni escribe nada,
    // solo que la cuenta puede ir vieja. El comando que sí tocaría la base de
    // datos, `pacman -Sy`, no se usa aquí en ningún caso.
    //
    // En el AUR se pide con `-Qua`, que lista solo los del AUR: su `-Qu` a secas
    // incluiría también los repos y se sumarían dos veces.
    //
    // Con esto el widget funciona sin instalar nada, porque pacman siempre está;
    // checkupdates y un ayudante de AUR solo lo afinan.
    readonly property bool hasCheckupdates: Deps.has("checkupdates")
    readonly property string aurHelper: Deps.has("paru") ? "paru"
                                      : Deps.has("yay") ? "yay" : ""
    readonly property bool available: Deps.has("pacman") || hasCheckupdates

    property int repoCount: 0
    property int aurCount: 0
    readonly property int count: repoCount + aurCount

    property bool checking: false
    property bool ready: false
    // Lista legible "paquete versión→versión", para el tooltip y el panel.
    property var packages: []

    // Cada cuánto se mira, en minutos: lo bastante para enterarse el mismo día
    // y lo bastante poco para no castigar la red ni el mirror.
    property int refreshMinutes: 30

    function refresh() {
        if (!available || repoProc.running || aurProc.running)
            return
        root.checking = true
        repoProc.running = true
    }

    // Abre el terminal preferido con la actualización en marcha: con ayudante de
    // AUR se actualiza todo de una pasada, y sin él, pacman a secas.
    function runUpdate() {
        const cmd = aurHelper !== "" ? (aurHelper + " -Syu") : "sudo pacman -Syu"
        const term = Settings.terminalApp !== "" ? Settings.terminalApp : "kitty"
        // `-e` es la bandera de "ejecuta esto" en los terminales soportados. El
        // `read` final deja la ventana abierta para ver el resultado.
        Quickshell.execDetached([term, "-e", "sh", "-c",
            cmd + "; printf '\\n[Enter] para cerrar '; read _"])
    }

    Process {
        id: repoProc
        // Los dos comandos salen con código distinto de 0 cuando no hay nada
        // pendiente. Eso no es un error, así que el `true` final lo normaliza
        // para que Process no lo trate como fallo.
        command: ["sh", "-c",
            (root.hasCheckupdates ? "checkupdates" : "pacman -Qu") + " 2>/dev/null; true"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const lines = String(this.text || "").split("\n")
                    .map(l => l.trim()).filter(l => l !== "")
                root.repoCount = lines.length
                root.packages = lines
                // Encadenado y no en paralelo: el ayudante de AUR toma el mismo
                // bloqueo de la base de datos, y a la vez uno de los dos espera
                // o falla.
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
            // Si el proceso muere sin emitir stdout, se cierra el estado
            // igualmente para no dejar el widget girando.
            if (root.checking && root.aurHelper === "") {
                root.checking = false
                root.ready = true
            }
        }
    }

    Process {
        id: aurProc
        // -Qua: solo el AUR. Los repos ya los ha contado repoProc.
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

    // Solo se sondea con el widget puesto en la barra: si no, mirar
    // actualizaciones cada media hora es tráfico que nadie ve.
    readonly property bool wanted: BarCatalog.has(Settings.barLayout, "updates")

    Timer {
        interval: Math.max(5, root.refreshMinutes) * 60 * 1000
        running: root.wanted && root.available
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Tras el resume la red suele tardar y el primer pulso puede fallar, así que
    // se aprovecha la última oleada de recuperación, cuando ya hay conectividad,
    // en vez de esperar media hora al siguiente tick.
    Connections {
        target: Resume
        function onResumed() {
            if (Resume.recoveryPulse === 3 && root.wanted)
                root.refresh()
        }
    }
}
