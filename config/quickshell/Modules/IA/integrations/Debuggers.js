// EL CATÁLOGO DE DEPURADORES: qué programa habla DAP para cada lenguaje, cómo
// se arranca, y qué forma tienen sus peticiones de lanzar y de engancharse.
//
// Vive en una tabla y no repartido por el código porque añadir un lenguaje debe
// ser añadir una fila. Antes había tres casos cosidos a mano dentro de start()
// —Python, Go y "nativo"— y cada lenguaje nuevo era otro `else if` con su
// detección, su mensaje de "falta esto" y su objeto de lanzamiento.
//
// Lo que cambia de un adaptador a otro, y por eso está en la tabla:
//   · cómo se arranca (`cmd` + `args`), y si habla por la entrada estándar o
//     solo por un puerto (delve: `modo: "socket"`).
//   · qué extensiones y qué archivos de raíz lo delatan (go.mod, Cargo.toml…).
//   · la forma de la petición: unos quieren `stopOnEntry`, netcoredbg quiere
//     `stopAtEntry`, gdb además `stopAtBeginningOfMainSubprogram`.
//   · cómo se dice "engánchate a este proceso": `pid`, `processId`, y delve
//     además necesita `mode: "local"`.
//
// El campo `paquete` es cosa nuestra: cuando falta el adaptador, decir "falta
// lldb-dap" no ayuda a nadie, y "pacman -S lldb" sí.
.pragma library

