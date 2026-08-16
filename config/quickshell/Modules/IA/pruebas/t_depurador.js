// EL CATÁLOGO DE DEPURADORES: que cada lenguaje vaya a su adaptador, que la
// petición tenga la forma que ese adaptador entiende, y que cuando falte el
// programa se diga cuál y cómo instalarlo.
//
// Esto se prueba sin depurar nada: son tablas y funciones puras. Lo que NO
// cubre es hablar DAP de verdad con lldb o delve — eso pide un programa que
// compilar y un adaptador instalado, y se comprueba a mano.
const fs = require("fs")
const vm = require("vm")
const { execFileSync } = require("child_process")

const src = fs.readFileSync(__dirname + "/../Debuggers.js", "utf8")
                .replace(/^\.pragma library$/m, "")
const m = {}
vm.createContext(m)
vm.runInContext(src + ";__x={ADAPTADORES,PREFERENCIA,lenguajes,deteccion,elige,"
                + "puente,peticionLanzar,peticionAdjuntar};", m)
const D = m.__x

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) { ok++; return }
    mal++
    console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : ""))
}

// ── 1. La tabla está completa ────────────────────────────────────────────────
comprueba("hay trece adaptadores", D.PREFERENCIA.length === 13, D.PREFERENCIA.length)
for (const id of D.PREFERENCIA) {
    const a = D.ADAPTADORES[id]
    comprueba(id + ": está en la tabla", !!a)
    if (!a) continue
    comprueba(id + ": dice qué programa arranca", typeof a.cmd === "string" && a.cmd !== "")
    comprueba(id + ": dice qué lenguajes cubre", Array.isArray(a.lenguajes) && a.lenguajes.length > 0)
    // Sin esto, "falta el depurador" es un callejón sin salida.
    comprueba(id + ": dice cómo instalarlo", typeof a.paquete === "string" && a.paquete !== "")
    comprueba(id + ": modo conocido", a.modo === "stdio" || a.modo === "socket", a.modo)
}
// Nadie fuera de la preferencia: un adaptador que no está en la lista no se
// detecta nunca y sería un adorno.
for (const id in D.ADAPTADORES)
    comprueba("en la preferencia: " + id, D.PREFERENCIA.indexOf(id) !== -1)

// Los dieciocho lenguajes que se prometen en la herramienta.
const prometidos = ["c", "cpp", "rust", "zig", "swift", "objc", "python", "go",
                    "javascript", "typescript", "csharp", "fsharp", "ruby",
                    "php", "kotlin", "dart", "elixir", "bash", "native"]
for (const l of prometidos)
    comprueba("cubre " + l, D.lenguajes().indexOf(l) !== -1)

// ── 2. La detección sale de la tabla ─────────────────────────────────────────
// Si se añade una fila y hay que acordarse de tocar el guion de detección, se
// olvidará. Aquí se comprueba que salen de la misma fuente.
const det = D.deteccion()
for (const id of D.PREFERENCIA)
    comprueba("la detección busca " + id, det.indexOf("echo " + id) !== -1)
comprueba("debugpy se busca como módulo, no como binario",
          det.indexOf('python3 -c "import debugpy"') !== -1)
// Y el guion tiene que ser shell válido de verdad.
const salida = execFileSync("sh", ["-c", det], { encoding: "utf8" })
comprueba("el guion de detección corre", typeof salida === "string")
console.log("  [instalados aquí: " + (salida.trim().split("\n").filter(Boolean).join(", ") || "ninguno") + "]")

// ── 3. La elección de adaptador ──────────────────────────────────────────────
const todos = {}
for (const id of D.PREFERENCIA) todos[id] = true

const porExt = [
    ["/casa/x/main.py", "debugpy"], ["/casa/x/main.go", "dlv"],
    ["/casa/x/main.rs", "gdb"], ["/casa/x/a.cpp", "gdb"],
    ["/casa/x/a.swift", "lldb-dap"], ["/casa/x/a.zig", "gdb"],
    ["/casa/x/app.ts", "js-debug-adapter"], ["/casa/x/app.js", "js-debug-adapter"],
    ["/casa/x/P.cs", "netcoredbg"], ["/casa/x/s.rb", "rdbg"],
    ["/casa/x/i.php", "php-debug-adapter"], ["/casa/x/M.kt", "kotlin-debug-adapter"],
    ["/casa/x/m.dart", "dart"], ["/casa/x/m.exs", "elixir-ls-debugger"],
    ["/casa/x/s.sh", "bash-debug-adapter"],
    // Sin extensión = binario compilado, que es el caso normal en C y Rust.
    ["/casa/x/mi-programa", "gdb"]
]
for (const [p, id] of porExt) {
    const e = D.elige(p, "", todos)
    comprueba("por extensión " + p.slice(8) + " → " + id, e && e.id === id,
              JSON.stringify(e && (e.id || e.falta)))
}
// Lo que pida el usuario manda sobre la extensión.
comprueba("lang manda sobre la extensión",
          D.elige("/casa/x/main.py", "go", todos).id === "dlv")
comprueba("y un lenguaje que no existe es un error, no una falta",
          D.elige("/casa/x/main.py", "cobol", todos) === null)

