pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ─────────────────────────────────────────────────────────────
//  Configuración de red (NetworkManager vía nmcli). Lista las
//  conexiones activas, LEE todos los parámetros de la seleccionada
//  y los APLICA (modify + up). Cubre IPv4/DNS, IPv6, autoconexión,
//  prioridad, aleatorización de MAC y MTU. Olvida conexiones.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: root

    // [{ name, type, device }] de conexiones activas (wifi/ethernet).
    property var    connections: []
    property string selected: ""
    property string connType: ""        // 802-11-wireless | 802-3-ethernet
    property bool   loading: false
    property string error: ""

    // Estado leído/editable de la conexión seleccionada.
    property string ip4method: "auto"   // auto | manual
    property string ip4addr: ""
    property string ip4mask: ""
    property string ip4gw: ""
    property string ip4dns: ""
    property string ip6method: "auto"   // auto | disabled | link-local
    property bool   autoconnect: true
    property int    priority: 0
    property string mac: "default"      // default | random | stable
    property string mtu: ""             // "" / "auto" = automático

    readonly property bool isWifi: connType === "802-11-wireless"

    function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function maskToPrefix(m) {
        const p = String(m).split(".")
        if (p.length !== 4) return -1
        let bits = 0
        for (let i = 0; i < 4; i++) {
            const n = parseInt(p[i])
            if (isNaN(n) || n < 0 || n > 255) return -1
            bits += (n.toString(2).match(/1/g) || []).length
        }
        return bits
    }
    function prefixToMask(pf) {
        pf = parseInt(pf)
        if (isNaN(pf) || pf < 0 || pf > 32) return ""
        const m = []
        for (let i = 0; i < 4; i++) {
            const n = Math.max(0, Math.min(8, pf - 8 * i))
            m.push(n === 0 ? 0 : 256 - Math.pow(2, 8 - n))
        }
        return m.join(".")
    }
    function validIp(s) {
        const p = String(s).split(".")
        if (p.length !== 4) return false
        return p.every(o => /^\d{1,3}$/.test(o) && parseInt(o) <= 255)
    }
    readonly property bool ready: ip4method !== "manual"
        || (validIp(ip4addr) && maskToPrefix(ip4mask) >= 0
            && (ip4gw === "" || validIp(ip4gw)))

    Component.onCompleted: refreshConnections()
    function refreshConnections() { listProc.running = true }

    function select(name) {
        root.selected = name
        const c = root.connections.find(x => x.name === name)
        root.connType = c ? c.type : ""
        readSelected()
    }

    function readSelected() {
        if (root.selected === "") return
        root.loading = true
        root.error = ""
        const k = root.isWifi ? "802-11-wireless" : "802-3-ethernet"
        const fields = "ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv6.method,"
                     + "connection.autoconnect,connection.autoconnect-priority,"
                     + k + ".cloned-mac-address," + k + ".mtu"
        readProc.command = ["sh", "-c",
            "nmcli -t -f " + fields + " connection show " + shellQuote(root.selected)]
        readProc.running = true
    }

    function apply() {
        if (root.selected === "" || !root.ready) return
        root.error = ""
        const q = root.shellQuote
        const k = root.isWifi ? "802-11-wireless" : "802-3-ethernet"
        let cmd = "nmcli connection modify " + q(root.selected)
        // IPv4
        cmd += (root.ip4method === "manual")
            ? " ipv4.method manual ipv4.addresses " + q(root.ip4addr + "/" + root.maskToPrefix(root.ip4mask))
              + " ipv4.gateway " + q(root.ip4gw)
              + " ipv4.dns " + q(root.ip4dns.trim().replace(/[\s,]+/g, ","))
            : " ipv4.method auto ipv4.addresses '' ipv4.gateway '' ipv4.dns ''"
        // IPv6
        cmd += " ipv6.method " + q(root.ip6method)
        // Conexión
        cmd += " connection.autoconnect " + (root.autoconnect ? "yes" : "no")
        cmd += " connection.autoconnect-priority " + q(String(root.priority))
        // Privacidad / avanzado
        cmd += " " + k + ".cloned-mac-address " + q(root.mac)
        const m = (root.mtu === "" || root.mtu.toLowerCase() === "auto") ? "0" : root.mtu
        cmd += " " + k + ".mtu " + q(m)
        cmd += " && nmcli connection up " + q(root.selected)
        applyProc.command = ["sh", "-c", cmd]
        applyProc.running = true
    }

    function forget() {
        if (root.selected === "") return
        forgetProc.command = ["nmcli", "connection", "delete", root.selected]
        forgetProc.running = true
    }

    // ── Procesos ─────────────────────────────────────────────
    Process {
        id: listProc
        command: ["sh", "-c",
            "nmcli -t -f NAME,TYPE,DEVICE connection show --active"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                ;(this.text || "").split("\n").forEach(line => {
                    if (line.trim() === "") return
                    const parts = line.split(":")
                    if (parts.length < 3) return
                    const device = parts.pop()
                    const type = parts.pop()
                    const name = parts.join(":")
                    if (type === "802-11-wireless" || type === "802-3-ethernet")
                        out.push(({ name: name, type: type, device: device }))
                })
                root.connections = out
                if (out.length > 0 && (root.selected === "" || !out.find(c => c.name === root.selected)))
                    root.select(out[0].name)
            }
        }
    }

    Process {
        id: readProc
        stdout: StdioCollector {
            onStreamFinished: {
                ;(this.text || "").split("\n").forEach(ln => {
                    const idx = ln.indexOf(":")
                    if (idx < 0) return
                    const key = ln.slice(0, idx)
                    const val = ln.slice(idx + 1)
                    if (key === "ipv4.method") root.ip4method = (val.trim() === "manual") ? "manual" : "auto"
                    else if (key === "ipv4.addresses") {
                        const first = val.split(",")[0].trim()
                        if (first.indexOf("/") >= 0) {
                            root.ip4addr = first.split("/")[0]
                            root.ip4mask = root.prefixToMask(first.split("/")[1])
                        } else { root.ip4addr = ""; root.ip4mask = "" }
                    }
                    else if (key === "ipv4.gateway") root.ip4gw = val.trim()
                    else if (key === "ipv4.dns") root.ip4dns = val.trim().replace(/,/g, ", ")
                    else if (key === "ipv6.method") root.ip6method = val.trim() || "auto"
                    else if (key === "connection.autoconnect") root.autoconnect = (val.trim() === "yes")
                    else if (key === "connection.autoconnect-priority") root.priority = parseInt(val.trim()) || 0
                    else if (key.endsWith("cloned-mac-address")) root.mac = (val.trim() === "") ? "default" : val.trim()
                    else if (key.endsWith(".mtu")) root.mtu = (val.trim() === "auto" || val.trim() === "0") ? "" : val.trim()
                })
                root.loading = false
            }
        }
    }

    Process {
        id: applyProc
        stdout: StdioCollector {}
        stderr: StdioCollector { id: applyErr }
        onExited: (code, status) => {
            if (code === 0) root.readSelected()
            else root.error = (applyErr.text || "").trim()
        }
    }

    Process {
        id: forgetProc
        onExited: (code, status) => root.refreshConnections()
    }
}
