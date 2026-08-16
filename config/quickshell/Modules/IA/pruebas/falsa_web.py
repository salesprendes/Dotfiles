#!/usr/bin/env python3
# Sitio de mentira para probar fetch_url. Cada ruta reproduce una de las formas
# en que una página puede salir mal — y todas salieron de casos REALES vistos en
# el registro de auditoría del asistente.
import sys, gzip, http.server, socketserver

puerto = int(sys.argv[1])

ARTICULO = """<!doctype html><html><head><title>Precios</title>
<style>.a{color:red}</style><script>var x=1;</script></head>
<body>
<nav><a href="/1">Inicio</a> <a href="/2">Tienda</a> <a href="/3">Ayuda</a></nav>
<aside>Publicidad: compre ya. Boletin. Cookies. Aceptar todas.</aside>
<article><h1>Precio del cacharro</h1>
<p>El cacharro cuesta 799&nbsp;&euro; en la tienda oficial, y la versi&oacute;n
grande sube hasta 899&nbsp;&euro;. Los precios incluyen impuestos y no
contemplan promociones puntuales, que suelen aparecer en temporada alta.</p>
<table><tr><th>Modelo</th><th>Precio</th></tr>
<tr><td>128 GB</td><td>799 &euro;</td></tr>
<tr><td>256 GB</td><td>899 &euro;</td></tr></table>
<p>Se&ntilde;alamos que el env&iacute;o es gratis a partir de cincuenta euros y
que la garant&iacute;a del fabricante cubre dos a&ntilde;os completos desde la
fecha que figure en la factura de compra original del producto.</p>
<p>Para cualquier duda sobre la disponibilidad conviene consultar la ficha del
producto, que se actualiza varias veces al d&iacute;a seg&uacute;n el
almac&eacute;n.</p></article>
<footer>Aviso legal. Privacidad. Contacto. Mapa del sitio.</footer>
</body></html>"""

# El armazón de una tienda: cabecera, menú y nada más. El listado lo pintaría
# JavaScript. Este es el caso que devolvía 297 caracteres de menú.
ESCAPARATE = ("<!doctype html><html><head><title>Buscar</title></head><body>"
              "<nav>Ir al contenido Todas las categorias Que estas buscando "
              "Mi tienda Top ofertas Ventajas exclusivas</nav>"
              "<div id='app'></div></body></html>")

# 404 disfrazado de respuesta correcta: estado 200 y "Error 404" en el cuerpo.
BLANDO404 = ("<!doctype html><html><head><title>Ups</title></head><body>"
             "<h1>Page Not Found</h1><p>Lo sentimos, esta pagina ha "
             "desaparecido. Vuelve a la pagina de inicio. Error 404.</p>"
             "</body></html>")

RETO = ("<!doctype html><html><head><title>Just a moment...</title></head>"
        "<body><h1>Checking your browser</h1><p>Verifying your browser before "
        "you continue. This process is automatic and takes a few seconds. "
        "Please enable JavaScript to continue browsing this website.</p>"
        "</body></html>")

JSON = '{"precio": 799, "moneda": "EUR", "nota": "a < b"}'
XML = '<?xml version="1.0"?><precios><item id="1">799</item></precios>'
TXT = "precio: 799\ncomparacion: a < b > c\n" + ("relleno " * 60)


class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        p = self.path
        cod, tipo, cuerpo, comprime = 200, "text/html; charset=utf-8", ARTICULO, False
        if p.startswith("/api"):
            tipo, cuerpo = "application/json", JSON
        elif p.startswith("/xml"):
            tipo, cuerpo = "application/xml", XML
        elif p.startswith("/txt"):
            tipo, cuerpo = "text/plain; charset=utf-8", TXT
        elif p.startswith("/vacio"):
            cuerpo = ""
        elif p.startswith("/largo"):
            cuerpo = "<html><body>" + ("hola ñ " * 6000) + "</body></html>"
        elif p.startswith("/escaparate"):
            cuerpo = ESCAPARATE
        elif p.startswith("/blando404"):
            cuerpo = BLANDO404
        elif p.startswith("/reto"):
            cuerpo = RETO
        elif p.startswith("/404"):
            cod, cuerpo = 404, ""
        elif p.startswith("/403"):
            cod, cuerpo = 403, "<html>Forbidden</html>"
        elif p.startswith("/500"):
            cod, cuerpo = 500, "<html>boom</html>"
        elif p.startswith("/pdf"):
            tipo = "application/pdf"
            cuerpo = "%PDF-1.4 fake"
        elif p.startswith("/binario"):
            # Miente en la cabecera: dice HTML y manda bytes con NUL dentro.
            b = b"\x1f\x8b\x08\x00" + bytes(range(256)) * 4
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)
            return
        elif p.startswith("/gzip"):
            # EL CASO AMAZON: comprime aunque el cliente no lo haya pedido.
            comprime = True

        b = cuerpo.encode()
        if comprime:
            b = gzip.compress(b)
        self.send_response(cod)
        self.send_header("Content-Type", tipo)
        if comprime:
            self.send_header("Content-Encoding", "gzip")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a):
        pass


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", puerto), H) as s:
    print("listo", flush=True)
    s.serve_forever()
