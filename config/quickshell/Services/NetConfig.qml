pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Configuración de red (NetworkManager vía nmcli):
// - Por interfaz/adaptador: lista wifi y ethernet y edita IPv4/DNS, IPv6, MAC
//   y MTU del perfil activo de la seleccionada.
// - Wifis guardadas: lista perfiles wifi, permite olvidar (borrar), conectar
//   y cambiar su prioridad de autoconexión.
Singleton {
    id: root

    // Interfaces (adaptadores)
    // [{ device, type, state, connection }]  type: wifi | ethernet
    property var    interfaces: []
    property string selectedIface: ""    // nombre del dispositivo (p.ej. wlp2s0)
    property string ifaceType: ""        // wifi | ethernet
    property string ifaceConn: ""        // perfil de conexión activo a editar ("" si ninguno)

    // Wifis guardadas
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

    // Utilidades
    function unesc(s) { return String(s).replace(/\\:/g, ":") }   // des-escapa ':' de nmcli -t

    // Parte la salida de `nmcli -t` en filas de campos (split por ':'),
    // descartando líneas vacías y las que no tengan las columnas mínimas.
    function nmRows(text, minCols) {
        const rows = []
        String(text || "").split("\n").forEach(line => {
            if (line.trim() === "") return
            const parts = line.split(":")
            if (parts.length >= minCols) rows.push(parts)
        })
        return rows
    }

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

    // Sin refreshAll() al arrancar: los datos (interfaces/wifis guardadas)
    // solo se usan en los modales de configuración IP, y IpSettingsModal ya
    // llama a refreshAll() en cada apertura. Ahorra 2 nmcli por arranque.
    function refreshAll() { ifaceProc.running = true; wifiProc.running = true }
    function refreshConnections() { refreshAll() }   // alias compat

    // Interfaz seleccionada
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
        const fields = "ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,IP4.DNS,ipv6.method,"
                     + "connection.autoconnect,connection.autoconnect-priority,"
                     + k + ".cloned-mac-address," + k + ".mtu"
        readProc.command = ["nmcli", "-t", "-f", fields, "connection", "show", root.ifaceConn]
        readProc.running = true
    }

    function apply() {
        if (!root.hasConn || !root.ready) return
        root.error = ""
        root.applying = true
        const q = Utils.shellQuote
        const k = root.isWifi ? "802-11-wireless" : "802-3-ethernet"
        const manual = root.ip4method === "manual"
        const dns = root.ip4dns.trim().replace(/[\s,]+/g, ",")
        const mtu = (root.mtu === "" || root.mtu.toLowerCase() === "auto") ? "0" : root.mtu

        // Pares propiedad/valor para `nmcli connection modify`. Se citan todos
        // de forma uniforme, así "" se convierte en '' (limpiar la propiedad).
        const args = manual
            ? ["ipv4.method", "manual",
               "ipv4.addresses", root.ip4addr + "/" + root.maskToPrefix(root.ip4mask),
               "ipv4.gateway", root.ip4gw]
            : ["ipv4.method", "auto", "ipv4.addresses", "", "ipv4.gateway", ""]
        // DNS en AMBOS métodos: vacío = automático (DHCP). En auto con DNS
        // propio, ignoramos los del DHCP para que prevalezca.
        args.push("ipv4.dns", dns,
                  "ipv4.ignore-auto-dns", (dns !== "" && !manual) ? "yes" : "no",
                  "ipv6.method", root.ip6method,
                  "connection.autoconnect", root.autoconnect ? "yes" : "no",
                  "connection.autoconnect-priority", String(root.priority),
                  // "default" en NetworkManager = cadena vacía.
                  k + ".cloned-mac-address", root.mac === "default" ? "" : root.mac,
                  k + ".mtu", mtu)

        const modify = "nmcli connection modify " + q(root.ifaceConn) + " " + args.map(q).join(" ")
        applyProc.command = ["sh", "-c", modify + " && nmcli connection up " + q(root.ifaceConn)]
        applyProc.running = true
    }

    // Gestión de wifis guardadas
    // Comandos en forma de array: nmcli recibe los argumentos tal cual,
    // sin shell intermedio ni necesidad de citar/escapar.
    function forgetWifi(name)  { wifiOp(["connection", "delete", name]) }
    function connectWifi(name) { wifiOp(["connection", "up", name]) }
    function setWifiPriority(name, val) {
        wifiOp(["connection", "modify", name, "connection.autoconnect-priority", String(val)])
    }
    function setWifiAutoconnect(name, on) {
        wifiOp(["connection", "modify", name, "connection.autoconnect", on ? "yes" : "no"])
    }
    function wifiOp(args) {
        wifiOpProc.command = ["nmcli"].concat(args)
        wifiOpProc.running = true
    }

    // Procesos
    Process {
        id: ifaceProc
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = root.nmRows(this.text, 4)
                    .filter(p => p[1] === "wifi" || p[1] === "ethernet")
                    .map(p => {
                        const conn = root.unesc(p.slice(3).join(":")).trim()
                        return ({ device: p[0], type: p[1], state: p[2],
                                  connection: conn === "--" ? "" : conn })
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
        command: ["nmcli", "-t", "-f", "UUID,TYPE,AUTOCONNECT,AUTOCONNECT-PRIORITY,ACTIVE,NAME",
            "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = root.nmRows(this.text, 6)
                    .filter(p => p[1] === "802-11-wireless")
                    .map(p => ({
                        uuid: p[0],
                        autoconnect: p[2] === "yes",
                        priority: parseInt(p[3]) || 0,
                        active: p[4] === "yes",
                        name: root.unesc(p.slice(5).join(":"))
                    }))
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
                let cfgDns = ""        // DNS guardados en el perfil (ipv4.dns)
                let activeDns = []     // DNS en uso ahora mismo (IP4.DNS, p.ej. del DHCP)
                ;(this.text || "").split("\n").forEach(ln => {
                    const idx = ln.indexOf(":")
                    if (idx < 0) return
                    const key = ln.slice(0, idx)
                    const val = ln.slice(idx + 1).trim()
                    if (key === "ipv4.method") root.ip4method = (val === "manual") ? "manual" : "auto"
                    else if (key === "ipv4.addresses") {
                        const first = val.split(",")[0].trim()
                        if (first.indexOf("/") >= 0) {
                            root.ip4addr = first.split("/")[0]
                            root.ip4mask = root.prefixToMask(first.split("/")[1])
                        } else { root.ip4addr = ""; root.ip4mask = "" }
                    }
                    else if (key === "ipv4.gateway") root.ip4gw = val
                    else if (key === "ipv4.dns") cfgDns = val.replace(/,/g, ", ")
                    else if (key.indexOf("IP4.DNS") === 0) { if (val !== "") activeDns.push(val) }
                    else if (key === "ipv6.method") root.ip6method = val || "auto"
                    else if (key === "connection.autoconnect") root.autoconnect = (val === "yes")
                    else if (key === "connection.autoconnect-priority") root.priority = parseInt(val) || 0
                    else if (key.endsWith("cloned-mac-address")) root.mac = (val === "") ? "default" : val
                    else if (key.endsWith(".mtu")) root.mtu = (val === "auto" || val === "0") ? "" : val
                })
                // En el campo: los DNS propios del perfil; si no hay, los que el
                // sistema usa ahora (DHCP) para que se vean los configurados por defecto.
                root.ip4dns = cfgDns !== "" ? cfgDns : activeDns.join(", ")
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
