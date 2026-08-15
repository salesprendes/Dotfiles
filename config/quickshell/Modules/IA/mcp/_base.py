"""Esqueleto común de los servidores MCP del harness.

Transporte stdio, JSON-RPC línea a línea (protocolo 2024-11-05), que es
justo lo que habla el cliente de AiService.qml. Sin dependencias: python3 a
secas, porque en este equipo no hay node ni uv y un servidor que no arranca
no sirve de nada.

Reglas que cumplen los tres servidores:
  · SOLO LECTURA. Nada de lo que hacen modifica el equipo.
  · stdout es SAGRADO: solo JSON de una línea. Cualquier otra cosa (avisos,
    trazas) va a stderr, o el cliente no entendería la respuesta.
  · Las rutas se acotan a la carpeta personal, como el resto del harness.
"""

import json
import os
import subprocess
import sys

HOME = os.path.realpath(os.path.expanduser("~"))


def send(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def text(s):
    return {"content": [{"type": "text", "text": str(s)}]}


def fail(s):
    return {"content": [{"type": "text", "text": str(s)}], "isError": True}


def safe_path(p, must_exist=True):
    """Ruta real dentro de $HOME, o None. Sigue los enlaces antes de decidir:
    un symlink que se va fuera no cuela."""
    if not p:
        return None
    p = os.path.expanduser(str(p))
    p = os.path.realpath(os.path.abspath(p))
    if p != HOME and not p.startswith(HOME + os.sep):
        return None
    if must_exist and not os.path.exists(p):
        return None
    return p


def run(argv, cwd=None, cap=16000, timeout=20, env=None):
    """Un comando, con sus argumentos como LISTA (nunca por shell)."""
    try:
        e = dict(os.environ)
        if env:
            e.update(env)
        p = subprocess.run(argv, cwd=cwd, capture_output=True, text=True,
                           timeout=timeout, env=e)
    except FileNotFoundError:
        return "No está instalado en este equipo: " + argv[0]
    except subprocess.TimeoutExpired:
        return "Tardó demasiado (más de %ds)." % timeout
    except OSError as ex:
        return "No se pudo ejecutar: %s" % ex
    out = p.stdout or ""
    if (p.stderr or "").strip():
        out += ("\n" if out else "") + "[stderr] " + p.stderr
    out = out.strip()
    if len(out) > cap:
        out = out[:cap] + "\n[…recortado]"
    return out or "(sin salida)"


def serve(name, tools, call):
    """El bucle del protocolo. 'tools' es la lista de esquemas y 'call' la
    función (nombre, argumentos) -> resultado MCP."""
    # readline() y no `for line in sys.stdin`: al iterar, Python lee por
    # bloques y puede quedarse esperando a llenar el buffer mientras el
    # cliente espera la respuesta de la línea que YA mandó. Un abrazo mortal
    # silencioso: el servidor parece colgado y nadie sabe por qué.
    while True:
        line = sys.stdin.readline()
        if line == "":                       # el cliente cerró: se acabó
            return
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        mid = msg.get("id")
        method = msg.get("method")
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": mid, "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": name, "version": "1.0"}}})
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": mid, "result": {"tools": tools}})
        elif method == "tools/call":
            params = msg.get("params") or {}
            try:
                res = call(params.get("name", ""), params.get("arguments") or {})
            except Exception as ex:              # noqa: BLE001 - nunca morir
                res = fail("Error interno del servidor %s: %s" % (name, ex))
            send({"jsonrpc": "2.0", "id": mid, "result": res})
        elif mid is not None:
            # Una petición que no entendemos se contesta igual: dejar a un
            # cliente esperando una respuesta que no llega es peor.
            send({"jsonrpc": "2.0", "id": mid, "error": {
                "code": -32601, "message": "método no soportado: %s" % method}})
        # Las notificaciones (sin id) no llevan respuesta.


def tool(name, description, properties, required=()):
    return {"name": name, "description": description,
            "inputSchema": {"type": "object", "properties": properties,
                            "required": list(required)}}


STR = {"type": "string"}
INT = {"type": "integer"}
BOOL = {"type": "boolean"}
