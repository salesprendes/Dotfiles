# Pruebas del shell

    sh tests/correr.sh

Tres baterías, en orden de coste creciente. Se paran en la primera que falle.

| Guion | Qué contesta | Coste |
|---|---|---|
| `qmllint.py` | ¿Resuelve cada tipo y cada importación? | segundos |
| `qmlcarga.py` | ¿**Compila** cada archivo? | ~2 min |
| `logica.py` | ¿Dan el resultado correcto las funciones puras? | ~10 s |

Las tres son independientes y se pueden correr sueltas.

## `qmllint.py`

qmllint por sí solo no puede resolver `import qs.Config` ni los tipos locales,
porque el módulo `qs` lo sintetiza Quickshell desde la carpeta de configuración.
Aquí se le da escrito: un espejo de enlaces con un `qmldir` generado en cada
carpeta. Los archivos van por enlace, así que el espejo nunca se queda viejo.

Imprime un **perfil de avisos** por archivo y categoría. Su uso no es leerlo
entero, sino compararlo:

    python3 tests/qmllint.py > antes.txt
    # … refactor …
    python3 tests/qmllint.py | diff antes.txt -

Si el perfil sale idéntico, no ha quedado ninguna referencia rota. Sin esto, un
refactor de cuarenta archivos en QML es mover a ciegas.

Los errores **de verdad** ("Property value set multiple times", un tipo que no
existe) van aparte y hacen fallar el guion, porque un error hace que qmllint
ABANDONE el archivo: en el informe por categorías eso se ve como el archivo
DESAPARECIENDO de la lista, que parece justo lo contrario de una alarma.

## `qmlcarga.py`

qmllint analiza, pero no **compila**. Hay una familia entera de errores que no
ve —el que costó caro fue declarar `Component.onCompleted` dos veces— y que
dejan el archivo sin cargar. Aquí se le pide al motor de QML de verdad que
compile cada archivo y se mira si protesta. Fuera de Quickshell los tipos
`Quickshell.*` no existen, así que los errores de importación se perdonan a
propósito: lo que queda es lo estructural.

## `logica.py`

Las otras dos dicen si el código carga; esta dice si **hace lo correcto**.
Levanta Quickshell de verdad contra un espejo del árbol, con `tests/logica.qml`
de `shell.qml`, y comprueba:

- la aritmética de índices al mover un widget de la barra (`BarCatalog`),
- el saneado de `barLayout` (ids desconocidos, duplicados, secciones que faltan),
- las **migraciones de `settings.json`** — una migración equivocada no rompe el
  arranque: te cambia los ajustes en silencio, que es peor,
- el catálogo de emojis (estructura y búsqueda),
- el recorrido del salto entre paneles.

Se aísla en tres frentes, y los tres importan: `HOME` apunta a una casa falsa
(así `Settings` no toca el `settings.json` del usuario),
`HYPRLAND_INSTANCE_SIGNATURE` se vacía (así no se lanza ni un `hyprctl` contra
la sesión que esté corriendo — sin esto, correr las pruebas recargaría Hyprland)
y `QT_QPA_PLATFORM=offscreen` (sin ventanas).

Detalle a tener en cuenta al escribir pruebas nuevas: **`Qt.exit()` no
funciona** dentro de Quickshell (avisa con *"Signal QQmlEngine::exit() emitted,
but no receivers connected"*). Por eso el guion de Python lee la salida y mata
el proceso al ver la línea `PRUEBA TOTAL`.

## `emoji.py`

No es una prueba: regenera `Modules/Emoji/emoji.json` a partir de la base de
datos Unicode de Python y los códigos ISO 3166-1 del sistema. Se corre a mano
cuando salga una versión de Unicode nueva.

    python3 tests/emoji.py

## Las del módulo de IA

Van aparte y no necesitan Quickshell: los `.js` del módulo son `.pragma library`
y node los carga directamente.

    sh Modules/IA/tests/correr.sh
