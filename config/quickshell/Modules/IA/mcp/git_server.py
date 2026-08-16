#!/usr/bin/env python3
"""Servidor MCP de git, en SOLO LECTURA.

Es el hueco más grande que tenía el harness para un programador: sabía leer
y editar archivos, pero no podía mirar la historia del repositorio — quién
tocó esto, qué cambió desde ayer, por qué está así. Todo lo de aquí es
lectura: ni commit, ni checkout, ni push. Escribir en el repo sigue siendo
cosa del agente principal con su tarjeta de aprobación.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _base import BOOL, INT, STR, fail, run, safe_path, serve, text, tool  # noqa: E402

TOOLS = [
    tool("git_status", "Estado del repositorio: rama, archivos modificados, sin seguir y en el índice.",
         {"repo": dict(STR, description="Carpeta del repositorio (admite ~)")}, ["repo"]),
    tool("git_diff", "Cambios aún sin confirmar (o los del índice con staged=true). Se puede acotar a una ruta.",
         {"repo": STR, "path": dict(STR, description="Limitar a este archivo o carpeta"),
          "staged": dict(BOOL, description="Ver lo que ya está en el índice"),
          "context": dict(INT, description="Líneas de contexto (3 por defecto)")}, ["repo"]),
    tool("git_log", "Historia reciente: hash corto, fecha, autor y asunto. Filtrable por ruta, autor y fecha.",
         {"repo": STR, "count": dict(INT, description="Cuántos commits (20 por defecto, máx. 200)"),
          "path": STR, "author": STR,
          "since": dict(STR, description="p. ej. '2 weeks ago', '2026-08-01'"),
          "grep": dict(STR, description="Buscar en los mensajes de commit")}, ["repo"]),
    tool("git_show", "Un commit entero: metadatos y su diff. ref admite hash, HEAD~3, una etiqueta…",
         {"repo": STR, "ref": dict(STR, description="Referencia del commit"),
          "path": dict(STR, description="Ver solo lo que cambió en esta ruta")}, ["repo", "ref"]),
    tool("git_blame", "Quién escribió cada línea de un archivo y en qué commit. Acota el rango: un archivo entero es ilegible.",
         {"repo": STR, "path": STR, "start": INT, "end": INT}, ["repo", "path"]),
    tool("git_branches", "Ramas locales y remotas, con su último commit y si están al día.",
         {"repo": STR}, ["repo"]),
    tool("git_grep", "Busca un patrón SOLO en los archivos que git sigue: sin node_modules, sin build, sin basura.",
         {"repo": STR, "pattern": STR,
          "path": dict(STR, description="Limitar la búsqueda a esta ruta")}, ["repo", "pattern"]),
    tool("git_file_history", "Cómo ha ido cambiando un archivo concreto: sus commits, y con diff=true también qué cambió en cada uno.",
         {"repo": STR, "path": STR, "count": INT, "diff": BOOL}, ["repo", "path"]),
]


def _repo(args):
    """La carpeta del repositorio, comprobando que sea una de verdad."""
    p = safe_path(args.get("repo"))
    if not p:
        return None, fail("Ruta fuera de la carpeta personal o inexistente.")
    if not os.path.isdir(p):
        p = os.path.dirname(p)
    inside = run(["git", "rev-parse", "--is-inside-work-tree"], cwd=p, timeout=10)
    if inside.strip() != "true":
        return None, fail("Ahí no hay un repositorio git (%s)." % p)
    return p, None


def _n(args, key, default, top):
    try:
        v = int(args.get(key) or default)
    except (TypeError, ValueError):
        v = default
    return max(1, min(top, v))


def call(name, a):
    repo, problem = _repo(a)
    if problem:
        return problem

    if name == "git_status":
        head = run(["git", "status", "-sb"], cwd=repo)
        return text(head)

    if name == "git_diff":
        argv = ["git", "--no-pager", "diff",
                "--unified=%d" % _n(a, "context", 3, 20)]
        if a.get("staged"):
            argv.append("--cached")
        if a.get("path"):
            argv += ["--", str(a["path"])]
        out = run(argv, cwd=repo)
        return text(out if out != "(sin salida)" else "(sin cambios)")

    if name == "git_log":
        argv = ["git", "--no-pager", "log",
                "--pretty=format:%h  %ad  %an  %s", "--date=short",
                "-n", str(_n(a, "count", 20, 200))]
        for flag, key in (("--author=", "author"), ("--since=", "since"),
                          ("--grep=", "grep")):
            if a.get(key):
                argv.append(flag + str(a[key]))
        if a.get("path"):
            argv += ["--", str(a["path"])]
        return text(run(argv, cwd=repo))

    if name == "git_show":
        # --end-of-options antes de la referencia: sin él, una ref que empiece
        # por guion la lee git como una OPCIÓN suya, y el modelo elige esa ref.
        # "--upload-pack=..." o "--output=..." dejan de ser una referencia y
        # pasan a ser una orden. Es el mismo motivo por el que las rutas van
        # detrás de "--", solo que para el otro lado del comando.
        argv = ["git", "--no-pager", "show", "--stat", "--patch",
                "--end-of-options", str(a.get("ref") or "HEAD")]
        if a.get("path"):
            argv += ["--", str(a["path"])]
        return text(run(argv, cwd=repo))

    if name == "git_blame":
        path = str(a.get("path") or "")
        argv = ["git", "--no-pager", "blame", "--date=short",
                "-w"]                      # -w: ignorar cambios de espacios
        start, end = a.get("start"), a.get("end")
        if start and end:
            argv += ["-L", "%d,%d" % (int(start), int(end))]
        elif start:
            argv += ["-L", "%d,+40" % int(start)]
        argv += ["--", path]
        return text(run(argv, cwd=repo))

    if name == "git_branches":
        out = run(["git", "--no-pager", "branch", "-vv", "--all"], cwd=repo)
        return text(out)

    if name == "git_grep":
        argv = ["git", "--no-pager", "grep", "-n", "-I", "--heading",
                "-e", str(a.get("pattern") or "")]
        if a.get("path"):
            argv += ["--", str(a["path"])]
        out = run(argv, cwd=repo)
        return text(out if out != "(sin salida)" else "(sin coincidencias)")

    if name == "git_file_history":
        argv = ["git", "--no-pager", "log",
                "--pretty=format:%h  %ad  %an  %s", "--date=short",
                "-n", str(_n(a, "count", 15, 100))]
        if a.get("diff"):
            argv += ["--patch", "--unified=2"]
        argv += ["--follow", "--", str(a.get("path") or "")]
        return text(run(argv, cwd=repo))

    return fail("Herramienta desconocida: %s" % name)


if __name__ == "__main__":
    serve("git", TOOLS, call)
