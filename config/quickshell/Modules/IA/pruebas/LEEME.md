# Baterías del harness

    sh pruebas/correr.sh

1056 comprobaciones, dos pasadas idénticas. No hace falta Quickshell ni un modelo:
los `.js` del módulo son `.pragma library`, así que node los carga quitando esa
línea, y los dobles de prueba en Python levantan el servidor que haga falta.

| Batería | Qué defiende |
|---|---|
| `t_transporte.js` | Que el cuerpo HTTP va por la entrada estándar y no por `argv` (128 kB por argumento, y el `argv` lo lee cualquiera en `/proc`). Incluye una comprobación **sobre el fuente** de los cinco llamantes: nació después de que el supervisor se quedara mudo semanas por no actualizarse a la firma nueva. |
| `t_redteam.js` | Página hostil → `web_search` → `fetch_url` → inyección → herramienta. El cerco del contenido externo, la falsificación del delimitador y el tapado de secretos. |
| `t_reloj.js` | Que los plazos cortan de verdad (lo hace coreutils, no QML), que el código de salida es el de la herramienta, y el tope de salida de 2 MB. |
| `t_websearch.js` | Fusión por consenso, cuarentena, caché, y que una fuente que no contesta se diga en vez de desaparecer. |
| `t_subagente.js` | Que el taller es una pared y no una sugerencia. |
| `t_fetch.js` | Extracción, tipos que no son texto, códigos HTTP y muros anti-robot. |
| `t_ssrf.js` | Que la red de casa no se lee **ni se toca**: se resuelve el nombre antes de conectar, se miran todas sus direcciones y se fija la elegida con `--resolve`. El `soplon.py` demuestra lo que no se puede ver en la respuesta — que la petición no llegó a salir. |
| `t_recetas.js` | Que un enlace de npm, PyPI, crates.io, GitHub, GitLab, arXiv, Stack Overflow, Hacker News, MDN, ReadTheDocs o docs.rs vaya a su API en vez de a la página, y que cuando esa API cambie de forma se caiga al HTML **sin escribir media cosa**. Respuestas grabadas en `muestras/`, recortadas a lo que se lee. |
| `t_cerco.js` | Que lo publicado por un servidor MCP no se auto-apruebe por el verbo de su nombre (`get_secrets` puede borrar una base de datos), y que una ruta que parece de casa pero apunta fuera por un enlace simbólico no se lea ni se escriba. |
| `t_depurador.js` | Que cada lenguaje vaya a su adaptador DAP (trece, de gdb a elixir-ls), que la petición tenga la forma que ese adaptador entiende —`stopAtEntry` en netcoredbg, `mode: local` en delve— y que al faltar uno se diga cuál y con qué paquete se instala. |

## Dobles de prueba

`falso_buscador.py`, `falsa_web.py`, `web_hostil.py`, `falso_llm.py` y
`colgado.py`. Los levanta cada batería y los para al terminar.

## Dos reglas

**Aislar el estado entre pasadas.** Cada tanda usa su directorio temporal
(`QS_CUAR`). Ya hubo siete falsos fallos por una caché que vivía en `~/.cache` y
contaminaba la segunda pasada.

**Aprobar la red local a mano.** Los dobles viven en `127.0.0.1` y `fetch_url` ya
no aterriza ahí sin permiso, así que las baterías ponen `QS_LAN=1` — lo que se
está probando es lo que pasa *después*, con el texto ya dentro.

## Lo que no cubren

No hay nada que ejecute QML: el ciclo de vida de los `Process`, las carreras
entre conversaciones y la interfaz se comprueban a mano. Para el QML,
`/usr/lib/qt6/bin/qmllint --bare` (está instalado, pero no en el `PATH`).
