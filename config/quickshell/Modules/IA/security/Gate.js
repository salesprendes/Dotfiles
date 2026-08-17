// LA PUERTA. Todo lo que hay que saber para dejar correr una llamada, decidido
// en UN sitio y entregado como un PERMISO que el ejecutor no puede ignorar.
//
// EL PROBLEMA QUE RESUELVE. Las invariantes de seguridad del harness estaban
// implementadas varias veces, una por cada camino que llega a ejecutar algo:
//
//               jaula  reloj  marco  secretos  auditoría
//   ejecutor      sí     sí     sí      sí        sí
//   subagente     sí     sí     sí      sí        sí
//   celda         sí     NO     NO      sí        sí
//
// La celda de Python podía traer una página web al contexto sin el marco de
// «esto lo escribió un desconocido» y sin plazo, no porque nadie lo hubiera
// pensado, sino porque la regla vivía escrita en el ejecutor y en el subagente
// y a la tercera puerta se olvidó. Una invariante que depende de que tres
// piezas se acuerden no es una invariante: es una costumbre.
//
// CÓMO SE ARREGLA. Aquí se calcula la ENVOLTURA de cada llamada —plazo, marco,
// permiso de red local, tope de resultado— y se sella en un permiso. El
// ejecutor deja de recibir un comando: recibe un permiso CON el comando, y sin
// permiso válido no ejecuta nada. Un camino que se olvide de pedirlo no se
// salta la regla en silencio: falla, y se ve.
//
// Es una biblioteca pura: ni red, ni QML, ni estado. Se prueba entera desde
// node (ver tests/t_puerta.js).
.pragma library
.import "../tools/ToolPolicy.js" as TP
.import "../tools/LocalTools.js" as LT
.import "../integrations/WebSearch.js" as WS

// La marca del permiso. No es un secreto ni pretende serlo: es lo que
// distingue un permiso ACUÑADO AQUÍ de un objeto cualquiera que llegue al
// ejecutor, que es justo el descuido que se quiere volver imposible.
const SELLO = "qs-permiso-1"

// Quién puede pedir permiso. Cada uno tiene su alcance y su jaula, pero la
// envoltura la calcula esta puerta para los tres.
const QUIENES = { agente: 1, subagente: 1, celda: 1 }

// ── Qué trae texto escrito por un desconocido ────────────────────────────────
// La lista es corta y explícita a propósito: si mañana entra una herramienta
// que sale a internet, tiene que aparecer AQUÍ o no se enmarca, y eso se ve en
// la prueba de la matriz.
function fuenteExterna(herramienta, args) {
    const a = args || ({})
    if (herramienta === "fetch_url")
        return String(a.url || "una página web")
    if (herramienta === "web_search")
        return "una búsqueda web"
    return ""
}

// ── El permiso ───────────────────────────────────────────────────────────────
//   pet = { quien, herramienta, args, aprobadaPorUsuario, zonaLocal }
//
//   aprobadaPorUsuario  la tarjeta se enseñó y el usuario la aprobó
//   zonaLocal           la URL YA nombraba una dirección de la red de casa
//
// Devuelve null si quien pide no existe o no hay herramienta: un permiso que no
// se puede acuñar es un "no", no un permiso vacío.
function evaluar(pet) {
    const p = pet || ({})
    const herramienta = String(p.herramienta || "")
    if (herramienta === "" || !QUIENES[String(p.quien || "")])
        return null
    const args = p.args || ({})
    // LA RED DE CASA. Solo se llega a ella cuando la dirección la enseñaba ya
    // la tarjeta que el usuario aprobó: entonces sabía a dónde iba. Lo que no
    // se permite nunca es aterrizar dentro por sorpresa —una URL pública que
    // redirige, un nombre que resuelve hacia dentro—, ni desde un subagente o
    // una celda, que trabajan sin que nadie mire.
    const redLocal = p.quien === "agente"
                  && p.aprobadaPorUsuario === true
                  && p.zonaLocal === true
    return {
        sello: SELLO,
        quien: String(p.quien),
        herramienta: herramienta,
        envoltura: {
            // El plazo lo pone la política, por nombre. Un solo reloj: el que
            // se anuncia es el que corta.
            plazoMs: TP.deadlineMs(herramienta),
            // De qué fuente viene lo que va a volver ("" = lo decimos nosotros).
            marcar: fuenteExterna(herramienta, args),
            redLocal: redLocal,
            // Lo que hay que añadirle al entorno del proceso. Va aquí y no en
            // cada constructor porque es una DECISIÓN, no un detalle del
            // comando: quien construye no sabe si el usuario aprobó la
            // dirección local.
            extraEnv: herramienta === "fetch_url"
                      ? ({ QS_LAN: redLocal ? "1" : "" }) : ({})
        }
    }
}

