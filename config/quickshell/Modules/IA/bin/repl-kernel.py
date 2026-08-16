#!/usr/bin/env python3
# Núcleo Python PERSISTENTE del harness (la idea de oh-my-pi: la celda vive
# entre llamadas y puede llamar de vuelta a las herramientas del agente).
#
# Protocolo por líneas NDJSON:
#   entra   {"t":"exec","code":"...","timeout":30}
#   sale    {"t":"result","ok":true,"out":"...","err":"...","value":"...","ms":12}
#   sale    {"t":"tool","id":1,"name":"read_file","args":{...}}   ← loopback
#   entra   {"t":"tool_result","id":1,"result":"..."}
#   sale    {"t":"ready","py":"3.13"}                              ← al arrancar
#
# Los prints del código del usuario van a un buffer (redirect), así que el
# stdout REAL solo lleva protocolo: no hay forma de que un print se confunda
# con un mensaje.
#
# Dentro de la celda vive `tool(nombre, **args)`: manda la petición al harness
# y se BLOQUEA hasta la respuesta. El harness solo atiende la familia de solo
# lectura (la misma que hereda el subagente) — el criterio es idéntico: puede
# ser autónomo justo porque nada de lo que alcanza cambia el equipo.
import io
import json
import signal
import sys
import time
import traceback
from contextlib import redirect_stderr, redirect_stdout

PROTO = sys.stdout
sys.stdout = sys.__stdout__          # los redirect ya harán su trabajo por celda

TOPE_SALIDA = 60000
_tool_id = 0


def emitir(obj):
    PROTO.write(json.dumps(obj, ensure_ascii=False) + "\n")
    PROTO.flush()


def leer_linea():
    linea = sys.stdin.readline()
    if linea == "":
        raise SystemExit
    return json.loads(linea)


class Agotado(Exception):
    pass


def _alarma(sig, frame):
    raise Agotado()


signal.signal(signal.SIGALRM, _alarma)


def tool(name, **args):
    """Llama a una herramienta de SOLO LECTURA del agente y devuelve su texto."""
    global _tool_id
    _tool_id += 1
    mio = _tool_id
    # La espera de la herramienta no cuenta contra el tiempo de la celda:
    # se pausa la alarma y se repone al volver.
    resto = signal.alarm(0)
    emitir({"t": "tool", "id": mio, "name": name, "args": args})
    try:
        while True:
            msg = leer_linea()
            if msg.get("t") == "tool_result" and msg.get("id") == mio:
                return str(msg.get("result", ""))
            # Cualquier otra cosa en mitad de una celda no tiene sentido: se ignora.
    finally:
        if resto:
            signal.alarm(resto)


def _sin_input(*a, **k):
    raise RuntimeError("input() no existe aquí: no hay terminal. Pide el dato con tool o en el chat.")


# ── El preludio compartido: coreutils DENTRO del runtime ─────────────────────
# La idea de pi-natives de oh-my-pi (ripgrep, find y coreutils compilados en el
# proceso para quitar el fork/exec del camino caliente), a mi escala: las
# lecturas comunes se hacen EN EL KERNEL con la stdlib de Python, sin lanzar un
# proceso ni volver por el puente. Todo con la MISMA jaula del harness: no se
# sale de la carpeta personal, ni por enlaces (realpath) ni por "..".
import fnmatch as _fnmatch  # noqa: E402
import glob as _glob        # noqa: E402
import json as _json        # noqa: E402
import math as _math        # noqa: E402
import os as _os            # noqa: E402
import re as _re            # noqa: E402
import subprocess as _sub   # noqa: E402
from pathlib import Path as _Path  # noqa: E402

_HOME = _os.path.realpath(_os.path.expanduser("~"))


def _jailed(p):
    ap = _os.path.realpath(_os.path.abspath(_os.path.expanduser(str(p))))
    if ap != _HOME and not ap.startswith(_HOME + _os.sep):
        raise PermissionError("fuera de la carpeta personal: " + str(p))
    return ap


def read(path, offset=1, limit=None):
    """Lee un archivo de texto (jaula $HOME). offset/limit en líneas (base 1)."""
    ap = _jailed(path)
    with open(ap, encoding="utf-8", errors="replace") as f:
        lines = f.read().split("\n")
    if offset > 1 or limit is not None:
        lines = lines[offset - 1: (offset - 1 + limit) if limit else None]
    return "\n".join(lines)


def ls(path="~"):
    """Lista una carpeta (nombres, con / en las carpetas)."""
    ap = _jailed(path)
    out = []
    for name in sorted(_os.listdir(ap)):
        full = _os.path.join(ap, name)
        out.append(name + ("/" if _os.path.isdir(full) else ""))
    return out


