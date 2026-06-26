pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ─────────────────────────────────────────────────────────────
//  Lista de familias tipográficas instaladas (vía fc-list).
//  Prioriza monoespaciadas y "Nerd Font" (las que llevan iconos),
//  que son las adecuadas para la barra/paneles.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: root

    property var list: []
    property var monoList: []

    Component.onCompleted: proc.running = true
    function refresh() { proc.running = true }

    Process {
        id: proc
        command: ["sh", "-c",
            "echo @ALL; fc-list family | sed 's/,.*//' | sort -u; " +
            "echo @MONO; { fc-list :spacing=mono family; fc-list family | grep -i 'nerd font'; } | sed 's/,.*//' | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: {
                const all = []
                const mono = []
                let section = ""
                const lines = text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim()
                    if (line === "@ALL" || line === "@MONO") {
                        section = line
                        continue
                    }
                    if (line === "")
                        continue
                    if (section === "@MONO")
                        mono.push(line)
                    else if (section === "@ALL")
                        all.push(line)
                }
                root.list = all
                root.monoList = mono
            }
        }
    }
}
