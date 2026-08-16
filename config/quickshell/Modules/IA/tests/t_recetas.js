// RECETAS POR SITIO: que la URL vaya a la puerta de servicio correcta, que el
// formateador saque lo que importa, y —sobre todo— que cuando algo cambie de
// forma se caiga al camino de siempre en vez de mentir.
//
// Sin red: las respuestas están grabadas en muestras/. Están RECORTADAS a lo
// que el formateador lee (el JSON de npm son 805 kB reales, de los que se miran
// cuatro campos), pero conservan la forma, que es lo que aquí se prueba: el día
// que una API renombre un campo, esto falla.
const fs = require("fs")
const vm = require("vm")
const { execFileSync } = require("child_process")

const src = fs.readFileSync(__dirname + "/../tools/LocalTools.js", "utf8")
                .replace(/^\.pragma library$/m, "")
const mod = {}
vm.createContext(mod)
vm.runInContext(src + ";__x={receta:receta,PY_RECETA:PY_RECETA,files:files};", mod)
const { receta, PY_RECETA, files } = mod.__x

let ok = 0, mal = 0
function comprueba(n, cond, extra) {
    if (cond) { ok++; return }
    mal++
    console.log("  FALLA: " + n + (extra !== undefined ? "  << " + extra : ""))
}
function formatea(fmt, archivo, url0) {
    try {
        return execFileSync("python3", ["-c", PY_RECETA], {
            input: fs.readFileSync(__dirname + "/muestras/" + archivo),
            env: Object.assign({}, process.env, { QS_FMT: fmt, QS_U0: url0 || "" }),
            encoding: "utf8" })
    } catch (e) { return null }        // salida 1 = "la receta no vale"
}

// ── 1. El enrutado ───────────────────────────────────────────────────────────
const rutas = [
    ["https://github.com/quickshell-mirror/quickshell", "gh_repo", "api.github.com/repos/quickshell-mirror/quickshell"],
    ["https://github.com/a/b.git", "gh_repo", "api.github.com/repos/a/b"],
    ["https://github.com/a/b/issues/12", "gh_issue", "/issues/12"],
    ["https://github.com/a/b/pull/7", "gh_pr", "/pulls/7"],
    ["https://github.com/a/b/blob/main/src/x.rs", "texto", "raw.githubusercontent.com/a/b/main/src/x.rs"],
    ["https://gitlab.com/gitlab-org/gitlab-runner", "gl_repo", "projects/gitlab-org%2Fgitlab-runner"],
    ["https://www.npmjs.com/package/express", "npm", "registry.npmjs.org/express"],
    ["https://www.npmjs.com/package/@scope/pkg", "npm", "registry.npmjs.org/@scope/pkg"],
    ["https://pypi.org/project/requests/", "pypi", "pypi.org/pypi/requests/json"],
    ["https://crates.io/crates/serde", "crates", "api/v1/crates/serde"],
    ["https://arxiv.org/abs/1706.03762", "arxiv", "id_list=1706.03762"],
    ["https://arxiv.org/pdf/1706.03762v5", "arxiv", "id_list=1706.03762"],
    ["https://stackoverflow.com/questions/11227809/por-que", "so", "/answers?site=stackoverflow"],
    ["https://news.ycombinator.com/item?id=42", "hn", "algolia.com/api/v1/items/42"],
    ["https://developer.mozilla.org/en-US/docs/Web/CSS/flex", "mdn", "/index.json"],
    ["https://requests.readthedocs.io/en/latest/user/quickstart/", "texto", "_sources/user/quickstart.rst.txt"],
    ["https://docs.rs/serde/latest/serde/", "docsrs", "docs.rs/serde/latest/serde/"]
]
for (const [u, id, trozo] of rutas) {
    const r = receta(u)
    comprueba("enruta " + u.slice(8, 46), r !== null && r.id === id,
              JSON.stringify(r))
    comprueba("  y apunta a " + trozo, r !== null && r.url.indexOf(trozo) !== -1,
              r && r.url)
}
// Lo que NO tiene receta se queda como estaba: es la mitad que evita que esto
// se convierta en un enrutador que secuestra medio internet.
for (const u of ["https://example.com/", "https://es.wikipedia.org/wiki/X",
                 "https://github.com", "https://gitlab.com/",
                 "https://blog.rust-lang.org/2024/01/post.html",
                 "https://notgithub.com/a/b"])
    comprueba("sin receta: " + u.slice(8, 40), receta(u) === null,
              JSON.stringify(receta(u)))