def grep(pattern, path=".", flags=_re.I):
    """Busca un patrón (regex) por líneas bajo una ruta. Devuelve [(archivo, nº, línea)]."""
    ap = _jailed(path)
    rx = _re.compile(pattern, flags)
    hits = []
    archivos = [ap] if _os.path.isfile(ap) else _find_files(ap)
    for f in archivos:
        try:
            with open(f, encoding="utf-8", errors="replace") as fh:
                for i, line in enumerate(fh, 1):
                    if rx.search(line):
                        hits.append((f, i, line.rstrip("\n")))
                        if len(hits) >= 500:
                            return hits
        except OSError:
            continue
    return hits


def _find_files(root):
    for dirpath, dirnames, filenames in _os.walk(root):
        if ".git" in dirnames:
            dirnames.remove(".git")
        for fn in filenames:
            yield _os.path.join(dirpath, fn)


def glob(pattern, root="~"):
    """Archivos que casan un patrón de nombre (p. ej. '*.py') bajo una ruta."""
    ap = _jailed(root)
    out = []
    for f in _find_files(ap):
        if _fnmatch.fnmatch(_os.path.basename(f), pattern):
            out.append(f)
            if len(out) >= 1000:
                break
    return out


def stat(path):
    """Metadatos de un archivo: tamaño, mtime y si es carpeta."""
    ap = _jailed(path)
    st = _os.stat(ap)
    return {"path": ap, "size": st.st_size, "mtime": st.st_mtime,
            "is_dir": _os.path.isdir(ap)}


def write(path, text):
    """Escribe un archivo DENTRO de la carpeta personal. La única que toca disco:
    el resto del preludio es de solo lectura, como el subagente. Úsala para
    entregables intermedios; el harness no la aprueba por tarjeta porque la
    celda entera ya la aprobó el usuario."""
    ap = _jailed(path)
    _os.makedirs(_os.path.dirname(ap), exist_ok=True)
    with open(ap, "w", encoding="utf-8") as f:
        f.write(str(text))
    return "escrito: " + ap + " (" + str(len(str(text))) + " car.)"


def tools():
    """Las herramientas del harness llamables por loopback (solo lectura)."""
    return ["read_file", "read_files", "list_dir", "grep_files", "glob_files",
            "fetch_url", "ast_search", "lsp", "system_status", "journal_query",
            "service_query", "process_query", "network_query", "disk_query",
            "package_query", "server_status", "server_logs", "sftp_ls",
            "hosting_query"]


# El entorno persistente de las celdas. Preludio: el loopback (tool/agent), las
# coreutils en proceso y unos módulos de uso común ya importados.
G = {
    "__name__": "__main__",
    "tool": tool, "agent": tool, "tools": tools,
    "read": read, "ls": ls, "grep": grep, "glob": glob,
    "find": glob, "stat": stat, "write": write,
    "input": _sin_input,
    "json": _json, "os": _os, "re": _re, "math": _math,
    "Path": _Path, "HOME": _HOME,
}


def ejecutar(code, timeout):
    import ast
    out, err = io.StringIO(), io.StringIO()
    valor = None
    ok = True
    t0 = time.monotonic()
    signal.alarm(max(1, int(timeout)))
    try:
        with redirect_stdout(out), redirect_stderr(err):
            arbol = ast.parse(code, "<celda>", "exec")
            # Si la última sentencia es una expresión, su valor se enseña
            # (estilo cuaderno): "2+2" contesta 4 sin obligar a un print.
            cola = None
            if arbol.body and isinstance(arbol.body[-1], ast.Expr):
                cola = ast.Expression(arbol.body.pop().value)
            if arbol.body:
                exec(compile(arbol, "<celda>", "exec"), G)
            if cola is not None:
                v = eval(compile(cola, "<celda>", "eval"), G)
                if v is not None:
                    valor = repr(v)
                    G["_"] = v
    except Agotado:
        ok = False
        err.write("\n[celda cortada por tiempo: " + str(timeout) + " s]")
    except SystemExit:
        raise
    except BaseException:
        ok = False
        err.write(traceback.format_exc(limit=8))
    finally:
        signal.alarm(0)
    emitir({"t": "result", "ok": ok,
            "out": out.getvalue()[:TOPE_SALIDA],
            "err": err.getvalue()[:TOPE_SALIDA],
            "value": (valor or "")[:4000],
            "ms": int((time.monotonic() - t0) * 1000)})


def main():
    emitir({"t": "ready",
            "py": ".".join(map(str, sys.version_info[:2])),
            "prelude": ["read", "ls", "grep", "glob", "find", "stat", "write",
                        "tool", "agent", "tools", "json", "os", "re", "Path", "HOME"]})
    while True:
        try:
            msg = leer_linea()
        except json.JSONDecodeError:
            continue
        if msg.get("t") == "exec":
            ejecutar(str(msg.get("code", "")), msg.get("timeout") or 30)
        # tool_result fuera de una celda: respuesta huérfana, se ignora.


if __name__ == "__main__":
    try:
        main()
    except (SystemExit, KeyboardInterrupt):
        pass
