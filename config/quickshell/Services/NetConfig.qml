pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ─────────────────────────────────────────────────────────────
//  Configuración de red (NetworkManager vía nmcli), estilo Windows:
//  · Por INTERFAZ/adaptador: lista todas las wifi y ethernet y edita
//    IPv4/DNS, IPv6, MAC, MTU del perfil activo de la seleccionada.
//  · Gestión de WIFIS GUARDADAS: lista perfiles wifi, permite olvidar
//    (borrar), conectar y cambiar su prioridad de autoconexión.
// ─────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Interfaces (adaptadores) ─────────────────────────────
    // [{ device, type, state, connection }]  type: wifi | ethernet
    property var    interfaces: []
    property string selectedIface: ""    // nombre del dispositivo (p.ej. wlp2s0)
    property string ifaceType: ""        // wifi | ethernet
    property string ifaceConn: ""        // perfil de conexión activo a editar ("" si ninguno)

    // ── Wifis guardadas ──────────────────────────────────────
    // [{ name, uuid, autoconnect, priority, active }]
    property var    savedWifis: []

    property bool   loading: false
    property bool   applying: false
    property string error: ""
    signal applyDone(bool ok)

    // Estado IP editable de la interfaz seleccionada (de su perfil activo).
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

    readonly property bool isWifi: ifaceType === "wifi"
    readonly property bool hasConn: ifaceConn !== ""

    function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function unesc(s) { return String(s).replace(/\\:/g, ":") }   // des-escapa ':' de nmcli -t

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

    Component.onCompleted: refreshAll()
    function refreshAll() { ifaceProc.running = true; wifiProc.running = true }
    function refreshConnections() { refreshAll() }   // alias compat

    // ── Interfaz seleccionada ────────────────────────────────
    function selectIface(dev) {
        root.selectedIface = dev
        const d = root.interfaces.find(x => x.device === dev)
        root.ifaceType = d ? d.type : ""
        root.ifaceConn = d ? d.connection : ""
        readSelected()
    }

    // Selecciona automáticamente la interfaz "activa" (la conectada; si hay
    // varias, prioriza ethernet). La usa el engranaje del centro rápido.
    function selectActive() {
        const conns = root.interfaces.filter(i => i.connection !== "")
        const pick = conns.find(i => i.type === "ethernet") || conns[0]
                   || (root.interfaces.length > 0 ? root.interfaces[0] : null)
        if (pick) root.selectIface(pick.device)
    }

    function readSelected() {
        if (root.ifaceConn === "") {
            // Interfaz sin perfil activo: nada que leer/editar.
            root.ip4method = "auto"; root.ip4addr = ""; root.ip4mask = ""; root.ip4gw = ""; root.ip4dns = ""
            root.ip6method = "auto"; root.autoconnect = true; root.priority = 0; root.mac = "default"; root.mtu = ""
            return
        }
        root.loading = true
        root.error = ""
        const k = root.isWifi ? "802-11-wireless" : "802-3-ethernet"
        const fields = "ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv6.method,"
                     + "connection.autoconnect,connection.autoconnect-priority,"
                     + k + ".cloned-mac-address," + k + ".mtu"
        readProc.command = ["sh", "-c",
            "nmcli -t -f " + fields + " connection show " + shellQuote(root.ifaceConn)]
        readProc.running = true
    }

    function apply() {
        if (!root.hasConn || !root.ready) return
        root.error = ""
        root.applying = true
        const q = root.shellQuote
        const k = root.isWifi ? "802-11-wireless" : "802-3-ethernet"
        let cmd = "nmcli connection modify " + q(root.ifaceConn)
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
        // Privacidad / avanzado. "default" en NetworkManager = cadena vacía.
        cmd += " " + k + ".cloned-mac-address " + q(root.mac === "default" ? "" : root.mac)
        const m = (root.mtu === "" || root.mtu.toLowerCase() === "auto") ? "0" : root.mtu
        cmd += " " + k + ".mtu " + q(m)
        cmd += " && nmcli connection up " + q(root.ifaceConn)
        applyProc.command = ["sh", "-c", cmd]
        applyProc.running = true
    }

    // ── Gestión de wifis guardadas ───────────────────────────
    function forgetWifi(name) {
        wifiOpProc.command = ["nmcli", "connection", "delete", name]
        wifiOpProc.running = true
    }
    function connectWifi(name) {
        wifiOpProc.command = ["nmcli", "connection", "up", name]
        wifiOpProc.running = true
    }
    function setWifiPriority(name, val) {
        const q = root.shellQuote
        wifiOpProc.command = ["sh", "-c",
            "nmcli connection modify " + q(name) + " connection.autoconnect-priority " + q(String(val))]
        wifiOpProc.running = true
    }
    function setWifiAutoconnect(name, on) {
        const q = root.shellQuote
        wifiOpProc.command = ["sh", "-c",
            "nmcli connection modify " + q(name) + " connection.autoconnect " + (on ? "yes" : "no")]
        wifiOpProc.running = true
    }

    // ── Procesos ─────────────────────────────────────────────
    Process {
        id: ifaceProc
        command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                ;(this.text || "").split("\n").forEach(line => {
                    if (line.trim() === "") return
                    const parts = line.split(":")
                    if (parts.length < 4) return
                    const device = parts[0]
                    const type = parts[1]
                    if (type !== "wifi" && type !== "ethernet") return
                    const state = parts[2]
                    let conn = root.unesc(parts.slice(3).join(":")).trim()
                    if (conn === "--") conn = ""
                    out.push(({ device: device, type: type, state: state, connection: conn }))
                })
                root.interfaces = out
                if (out.length > 0 && (root.selectedIface === "" || !out.find(i => i.device === root.selectedIface)))
                    root.selectIface(out[0].device)
                else if (out.length === 0) {
                    root.selectedIface = ""; root.ifaceType = ""; root.ifaceConn = ""
                }
            }
        }
    }

    Process {
        id: wifiProc
        command: ["sh", "-c",
            "nmcli -t -f UUID,TYPE,AUTOCONNECT,AUTOCONNECT-PRIORITY,ACTIVE,NAME connection show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                ;(this.text || "").split("\n").forEach(line => {
                    if (line.trim() === "") return
                    const parts = line.split(":")
                    if (parts.length < 6) return
                    if (parts[1] !== "802-11-wireless") return
                    out.push(({
                        uuid: parts[0],
                        autoconnect: parts[2] === "yes",
                        priority: parseInt(parts[3]) || 0,
                        active: parts[4] === "yes",
                        name: root.unesc(parts.slice(5).join(":"))
                    }))
                })
                // Orden: activa primero, luego por prioridad desc, luego nombre.
                out.sort((a, b) => (b.active - a.active) || (b.priority - a.priority) || a.name.localeCompare(b.name))
                root.savedWifis = out
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
            root.applying = false
            if (code === 0) root.readSelected()
            else root.error = (applyErr.text || "").trim()
            root.applyDone(code === 0)
        }
    }

    Process {
        id: wifiOpProc
        stderr: StdioCollector { id: wifiOpErr }
        onExited: (code, status) => {
            if (code !== 0) root.error = (wifiOpErr.text || "").trim()
            root.refreshAll()
        }
    }
}