// ¿Es esto un permiso de verdad, y es el de ESTA herramienta? Lo segundo
// importa tanto como lo primero: un permiso de read_file reutilizado para un
// run_command traería el plazo y el marco equivocados.
function valido(permiso, herramienta) {
    if (!permiso || permiso.sello !== SELLO || !permiso.envoltura)
        return false
    if (herramienta !== undefined && permiso.herramienta !== String(herramienta))
        return false
    return true
}

// ── Aplicar la envoltura ─────────────────────────────────────────────────────
// El comando que de verdad se lanza. Aquí se pone el reloj y el tope de salida
// (que los pone coreutils dentro del propio comando, no un temporizador de
// fuera: así el que mata es el sistema y no hay carrera con la salida tardía) y
// se resuelve el permiso de red local.
//
// Devuelve null cuando el permiso no vale: quien llama debe tratar eso como un
// fallo ruidoso, nunca ejecutar de todas formas.
function envolver(permiso, cmd, env) {
    if (!valido(permiso))
        return null
    const e = ({})
    const base = env || ({})
    for (const k in base)
        e[k] = base[k]
    const extra = permiso.envoltura.extraEnv || ({})
    for (const k in extra)
        e[k] = extra[k]
    return {
        cmd: LT.acotado(Math.round(permiso.envoltura.plazoMs / 1000), cmd),
        env: e
    }
}

// ── El marco del texto ajeno ─────────────────────────────────────────────────
// ¿Lo que vuelve lo escribió un desconocido? Solo si la herramienta salía a
// buscarlo fuera Y no es un aviso NUESTRO. Enmarcar un rechazo propio ("solo
// URLs http(s)", "esta página exige JavaScript") como escrito por un extraño
// sería mentirle al modelo sobre quién le está hablando.
function ajeno(permiso, texto) {
    if (!valido(permiso) || permiso.envoltura.marcar === "")
        return false
    return String(texto).indexOf(LT.FETCH_KO) === -1
}

// El texto ya listo para entrar al contexto. Idempotente: lo que ya viene
// enmarcado no se enmarca dos veces.
function marcar(permiso, texto) {
    if (!ajeno(permiso, texto) || WS.fenced(texto))
        return String(texto)
    return WS.fence(String(texto), permiso.envoltura.marcar)
}

// ── La matriz, escrita ───────────────────────────────────────────────────────
// Qué le corresponde a cada llamante. No lo consume el código: lo consume la
// prueba, que comprueba que los tres ejecutores aplican de verdad lo que aquí
// se declara. Tener la matriz escrita es lo que convierte "hay que acordarse"
// en "falla en rojo".
const MATRIZ = {
    agente:    { jaula: true, reloj: true, marco: true, secretos: true,
                 auditoria: true, hooks: true, supervisor: true,
                 bucles: true, redLocal: true },
    subagente: { jaula: true, reloj: true, marco: true, secretos: true,
                 auditoria: true, hooks: false, supervisor: false,
                 bucles: true, redLocal: false },
    celda:     { jaula: true, reloj: true, marco: true, secretos: true,
                 auditoria: true, hooks: false, supervisor: false,
                 bucles: false, redLocal: false }
}
