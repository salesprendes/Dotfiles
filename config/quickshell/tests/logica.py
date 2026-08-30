#!/usr/bin/env python3
"""Pruebas de LÓGICA del shell, ejecutadas por el Quickshell de verdad.

    python3 tests/logica.py

Qué cubre esto que no cubran las otras dos: qmllint dice si los tipos resuelven
y qmlcarga.py si los archivos compilan, pero ninguno EJECUTA nada. Aquí se
comprueba que las funciones puras del shell dan el resultado correcto — la
aritmética de índices al mover un widget de la barra, y sobre todo que las
migraciones de settings.json convierten bien una configuración vieja. Una
migración equivocada no rompe el arranque: te cambia los ajustes en silencio,
que es peor.

CÓMO SE AÍSLA. Se monta un espejo de enlaces del árbol (como tests/qmllint.py)
con un shell.qml propio, y se lanza Quickshell contra él con:

  · HOME apuntando a una casa falsa → Settings escribe su settings.json ahí y
    no toca el del usuario.
  · HYPRLAND_INSTANCE_SIGNATURE vacío → Settings.hyprlandAvailable es false, así
    que no se lanza ni un hyprctl contra la sesión que esté corriendo. Sin esto,
    ejecutar las pruebas recargaría Hyprland del usuario.
  · QT_QPA_PLATFORM=offscreen → sin ventanas. Nada de layer-shell.
"""
import os, re, shutil, subprocess, sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "qs-logica")
SALTAR = {".git", "node_modules", "__pycache__", "muestras", "data", "qmlroot", "tests"}


def espejo():
    """Árbol de enlaces con la misma forma, para no ejecutar sobre el original."""
    shutil.rmtree(DEST, ignore_errors=True)
    for aqui, dirs, archivos in os.walk(RAIZ):
        dirs[:] = [d for d in dirs if d not in SALTAR and not d.startswith(".")]
        rel = os.path.relpath(aqui, RAIZ)
        destino = DEST if rel == "." else os.path.join(DEST, rel)
        os.makedirs(destino, exist_ok=True)
        for f in archivos:
            if f.startswith(".") or f == "shell.qml":
                continue          # el shell.qml de verdad abriría ventanas
            try:
                os.symlink(os.path.join(aqui, f), os.path.join(destino, f))
            except FileExistsError:
                pass
    os.makedirs(os.path.join(DEST, "home", ".config", "quickshell"), exist_ok=True)
    with open(os.path.join(DEST, "shell.qml"), "w") as f:
        f.write(open(os.path.join(RAIZ, "tests", "logica.qml")).read())


def main():
    if not shutil.which("qs"):
        print("no está quickshell (qs) en el PATH")
        return 1
    espejo()
    entorno = dict(os.environ)
    entorno["HOME"] = os.path.join(DEST, "home")
    entorno["QT_QPA_PLATFORM"] = "offscreen"
    entorno.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    entorno.pop("WAYLAND_DISPLAY", None)

    # Se lee la salida y se mata en cuanto la batería dice que ha terminado.
    # Qt.exit() NO sirve aquí: Quickshell no conecta la señal exit() del motor
    # ("Signal QQmlEngine::exit() emitted, but no receivers connected"), así que
    # el proceso se quedaría vivo para siempre esperando eventos que en modo
    # offscreen no van a llegar.
    proc = subprocess.Popen(["qs", "-p", os.path.join(DEST, "shell.qml")],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, env=entorno)
    ansi = re.compile(r"\x1b\[[0-9;]*m")
    total = None
    lineas = []
    try:
        for cruda in proc.stdout:
            linea = ansi.sub("", cruda).rstrip()
            lineas.append(linea)
            if "PRUEBA" not in linea:
                continue
            print(linea[linea.index("PRUEBA"):])
            if "PRUEBA TOTAL" in linea:
                total = linea
                break
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()

    if total is None:
        print("la batería no llegó al final. Salida completa:")
        print("\n".join(lineas))
        return 1
    return 0 if " 0 mal" in total else 1


if __name__ == "__main__":
    sys.exit(main())
