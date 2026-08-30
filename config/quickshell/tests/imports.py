#!/usr/bin/env python3
"""¿Tiene cada archivo los imports que necesita para EJECUTARSE?

    python3 tests/imports.py

POR QUÉ ES UNA PRUEBA APARTE. Esto es una familia entera de fallos que pasan
por delante de las otras dos baterías sin despeinarse:

  · qmllint no se queja, porque el símbolo existe en el módulo — solo que no
    está importado en ESE archivo.
  · qmlcarga.py tampoco, porque el archivo COMPILA: en QML, `Quickshell.algo`
    dentro de un binding no se resuelve hasta que el binding se evalúa.

Así que el archivo carga, la interfaz se monta, y el error aparece en tiempo de
ejecución cada vez que se pinta ese trozo — en el registro, donde nadie mira.
Pasó de verdad: Modules/Island/activities/NotificationCompact.qml usaba
`Quickshell.iconPath()` sin `import Quickshell`, y el resultado fueron 65
ReferenceError en el log y notificaciones sin icono, con todo lo demás en verde.

CÓMO EVITAR EL FALSO POSITIVO. La primera versión de esto marcó once archivos
sanos, porque las propias líneas `import Quickshell.Hyprland` contienen
"Quickshell." y la expresión regular las contaba como uso. Se quitan las líneas
de import y los comentarios ANTES de buscar. Si esta prueba vuelve a marcar algo
que lleva meses funcionando, sospecha de la tabla antes que del archivo.
"""
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SALTAR = {".git", "tests", "__pycache__", "data", "muestras", "node_modules", "qmlroot"}

# Símbolo global → módulo que hay que importar para que exista.
NECESITA = {
    "Quickshell": "Quickshell",
    "DesktopEntries": "Quickshell",
    "QsMenuButtonType": "Quickshell",
    "Hyprland": "Quickshell.Hyprland",
    "Pipewire": "Quickshell.Services.Pipewire",
    "SystemTray": "Quickshell.Services.SystemTray",
    "Mpris": "Quickshell.Services.Mpris",
    "MprisPlaybackState": "Quickshell.Services.Mpris",
    "UPower": "Quickshell.Services.UPower",
    "UPowerDeviceState": "Quickshell.Services.UPower",
    "PamResult": "Quickshell.Services.Pam",
    "PamError": "Quickshell.Services.Pam",
    "Networking": "Quickshell.Networking",
    "WifiSecurityType": "Quickshell.Networking",
}

# Los singletons PROPIOS del shell. Faltaban, y esa ausencia dejó pasar
# exactamente el fallo que esta prueba existe para cazar:
# Components/ClearableListState.qml pasó a usar Theme.curveEmphasizedDecel sin
# importar qs.Config, y esto dio verde. Antes no le hacía falta el import porque
# usaba Easing.OutCubic, que es de QtQuick.
#
# El valor es una LISTA porque un símbolo puede venir de más de un sitio: el
# greeter tiene su propio Theme (Modules/Greeter/Theme.qml), a propósito, para
# correr antes de la sesión sin arrastrar Settings.
PROPIOS_CONFIG = ["Globals", "Resume", "BarCatalog", "PowerActions", "Utils",
                  "SettingsSearchIndex", "I18n", "Theme", "SettingsFilter",
                  "Settings", "IslandState", "AppTemplates"]
PROPIOS_SERVICIOS = ["BT", "AppCatalog", "Brightness", "Deps", "Emoji", "Battery",
                     "Power", "Media", "Displays", "Clipboard", "Net", "Fonts",
                     "SysMon", "NightLight", "NotifService", "Time", "FileSearch",
                     "ScreenCapture", "Keyboard", "Lock", "NetConfig", "Weather",
                     "Terminal", "Updates", "Wallpaper"]

for _s in PROPIOS_CONFIG:
    NECESITA[_s] = ["qs.Config", "qs.Modules.Greeter"]
for _s in PROPIOS_SERVICIOS:
    NECESITA[_s] = ["qs.Services"]


def cuerpo_sin_imports(src):
    """El texto sin líneas de import ni comentarios: solo código de verdad."""
    sin_imports = "\n".join(l for l in src.split("\n")
                            if not re.match(r"\s*import\s", l))
    sin_linea = re.sub(r"//[^\n]*", "", sin_imports)
    return re.sub(r"/\*.*?\*/", "", sin_linea, flags=re.S)


# Módulo → carpeta que lo provee. Un archivo que VIVE en esa carpeta no
# necesita importarla: QML resuelve los singletons vecinos por el import
# implícito del directorio. Sin esta regla, Services/Weather.qml (que usa Net)
# saldría marcado, y lleva meses funcionando.
CARPETA_DE = {
    "qs.Config": os.path.join("Config", ""),
    "qs.Services": os.path.join("Services", ""),
    "qs.Modules.Greeter": os.path.join("Modules", "Greeter", ""),
}


def revisa(ruta):
    src = open(ruta, encoding="utf-8").read()
    imports = set(re.findall(r"^\s*import\s+([\w.]+)", src, re.M))
    rel = os.path.relpath(ruta, RAIZ)
    # Los módulos que este archivo tiene "gratis" por dónde vive.
    for mod, carpeta in CARPETA_DE.items():
        if rel.startswith(carpeta):
            imports.add(mod)
    cuerpo = cuerpo_sin_imports(src)
    faltan = []
    for simbolo, modulo in NECESITA.items():
        # Uno o varios módulos válidos: basta con tener UNO.
        validos = modulo if isinstance(modulo, list) else [modulo]
        # El símbolo seguido de punto, corchete o paréntesis: un USO, no una
        # palabra que casualmente se llame igual dentro de otra.
        if re.search(r"(?<![\w.])" + simbolo + r"\s*[.\[(]", cuerpo):
            if not any(m in imports for m in validos):
                faltan.append((simbolo, " o ".join(validos)))
    return faltan


def main():
    malos = []
    n = 0
    for aqui, dirs, archivos in os.walk(RAIZ):
        dirs[:] = [d for d in dirs if d not in SALTAR and not d.startswith(".")]
        for f in archivos:
            if not f.endswith(".qml"):
                continue
            ruta = os.path.join(aqui, f)
            n += 1
            for simbolo, modulo in revisa(ruta):
                malos.append((os.path.relpath(ruta, RAIZ), simbolo, modulo))

    print("%d archivos .qml revisados" % n)
    if not malos:
        print("todos los símbolos globales tienen su import")
        return 0
    print()
    print("── %d IMPORT(S) QUE FALTAN ──" % len(malos))
    for ruta, simbolo, modulo in sorted(malos):
        print("  %-50s usa %-18s → falta 'import %s'" % (ruta, simbolo, modulo))
    return 1


if __name__ == "__main__":
    sys.exit(main())
