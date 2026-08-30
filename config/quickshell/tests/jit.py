#!/usr/bin/env python3
"""Prueba de esfuerzo del JIT de QV4.

    python3 tests/jit.py [segundos]

POR QUÉ EXISTE. El shell arrancaba con `QV4_FORCE_INTERPRETER=1`, un pragma que
apagaba el compilador JIT para esquivar una caída de Qt 6.11.1
(`QV4::Value::sameValueZero`) al reevaluar bindings de larga vida. Al retirar
ese pragma —Qt 6.11.2 ya corrige esa serie— hace falta algo que respalde la
decisión, porque un fallo de JIT no se ve leyendo el código: aparece cuando el
motor decide compilar una función que ya ha ejecutado muchas veces, y solo
entonces.

Y ese "muchas veces" es la clave: el JIT no compila una función hasta que se ha
llamado bastante. Un arranque normal del shell nunca llega a ese umbral en los
bindings raros, así que "arranca y se ve bien" no demuestra nada. Aquí se
machacan a propósito los patrones donde se caía —`property var` con objetos
dentro, reevaluados una y otra vez— hasta pasar de largo el umbral.

Se aísla igual que tests/logica.py: HOME falso (no toca tu settings.json) y sin
HYPRLAND_INSTANCE_SIGNATURE (no lanza ni un hyprctl contra tu sesión).

Salida: 0 si el motor sigue en pie, 1 si se cayó (y entonces hay un fallo del
JIT de verdad y el pragma debe volver a shell.qml).
"""
import os
import re
import shutil
import subprocess
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "qs-jit")
SALTAR = {".git", "node_modules", "__pycache__", "muestras", "data", "qmlroot", "tests"}


def espejo():
    shutil.rmtree(DEST, ignore_errors=True)
    for aqui, dirs, archivos in os.walk(RAIZ):
        dirs[:] = [d for d in dirs if d not in SALTAR and not d.startswith(".")]
        rel = os.path.relpath(aqui, RAIZ)
        destino = DEST if rel == "." else os.path.join(DEST, rel)
        os.makedirs(destino, exist_ok=True)
        for f in archivos:
            if f.startswith(".") or f == "shell.qml":
                continue
            try:
                os.symlink(os.path.join(aqui, f), os.path.join(destino, f))
            except FileExistsError:
                pass
    os.makedirs(os.path.join(DEST, "home", ".config", "quickshell"), exist_ok=True)
    shutil.copy(os.path.join(RAIZ, "tests", "jit.qml"), os.path.join(DEST, "shell.qml"))


def main():
    segundos = int(sys.argv[1]) if len(sys.argv) > 1 else 25
    if not shutil.which("qs"):
        print("no está quickshell (qs) en el PATH")
        return 1
    espejo()
    entorno = dict(os.environ)
    entorno["HOME"] = os.path.join(DEST, "home")
    entorno["QT_QPA_PLATFORM"] = "offscreen"
    entorno["QS_JIT_SECONDS"] = str(segundos)
    entorno.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    entorno.pop("WAYLAND_DISPLAY", None)
    # Por si acaso: que nadie herede un force-interpreter del entorno y la
    # prueba acabe midiendo justo lo que NO quiere medir.
    entorno.pop("QV4_FORCE_INTERPRETER", None)

    proc = subprocess.Popen(["qs", "-p", os.path.join(DEST, "shell.qml")],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, env=entorno)
    ansi = re.compile(r"\x1b\[[0-9;]*m")
    lineas = []
    final = None
    try:
        for cruda in proc.stdout:
            linea = ansi.sub("", cruda).rstrip()
            lineas.append(linea)
            if "JIT" not in linea:
                continue
            print(linea[linea.index("JIT"):])
            if "JIT FIN" in linea:
                final = linea
                break
    finally:
        proc.terminate()
        try:
            codigo = proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            codigo = -9

    if final is None:
        print("el motor NO llegó al final — posible caída. Salida completa:")
        print("\n".join(lineas[-40:]))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
