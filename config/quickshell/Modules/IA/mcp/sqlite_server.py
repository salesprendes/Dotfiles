#!/usr/bin/env python3
"""Servidor MCP de SQLite, en SOLO LECTURA de verdad.

Un administrador se topa con bases SQLite por todas partes (Firefox, systemd,
paneles, aplicaciones), y hasta ahora la única forma de mirarlas era pedirle
al agente un `sqlite3 …` por run_command, escrito a mano y con aprobación.

Dos cerrojos, no uno:
  · La base se abre en modo ro por URI: aunque la consulta consiguiera ser
    de escritura, SQLite la rechaza.
  · Solo se aceptan sentencias de lectura, y UNA por llamada — así un
    "SELECT 1; DROP TABLE x" ni se plantea.
"""

import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _base import INT, STR, fail, safe_path, serve, text, tool  # noqa: E402

TOOLS = [
    tool("sqlite_tables", "Lista las tablas y vistas de una base SQLite, con cuántas filas tiene cada una.",
         {"db": dict(STR, description="Ruta del archivo .db/.sqlite (admite ~)")}, ["db"]),
    tool("sqlite_schema", "El CREATE TABLE de una tabla: sus columnas, tipos e índices. Míralo ANTES de consultar.",
         {"db": STR, "table": STR}, ["db", "table"]),
    tool("sqlite_query", "Ejecuta UNA consulta de lectura (SELECT/WITH/PRAGMA/EXPLAIN) y devuelve el resultado en tabla.",
         {"db": STR, "sql": STR,
          "limit": dict(INT, description="Máximo de filas (100 por defecto, tope 500)")},
         ["db", "sql"]),
]

READ_ONLY = re.compile(r"^\s*(select|with|pragma|explain)\b", re.IGNORECASE)


def _open(args):
    p = safe_path(args.get("db"))
    if not p:
        return None, fail("Ruta fuera de la carpeta personal o inexistente.")
    try:
        con = sqlite3.connect("file:%s?mode=ro" % p.replace("?", "%3f"),
                              uri=True, timeout=5)
        con.row_factory = sqlite3.Row
        return con, None
    except sqlite3.Error as ex:
        return None, fail("No se pudo abrir la base: %s" % ex)


def _table(rows, cols, cap=12000):
    """Filas en columnas alineadas: se lee mejor que un JSON en el chat."""
    if not rows:
        return "(sin filas)"
    data = [[("" if v is None else str(v))[:120] for v in r] for r in rows]
    width = [min(40, max(len(cols[i]), *(len(r[i]) for r in data)))
             for i in range(len(cols))]
    line = lambda cells: "  ".join(c[:width[i]].ljust(width[i])
                                   for i, c in enumerate(cells))
    out = [line(cols), line(["-" * w for w in width])]
    out += [line(r) for r in data]
    return "\n".join(out)[:cap]


def call(name, a):
    con, problem = _open(a)
    if problem:
        return problem
    try:
        if name == "sqlite_tables":
            cur = con.execute(
                "SELECT name, type FROM sqlite_master "
                "WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' "
                "ORDER BY name")
            rows = []
            for r in cur.fetchall():
                try:
                    n = con.execute('SELECT count(*) FROM "%s"'
                                    % r["name"].replace('"', '""')).fetchone()[0]
                except sqlite3.Error:
                    n = "?"
                rows.append([r["name"], r["type"], n])
            return text(_table(rows, ["nombre", "tipo", "filas"]))

        if name == "sqlite_schema":
            t = str(a.get("table") or "")
            cur = con.execute(
                "SELECT sql FROM sqlite_master WHERE name = ? AND sql IS NOT NULL", (t,))
            parts = [r[0] for r in cur.fetchall()]
            cur = con.execute(
                "SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name = ? "
                "AND sql IS NOT NULL", (t,))
            parts += [r[0] for r in cur.fetchall()]
            if not parts:
                return fail("No existe la tabla '%s'." % t)
            return text(";\n".join(parts))

        if name == "sqlite_query":
            sql = str(a.get("sql") or "").strip().rstrip(";")
            if not READ_ONLY.match(sql):
                return fail("Solo se permiten consultas de lectura "
                            "(SELECT, WITH, PRAGMA, EXPLAIN).")
            if ";" in sql:
                return fail("Una sola sentencia por llamada.")
            try:
                limit = max(1, min(500, int(a.get("limit") or 100)))
            except (TypeError, ValueError):
                limit = 100
            cur = con.execute(sql)
            rows = cur.fetchmany(limit)
            if cur.description is None:
                return text("(la consulta no devuelve filas)")
            cols = [d[0] for d in cur.description]
            body = _table([list(r) for r in rows], cols)
            if len(rows) == limit:
                body += "\n[…cortado en %d filas; sube 'limit' o afina la consulta]" % limit
            return text(body)

        return fail("Herramienta desconocida: %s" % name)
    except sqlite3.Error as ex:
        return fail("SQLite: %s" % ex)
    finally:
        con.close()


if __name__ == "__main__":
    serve("sqlite", TOOLS, call)
