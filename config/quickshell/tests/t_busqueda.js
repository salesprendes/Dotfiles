// EL BUSCADOR DE SPOTLIGHT: que lo que escribes salga arriba.
//
// Un buscador no se comprueba mirando si "sale algo": sale algo casi siempre.
// Lo que hay que defender es el ORDEN, que es lo único que lo hace útil — y el
// orden es justo lo que se rompe en silencio al tocar un peso.
//
// Tres familias mandan aquí:
//
//   · La ESCALERA. Un prefijo tiene que ganarle a una subcadena SIEMPRE, por
//     mucho uso que traiga la otra. Si la frecencia puede saltarse un peldaño,
//     lo que usas mucho se te cuela delante de lo que acabas de escribir, y el
//     buscador deja de obedecer.
//   · Los ACENTOS. En castellano, un buscador que exige teclear la tilde no
//     sirve: nadie escribe «música» con prisa. La referencia (DankMaterialShell)
//     no lo hace, y es la diferencia entre encontrar tus cosas o no.
//   · La CALCULADORA. Lo que se teclea en un buscador acaba aquí, así que el
//     evaluador tiene que entender aritmética y NADA más. Media batería son
//     cosas que debe rechazar.
const fs = require("fs")
const vm = require("vm")
const path = require("path")

function carga(rel, expuestos) {
    const src = fs.readFileSync(path.resolve(__dirname, "..", rel), "utf8")
                  .replace(/^\.pragma library$/m, "")
    const caja = {}
    vm.createContext(caja)
    vm.runInContext(src + ";__x={" + expuestos.map(n => n + ":" + n).join(",") + "};", caja)
    return caja.__x
}

const S = carga("Modules/Spotlight/Search.js",
    ["norm", "words", "textScore", "score", "rank",
     "frecency", "parseQuery", "calc", "formatNumber", "typoBudget",
     "editDistance", "W"])

let total = 0, malas = 0
function ok(nombre, cond) {
    total++
    if (!cond) { malas++; console.log("  MAL  " + nombre) }
}
function igual(nombre, a, b) {
    total++
    const x = JSON.stringify(a), y = JSON.stringify(b)
    if (x !== y) { malas++; console.log("  MAL  " + nombre + "\n       esperado " + y + "\n       obtenido " + x) }
}

const AHORA = 1700000000000
const app = (id, name, extra) => Object.assign({ id, name, type: "app" }, extra || {})

// ── Normalización ───────────────────────────────────────────────────────────
igual("quita tildes", S.norm("Música"), "musica")
igual("y la eñe", S.norm("ESPAÑA"), "espana")
igual("y las catalanas", S.norm("Aïllat"), "aillat")
igual("recorta y baja a minúsculas", S.norm("  ARCHIVOS  "), "archivos")
igual("null no revienta", S.norm(null), "")
igual("parte por espacios, guiones, puntos y barras",
      S.words("Visual-Studio_Code/2.app"), ["visual", "studio", "code", "2", "app"])

// ── La escalera ─────────────────────────────────────────────────────────────
ok("exacto gana a prefijo", S.textScore("firefox", "firefox") > S.textScore("firefox", "fire"))
ok("prefijo gana a inicio de palabra",
   S.textScore("firefox", "fire") > S.textScore("mozilla firefox", "fire"))
ok("inicio de palabra gana a subcadena",
   S.textScore("mozilla firefox", "fire") > S.textScore("bonfire", "fire"))
ok("subcadena gana a difuso",
   S.textScore("bonfire", "fire") > S.textScore("firefax", "firefox"))
igual("lo que no se parece en nada da cero", S.textScore("calculadora", "xyz"), 0)

// Iniciales: "vsc" → Visual Studio Code.
ok("las iniciales cuentan", S.textScore("visual studio code", "vsc") > 0)
ok("pero no con una sola palabra", S.textScore("visualstudiocode", "vsc") === 0)

// ── Erratas ─────────────────────────────────────────────────────────────────
igual("con dos letras no se perdona nada", S.typoBudget(2), 0)
ok("con tres, un fallo", S.typoBudget(3) === 1)
ok("firefx encuentra firefox", S.textScore("firefox", "firefx") > 0)

