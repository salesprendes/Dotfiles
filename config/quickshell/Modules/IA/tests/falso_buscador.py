#!/usr/bin/env python3
# Buscador de mentira para probar WebSearch.js. Sirve una respuesta fija y
# apunta en un archivo las peticiones que recibe (ruta, cabecera de clave y
# cuerpo), que es como se comprueba que el secreto viaja donde debe.
import sys, json, http.server, socketserver

puerto = int(sys.argv[1])
modo = sys.argv[2]
diario = sys.argv[3] if len(sys.argv) > 3 else "/dev/null"

CUERPOS = {
    "json": (200, "application/json", json.dumps({"results": [
        {"title": "iPhone 15 precio", "url": "https://a.example/1",
         "content": "Desde <strong>799</strong>&nbsp;€ en tienda"},
        {"title": "Comparativa", "url": "https://b.example/2", "content": "Otro"}]})),
    "vacio": (200, "application/json", json.dumps({"results": []})),
    "html": (200, "text/html", "<!doctype html><html><title>Verifying your browser</title>"),
    "brave": (200, "application/json", json.dumps({"web": {"results": [
        {"title": "Brave dice", "url": "https://x", "description": "<b>399</b> €"}]}})),
    "tavily": (200, "application/json", json.dumps({"results": [
        {"title": "Tavily dice", "url": "https://t", "content": "349 €"}]})),
    "error": (200, "application/json", json.dumps({"error": {"detail": "clave invalida"}})),
    # El mismo resultado con URL cosméticamente distintas, que es como llega
    # cuando el agregador junta varios motores.
    "dobles": (200, "application/json", json.dumps({"results": [
        {"title": "Uno", "url": "https://a.example/x", "content": "c",
         "publishedDate": "2026-08-01T10:00:00"},
        {"title": "Uno otra vez", "url": "https://a.example/x/", "content": "c"},
        {"title": "Uno con campana", "url": "https://a.example/x?utm_source=z", "content": "c"},
        {"title": "Dos", "url": "https://b.example/y", "content": "c"}]})),
}


class H(http.server.BaseHTTPRequestHandler):
    def _sirve(self, extra=""):
        with open(diario, "a") as f:
            f.write(self.path + "\t"
                    + self.headers.get("X-Subscription-Token", "-") + "\t"
                    + extra + "\n")
        cod, tipo, cuerpo = CUERPOS[modo]
        b = cuerpo.encode()
        self.send_response(cod)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        self._sirve()

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        self._sirve(self.rfile.read(n).decode("utf-8", "replace"))

    def log_message(self, *a):
        pass


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", puerto), H) as s:
    print("listo", flush=True)
    s.serve_forever()