// ── 2. Los formateadores, contra respuestas de verdad ────────────────────────
const casos = [
    ["npm", "npm.json", null, ["npm: express", "Licencia: MIT", "Repositorio:", "Dependencias"]],
    ["pypi", "pypi.json", null, ["PyPI: requests", "Python: >=", "Resumen:"]],
    ["crates", "crates.json", null, ["crates.io: serde", "Descargas:", "Últimas versiones"]],
    ["gh_repo", "ghrepo.json", null, ["GitHub: quickshell-mirror/quickshell", "Estrellas:", "Lenguaje: C++"]],
    ["gl_repo", "glrepo.json", null, ["GitLab: gitlab-org/gitlab-runner", "Rama por defecto:"]],
    ["hn", "hn.json", null, ["Hacker News:", "Puntos:"]],
    ["arxiv", "arxiv.xml", null, ["arXiv: Attention Is All You Need", "Autores: Ashish Vaswani", "Resumen:"]],
    ["mdn", "mdn.json", null, ["MDN: flex CSS property"]],
    ["docsrs", "docsrs.html", null, ["docs.rs", "Serde is a framework"]],
    ["so", "so.json", "https://stackoverflow.com/questions/11227809/why-is-processing-a-sorted-array-faster",
     ["Stack Overflow: why is processing a sorted array faster", "ACEPTADA", "branch prediction"]]
]
for (const [fmt, arch, u0, esperado] of casos) {
    const out = formatea(fmt, arch, u0)
    comprueba(fmt + ": saca algo", out !== null && out.length > 40,
              out === null ? "salió con 1" : String(out.length))
    for (const e of esperado)
        comprueba("  " + fmt + " dice «" + e.slice(0, 34) + "»",
                  out !== null && out.indexOf(e) !== -1)
    // Lo que se le manda al modelo tiene que ser CORTO: el JSON de npm son
    // 805 kB y el resumen cabe en un mensaje.
    if (out !== null)
        comprueba("  " + fmt + " cabe en 13 kB", out.length < 13000, String(out.length))
}

// ── 3. Que falle bien ────────────────────────────────────────────────────────
// Esta es la parte que de verdad importa. Una API cambiará de forma, y cuando
// pase el formateador tiene que salir con código 1 SIN escribir nada, para que
// quien llama reintente la URL original. Si escribiera media cosa, el modelo se
// la creería.
function falla(fmt, texto) {
    try {
        const out = execFileSync("python3", ["-c", PY_RECETA],
            { input: texto, env: Object.assign({}, process.env, { QS_FMT: fmt }),
              encoding: "utf8" })
        return { salio: 0, out: out }
    } catch (e) { return { salio: e.status, out: String(e.stdout || "") } }
}
const rotos = [
    ["npm", "esto no es json", "basura"],
    ["npm", "{}", "JSON vacío"],
    ["pypi", '{"info":{}}', "sin los campos"],
    ["gh_repo", '{"message":"API rate limit exceeded","documentation_url":"x"}', "cuota agotada"],
    ["gh_repo", '{"message":"Not Found"}', "no existe"],
    ["gl_repo", '{"message":"404 Project Not Found"}', "proyecto que no existe"],
    ["so", '{"items":[]}', "sin respuestas"],
    ["arxiv", "<feed></feed>", "Atom vacío"],
    ["docsrs", "<html><body>nada</body></html>", "HTML sin documentación"],
    ["mdn", '{"doc":{}}', "doc vacío"],
    ["texto", "  ", "texto en blanco"],
    ["inventado", '{"a":1}', "formateador que no existe"]
]
for (const [fmt, cuerpo, desc] of rotos) {
    const r = falla(fmt, cuerpo)
    comprueba(fmt + " con " + desc + ": sale con 1", r.salio === 1, "salió " + r.salio)
    comprueba("  y no escribe nada", r.out.trim() === "", JSON.stringify(r.out.slice(0, 60)))
}

// ── 4. El cableado ───────────────────────────────────────────────────────────
// Que el constructor de fetch_url pase de verdad la receta, y que una URL sin
// receta siga viajando exactamente como antes.
const con = files("fetch_url", { url: "https://crates.io/crates/serde" }, { home: process.env.HOME })
comprueba("fetch_url pasa la URL de la receta", con.env.QS_RURL.indexOf("api/v1/crates/serde") !== -1, con.env.QS_RURL)
comprueba("y el nombre del formateador", con.env.QS_FMT === "crates", con.env.QS_FMT)
comprueba("y el propio formateador", con.env.QS_REC.indexOf("crates.io: ") !== -1)
comprueba("y conserva la URL original", con.env.QS_U === "https://crates.io/crates/serde")
comprueba("y la deja también en QS_U0", con.env.QS_U0 === "https://crates.io/crates/serde")
const sin = files("fetch_url", { url: "https://example.com/x" }, { home: process.env.HOME })
comprueba("sin receta: QS_RURL vacío", sin.env.QS_RURL === "", sin.env.QS_RURL)
comprueba("sin receta: QS_FMT vacío", sin.env.QS_FMT === "", sin.env.QS_FMT)
comprueba("sin receta: no se manda el formateador", sin.env.QS_REC === "")
// La jaula de siempre no se toca: una receta no puede saltarse la comprobación
// de a qué red apunta cada salto.
comprueba("la receta sigue pasando por el resolutor",
          con.env.QS_RES.indexOf("is_global") !== -1)
comprueba("y sigue sin permitir la red local sin permiso", con.env.QS_LAN === "")

console.log("\n" + ok + " bien, " + mal + " mal")
process.exit(mal === 0 ? 0 : 1)
