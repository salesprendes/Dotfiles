// Prueba de fetch_url (LocalTools.js) contra un sitio de mentira. Carga el
// archivo de PRODUCCIÓN quitándole el .pragma library, así no hay copia que se
// desincronice. El servidor falso corre en OTRO proceso a propósito:
// execFileSync bloquea el bucle de node, así que uno montado aquí dentro no
// llegaría a contestar nunca.
const fs = require("fs")
const { execFileSync, spawn } = require("child_process")

const DIR = __dirname
const src = fs.readFileSync(require("path").resolve(__dirname, "../tools/LocalTools.js"),
                            "utf8").replace(/^\.pragma library$/m, "")
const mod = {}
new Function("exports", src + "\nexports.files=files;exports.FETCH_KO=FETCH_KO;")(mod)

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) ok++
    else { mal++; console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : "")) }
}

const PUERTO = 8099
const srv = spawn("python3", [DIR + "/falsa_web.py", String(PUERTO)],
                  { stdio: ["ignore", "pipe", "inherit"] })
for (let i = 0; i < 100; i++) {
    try {
        execFileSync("sh", ["-c", "curl -s --max-time 1 -o /dev/null http://127.0.0.1:"
                                  + PUERTO + "/api"], { stdio: "ignore" })
        break
    } catch (e) { execFileSync("sleep", ["0.05"]) }
}

// Un PATH recortado a mano fuerza la rama baja de la cascada de extractores, se
// tenga instalado lo que se tenga en esta máquina.
function trae(ruta, sinExtractores, opciones) {
    const b = mod.files("fetch_url",
        Object.assign({ url: "http://127.0.0.1:" + PUERTO + ruta }, opciones || {}),
        { home: process.env.HOME })
    if (b.error !== undefined) return b.error
    const env = Object.assign({}, process.env, b.env)
    if (sinExtractores) {
        const bin = DIR + "/bin-pelado"
        fs.mkdirSync(bin, { recursive: true })
        for (const c of ["curl", "python3", "mktemp", "sh", "rm", "wc"]) {
            const dest = bin + "/" + c
            try { fs.unlinkSync(dest) } catch (e) {}
            const real = execFileSync("sh", ["-c", "command -v " + c + " || true"],
                                      { encoding: "utf8" }).trim()
            if (real) fs.symlinkSync(real, dest)
        }
        env.PATH = bin
    }
    // El doble de web vive en 127.0.0.1, y fetch_url ahora se niega a
    // aterrizar en la red local salvo que quien llama lo haya aprobado
    // (QS_LAN=1, que en el harness solo levanta ToolRunner tras enseñar
    // la tarjeta). Aquí somos nosotros quienes aprobamos.
    env.QS_LAN = "1"
    try {
        return execFileSync(b.cmd[0], b.cmd.slice(1),
            { env: env, encoding: "utf8", timeout: 40000 })
    } catch (e) { return "EXCEPCION " + e.message }
}
const seca = (t) => t.indexOf(mod.FETCH_KO) !== -1
const cuerpo = (t) => t.replace(mod.FETCH_KO, "")
                       .replace(/\[extracción básica[^\]]*\]/, "").trim()

