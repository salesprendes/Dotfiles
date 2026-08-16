import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Cliente MCP (Model Context Protocol, transporte stdio).
//
// Cada servidor de Settings.aiMcpServers es un proceso hijo que habla JSON-RPC
// línea a línea: initialize → notifications/initialized → tools/list, y sus
// herramientas se anuncian al modelo con el prefijo mcp__<servidor>__<tool> (el
// mismo esquema de nombres de Claude Code). Ejecutar una pasa por la MISMA
// tarjeta de aprobación que el resto.
//
// Este componente NO sabe nada de tarjetas ni de mensajes: expone `rpc` con una
// devolución de llamada y quien la pidió decide qué hacer con la respuesta. Esa
// frontera es lo que permite que el protocolo se pruebe y se cambie sin tocar el
// harness.
Scope {
    id: mcpRoot

    property var tools: []              // [{server, name, description, schema}]
    property var status: ({})           // servidor → starting|ok|error(<msg>)
    property var _procs: ({})           // servidor → Process vivo (registro)

    function _setStatus(name, st) {
        const m = Object.assign({}, status)
        m[name] = st
        status = m
    }
    function _setTools(name, list) {
        // Reemplaza las de ese servidor, conserva las del resto.
        tools = tools.filter(t => t.server !== name).concat(list)
    }

    // Quitar un servidor de la lista debe retirar sus herramientas AHORA: el
    // Instantiator destruye el proceso y su onExited puede no llegar a correr.
    Connections {
        target: Settings
        function onAiMcpServersChanged() {
            const names = (Settings.aiMcpServers || []).map(s => s.name)
            mcpRoot.tools = mcpRoot.tools.filter(t => names.indexOf(t.server) !== -1)
        }
    }

    // Las herramientas MCP en formato OpenAI, listas para req.tools.
    readonly property var toolDefs: tools.map(t => ({
        type: "function", "function": {
            name: "mcp__" + t.server + "__" + t.name,
            description: "[" + t.server + "] " + t.description,
            parameters: t.schema
        } }))

    Instantiator {
        model: Settings.aiMcpServers
        delegate: Process {
            id: mcp
            // modelData llega como propiedad de contexto del Instantiator.
            readonly property var srv: modelData
            readonly property string srvName: (srv && srv.name) || "mcp"
            property int nextId: 1
            property var pending: ({})     // id → callback(result, error)

            running: true
            command: ["sh", "-c", (srv && srv.command) || "false"]
            stdinEnabled: true

            function rpc(method, params, cb) {
                const id = nextId++
                if (cb) pending[id] = cb
                mcp.write(JSON.stringify({ jsonrpc: "2.0", id: id,
                                           method: method, params: params }) + "\n")
            }
            function notify(method, params) {
                mcp.write(JSON.stringify({ jsonrpc: "2.0",
                                           method: method, params: params }) + "\n")
            }

            onStarted: {
                mcpRoot._procs[srvName] = mcp
                mcpRoot._setStatus(srvName, "starting")
                rpc("initialize", {
                    protocolVersion: "2024-11-05",
                    capabilities: {},
                    clientInfo: { name: "quickshell-ia", version: "1.0" }
                }, () => {
                    notify("notifications/initialized", {})
                    rpc("tools/list", {}, (res) => {
                        const list = (res && res.tools) || []
                        mcpRoot._setTools(mcp.srvName, list.map(t => ({
                            server: mcp.srvName,
                            name: t.name,
                            description: String(t.description || "").slice(0, 250),
                            schema: t.inputSchema || { type: "object", properties: {} }
                        })))
                        mcpRoot._setStatus(mcp.srvName, "ok")
                    })
                })
            }

            stdout: SplitParser {
                onRead: (line) => {
                    const l = line.trim()
                    if (l === "" || l[0] !== "{")
                        return
                    try {
                        const j = JSON.parse(l)
                        if (j.id !== undefined && mcp.pending[j.id]) {
                            const cb = mcp.pending[j.id]
                            delete mcp.pending[j.id]
                            cb(j.result, j.error)
                        }
                    } catch (e) { /* línea no-JSON del servidor: se ignora */ }
                }
            }
            stderr: SplitParser { onRead: () => {} }

            onExited: (code) => {
                delete mcpRoot._procs[srvName]
                mcpRoot._setTools(srvName, [])
                mcpRoot._setStatus(srvName, "error: terminó con " + code)
                // Al morir el servidor, sus llamadas en vuelo NO iban a volver
                // nunca: el callback se quedaba en 'pending' y la tarjeta que lo
                // esperaba, pendiente para siempre. Se contestan todas aquí, con
                // el motivo, que es información que el modelo puede usar (probar
                // otra cosa) y el usuario también (arreglar el servidor).
                const cuelgan = mcp.pending
                mcp.pending = ({})
                for (const id in cuelgan)
                    cuelgan[id](null, { message: "el servidor MCP '" + srvName
                        + "' se cerró (código " + code + ") antes de contestar" })
            }
        }
    }

    // Una llamada JSON-RPC a un servidor. Los tres usos (ejecutar una
    // herramienta, listar recursos, leer uno) solo se diferencian en cómo se lee
    // la respuesta, así que eso lo pone quien llama; lo demás —servidor caído,
    // error del protocolo— se contesta igual siempre.
    //   cb(resultado, textoDeError)  — uno de los dos llega vacío
    function rpc(server, method, params, cb) {
        const proc = _procs[server]
        if (!proc || !proc.running) {
            cb(null, "El servidor MCP '" + server + "' no está conectado.")
            return
        }
        proc.rpc(method, params, (res, err) => {
            if (err)
                cb(null, "Error MCP: " + (err.message || JSON.stringify(err)))
            else
                cb(res || ({}), "")
        })
    }

    // Los bloques de texto de una respuesta MCP, aplanados.
    function flatten(list) {
        let out = ""
        const l = list || []
        for (let i = 0; i < l.length; i++)
            if (l[i].text !== undefined)
                out += l[i].text + "\n"
        return out
    }
}
