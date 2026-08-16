#!/usr/bin/env python3
# El SOPLÓN: un servicio interno que delata si alguien le ha hablado.
#
# Existe para probar una cosa que no se puede probar mirando la respuesta: que
# una petición NO llegó a salir. Escribe un archivo la primera vez que alguien
# le pide algo, así que su ausencia es la prueba.
#
# Y contesta con una redirección a una dirección pública, que es la forma del
# ataque que interesa: internet → máquina de casa → internet. Con la
# comprobación puesta solo al final, ese salto de en medio se hacía —la petición
# al router YA es la acción— y luego la última IP era pública, así que pasaba.
#
#   soplon.py <puerto> <archivo-testigo>
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

TESTIGO = sys.argv[2] if len(sys.argv) > 2 else "/tmp/soplon.testigo"


class Manejador(BaseHTTPRequestHandler):
    def do_GET(self):
        with open(TESTIGO, "w", encoding="utf-8") as f:
            f.write(self.path + "\n")
        self.send_response(302)
        self.send_header("Location", "https://example.com/")
        self.end_headers()

    def log_message(self, *_a):
        pass


HTTPServer(("127.0.0.1", int(sys.argv[1])), Manejador).serve_forever()
