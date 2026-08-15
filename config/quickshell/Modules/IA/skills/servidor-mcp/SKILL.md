---
name: "Construir un servidor MCP"
description: "Cómo diseñar y escribir un servidor MCP que un modelo sepa usar: nombres de herramientas, esquemas, errores que enseñan y cómo probarlo. Úsala para conectar el asistente a una API, a un servicio o a datos que aún no puede tocar."
source: "adaptada de anthropics/skills (mcp-builder), Apache-2.0"
---

# Construir un servidor MCP

Adaptada del `mcp-builder` de Anthropic (Apache-2.0) al harness de este
equipo. **La calidad de un servidor MCP no se mide en herramientas: se mide
en tareas reales que el modelo consigue terminar con ellas.**

## Antes de escribir nada

Contesta tres cosas:

1. **¿Qué tareas** quiere resolver el usuario? Escríbelas como frases
   («ver qué cambió en el repo desde ayer»), no como endpoints.
2. **¿Qué datos** hacen falta para cada una, y de dónde salen.
3. **¿Qué NO debe poder hacer?** En este equipo la respuesta suele ser
   «escribir»: un servidor de solo lectura se aprueba una vez y ya.

Si dudas entre cubrir la API entera o hacer herramientas por flujo de
trabajo, cubre la API: el modelo compone. Las herramientas de flujo son para
cuando una tarea concreta necesita cinco llamadas siempre en el mismo orden.

## Diseño de las herramientas

**Nombres.** Prefijo consistente y verbo: `git_status`, `git_log`,
`sqlite_query`. El modelo elige por el nombre antes que por la descripción.

**Descripción.** Qué hace, cuándo usarla y qué devuelve — en dos líneas.
Aquí se paga contexto en CADA mensaje, así que la prosa sobra. Si hay una
trampa («míralo antes con `sqlite_schema`»), esa frase vale más que un
párrafo de introducción.

**Esquema de entrada.** Tipos, `enum` cuando hay opciones cerradas, y una
`description` por campo con un ejemplo si el formato no es obvio
(`since: "-1h, -2d, today"`). Marca solo como `required` lo imprescindible.

**Salida.** Pensada para leerse: tablas alineadas mejor que JSON crudo,
recortada con un tope y diciendo que se recortó. Un volcado de 200 kB no
ayuda a nadie: se come el contexto y entierra la respuesta. Si el conjunto
es grande de verdad, pagina: un parámetro `offset` o `cursor` y la salida
diciendo cuántos quedan — el modelo sabe pedir la siguiente página si se
lo dices. Y si una herramienta lista cosas, que devuelva el identificador
EXACTO que otra herramienta acepta: el modelo encadena copiando literal, y
un id que hay que transformar a mano es una llamada fallida segura.

**Errores que enseñan.** Un error es una oportunidad de que el modelo
acierte a la siguiente:

```
mal:  "Error: not found"
bien: "No existe la tabla 'usuarios'. Las que hay: clientes, pedidos.
       Míralas con sqlite_tables."
```

## Fallos con nombre y apellidos

- **El cliente se queda esperando para siempre.** Causa casi única: algo
  escribió en stdout lo que no era JSON-RPC — un `print` de depuración,
  una biblioteca que saluda al importarse. Diagnóstico: la tubería de
  abajo, leyendo la salida línea a línea. Arreglo: todo a stderr
  (`print(..., file=sys.stderr)`) y revisar qué imprimen los imports.
- **Responder a una notificación.** Los mensajes SIN `id`
  (`notifications/initialized`, cancelaciones) no se responden JAMÁS:
  contestar a uno descoloca a los clientes. Regla mecánica: sin `id`, sin
  respuesta.
- **Error de protocolo donde tocaba error de herramienta.** Si la
  herramienta corrió pero el resultado es un fallo («no existe esa
  tabla»), se devuelve como resultado normal con `isError: true` y un
  texto que enseñe — así el modelo lo LEE y rectifica. El error JSON-RPC
  (`"error": {...}`) se reserva para peticiones malformadas: los clientes
  lo tratan como avería del servidor, no como algo que el modelo deba
  leer.
- **Una herramienta colgada congela el servidor entero.** El bucle es de
  un solo hilo: si una llamada externa no vuelve, no vuelve NADA. Todo
  subprocess lleva `timeout=` (capturando `TimeoutExpired` con un error
  útil) y toda petición de red lleva plazo.
- **Los argumentos llegan «casi» bien.** Los modelos mandan `"5"` donde el
  esquema pedía 5, y `null` en los opcionales. A la entrada se convierte
  con manga ancha, y se valida lo que de verdad importa: rutas con
  `safe_path()`, valores contra su `enum`.

## El patrón de este equipo

Los tres servidores de `Modules/IA/mcp/` (git, docs, sqlite) son python3 a
secas, sin dependencias, porque aquí **no hay node ni uv**. Para uno nuevo,
copia ese patrón:

- `_base.py` ya trae `serve()`, `send()`, `text()`, `fail()`, `run()`,
  `safe_path()` y `tool()`. No lo reescribas.
- Solo lectura salvo que haya un motivo fuerte, y las rutas acotadas a
  `$HOME` con `safe_path()`. «Solo lectura» de verdad es DOBLE cerrojo,
  como el sqlite de la casa: abrir con `mode=ro` Y además una lista blanca
  de sentencias (SELECT/WITH/PRAGMA/EXPLAIN, una sola por llamada). Un
  cerrojo único siempre acaba teniendo un agujero.
- Los comandos se ejecutan con **lista de argumentos**, nunca por shell.
- **Secretos por entorno, nunca por parámetro**: un token que viaja como
  argumento de herramienta acaba en la transcripción y en los registros.
  El servidor lo lee de una variable de entorno y las herramientas ni lo
  mencionan.
- **stdout es sagrado**: solo JSON de una línea. Cualquier traza, a stderr.
- El resultado de una herramienta vuelve como bloques de contenido, y el
  cliente de este harness solo aplana los de `type: "text"`: cualquier
  otro tipo se descarta en silencio. Texto siempre.
- Lee stdin con `readline()` en bucle y arranca con `python3 -u`: iterando
  con `for line in sys.stdin` el proceso puede quedarse esperando a llenar
  el buffer mientras el cliente espera la respuesta.

Registrarlo: se añade a `aiMcpServers` en Ajustes avanzados (nombre +
comando). Sus herramientas le llegan al modelo como `mcp__<nombre>__<tool>`
y pasan por la misma tarjeta de aprobación que las demás. Si en vez de la
interfaz editas `settings.json` a mano, fuerza después una recarga del
shell: no vigila ese archivo, y su próximo guardado pisaría tu edición.

## Probarlo antes de enchufarlo

Sin el shell de por medio, con tuberías y en el mismo orden que un cliente
real (initialize, la notificación, y las llamadas):

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"mi_tool","arguments":{}}}' \
  | python3 mi_servidor.py
```

Comprueba tres cosas: que cada respuesta es UNA línea de JSON válido, que
la notificación (sin `id`) no recibió respuesta, y que no se coló ninguna
línea de texto suelto. Luego una `tools/call` de cada herramienta, incluida
**una que falle** a propósito: la mitad de los fallos de un servidor MCP
están en el camino del error, que nadie prueba.

## La prueba de verdad

Escribe cinco preguntas reales que el usuario haría, y comprueba que el
modelo las resuelve con tus herramientas sin ayuda. Si tiene que adivinar un
formato, falta una `description`. Si necesita cuatro llamadas para algo
cotidiano, falta una herramienta.