const ADAPTADORES = ({
    // ── Nativos ─────────────────────────────────────────────────────────────
    // gdb va PRIMERO en la preferencia de los nativos a propósito: en Linux está
    // instalado casi siempre y lldb-dap casi nunca. Habla DAP desde GDB 14
    // (`-i dap`); en una versión anterior el arranque falla y se dice.
    "gdb": {
        cmd: "gdb", args: ["-i", "dap"], modo: "stdio", paquete: "gdb",
        // Zig también: genera DWARF normal y gdb lo lee sin más. La tabla de
        // oh-my-pi no lo lista, pero dejarlo fuera obligaba a instalar lldb en
        // una máquina que ya tiene gdb.
        lenguajes: ["c", "cpp", "rust", "zig", "native"],
        ext: [".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", ".rs", ".zig"],
        raiz: ["Makefile", "CMakeLists.txt", "Cargo.toml", "compile_commands.json", "build.zig"],
        lanzar: ({ stopAtBeginningOfMainSubprogram: true }),
        pidClave: "pid"
    },
    "lldb-dap": {
        cmd: "lldb-dap", args: [], modo: "stdio", paquete: "lldb",
        lenguajes: ["c", "cpp", "objc", "swift", "rust", "zig", "native"],
        ext: [".c", ".cc", ".cpp", ".cxx", ".m", ".mm", ".swift", ".rs", ".zig"],
        raiz: ["Package.swift", "Cargo.toml", "Makefile", "CMakeLists.txt", "build.zig"],
        lanzar: ({}), pidClave: "pid"
    },
    "codelldb": {
        cmd: "codelldb", args: ["--port", "0"], modo: "stdio", paquete: "codelldb (AUR)",
        lenguajes: ["c", "cpp", "rust", "zig", "native"],
        ext: [".c", ".cc", ".cpp", ".cxx", ".rs", ".zig"],
        raiz: ["Cargo.toml", "CMakeLists.txt", "Makefile", "build.zig"],
        lanzar: ({}), pidClave: "pid"
    },

    // ── Con máquina virtual o intérprete ────────────────────────────────────
    // debugpy no es un binario, es un módulo: se comprueba distinto.
    "debugpy": {
        cmd: "python3", args: ["-m", "debugpy.adapter"], modo: "stdio",
        paquete: "python-debugpy", modulo: "debugpy",
        lenguajes: ["python"], ext: [".py"],
        raiz: ["pyproject.toml", "setup.py", "requirements.txt", "Pipfile"],
        // justMyCode false: si el fallo está en una biblioteca, esconderla es
        // esconder justo lo que hace falta ver.
        lanzar: ({ type: "python", console: "internalConsole", justMyCode: false }),
        adjuntar: ({ justMyCode: false }), pidClave: "processId"
    },
    // delve solo escucha TCP: el puente lo arranca y se conecta él.
    "dlv": {
        cmd: "dlv", args: ["dap"], modo: "socket", paquete: "delve",
        lenguajes: ["go"], ext: [".go"], raiz: ["go.mod", "go.sum", "go.work"],
        // 'debug' compila el fuente antes; 'exec' corre un binario ya hecho.
        lanzar: (p) => ({ mode: p.endsWith(".go") ? "debug" : "exec" }),
        adjuntar: ({ mode: "local" }), pidClave: "processId"
    },
    "js-debug-adapter": {
        cmd: "js-debug-adapter", args: [], modo: "stdio",
        paquete: "js-debug-adapter (AUR) o npm i -g js-debug",
        lenguajes: ["javascript", "typescript", "js", "ts", "node"],
        ext: [".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"],
        raiz: ["package.json", "tsconfig.json", "jsconfig.json"],
        lanzar: ({ type: "pwa-node" }), adjuntar: ({ type: "pwa-node" }),
        pidClave: "processId"
    },
    "netcoredbg": {
        cmd: "netcoredbg", args: ["--interpreter=vscode"], modo: "stdio",
        paquete: "netcoredbg (AUR)",
        lenguajes: ["csharp", "fsharp", "cs", "dotnet"],
        ext: [".cs", ".fs", ".fsx", ".dll"],
        raiz: ["*.sln", "*.csproj", "*.fsproj"],
        // Este llama al de entrada 'stopAtEntry', no 'stopOnEntry'.
        lanzar: ({}), entradaClave: "stopAtEntry", pidClave: "processId"
    },
    "rdbg": {
        cmd: "rdbg", args: ["--open", "--command", "--"], modo: "stdio",
        paquete: "ruby-debug", lenguajes: ["ruby", "rb"], ext: [".rb"],
        raiz: ["Gemfile", "Rakefile", ".ruby-version"],
        lanzar: ({ type: "rdbg" }), adjuntar: ({ type: "rdbg" }),
        pidClave: "processId"
    },
    "php-debug-adapter": {
        cmd: "php-debug-adapter", args: [], modo: "stdio",
        paquete: "php-debug-adapter (AUR) — necesita Xdebug en el PHP",
        lenguajes: ["php"], ext: [".php"],
        raiz: ["composer.json", "composer.lock"],
        lanzar: ({}), pidClave: "processId"
    },
    "kotlin-debug-adapter": {
        cmd: "kotlin-debug-adapter", args: [], modo: "stdio",
        paquete: "kotlin-debug-adapter (AUR)",
        lenguajes: ["kotlin", "kt"], ext: [".kt", ".kts"],
        raiz: ["build.gradle", "build.gradle.kts", "pom.xml"],
        lanzar: ({ mainClass: "", projectRoot: "" }), pidClave: "processId"
    },
    "dart": {
        cmd: "dart", args: ["debug_adapter"], modo: "stdio", paquete: "dart",
        lenguajes: ["dart"], ext: [".dart"],
        raiz: ["pubspec.yaml", "pubspec.lock"],
        lanzar: ({}), pidClave: "processId"
    },
    "elixir-ls-debugger": {
        cmd: "elixir-ls-debugger", args: [], modo: "stdio",
        paquete: "elixir-ls", lenguajes: ["elixir", "ex"], ext: [".ex", ".exs"],
        raiz: ["mix.exs", "mix.lock"],
        lanzar: ({ type: "mix_task", task: "run" }), pidClave: "processId"
    },
    "bash-debug-adapter": {
        cmd: "bash-debug-adapter", args: [], modo: "stdio",
        paquete: "bash-debug-adapter (AUR) — necesita bashdb",
        lenguajes: ["bash", "shell", "sh"], ext: [".sh", ".bash"], raiz: [],
        lanzar: ({ type: "bashdb", pathBashdb: "bashdb", pathBash: "bash" }),
        pidClave: "processId"
    }
})

// El orden importa cuando varios sirven para lo mismo: el primero disponible
// gana. gdb antes que lldb-dap porque en Linux está en todas las máquinas.
const PREFERENCIA = ["gdb", "lldb-dap", "codelldb", "debugpy", "dlv",
                     "js-debug-adapter", "netcoredbg", "rdbg",
                     "php-debug-adapter", "kotlin-debug-adapter", "dart",
                     "elixir-ls-debugger", "bash-debug-adapter"]