// La distancia de edición está ACOTADA: solo calcula la banda de celdas cerca
// de la diagonal y abandona en cuanto se sale del presupuesto. Eso la hace
// rápida y también frágil de una forma fea — si un centinela de borde falta,
// no se rompe: devuelve "no coincide" y la errata deja de encontrarse en
// silencio. Por eso se comprueba contra valores conocidos, y con el tope justo
// por encima y por debajo del real.
igual("distancia: sustitución", S.editDistance("gato", "goto", 3), 1)
igual("distancia: borrado", S.editDistance("firefox", "firefx", 3), 1)
igual("distancia: inserción", S.editDistance("kity", "kitty", 3), 1)
igual("distancia: dos cambios", S.editDistance("krita", "kryta", 3), 1)
igual("distancia: idénticas", S.editDistance("blender", "blender", 3), 0)
igual("distancia: largos distintos", S.editDistance("vlc", "vlcplayer", 9), 6)
ok("con el tope justo, cabe", S.editDistance("firefox", "firefax", 1) <= 1)
ok("con el tope por debajo, se rinde", S.editDistance("firefox", "chromium", 2) > 2)
ok("una errata al principio también cuenta", S.textScore("firefox", "girefox") > 0)
ok("dos erratas en una palabra larga", S.textScore("libreoffice", "librofice") > 0)
ok("tres erratas ya no son la misma palabra", S.textScore("gimp", "abcd") === 0)

// ── CONSULTA DE VARIAS PALABRAS ─────────────────────────────────────────────
// Escribir trozos sueltos es como se busca de verdad cuando se tiene prisa.
ok("trozos sueltos encuentran el nombre largo",
   S.textScore("visual studio code", "vis stu cod") > 0)
ok("el orden no importa",
   S.textScore("visual studio code", "code visual") > 0)
ok("dos trozos bastan",
   S.textScore("libreoffice writer", "libre wri") > 0)
ok("un trozo que no casa tumba la coincidencia",
   S.textScore("visual studio code", "vis xyz") === 0)
ok("no se reutiliza la misma palabra para dos trozos",
   S.textScore("code", "cod cod") === 0)
ok("con más trozos que palabras, no",
   S.textScore("gimp", "gi mp xx") === 0)
igual("varias palabras puntúan en el peldaño de palabra",
      S.textScore("visual studio code", "vis cod"), S.W.wordStart)
ok("una sola palabra sigue yendo por su camino",
   S.textScore("firefox", "fire") === S.W.wordStart || S.textScore("firefox", "fire") === S.W.prefix)

// El orden manda sobre lo demás: un prefijo literal tiene que ganarle a un
// acierto por trozos, porque escribir el principio entero es más señal.
ok("el prefijo literal gana a los trozos",
   S.textScore("visual studio code", "visual stu") > S.textScore("visual studio code", "stu visual"))
ok("pero 'ab' no encuentra 'firefox'", S.textScore("firefox", "ab") === 0)

// ── LA REGLA QUE NO SE PUEDE ROMPER ─────────────────────────────────────────
// Un peldaño mejor gana SIEMPRE, aunque el otro venga con toda la frecencia
// del mundo. Es lo que hace que el buscador obedezca a lo que escribes.
{
    const items = [app("bonfire", "Bonfire"), app("firefox", "Firefox")]
    const statsFor = id => id === "bonfire" ? { count: 9999, last: AHORA } : null
    const r = S.rank(items, "fire", statsFor, AHORA)
    igual("el prefijo gana a la subcadena MUY usada", r[0].item.id, "firefox")
}

// Y a igualdad de peldaño, sí manda el uso.
{
    const items = [app("a", "Fire A"), app("b", "Fire B")]
    const statsFor = id => id === "b" ? { count: 20, last: AHORA } : null
    const r = S.rank(items, "fire", statsFor, AHORA)
    igual("a igual coincidencia, gana lo más usado", r[0].item.id, "b")
}

