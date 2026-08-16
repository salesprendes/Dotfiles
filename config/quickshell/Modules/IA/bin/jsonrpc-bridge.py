#!/usr/bin/env python3
# Puente de framing para LSP y DAP.
#
# Los dos protocolos hablan JSON-RPC con cabeceras Content-Length, un formato
# que el lado QML no puede trocear cómodo (SplitParser corta por líneas). Este
# puente lo traduce a NDJSON en las dos direcciones: QML escribe UNA línea de
# JSON por mensaje y recibe UNA línea por mensaje, y el puente pone y quita las
# cabeceras contra el proceso servidor.
#
# Modos:
#   jsonrpc-bridge.py stdio -- <servidor> [args...]
#       El servidor habla por su stdin/stdout (LSP típico, lldb-dap, debugpy).
#   jsonrpc-bridge.py tcp <puerto> -- <servidor> [args...]
#       Arranca el servidor y se conecta a 127.0.0.1:<puerto> con reintentos
#       (delve: `dlv dap --listen` solo escucha TCP).
#
# Además atiende dos recados locales del lado QML (mensajes {"_qs": ...} que
# NO viajan al servidor), porque el puente ya es python y tiene el disco a
# mano mientras que QML no:
#   {"_qs":"open","path":...,"languageId":...}   lee el archivo y manda el
#       didOpen (didClose antes si ya estaba abierto: re-análisis fresco).
#   {"_qs":"apply_edit","edit":<WorkspaceEdit>,"backupDir":...}   aplica un
#       WorkspaceEdit (rename de LSP) con copia previa de cada archivo y la
#       misma jaula de $HOME que el resto del harness.
import json
import os
import socket
import subprocess
import sys
import threading
import urllib.parse
import urllib.request

OUT = sys.stdout.buffer
OUT_LOCK = threading.Lock()


def emitir(obj):
    with OUT_LOCK:
        OUT.write((json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8"))
        OUT.flush()


def leer_enmarcado(rd):
    # Un mensaje con cabeceras Content-Length, o None si el canal murió.
    largo = None
    while True:
        linea = rd.readline()
        if not linea:
            return None
        linea = linea.strip()
        if linea == b"":
            break
        if linea.lower().startswith(b"content-length:"):
            try:
                largo = int(linea.split(b":", 1)[1])
            except ValueError:
                return None
    if largo is None:
        return None
    cuerpo = b""
    while len(cuerpo) < largo:
        trozo = rd.read(largo - len(cuerpo))
        if not trozo:
            return None
        cuerpo += trozo
    try:
        return json.loads(cuerpo.decode("utf-8", errors="replace"))
    except json.JSONDecodeError:
        return None


def escribir_enmarcado(wr, obj):
    cuerpo = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    wr.write(b"Content-Length: " + str(len(cuerpo)).encode() + b"\r\n\r\n" + cuerpo)
    wr.flush()


def uri_de(path):
    return "file://" + urllib.parse.quote(os.path.abspath(path))


def path_de(uri):
    if not uri.startswith("file://"):
        return ""
    return urllib.parse.unquote(uri[len("file://"):])


HOME = os.path.realpath(os.path.expanduser("~"))
ABIERTOS = {}          # path → versión enviada

LANG_POR_EXT = {
    ".qml": "qml", ".js": "javascript", ".mjs": "javascript", ".ts": "typescript",
    ".py": "python", ".c": "c", ".h": "c", ".cpp": "cpp", ".hpp": "cpp",
    ".cc": "cpp", ".rs": "rust", ".go": "go", ".sh": "shellscript",
    ".bash": "shellscript", ".lua": "lua", ".json": "json", ".md": "markdown"
}


def en_home(path):
    real = os.path.realpath(os.path.abspath(path))
    return real == HOME or real.startswith(HOME + os.sep)


def recado_open(msg, wr):
    path = os.path.abspath(os.path.expanduser(msg.get("path", "")))
    if not en_home(path):
        emitir({"_qs": "opened", "path": path, "ok": False,
                "error": "fuera de la carpeta personal"})
        return
    try:
        texto = open(path, encoding="utf-8", errors="replace").read()
    except OSError as e:
        emitir({"_qs": "opened", "path": path, "ok": False, "error": str(e)})
        return
    lang = msg.get("languageId") or LANG_POR_EXT.get(
        os.path.splitext(path)[1].lower(), "plaintext")
    uri = uri_de(path)
    if path in ABIERTOS:
        escribir_enmarcado(wr, {"jsonrpc": "2.0",
            "method": "textDocument/didClose",
            "params": {"textDocument": {"uri": uri}}})
    version = ABIERTOS.get(path, 0) + 1
    ABIERTOS[path] = version
    escribir_enmarcado(wr, {"jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {"textDocument": {"uri": uri, "languageId": lang,
                                    "version": version, "text": texto}}})
    emitir({"_qs": "opened", "path": path, "ok": True, "uri": uri})


