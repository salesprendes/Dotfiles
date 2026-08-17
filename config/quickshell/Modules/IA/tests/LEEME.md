# Baterías del harness

    sh tests/correr.sh

1562 comprobaciones, dos pasadas idénticas. No hace falta Quickshell ni un modelo:
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
| `t_cerco.js` | Que lo publicado por un servidor MCP no se auto-apruebe por el verbo de su nombre (`get_secrets` puede borrar una base de datos), que una ruta que apunta fuera por un enlace simbólico no se lea ni se escriba, y que el shell libre no vea las credenciales del entorno ni se salte el detector de peligro. |
| `t_depurador.js` | Que cada lenguaje vaya a su adaptador DAP (trece, de gdb a elixir-ls), que la petición tenga la forma que ese adaptador entiende —`stopAtEntry` en netcoredbg, `mode: local` en delve— y que al faltar uno se diga cuál y con qué paquete se instala. |
| `t_podar.js` | Que antes de pagar un resumen se tire lo que ya no hace falta **y solo eso**: la mayoría de las comprobaciones son de lo que NO se poda (un fallo, una edición, el informe de un subagente, las instrucciones de una habilidad, la búsqueda que llevó a algo, y los tramos de un archivo que se está leyendo por partes). Y que la **caché de prefijo** mande: sin ahorro suficiente o con mucho que reprocesar detrás, no se toca nada. |
| `t_puerta.js` | Que no se pueda ejecutar nada del modelo sin pasar por `security/Gate.js`: el ejecutor recibe un **permiso**, no un comando, y sin permiso válido falla en vez de ejecutar. Incluye el **censo de ejecutores** —cada `Process` del módulo, contado— para que abrir uno nuevo sea una decisión consciente y no un camino que aparece sin que nadie lo mire. |
| `t_despacho.js` | Los doce constructores de comando que vivían dentro de un `switch` de 367 líneas en QML, ahora comprobables uno a uno: la jaula de rutas, que una unidad de systemd no pueda parecer una opción, que el PID 1 se rechace, que subir y bajar por scp no diverjan. Y que el despachador **no** ponga reloj ni marco: eso es de la puerta. |
| `t_endpoint.js` | Las doce formas en que se pega mal la URL de un servidor propio y por qué todas tienen que acabar en la misma raíz `/v1`. Y el caso que lo rompía todo: un `:free` de OpenRouter lleva dos puntos y **no** es un prefijo de proveedor. |
| `t_guion.js` | Que al archivero se le mande una **transcripción acotada** y no el protocolo de herramientas con los resultados íntegros —de eso depende que resumir sea barato y que quepa justo cuando el contexto acaba de desbordar—, que la bandera de «no encontré nada» la ponga la propia herramienta, y que los nueve dialectos de «no cabe» se reconozcan sin confundirlos con un 429. |

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

## El QML

    python3 tests/qmllint.py

Comprueba que cada tipo y cada importación resuelvan de verdad. qmllint por sí
solo no puede: el módulo `qs` lo sintetiza Quickshell desde la carpeta de
configuración, y qmllint no sabe de eso. El guion le monta un espejo de enlaces
con un `qmldir` generado en cada carpeta y se lo da masticado.

Es lo que permitió reorganizar el módulo entero sin romperlo: se guarda el
perfil de avisos antes, se mueve todo, y si sale idéntico es que no ha quedado
ninguna referencia rota.

    python3 tests/qmllint.py > /tmp/antes.txt
    …mover cosas…
    python3 tests/qmllint.py | diff /tmp/antes.txt -

## Probar una biblioteca en el motor de Qt de verdad

Node carga los `.pragma library` quitando esa línea, pero node **no** es el
motor de Qt. Cuando una biblioteca usa algo propio de QML —`.import` entre
bibliotecas, por ejemplo— hay que comprobarlo donde va a correr, y se puede
hacer sin tocar el shell del usuario:

    /usr/lib/qt6/bin/qml -platform offscreen prueba.qml

con un `Component.onCompleted` que termine en `Qt.exit(0)` o `Qt.exit(3)`. Así
se comprobó que `security/Gate.js` podía importar la política, las herramientas
locales y el buscador antes de escribir una sola línea que dependiera de ello.
`console.log` no sale por ahí: el veredicto va en el código de salida.

## ¿Carga cada .qml?

    python3 tests/qmlcarga.py

qmllint **analiza, pero no compila**, y hay una familia entera de errores que no
ve. El que costó caro: declarar `Component.onCompleted` dos veces en el mismo
objeto. qmllint no dice ni una palabra —comprobado— y el shell entero se queda
sin cargar.

Y hay algo peor que no verlo. Cuando un archivo no carga, qmllint **abandona** y
deja de emitir sus avisos, así que en el informe por categorías el archivo roto
se ve *desapareciendo de la lista*. Eso no parece una alarma: parece que ha
mejorado. Pasó exactamente así.

Este guion le pide al motor de QML de verdad que compile cada archivo
(`Qt.createComponent`) y mira si protesta. Como fuera de Quickshell sus tipos no
existen, todos dan error de importación: eso se perdona, y lo que queda es lo
estructural. 168 archivos en menos de un segundo, en paralelo.

## Y la última palabra la tiene el shell

    qs log -i <instancia> | tail

`qmlcarga.py` dice que un archivo **compila**; no dice que se **instancie**. Hay
errores que solo aparecen al montar el objeto — animar una propiedad de solo
lectura, por ejemplo: compila perfecto y luego «Invalid property assignment:
"carril" is a read-only property», y el panel no carga.

Así que el orden es: `qmlcarga.py` primero (rápido, y caza lo estructural sin
tocar nada), y el log del shell después, que es quien de verdad lo monta. Con la
recarga en caliente, mirar el log cuesta dos segundos y es la única prueba que
no miente.

## Lo que no cubren

Ninguna batería levanta el shell entero: el ciclo de vida de los `Process`, las
carreras entre conversaciones y **el aspecto** de la interfaz se comprueban a
mano. `qmlcarga.py` dice que un archivo compila, no que se vea bien.