// ── Acentos, de punta a punta ───────────────────────────────────────────────
{
    const items = [app("m", "Reproductor de Música"), app("o", "Otra cosa")]
    const r = S.rank(items, "musica", null, AHORA)
    ok("buscar sin tilde encuentra con tilde", r.length === 1 && r[0].item.id === "m")
    const r2 = S.rank(items, "MÚSICA", null, AHORA)
    ok("y con tilde y mayúsculas también", r2.length === 1 && r2[0].item.id === "m")
}

// ── Campos secundarios ──────────────────────────────────────────────────────
{
    const items = [
        app("x", "Zzz", { subtitle: "Navegador web" }),
        app("y", "Yyy", { keywords: ["navegador"] })
    ]
    const r = S.rank(items, "navegador", null, AHORA)
    igual("subtítulo y palabras clave también encuentran", r.length, 2)
    // Aquí gana la palabra clave, y está bien: es una coincidencia EXACTA
    // (10000 × 0,35) contra un subtítulo por prefijo (5000 × 0,5). La escalera
    // manda sobre los factores — los factores solo ordenan a igualdad de
    // peldaño, que es lo que se comprueba justo debajo.
    igual("gana la coincidencia mejor, no el campo mejor", r[0].item.id, "y")
}
{
    // A IGUALDAD de peldaño (los dos exactos), sí manda el campo.
    const items = [
        app("sub", "Zzz", { subtitle: "navegador" }),
        app("key", "Yyy", { keywords: ["navegador"] })
    ]
    const r = S.rank(items, "navegador", null, AHORA)
    igual("a igual coincidencia, el subtítulo pesa más que la palabra clave",
          r[0].item.id, "sub")
}

// ── Sin coincidencia no hay resultado ───────────────────────────────────────
{
    const items = [app("a", "Firefox")]
    const statsFor = () => ({ count: 500, last: AHORA })
    igual("lo muy usado NO sale si no coincide",
          S.rank(items, "zzzzz", statsFor, AHORA).length, 0)
    ok("sin consulta, sí sale todo", S.rank(items, "", statsFor, AHORA).length === 1)
}

// ── Frecencia con memoria ───────────────────────────────────────────────────
// Lo que la referencia no hace: allí es frecuencia pura y lo de hace un año
// pesa igual que lo de esta mañana.
{
    const hoy = { count: 4, last: AHORA }
    const viejo = { count: 4, last: AHORA - 60 * 86400000 }
    ok("lo reciente pesa más que lo viejo con el mismo número de usos",
       S.frecency(hoy, AHORA) > S.frecency(viejo, AHORA))
    ok("y lo muy viejo casi no pesa", S.frecency(viejo, AHORA) < S.frecency(hoy, AHORA) * 0.1)
    igual("sin datos, cero", S.frecency(null, AHORA), 0)
    ok("la frecencia NUNCA pasa del tope",
       S.frecency({ count: 1e9, last: AHORA }, AHORA) <= S.W.frecencyMax)
    // Y el tope tiene que estar por debajo de un peldaño, o se lo saltaría.
    ok("el tope de frecencia es menor que un peldaño", S.W.frecencyMax < S.W.substring * 4)
}

// Cuatro usos de hoy le ganan a cien de hace medio año.
{
    const items = [app("nuevo", "Zeta Uno"), app("viejo", "Zeta Dos")]
    const statsFor = id => id === "nuevo"
        ? { count: 4, last: AHORA }
        : { count: 100, last: AHORA - 180 * 86400000 }
    const r = S.rank(items, "", statsFor, AHORA)
    igual("lo de ahora le gana a lo de hace medio año", r[0].item.id, "nuevo")
}

// ── Orden estable ───────────────────────────────────────────────────────────
{
    const items = [app("a", "Zeta"), app("b", "Zeta"), app("c", "Zeta")]
    const r1 = S.rank(items, "zeta", null, AHORA).map(x => x.item.id)
    const r2 = S.rank(items, "zeta", null, AHORA).map(x => x.item.id)
    igual("con la misma puntuación, el orden no baila", r1, r2)
    igual("y respeta el orden de entrada", r1, ["a", "b", "c"])
}