try {
    // ── 1. Página normal: sale el artículo, no el menú ───────────────────────
    let t = trae("/pagina", true)
    console.log("[1] artículo: " + cuerpo(t).length + " caracteres")
    comprueba("no es seca", !seca(t), JSON.stringify(t.slice(0, 120)))
    comprueba("trae el precio", /799/.test(t))
    comprueba("desescapa entidades", /€/.test(t) && !/&euro;/.test(t))
    comprueba("desescapa la eñe", /Señalamos/.test(t))
    comprueba("no cuela el script", !/var x=1/.test(t))
    comprueba("tira nav, aside y footer",
              !/Mapa del sitio/.test(t) && !/Publicidad/.test(t))
    comprueba("avisa de la extracción básica", /extracción básica/.test(t))

    // ── 2. EL CASO AMAZON: comprimido sin pedirlo ────────────────────────────
    // Sin --compressed esto entraba como veinte mil caracteres de basura
    // binaria, el tope entero, reenviados en todas las rondas siguientes.
    t = trae("/gzip", true)
    console.log("[2] gzip no solicitado: " + cuerpo(t).length + " caracteres")
    comprueba("descomprime", /Precio del cacharro/.test(t), JSON.stringify(t.slice(0, 120)))
    comprueba("sin basura binaria", !/�/.test(t))
    comprueba("con los precios dentro", /799/.test(t) && /899/.test(t))

    // ── 3. Códigos HTTP, cada uno con su consejo ─────────────────────────────
    t = trae("/404")
    console.log("[3] 404: " + JSON.stringify(cuerpo(t).slice(0, 60)))
    comprueba("404 es seca", seca(t))
    comprueba("404 dice que no existe", /no existe \(HTTP 404\)/.test(t), JSON.stringify(t))
    comprueba("404 NO se confunde con error de red", !/error de red/.test(t), JSON.stringify(t))

    t = trae("/403")
    comprueba("403 es seca", seca(t))
    comprueba("403 se explica como muro anti-robot", /muro anti-robot/.test(t),
              JSON.stringify(t))
    comprueba("403 dice que no siga por ese sitio", /no pruebes más páginas/.test(t))

    t = trae("/500")
    comprueba("500 es seca", seca(t))
    comprueba("500 dice que puede ser temporal", /temporal/.test(t), JSON.stringify(t))

    // ── 4. Retos anti-robot y 404 blandos ────────────────────────────────────
    t = trae("/reto", true)
    console.log("[4] reto: " + JSON.stringify(cuerpo(t).slice(0, 60)))
    comprueba("el reto es seco", seca(t))
    comprueba("nombra el JavaScript", /JavaScript/.test(t), JSON.stringify(t))

    t = trae("/blando404", true)
    comprueba("el 404 blando es seco", seca(t), JSON.stringify(t))
    comprueba("lo llama 404 disfrazado", /disfrazado/.test(t), JSON.stringify(t))

    t = trae("/escaparate", true)
    console.log("[4c] escaparate: " + JSON.stringify(cuerpo(t).slice(0, 60)))
    comprueba("el armazón de tienda es seco", seca(t), JSON.stringify(t))
    comprueba("explica que lo pinta JavaScript", /pinta JavaScript/.test(t))

    // ── 5. Binarios: ni se intentan leer ─────────────────────────────────────
    t = trae("/pdf")
    comprueba("el PDF es seco", seca(t), JSON.stringify(t))
    comprueba("dice que no es texto", /no es una página de texto/.test(t), JSON.stringify(t))

    t = trae("/binario")
    console.log("[5b] binario que miente en la cabecera: " + JSON.stringify(cuerpo(t).slice(0, 60)))
    comprueba("el binario es seco", seca(t), JSON.stringify(t))
    comprueba("sin mojibake en el contexto", !/�/.test(t), JSON.stringify(t.slice(0, 80)))

    // ── 6. Lo que NO es HTML llega tal cual ──────────────────────────────────
    t = trae("/api")
    comprueba("el JSON llega entero", t.trim().indexOf('{"precio": 799') === 0,
              JSON.stringify(t))
    comprueba("no se come el < del texto", /a < b/.test(t))
    t = trae("/xml")
    comprueba("conserva las etiquetas del XML", /<item id="1">799<\/item>/.test(t),
              JSON.stringify(t))
    t = trae("/txt")
    comprueba("texto plano intacto", /a < b > c/.test(t), JSON.stringify(t.slice(0, 80)))

    // ── 7. Recorte por CARACTERES, no por bytes ──────────────────────────────
    t = trae("/largo", true)
    const cortado = t.split("[...cortado")[0]
    console.log("[7] largo: " + t.length + " caracteres")
    comprueba("avisa del recorte", /cortado a 20 000 caracteres/.test(t))
    comprueba("corta por caracteres", cortado.length <= 20002, cortado.length)
    comprueba("no parte una eñe", !/�/.test(t))

    // ── 8. Respuesta vacía ───────────────────────────────────────────────────
    t = trae("/vacio")
    comprueba("la vacía es seca", seca(t))
    comprueba("lo explica", /No se pudo descargar/.test(t), JSON.stringify(t))

    // ── 9. Un host muerto no cuelga ──────────────────────────────────────────
    const b = mod.files("fetch_url", { url: "http://127.0.0.1:9/nada" },
                        { home: process.env.HOME })
    b.env.QS_LAN = "1"       // aprobado a mano: aquí se prueba el puerto cerrado
    const t0 = Date.now()
    let caido
    try {
        caido = execFileSync(b.cmd[0], b.cmd.slice(1),
            { env: Object.assign({}, process.env, b.env), encoding: "utf8", timeout: 40000 })
    } catch (e) { caido = "EXCEPCION" }
    console.log("[9] host muerto: " + (Date.now() - t0) + " ms")
    comprueba("responde rápido", Date.now() - t0 < 5000)
    comprueba("lo dice claro", /No se pudo descargar/.test(caido), JSON.stringify(caido))


    // ── 11. Los enlaces, que son lo que permite NAVEGAR ──────────────────────
    // Sin esto el modelo bajaba al shell: en el registro de auditoría están sus
    // `curl -o /tmp/p.html` seguidos de `grep -oiE 'href="[^"]*"'`. Reimplementar
    // la herramienta a mano, y con la página cruda entrando en su contexto.
    const sinEnlaces = trae("/articulo")
    const conEnlaces = trae("/articulo", false, { links: true })
    comprueba("por defecto NO salen enlaces", !/── Enlaces de esta página/.test(sinEnlaces))
    comprueba("con links:true sí", /── Enlaces de esta página/.test(conEnlaces),
              JSON.stringify(conEnlaces.slice(-100)))
    comprueba("y el texto sigue estando igual",
              conEnlaces.indexOf(sinEnlaces.trim().slice(0, 60)) !== -1)
    // Relativos resueltos a absolutos: un "/precios" a secas no sirve de nada
    // para volver a pedirlo.
    comprueba("los relativos salen absolutos",
              !/· [^\n]*→ \//.test(conEnlaces), JSON.stringify(conEnlaces.slice(-200)))
    comprueba("nada de javascript: ni mailto:",
              !/→ (javascript|mailto|tel):/.test(conEnlaces), JSON.stringify(conEnlaces.slice(-400)))
    comprueba("ni anclas de la misma página", !/→ [^\n]*#arriba/.test(conEnlaces))
    comprueba("el relativo sale con el servidor delante",
              conEnlaces.indexOf("http://127.0.0.1:" + PUERTO + "/ficha-tecnica") !== -1)
    comprueba("el absoluto de otro sitio se conserva",
              conEnlaces.indexOf("https://ejemplo.es/fabricante") !== -1)
    comprueba("y el menú de navegación NO se cuela",
              !/→ [^\n]*\/(1|2|3)$/m.test(conEnlaces))

    // ── 12. Solo la cabecera ─────────────────────────────────────────────────
    // Era, tal cual, `curl -s -o /dev/null -w "%{http_code}"` escrito a mano.
    const cabecera = trae("/articulo", false, { head: true })
    comprueba("head:true dice el código", /^HTTP 200/m.test(cabecera), JSON.stringify(cabecera))
    comprueba("y el tipo", /Tipo: text\/html/.test(cabecera))
    comprueba("y el tamaño", /Tamaño: \d+ bytes/.test(cabecera))
    comprueba("y NO trae el contenido", cabecera.length < 200, cabecera.length)
    const cab404 = trae("/404", false, { head: true })
    comprueba("un 404 se sigue diciendo como 404", /no existe/.test(cab404),
              JSON.stringify(cab404.slice(0, 80)))

    // ── 10. La jaula ─────────────────────────────────────────────────────────
    const mala = mod.files("fetch_url", { url: "file:///etc/passwd" },
                           { home: process.env.HOME })
    comprueba("rechaza file://", mala.error === "Solo URLs http(s).", JSON.stringify(mala))
    const inj = mod.files("fetch_url", { url: 'http://x/"; rm -rf ~; echo "' },
                          { home: process.env.HOME })
    comprueba("la URL viaja por entorno", inj.cmd.join(" ").indexOf("rm -rf") === -1)
    comprueba("y está en el entorno", /rm -rf/.test(inj.env.QS_U))

    // ── 11. Las ramas altas de la cascada ────────────────────────────────────
    // En esta máquina no hay ni w3m ni trafilatura: se ponen dobles de prueba
    // en el PATH. Lo que se comprueba es que la cascada los ELIGE y en qué
    // orden, no lo que ellos extraen.
    const binFalso = DIR + "/bin-falso"
    fs.mkdirSync(binFalso, { recursive: true })
    const pon = (nombre, texto) => fs.writeFileSync(binFalso + "/" + nombre,
        "#!/bin/sh\nprintf '%s\\n' " + JSON.stringify(texto) + "\n", { mode: 0o755 })
    const quita = (n) => { try { fs.unlinkSync(binFalso + "/" + n) } catch (e) {} }
    const traeCon = (ruta) => {
        const bb = mod.files("fetch_url", { url: "http://127.0.0.1:" + PUERTO + ruta },
                             { home: process.env.HOME })
        const env = Object.assign({}, process.env, bb.env)
        env.QS_LAN = "1"     // el doble de web es local: ver arriba
        env.PATH = binFalso + ":" + process.env.PATH
        return execFileSync(bb.cmd[0], bb.cmd.slice(1),
            { env: env, encoding: "utf8", timeout: 40000 })
    }
    // Los dobles devuelven texto largo para no chocar con el umbral de "corta".
    const LARGO = (s) => s + " " + "relleno ".repeat(60)
    pon("trafilatura", LARGO("TEXTO-DE-TRAFILATURA"))
    pon("w3m", LARGO("TEXTO-DE-W3M"))
    t = traeCon("/pagina")
    comprueba("trafilatura manda sobre w3m", /TEXTO-DE-TRAFILATURA/.test(t),
              JSON.stringify(t.slice(0, 90)))
    comprueba("sin aviso cuando hay extractor", !/extracción básica/.test(t))
    quita("trafilatura")
    t = traeCon("/pagina")
    comprueba("cae a w3m", /TEXTO-DE-W3M/.test(t), JSON.stringify(t.slice(0, 90)))
    // Un extractor que existe pero calla (le pasa a trafilatura con las páginas
    // que no son artículos) no debe dejar la herramienta muda.
    pon("trafilatura", "")
    t = traeCon("/pagina")
    comprueba("cae al siguiente si el primero calla", /TEXTO-DE-W3M/.test(t),
              JSON.stringify(t.slice(0, 90)))
    quita("trafilatura"); quita("w3m")
} finally {
    srv.kill()
}

console.log("\n" + ok + " bien, " + mal + " mal")
process.exit(mal === 0 ? 0 : 1)