def aplicar_edits_texto(path, edits):
    # Los rangos de un TextEdit son de ANTES de tocar nada: se aplican de
    # atrás hacia delante para que los offsets no se muevan bajo los pies.
    texto = open(path, encoding="utf-8", errors="replace").read()
    lineas = texto.split("\n")
    offsets, acc = [], 0
    for l in lineas:
        offsets.append(acc)
        acc += len(l) + 1

    def off(pos):
        li = min(pos.get("line", 0), len(lineas) - 1)
        return offsets[li] + min(pos.get("character", 0), len(lineas[li]))

    orden = sorted(edits, key=lambda e: (e["range"]["start"]["line"],
                                         e["range"]["start"]["character"]),
                   reverse=True)
    for e in orden:
        a, b = off(e["range"]["start"]), off(e["range"]["end"])
        texto = texto[:a] + e.get("newText", "") + texto[b:]
    open(path, "w", encoding="utf-8").write(texto)
    return len(edits)


def recado_apply_edit(msg):
    edit = msg.get("edit") or {}
    bdir = msg.get("backupDir", "")
    # Las dos formas del contrato: changes (uri→edits) y documentChanges.
    por_archivo = {}
    for uri, edits in (edit.get("changes") or {}).items():
        por_archivo.setdefault(path_de(uri), []).extend(edits)
    for dc in (edit.get("documentChanges") or []):
        if "textDocument" in dc:
            por_archivo.setdefault(path_de(dc["textDocument"]["uri"]),
                                   []).extend(dc.get("edits", []))
    hechos, copias, errores = [], [], []
    for path, edits in por_archivo.items():
        if path == "" or not en_home(path):
            errores.append(path + ": fuera de la carpeta personal")
            continue
        try:
            if bdir:
                os.makedirs(bdir, mode=0o700, exist_ok=True)
                import shutil
                import time
                bak = os.path.join(bdir, str(int(time.time() * 1000))
                                   + "-" + os.path.basename(path))
                shutil.copy2(path, bak)
                copias.append(bak)
            n = aplicar_edits_texto(path, edits)
            hechos.append({"path": path, "edits": n})
        except OSError as e:
            errores.append(path + ": " + str(e))
    emitir({"_qs": "applied", "files": hechos, "backups": copias,
            "errors": errores})


def main():
    argv = sys.argv[1:]
    modo = argv[0] if argv else "stdio"
    puerto = 0
    if modo == "tcp":
        puerto = int(argv[1])
        cmd = argv[argv.index("--") + 1:]
    else:
        cmd = argv[argv.index("--") + 1:]

    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL)

    if modo == "tcp":
        # El servidor escucha TCP (delve): reintentos hasta que abra.
        import time
        sock = None
        for _ in range(50):
            try:
                sock = socket.create_connection(("127.0.0.1", puerto), timeout=1)
                break
            except OSError:
                if proc.poll() is not None:
                    emitir({"_qs": "fatal", "error": "el servidor murió antes de escuchar"})
                    return
                time.sleep(0.2)
        if sock is None:
            emitir({"_qs": "fatal", "error": "no se pudo conectar al puerto " + str(puerto)})
            proc.terminate()
            return
        rd = sock.makefile("rb")
        wr = sock.makefile("wb")
    else:
        rd, wr = proc.stdout, proc.stdin

    emitir({"_qs": "up"})

    def del_servidor():
        while True:
            m = leer_enmarcado(rd)
            if m is None:
                break
            emitir(m)
        emitir({"_qs": "down", "code": proc.poll()})
        # Sin servidor no hay nada que hacer: se suelta el stdin bloqueado.
        os._exit(0)

    threading.Thread(target=del_servidor, daemon=True).start()

    for linea in sys.stdin.buffer:
        linea = linea.strip()
        if not linea:
            continue
        try:
            msg = json.loads(linea.decode("utf-8", errors="replace"))
        except json.JSONDecodeError:
            continue
        recado = msg.get("_qs")
        if recado == "open":
            recado_open(msg, wr)
        elif recado == "apply_edit":
            recado_apply_edit(msg)
        else:
            try:
                escribir_enmarcado(wr, msg)
            except (BrokenPipeError, OSError):
                break

    try:
        proc.terminate()
    except OSError:
        pass


if __name__ == "__main__":
    main()