// ── Prefijos de modo ────────────────────────────────────────────────────────
igual("= es calcular", S.parseQuery("=2+2"), { mode: "calc", text: "2+2", prefixed: true })
igual("> es comando", S.parseQuery("> htop"), { mode: "command", text: "htop", prefixed: true })
igual(": es emoji", S.parseQuery(":fuego"), { mode: "emoji", text: "fuego", prefixed: true })
igual("? es ajustes", S.parseQuery("?blur"), { mode: "setting", text: "blur", prefixed: true })
igual("@ es portapapeles", S.parseQuery("@http"), { mode: "clipboard", text: "http", prefixed: true })
// La barra es prefijo de modo Y principio de ruta: la ruta se conserva entera.
igual("/ conserva la barra de la ruta",
      S.parseQuery("/etc/hosts"), { mode: "file", text: "/etc/hosts", prefixed: true })
igual("sin prefijo, no hay modo", S.parseQuery("firefox"), { mode: "", text: "firefox", prefixed: false })
igual("vacío no revienta", S.parseQuery(""), { mode: "", text: "", prefixed: false })
igual("null tampoco", S.parseQuery(null), { mode: "", text: "", prefixed: false })

// ── La calculadora ──────────────────────────────────────────────────────────
igual("suma y precedencia", S.calc("2+3*4"), 14)
igual("paréntesis", S.calc("(2+3)*4"), 20)
igual("resta y unario", S.calc("-5+3"), -2)
igual("potencia", S.calc("2^10"), 1024)
igual("potencia asociativa a la derecha", S.calc("2^3^2"), 512)
igual("módulo", S.calc("17%5"), 2)
igual("decimales", S.calc("1.5*2"), 3)
igual("coma decimal a la europea", S.calc("1,5*2"), 3)
igual("espacios", S.calc("  2 +  2 "), 4)

// LO QUE TIENE QUE RECHAZAR. Aquí llega lo que el usuario teclee, así que un
// `eval` convertiría la barra de búsqueda en una consola: basta pegar algo
// copiado de una web para ejecutarlo.
igual("un comando no es una cuenta", S.calc("rm -rf /"), null)
igual("ni una llamada a función", S.calc("alert(1)"), null)
igual("ni acceso a objetos", S.calc("process.exit"), null)
igual("ni código", S.calc("(function(){return 1})()"), null)
igual("ni nombres sueltos", S.calc("Math.PI"), null)
igual("dividir por cero no es un resultado", S.calc("1/0"), null)
igual("módulo por cero tampoco", S.calc("5%0"), null)
igual("una expresión a medias se rechaza", S.calc("2+"), null)
igual("y con basura detrás también", S.calc("2+3 4"), null)
igual("paréntesis sin cerrar", S.calc("(2+3"), null)
igual("texto suelto", S.calc("firefox"), null)
igual("vacío", S.calc(""), null)

// ── Formato del resultado ───────────────────────────────────────────────────
igual("los enteros salen sin coma", S.formatNumber(4), "4")
igual("sin ceros de relleno", S.formatNumber(1.5), "1.5")
igual("sin la basura del coma flotante", S.formatNumber(0.1 + 0.2), "0.3")
// Más allá del entero seguro los dígitos no son reales (1e20 + 1 === 1e20),
// así que enseñarlos sería inventarse una exactitud que no hay.
ok("lo que pasa del entero seguro va en notación científica",
   S.formatNumber(1e20).indexOf("e") !== -1)
igual("pero un entero grande y EXACTO sale entero", S.formatNumber(123456789012), "123456789012")
ok("y lo minúsculo también va en científica", S.formatNumber(0.0000001).indexOf("e") !== -1)

// ── Tope de resultados ──────────────────────────────────────────────────────
{
    const muchos = []
    for (let i = 0; i < 100; i++) muchos.push(app("i" + i, "Fire " + i))
    igual("el límite recorta", S.rank(muchos, "fire", null, AHORA, 10).length, 10)
}

console.log(total + " comprobaciones, " + malas + " mal")
process.exit(malas === 0 ? 0 : 1)
