#!/usr/bin/env python3
"""Comprueba el QML de verdad: que cada tipo y cada importación resuelvan.

    python3 tests/qmllint.py            # avisos por archivo y categoría
    python3 tests/qmllint.py > base.txt # …y luego `diff` tras un cambio

qmllint por sí solo no puede resolver `import qs.Config` ni los tipos locales,
porque el módulo `qs` lo sintetiza Quickshell desde la carpeta de configuración
y qmllint no sabe de eso. Aquí se le da escrito: un espejo de enlaces con un
`qmldir` generado en cada carpeta. Los archivos van por enlace, así que el
espejo nunca se queda viejo.

Esto es lo que permitió reorganizar el módulo entero sin romperlo: se guarda el
perfil de avisos ANTES, se mueve todo, y si el perfil sale idéntico es que no ha
quedado ninguna referencia rota. Sin esto, un refactor de cuarenta archivos en
QML es mover a ciegas y esperar a que el escritorio deje de arrancar.

qmllint y qmlformat están en /usr/lib/qt6/bin/, que no está en el PATH.
"""
import os, re, shutil

# Sale del propio archivo (tests/ → IA/ → Modules/ → la raíz), no escrita a
# mano: si la configuración vive en otra carpeta —o en la casa de otro usuario—
# esto sigue funcionando sin tocar nada.
RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
# FUERA del árbol de configuración a propósito: dentro, el propio recorrido
# se metería por el espejo y acabaría siguiendo enlaces en círculo.
DEST = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "qs-qmllint")
SALTAR = {".git", "node_modules", "__pycache__", "muestras", "data", "qmlroot"}

shutil.rmtree(DEST, ignore_errors=True)
for aqui, dirs, archivos in os.walk(RAIZ):
    dirs[:] = [d for d in dirs if d not in SALTAR and not d.startswith(".")]
    rel = os.path.relpath(aqui, RAIZ)
    destino = os.path.join(DEST, "qs") if rel == "." else os.path.join(DEST, "qs", rel)
    os.makedirs(destino, exist_ok=True)
    tipos = []
    for f in archivos:
        if f.startswith("."):
            continue
        try:
            os.symlink(os.path.join(aqui, f), os.path.join(destino, f))
        except FileExistsError:
            pass
        if f.endswith(".qml") and f[0].isupper():
            tipos.append("%s 1.0 %s" % (f[:-4], f))
    uri = "qs" if rel == "." else "qs." + rel.replace(os.sep, ".")
    with open(os.path.join(destino, "qmldir"), "w") as q:
        q.write("module %s\n" % uri)
        for t in sorted(tipos):
            q.write(t + "\n")
# ── y ahora sí, el análisis ──────────────────────────────────────────────────
import subprocess
QMLLINT = "/usr/lib/qt6/bin/qmllint"
if not os.path.exists(QMLLINT):
    print("no está qmllint en", QMLLINT); raise SystemExit(1)
archivos = []
for aqui, dirs, fs_ in os.walk(RAIZ):
    dirs[:] = [d for d in dirs if d not in SALTAR and not d.startswith(".")]
    for f in fs_:
        if f.endswith(".qml"):
            archivos.append(os.path.join(aqui, f))
import collections
# LOS ERRORES VAN PRIMERO Y APARTE, y esto no es cosmética.
#
# Un error de verdad —"Property value set multiple times", un tipo que no
# existe— hace que qmllint ABANDONE el análisis del archivo, así que deja de
# emitir sus avisos habituales. En el informe por categorías eso se ve como el
# archivo DESAPARECIENDO de la lista, que es justo lo contrario de una alarma:
# parece que ha mejorado.
#
# Pasó: un Component.onCompleted declarado dos veces dejó el panel de IA sin
# cargar, y el informe solo dijo que MessageBubble ya no salía. Ahora un
# archivo que no carga se dice con todas las letras, y el guion termina en
# fallo para que no se pueda pasar por alto.
errores = []
for ruta in sorted(archivos):
    r = subprocess.run([QMLLINT, "-I", DEST, "-I", "/usr/lib/qt6/qml", ruta],
                       capture_output=True, text=True)
    salida = r.stdout + r.stderr
    for linea in salida.split("\n"):
        if linea.startswith("Error:") or "Property value set multiple times" in linea:
            errores.append((os.path.relpath(ruta, RAIZ), linea.strip()))
    cats = collections.Counter(re.findall(r"\[([a-z-]+)\]$", salida, re.M))
    rel = os.path.relpath(ruta, RAIZ)
    for cat, n in sorted(cats.items()):
        # Este es de Quickshell (tipos de C++ que qmllint no ve): ruido fijo.
        if cat == "signal-handler-parameters":
            continue
        print("%-44s %-28s %s" % (rel, cat, n))

if errores:
    print()
    print("── %d ERROR(ES): estos archivos NO CARGAN ──" % len(errores))
    for rel, linea in errores:
        print("  %-44s %s" % (rel, linea[:110]))
    raise SystemExit(1)
