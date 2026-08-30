#!/bin/sh
# Las tres baterías del shell, en orden de coste creciente.
#
#     sh tests/correr.sh
#
# Se paran en la primera que falle: si los tipos no resuelven, que los archivos
# no compilen no es información nueva, y correr la lógica encima solo entierra
# el error de verdad bajo otros tres.
#
#   qmllint.py   ¿resuelve cada tipo y cada importación? Rápido (segundos).
#                Imprime un perfil de avisos por archivo y categoría; guárdalo
#                antes de un refactor y compáralo después — es lo que permite
#                mover cuarenta archivos sin quedarse a ciegas.
#   qmlcarga.py  ¿COMPILA cada archivo? qmllint analiza, no compila: hay errores
#                (un Component.onCompleted declarado dos veces) que solo se ven
#                pidiéndole al motor que lo cargue. Tarda un par de minutos.
#   jit.py       ¿aguanta el motor con el compilador JIT encendido? Machaca
#                los bindings de larga vida hasta pasar el umbral a partir del
#                cual QV4 compila. Existe porque shell.qml llevaba un pragma
#                que apagaba el JIT por un fallo de Qt 6.11.1, y quitarlo pedía
#                algo que lo respaldara.
#   imports.py   ¿tiene cada archivo los imports que necesita para EJECUTARSE?
#                Es su propia batería porque este fallo pasa por delante de las
#                otras dos: qmllint no se queja (el símbolo existe en el módulo)
#                y el archivo COMPILA (los bindings no se resuelven hasta que se
#                evalúan). Solo se ve en el registro, en ejecución.
#   t_busqueda.js ¿ordena bien el buscador de Spotlight? JS puro con node, sin
#                Quickshell: escalera de coincidencia, acentos y frecencia.
#   logica.py    ¿hacen lo correcto las funciones puras? Levanta Quickshell de
#                verdad, con HOME falso y sin Hyprland, y comprueba la
#                aritmética del layout de la barra, las migraciones de
#                settings.json, el catálogo de emojis y el salto entre paneles.
#
# Las del módulo de IA van aparte y no necesitan Quickshell:
#
#     sh Modules/IA/tests/correr.sh
cd "$(dirname "$0")/.." || exit 1

echo "── qmllint ──"
python3 tests/qmllint.py > /dev/null || { python3 tests/qmllint.py; exit 1; }
echo "  tipos e importaciones OK"

echo "── carga ──"
python3 tests/qmlcarga.py || exit 1

echo "── imports ──"
python3 tests/imports.py > /dev/null || { python3 tests/imports.py; exit 1; }
echo "  todos los símbolos globales tienen su import"

echo "── buscador ──"
node tests/t_busqueda.js || exit 1

echo "── lógica ──"
python3 tests/logica.py || exit 1

echo "── JIT ──"
python3 tests/jit.py 15 || exit 1
