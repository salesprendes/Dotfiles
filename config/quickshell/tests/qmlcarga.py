#!/usr/bin/env python3
"""¿CARGA CADA .qml? Lo que qmllint no puede contestar.

    python3 tests/qmlcarga.py

qmllint analiza, pero no COMPILA. Hay una familia entera de errores que no ve
—el que costó caro fue declarar `Component.onCompleted` dos veces en el mismo
objeto— y que dejan el archivo sin cargar. Peor todavía: cuando el archivo no
carga, qmllint abandona y deja de emitir sus avisos, así que en el informe por
categorías el archivo roto se ve DESAPARECIENDO de la lista. Eso no parece una
alarma; parece que ha mejorado. Y con Quickshell de por medio, un tipo que no
carga se lleva por delante el escritorio entero hasta que se arregla.

Aquí se le pide al motor de QML de verdad que compile cada archivo
(Qt.createComponent) y se mira si protesta. Como fuera de Quickshell los tipos
`Quickshell.*` no existen, TODOS los archivos dan error de importación: eso se
filtra, y lo que queda —lo estructural— es lo que de verdad rompe.

Códigos del sondeo: 0 carga · 1 solo le faltan importaciones · 2 error real.
"""
import os, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QML = "/usr/lib/qt6/bin/qml"
ESPEJO = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "qs-qmllint")
SALTAR = {".git", "node_modules", "__pycache__", "muestras", "data", "qmlroot", "tests"}

# Lo que se perdona: fuera de Quickshell no existen ni sus tipos ni los
# singletons que el espejo no marca. No son fallos del archivo.
# Ojo: nada de comillas dobles aquí dentro — esta lista se incrusta tal cual
# como literal de JavaScript en la sonda, y una comilla la parte por la mitad.
# Pasó, y el resultado fue que los 168 archivos salían "rotos" a la vez, que es
# justo el aspecto que tiene una prueba que no está probando nada.
PERDONABLES = (
    "is not installed", "is not a type", "No such file or directory",
    "was not found", "is not a qualified", "Cannot load library",
    "Quickshell", "not a type", "unavailable", "Cannot assign to non-existent",
)

SONDA = r'''
import QtQuick
Item {
    Component.onCompleted: {
        var c = Qt.createComponent(Qt.application.arguments[Qt.application.arguments.length - 1])
        if (c.status !== Component.Error) { Qt.exit(0); return }
        var perdonables = %s
        var real = false
        var lineas = c.errorString().split("\n")
        for (var i = 0; i < lineas.length; i++) {
            var l = lineas[i].trim()
            if (l === "") continue
            var ok = false
            for (var j = 0; j < perdonables.length; j++)
                if (l.indexOf(perdonables[j]) !== -1) { ok = true; break }
            if (!ok) real = true
        }
        Qt.exit(real ? 2 : 1)
    }
}
''' % str(list(PERDONABLES)).replace("'", '"')


def archivos():
    out = []
    for aqui, dirs, fs_ in os.walk(RAIZ):
        dirs[:] = [d for d in dirs if d not in SALTAR and not d.startswith(".")]
        for f in fs_:
            if f.endswith(".qml"):
                out.append(os.path.join(aqui, f))
    return sorted(out)


def comprueba(sonda, ruta):
    try:
        r = subprocess.run([QML, "-platform", "offscreen", "-I", ESPEJO, sonda, "--", ruta],
                           capture_output=True, text=True, timeout=40)
        return r.returncode
    except subprocess.TimeoutExpired:
        return 3


def main():
    if not os.path.exists(QML):
        print("no está el runtime de qml en", QML)
        return 1
    fs_ = archivos()
    with tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False) as t:
        t.write(SONDA)
        sonda = t.name
    try:
        with ThreadPoolExecutor(max_workers=8) as pool:
            codigos = list(pool.map(lambda r: comprueba(sonda, r), fs_))
    finally:
        os.unlink(sonda)

    rotos = [(os.path.relpath(r, RAIZ), c) for r, c in zip(fs_, codigos) if c >= 2]
    print("%d archivos .qml comprobados contra el motor de QML" % len(fs_))
    if not rotos:
        print("todos compilan (los errores de importación se perdonan a propósito)")
        return 0
    print()
    print("── %d NO COMPILAN ──" % len(rotos))
    for rel, c in rotos:
        print("  %-46s %s" % (rel, "se colgó" if c == 3 else "error estructural"))
    print()
    print("Para ver el motivo:  /usr/lib/qt6/bin/qml -I %s <archivo>" % ESPEJO)
    return 1


if __name__ == "__main__":
    sys.exit(main())
