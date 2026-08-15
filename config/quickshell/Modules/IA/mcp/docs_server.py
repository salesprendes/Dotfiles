#!/usr/bin/env python3
"""Servidor MCP de documentación LOCAL: manuales, búsqueda en ellos, tldr y
unidades de systemd.

Por qué importa: un modelo local pequeño se inventa opciones de comandos con
una seguridad pasmosa. Con esto puede COMPROBAR la opción en el manual de
ESTE equipo antes de proponerte un `rsync --delete` que no hace lo que cree.
Y funciona sin red, que es justo cuando más falta hace.

Detalle de este equipo: no está instalado man-db (no hay `man` ni `apropos`),
pero sí las 17 000 páginas de manual y groff. Así que el servidor las busca y
las compone él mismo; si algún día instalas man-db, usará `man` sin cambiar
nada. En castellano si la página está traducida.

Deliberadamente NO hay un 'ejecuta <cmd> --help': eso sería ejecutar binarios
arbitrarios sin tarjeta de aprobación. Leer manuales es leer archivos; para
lo demás está run_command, que sí pregunta.
"""

import glob
import gzip
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _base import STR, fail, run, serve, text, tool  # noqa: E402

MAN_ROOT = "/usr/share/man"
# El idioma primero, el inglés después: una página traducida se agradece, y
# si no existe se cae al original sin ruido.
LANGS = ["es", ""]

TOOLS = [
    tool("man_page", "Lee la página de manual de un comando o de un archivo de configuración. Sección opcional (1 comandos, 5 formatos de archivo, 8 administración). Con 'grep' devuelve solo las partes que hablen de eso: útil para mirar UNA opción sin tragarse el manual entero.",
         {"name": dict(STR, description="Comando o tema, p. ej. 'tar' o 'sshd_config'"),
          "section": dict(STR, description="Sección: 1, 5, 8…"),
          "grep": dict(STR, description="Buscar dentro de la página")},
         ["name"]),
    tool("apropos", "Busca por PALABRAS entre los nombres y descripciones de todos los manuales instalados. Para cuando sabes qué quieres hacer pero no cómo se llama la herramienta.",
         {"query": STR}, ["query"]),
    tool("tldr", "Ejemplos prácticos de un comando (páginas tldr), si están instaladas. Más corto que el manual para el uso del día a día.",
         {"name": STR}, ["name"]),
    tool("systemd_unit_doc", "Muestra el archivo de una unidad de systemd tal y como systemd la ve, con los overrides ya aplicados.",
         {"unit": dict(STR, description="p. ej. nginx.service"),
          "user": {"type": "boolean", "description": "Unidad de usuario"}}, ["unit"]),
    tool("config_example", "Lista los archivos de configuración y ejemplos que instala un paquete de pacman. Para saber QUÉ tocar antes de tocarlo.",
         {"package": STR}, ["package"]),
]


def _clean_name(s):
    """Sin barras ni metacaracteres: aquí solo entran nombres de página."""
    ok = ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
          "0123456789._-+@:")
    return "".join(c for c in str(s or "").strip() if c in ok)[:120]


def _read(path):
    try:
        if path.endswith(".gz"):
            return gzip.open(path, "rb").read()
        return open(path, "rb").read()
    except OSError:
        return b""


def _find(name, section):
    """La página de manual que mejor case, mirando primero el idioma."""
    sec = _clean_name(section) or "[1-8]"
    for lang in LANGS:
        root = os.path.join(MAN_ROOT, lang) if lang else MAN_ROOT
        for pattern in ("%s.%s*" % (name, sec), "%s.%s*" % (name, sec.lower())):
            hits = sorted(glob.glob(os.path.join(root, "man" + sec[-1]
                                                 if sec != "[1-8]" else "man[1-8]",
                                                 pattern)))
            if hits:
                return hits[0]
    return None


# groff deja el subrayado y la negrita como "_\bx" y "x\bx": sobra en un chat.
_OVERSTRIKE = re.compile(rb".\x08")


def _render(path):
    """La página compuesta. groff necesita el roff por la entrada estándar,
    así que este es el único sitio que no pasa por run()."""
    raw = _read(path)
    if not raw:
        return None
    try:
        p = subprocess.run(["groff", "-mandoc", "-Tutf8", "-rLL=100n",
                            "-rLT=100n", "-P-c"],
                           input=raw, capture_output=True, timeout=25)
    except (OSError, subprocess.SubprocessError):
        return None
    body = _OVERSTRIKE.sub(b"", p.stdout).decode("utf-8", "replace")
    return re.sub(r"\n{3,}", "\n\n", body).strip() or None


# Limpieza de las marcas de roff que se cuelan en la línea NAME.
_ROFF = re.compile(r"\\f[BIRP]|\\%|\\&|\\-|\\\(em|\\\(en|\\e")