// Todos los nombres de lenguaje que se aceptan, para la lista de la herramienta.
function lenguajes() {
    const v = []
    for (const id of PREFERENCIA)
        for (const l of ADAPTADORES[id].lenguajes)
            if (v.indexOf(l) === -1)
                v.push(l)
    return v.sort()
}

// El guion de detección sale de la misma tabla que todo lo demás: así no puede
// pasar que se añada un adaptador y se olvide detectarlo.
function deteccion() {
    const filas = []
    for (const id of PREFERENCIA) {
        const a = ADAPTADORES[id]
        if (a.modulo)
            filas.push('python3 -c "import ' + a.modulo + '" 2>/dev/null && echo ' + id)
        else
            filas.push('command -v ' + a.cmd + ' >/dev/null 2>&1 && echo ' + id)
    }
    // El `true` final no es adorno: si el último adaptador de la lista no está
    // instalado —lo normal— el guion entero saldría con código 1 y parecería
    // que la detección falló, cuando lo que ha hecho es funcionar.
    return filas.join("; ") + "; true"
}

// ¿Qué adaptador toca? Por este orden: lo que diga el usuario, lo que diga la
// extensión, y lo que digan los archivos que hay junto al programa.
//
// Devuelve { id, def } si hay uno disponible; { falta, paquete, lenguaje } si se
// sabe cuál hace falta pero no está instalado; null si no se reconoce nada.
function elige(prog, lang, disponibles) {
    const dis = disponibles || ({})
    const pedido = String(lang || "").toLowerCase().trim()
    let candidatos = []

    if (pedido !== "") {
        candidatos = PREFERENCIA.filter(
            id => ADAPTADORES[id].lenguajes.indexOf(pedido) !== -1)
        // Un nombre de lenguaje que no conoce nadie es un error del que llama,
        // no una falta de instalación: se distingue.
        if (candidatos.length === 0)
            return null
    } else {
        const p = String(prog || "").toLowerCase()
        const punto = p.lastIndexOf(".")
        const ext = punto > p.lastIndexOf("/") ? p.slice(punto) : ""
        if (ext !== "")
            candidatos = PREFERENCIA.filter(
                id => ADAPTADORES[id].ext.indexOf(ext) !== -1)
        // Sin extensión (un binario compilado, que es el caso normal en C, C++,
        // Rust y Zig) manda el nativo.
        if (candidatos.length === 0)
            candidatos = PREFERENCIA.filter(
                id => ADAPTADORES[id].lenguajes.indexOf("native") !== -1)
    }

    for (const id of candidatos)
        if (dis[id])
            return { id: id, def: ADAPTADORES[id] }

    const primero = candidatos[0]
    if (!primero)
        return null
    return { falta: primero, paquete: ADAPTADORES[primero].paquete,
             lenguaje: pedido || "ese tipo de programa",
             otros: candidatos.slice(1).map(id => ADAPTADORES[id].paquete) }
}

// El comando del puente. Los de socket no hablan por la entrada estándar: el
// puente los arranca y se conecta al puerto, y desde fuera no se nota.
function puente(def, puerto) {
    if (def.modo === "socket")
        return ["tcp", String(puerto), "--", def.cmd]
               .concat(def.args, ["--listen=127.0.0.1:" + puerto])
    return ["stdio", "--"].concat([def.cmd], def.args)
}

function _mezcla(base, extra) {
    const o = ({})
    for (const k in base) o[k] = base[k]
    for (const k in (extra || ({}))) o[k] = extra[k]
    return o
}

// La petición de lanzar. Lo común lo pone esto; lo propio de cada adaptador
// sale de la tabla, incluido el nombre del "para en la primera línea", que
// netcoredbg llama de otra manera.
function peticionLanzar(def, prog, progArgs, dir, pararAlEntrar) {
    const propio = typeof def.lanzar === "function" ? def.lanzar(prog) : def.lanzar
    const p = _mezcla({ request: "launch", program: prog,
                        args: progArgs || [], cwd: dir }, propio)
    p[def.entradaClave || "stopOnEntry"] = pararAlEntrar === true
    return p
}

// La petición de engancharse a un proceso que YA corre. Cada adaptador llama al
// número de proceso a su manera, y delve además quiere saber que es local.
function peticionAdjuntar(def, pid) {
    const p = _mezcla({ request: "attach" }, def.adjuntar)
    p[def.pidClave || "pid"] = pid
    return p
}