// Sin nada instalado: dice cuál falta y cómo instalarlo.
const nada = D.elige("/casa/x/main.py", "", ({}))
comprueba("sin nada instalado avisa", nada && nada.falta === "debugpy", JSON.stringify(nada))
comprueba("y dice el paquete", nada && nada.paquete === "python-debugpy", nada && nada.paquete)
const nativoNada = D.elige("/casa/x/binario", "", ({}))
comprueba("para nativos propone gdb primero", nativoNada.falta === "gdb", nativoNada.falta)
comprueba("y menciona las alternativas", nativoNada.otros.length >= 2, JSON.stringify(nativoNada.otros))
// Con gdb ausente pero lldb presente, se usa lldb sin quejarse.
comprueba("cae al siguiente disponible",
          D.elige("/casa/x/binario", "", { "lldb-dap": true }).id === "lldb-dap")

// ── 4. La forma de las peticiones ────────────────────────────────────────────
const py = D.ADAPTADORES["debugpy"]
const lPy = D.peticionLanzar(py, "/casa/x/m.py", ["--v"], "/casa/x", true)
comprueba("lanzar: es un launch", lPy.request === "launch")
comprueba("lanzar: lleva el programa", lPy.program === "/casa/x/m.py")
comprueba("lanzar: lleva los argumentos", JSON.stringify(lPy.args) === '["--v"]')
comprueba("lanzar: lleva el directorio", lPy.cwd === "/casa/x")
comprueba("lanzar: para en la entrada", lPy.stopOnEntry === true)
// justMyCode false a propósito: si el fallo está en una biblioteca, esconderla
// es esconder justo lo que hace falta ver.
comprueba("python mira también las bibliotecas", lPy.justMyCode === false)
comprueba("sin stop_on_entry queda en false",
          D.peticionLanzar(py, "/a/b.py", [], "/a", false).stopOnEntry === false)

// netcoredbg llama de otra manera a "para en la entrada": si esto se pierde, el
// programa no para y nadie entiende por qué.
const lCs = D.peticionLanzar(D.ADAPTADORES["netcoredbg"], "/a/P.dll", [], "/a", true)
comprueba("netcoredbg usa stopAtEntry", lCs.stopAtEntry === true, JSON.stringify(lCs))
comprueba("y no stopOnEntry", lCs.stopOnEntry === undefined)
// gdb quiere además parar al principio de main.
comprueba("gdb para al principio de main",
          D.peticionLanzar(D.ADAPTADORES["gdb"], "/a/b", [], "/a", true)
              .stopAtBeginningOfMainSubprogram === true)
// delve compila si le das el fuente y ejecuta si le das el binario.
comprueba("delve compila un .go",
          D.peticionLanzar(D.ADAPTADORES["dlv"], "/a/m.go", [], "/a", false).mode === "debug")
comprueba("y ejecuta un binario",
          D.peticionLanzar(D.ADAPTADORES["dlv"], "/a/prog", [], "/a", false).mode === "exec")

// Engancharse: cada adaptador llama al número de proceso a su manera.
const aGdb = D.peticionAdjuntar(D.ADAPTADORES["gdb"], 4242)
comprueba("adjuntar: es un attach", aGdb.request === "attach")
comprueba("gdb quiere 'pid'", aGdb.pid === 4242, JSON.stringify(aGdb))
comprueba("debugpy quiere 'processId'",
          D.peticionAdjuntar(py, 7).processId === 7)
const aGo = D.peticionAdjuntar(D.ADAPTADORES["dlv"], 9)
comprueba("delve quiere además saber que es local", aGo.mode === "local", JSON.stringify(aGo))
comprueba("y el proceso en processId", aGo.processId === 9)
for (const id of D.PREFERENCIA) {
    const a = D.peticionAdjuntar(D.ADAPTADORES[id], 123)
    comprueba(id + ": el attach lleva el proceso",
              a.pid === 123 || a.processId === 123, JSON.stringify(a))
}

// ── 5. El puente ─────────────────────────────────────────────────────────────
const pStdio = D.puente(py, 38001)
comprueba("stdio: modo stdio", pStdio[0] === "stdio")
comprueba("stdio: arranca el adaptador",
          pStdio.join(" ") === "stdio -- python3 -m debugpy.adapter", pStdio.join(" "))
const pTcp = D.puente(D.ADAPTADORES["dlv"], 38001)
comprueba("socket: modo tcp", pTcp[0] === "tcp" && pTcp[1] === "38001", pTcp.join(" "))
comprueba("socket: le dice al adaptador dónde escuchar",
          pTcp.join(" ").indexOf("--listen=127.0.0.1:38001") !== -1, pTcp.join(" "))
// Solo en el bucle local: un depurador escuchando en todas las interfaces es
// una consola remota abierta.
comprueba("y solo en el bucle local", pTcp.join(" ").indexOf("--listen=0.0.0.0") === -1)

// ── 6. Que la herramienta y el catálogo digan lo mismo ───────────────────────
const defs = fs.readFileSync(__dirname + "/../ToolDefs.js", "utf8")
const mDefs = defs.match(/name: "debug_start"[\s\S]*?required|name: "debug_start"[\s\S]*?\} \} \}/)
comprueba("debug_start acepta attach_pid", defs.indexOf("attach_pid") !== -1)
for (const l of ["python", "go", "rust", "javascript", "csharp", "ruby", "php",
                 "kotlin", "dart", "elixir", "bash", "swift", "zig"])
    comprueba("debug_start ofrece lang=" + l,
              mDefs !== null && mDefs[0].indexOf('"' + l + '"') !== -1)

console.log("\n" + ok + " bien, " + mal + " mal")
process.exit(mal === 0 ? 0 : 1)