def _describe(path):
    """El 'NAME' de una página, sin componerla entera (esto se hace 17 000
    veces en un apropos: aquí no se puede llamar a groff)."""
    try:
        if path.endswith(".gz"):
            head = gzip.open(path, "rt", encoding="utf-8",
                             errors="replace").read(4000)
        else:
            head = open(path, encoding="utf-8", errors="replace").read(4000)
    except (OSError, EOFError):
        return ""
    m = re.search(r'^\.SH\s+"?NAME"?\s*\n(.*?)(?=^\.SH|\Z)', head, re.M | re.S)
    if not m:
        return ""
    body = " ".join(l for l in m.group(1).split("\n")
                    if l and not l.startswith("."))
    return re.sub(r"\s+", " ", _ROFF.sub("", body)).strip()[:160]


def _excerpts(body, pattern, before=2, after=7):
    """Los trozos de la página que hablan del patrón. Los rangos que se
    solapan se funden, para no repetir las mismas líneas dos veces."""
    lines = body.split("\n")
    low = pattern.lower()
    spans = []
    for i, line in enumerate(lines):
        if low not in line.lower():
            continue
        start, end = max(0, i - before), min(len(lines), i + after + 1)
        if spans and start <= spans[-1][1]:
            spans[-1][1] = max(spans[-1][1], end)
        else:
            spans.append([start, end])
    if not spans:
        return "La página existe pero no menciona '%s'." % pattern
    return "\n   ···\n".join("\n".join(lines[s:e]) for s, e in spans)


def call(name, a):
    if name == "man_page":
        topic = _clean_name(a.get("name"))
        if not topic:
            return fail("Falta el nombre.")
        # Si el equipo tiene man-db, mandan sus reglas.
        if shutil.which("man"):
            argv = ["man"]
            if _clean_name(a.get("section")):
                argv.append(_clean_name(a["section"]))
            argv.append(topic)
            body = run(argv, cap=200000, env={"MANWIDTH": "100",
                                              "MANPAGER": "cat", "PAGER": "cat"})
            if "No manual entry" in body:
                body = None
        else:
            path = _find(topic, a.get("section"))
            body = _render(path) if path else None
        if not body:
            return fail("No hay manual para '%s'%s. Prueba apropos para dar "
                        "con el nombre correcto."
                        % (topic, " en la sección " + _clean_name(a["section"])
                           if a.get("section") else ""))

        pattern = str(a.get("grep") or "").strip()
        if pattern:
            body = _excerpts(body, pattern)
        return text(body[:20000])

    if name == "apropos":
        words = [w.lower() for w in re.split(r"\W+", str(a.get("query") or ""))
                 if len(w) > 2]
        if not words:
            return fail("Dame al menos una palabra de tres letras.")
        hits = []
        # Por orden de utilidad para quien administra un equipo: comandos (1),
        # administración (8), formatos de archivo (5)… y al final las llamadas
        # de biblioteca (3), que si no inundan cualquier búsqueda.
        for section in "18572643":
            d = os.path.join(MAN_ROOT, "man" + section)
            if not os.path.isdir(d):
                continue
            batch = []
            for fn in sorted(os.listdir(d)):
                page = fn.split(".")[0]
                # Primero por nombre (barato); si no casa, se lee su NAME.
                desc = _describe(os.path.join(d, fn))
                if not all(w in page.lower() for w in words) \
                        and not all(w in desc.lower() for w in words):
                    continue
                batch.append("%s(%s)  %s" % (page, section, desc))
                if len(hits) + len(batch) >= 60:
                    break
            hits += batch
            if len(hits) >= 60:
                break
        if not hits:
            return text("Ningún manual menciona eso.")
        return text("\n".join(hits)[:12000])

    if name == "tldr":
        topic = _clean_name(a.get("name"))
        if not topic:
            return fail("Falta el nombre.")
        if not shutil.which("tldr"):
            return fail("No hay 'tldr' en este equipo (pacman -S tealdeer). "
                        "Usa man_page mientras tanto.")
        return text(run(["tldr", topic], env={"NO_COLOR": "1"}))

    if name == "systemd_unit_doc":
        unit = _clean_name(a.get("unit"))
        if not unit:
            return fail("Falta la unidad.")
        argv = ["systemctl"]
        if a.get("user"):
            argv.append("--user")
        argv += ["cat", "--no-pager", "--", unit]
        return text(run(argv))

    if name == "config_example":
        pkg = _clean_name(a.get("package"))
        if not pkg:
            return fail("Falta el paquete.")
        listing = run(["pacman", "-Ql", pkg], cap=400000)
        if listing.startswith("No está instalado") or "error:" in listing[:80]:
            return fail("El paquete '%s' no está instalado." % pkg)
        hits = [ln.split(" ", 1)[1] for ln in listing.split("\n")
                if " " in ln and any(k in ln for k in
                                     (".conf", ".example", ".sample",
                                      ".default", "/etc/"))
                and not ln.rstrip().endswith("/")]
        if not hits:
            return text("El paquete '%s' no instala archivos de configuración."
                        % pkg)
        return text("Configuración que instala %s:\n%s"
                    % (pkg, "\n".join(hits[:60])))

    return fail("Herramienta desconocida: %s" % name)


if __name__ == "__main__":
    serve("docs", TOOLS, call)
