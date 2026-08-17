// A QUÉ SERVIDOR SE HABLA Y CON QUÉ MODELO.
//
// Estaba dentro de AiService.qml, o sea dentro de un singleton de mil
// trescientas líneas, o sea sin ninguna forma de probarlo: la única manera de
// saber si una URL pegada a medias acababa en la base correcta era pegarla en
// los ajustes y mirar si el envío fallaba.
//
// Aquí es JavaScript puro sobre un objeto de ajustes, así que las docenas de
// formas en que un usuario pega mal una URL se comprueban de una en una (ver
// tests/t_endpoint.js). Lo que queda en QML son enlaces de una línea que llaman
// aquí.
.pragma library
.import "../TextUtils.js" as TU

// 'base' es la raíz /v1 del contrato OpenAI: de ahí salen SIEMPRE las dos
// direcciones que usa el harness (/chat/completions para hablar y /models para
// descubrir el catálogo). Los dos proveedores con URL de usuario la dejan vacía
// y la calculan en baseDe().
//
// La etiqueta de 'custom' la traduce el harness: aquí no puede, porque una
// biblioteca pura no ve I18n.
const PROVEEDORES = {
    gemini: {
        label: "Gemini",
        base: "https://generativelanguage.googleapis.com/v1beta/openai",
        needsKey: true, userUrl: false
    },
    openrouter: {
        label: "OpenRouter",
        base: "https://openrouter.ai/api/v1",
        needsKey: true, userUrl: false
    },
    ollama: {
        label: "Ollama",
        base: "",           // la URL base la pone el usuario (aiOllamaUrl)
        needsKey: false, userUrl: true
    },
    // Cualquier servidor OpenAI-compatible, REMOTO o local: vLLM, TGI, LiteLLM,
    // LM Studio publicado, un Ollama tras un proxy inverso… URL base /v1
    // configurable y clave OPCIONAL (needsKey false: sin clave no se bloquea el
    // envío; si la pones, viaja como Bearer).
    custom: {
        label: "",          // lo rotula el harness
        base: "",
        needsKey: false, userUrl: true
    }
}

function proveedorDe(id) {
    return PROVEEDORES[String(id || "")] || PROVEEDORES.gemini
}

// El modelo elegido de CADA proveedor vive en su propio ajuste. Este par de
// funciones es el único sitio que conoce ese reparto: antes el mismo switch de
// cuatro ramas estaba copiado en cinco puntos del archivo.
//
//   aj = { openrouter, ollama, custom, gemini }  (los cuatro ajustes de modelo)
function modeloDe(id, aj) {
    const a = aj || ({})
    return id === "openrouter" ? String(a.openrouter || "")
         : id === "ollama"     ? String(a.ollama || "")
         : id === "custom"     ? String(a.custom || "")
                               : String(a.gemini || "")
}

// A qué ajuste hay que escribirle un modelo nuevo.
function ajusteDe(id) {
    return id === "openrouter" ? "openrouter"
         : id === "ollama"     ? "ollama"
         : id === "custom"     ? "custom" : "gemini"
}

// Raíz /v1 efectiva del proveedor activo ("" si aún falta la URL). La
// normalización es deliberadamente indulgente: una URL remota se copia y se
// pega mal —sobran barras, falta el esquema, se pega el endpoint completo— y
// todo eso tiene que acabar en la misma base.
//
//   urls = { ollama, custom }
function baseDe(id, urls) {
    const p = proveedorDe(id)
    if (!p.userUrl)
        return p.base
    const u = urls || ({})
    return TU.normalizeBase(id === "ollama" ? u.ollama : u.custom)
}

function endpointDe(base) {
    return base === "" ? "" : base + "/chat/completions"
}

// Catálogo del servidor. Ollama publica el suyo FUERA de /v1 (/api/tags); el
// resto, en el /models del contrato OpenAI.
function modelosUrl(base, id) {
    if (base === "")
        return ""
    return id === "ollama" ? base.replace(/\/v1$/, "") + "/api/tags"
                           : base + "/models"
}

// La sintaxis "proveedor:modelo" de aisuite: "ollama:qwen3" cambia proveedor Y
// modelo en un gesto. Sin prefijo conocido es solo el modelo del proveedor
// actual — los ":free" de OpenRouter no chocan porque el prefijo se compara
// contra el catálogo de proveedores, no contra cualquier cosa antes de un dos
// puntos.
//
//   → { proveedor, modelo }
function parseModelo(texto, actual) {
    let nombre = String(texto || "").trim()
    let destino = String(actual || "")
    const dosPuntos = nombre.indexOf(":")
    if (dosPuntos > 0) {
        const prefijo = nombre.slice(0, dosPuntos)
        if (PROVEEDORES[prefijo]) {
            destino = prefijo
            nombre = nombre.slice(dosPuntos + 1)
        }
    }
    return { proveedor: destino, modelo: nombre }
}

// Qué falta para poder hablar. El panel lo usa para invitar a configurar en vez
// de dejar que el envío falle con un error de red que no explica nada.
function faltan(id, base, clave) {
    const p = proveedorDe(id)
    const sinUrl = p.userUrl && base === ""
    const sinClave = p.needsKey && String(clave || "") === ""
    return { url: sinUrl, clave: sinClave, alguna: sinUrl || sinClave }
}
