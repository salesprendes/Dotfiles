#!/usr/bin/env python3
# Servidor de mentira compatible con /v1/chat/completions. Apunta en un archivo
# lo que ha recibido —cabeceras y cuerpo— para que la prueba pueda comprobar qué
# viajó de verdad, que es lo único que importa aquí.
import sys, json, http.server, socketserver

puerto = int(sys.argv[1])
diario = sys.argv[2]

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/ping":
            self.responde(b"ok", "text/plain"); return
        if self.path.endswith("/models"):
            self.responde(json.dumps({"models": [{"id": "uno"}]}).encode(),
                          "application/json")
            return
        self.send_response(404); self.end_headers()

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        crudo = self.rfile.read(n)
        try:
            cuerpo = json.loads(crudo)
        except Exception:
            cuerpo = {"_ilegible": len(crudo)}
        with open(diario, "w") as f:
            json.dump({"auth": self.headers.get("Authorization"),
                       "pasarela": self.headers.get("X-Pasarela"),
                       "ct": self.headers.get("Content-Type"),
                       "title": self.headers.get("X-Title"),
                       "len": len(crudo),
                       "body": cuerpo}, f)
        self.responde(json.dumps({"choices": [
            {"message": {"role": "assistant", "content": "vale"}}]}).encode(),
            "application/json")

    def responde(self, b, tipo):
        self.send_response(200)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a):
        pass

socketserver.TCPServer.allow_reuse_address = True
class S(socketserver.ThreadingTCPServer):
    daemon_threads = True
with S(("127.0.0.1", puerto), H) as s:
    s.serve_forever()
