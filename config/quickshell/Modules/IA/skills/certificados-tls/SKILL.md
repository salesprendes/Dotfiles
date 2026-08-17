---
name: "Certificados TLS"
description: "Diagnosticar y renovar certificados HTTPS: certificado caducado o que caducó, cadena incompleta, SAN que no casa, Let's Encrypt que no renueva, wildcard y los avisos del navegador. Úsala si se habla de un certificado, de HTTPS roto, de un candado en rojo o de SSL."
triggers: "certbot, acme, letsencrypt, well-known, acme-challenge, wildcard, fullchain, privkey, openssl, s_client, caducado, caducar, expirado, candado, https, ssl, tls, pfx, csr, cadena incompleta, intermedio, reemitir, renovacion, dns-01, http-01"
---

# Certificados TLS

Regla número uno: **compruébalo desde fuera**, como lo ve un navegador. El
archivo que hay en el disco del servidor no siempre es el que el servicio
está sirviendo — recargar tras renovar se olvida constantemente.

## El comando que responde casi todo

```sh
echo | openssl s_client -servername example.com -connect example.com:443 2>/dev/null | openssl x509 -noout -dates -subject -issuer -ext subjectAltName
```

De un tiro: fechas, para qué nombres vale (SAN), y quién lo emitió. El
`-servername` importa — sin él, con varios dominios en la misma IP (SNI),
te enseña OTRO certificado y el diagnóstico sale mal.

Para ver la cadena completa: el mismo `s_client` con `-showcerts`. Y al
final de su salida, la línea `Verify return code`: `0 (ok)` o el motivo
exacto por el que un cliente estricto desconfía.

El mismo truco vale para el correo y para un servidor que aún no recibe
tráfico:

```sh
openssl s_client -connect mail.example.com:993 -servername mail.example.com  # IMAPS
openssl s_client -starttls smtp -connect mail.example.com:587                # SMTP con STARTTLS
openssl s_client -connect 203.0.113.7:443 -servername example.com            # el servidor NUEVO, antes de mover el DNS
curl -sv --resolve example.com:443:203.0.113.7 https://example.com -o /dev/null  # ídem, con petición HTTP real
```

Probar el servidor nuevo contra su IP con `--resolve` antes de cambiar el
DNS es lo que evita estrenar la migración con el candado roto.

## Fallos con nombre y apellidos

**Caducado.** Las fechas de arriba lo dicen. Si hay renovación automática
configurada y aun así caducó, el problema es POR QUÉ no renovó (siguiente
punto), no renovar a mano y ya — eso vuelve a pasar en 90 días. Para
vigilar sin mirar fechas a ojo: `openssl x509 -checkend 2592000 -noout -in
cert.pem` devuelve error si caduca en menos de 30 días — perfecto para un
aviso programado.

**Let's Encrypt no renueva.** Su validación http-01 necesita que
`http://dominio/.well-known/acme-challenge/` sea alcanzable desde fuera:
una redirección forzada a HTTPS mal hecha, un firewall o un DNS que ya no
apunta ahí la rompen. El error exacto está en el log del cliente ACME
(certbot en `/var/log/letsencrypt/`, o el propio panel en Plesk/cPanel).
Prueba en seco antes de nada: `certbot renew --dry-run`.

Tres trampas de certbot que cuestan horas. `certbot renew` solo actúa
sobre certificados a menos de 30 días de caducar — que «no haga nada» es
lo normal, no un fallo. `certbot certificates` lista qué gestiona y con
qué rutas, la foto que faltaba en la mitad de las averías. Y renovar no
recarga servicios: sin un `--deploy-hook "systemctl reload nginx"` el
certificado nuevo se queda en el disco sin servirse. Al depurar, siempre
`--dry-run`: valida contra el entorno de pruebas y no quema el límite de
5 certificados duplicados por semana, que al quinto intento «para probar»
deja el dominio bloqueado unos días.

**«El certificado no es válido para este nombre».** El SAN no incluye el
nombre visitado. El caso típico: cubre `example.com` pero no
`www.example.com`, o al revés. Se reemite incluyendo ambos — no se arregla
con redirecciones.

**Funciona en el navegador pero falla en curl, una app o un móvil viejo.**
Cadena incompleta: el servidor manda solo su certificado sin el
intermedio. Los navegadores lo disimulan (cachean intermedios) y el resto
no. Se ve con `openssl s_client -showcerts` — deben salir al menos dos. Se
arregla sirviendo el `fullchain`, no el `cert` a secas.

**Renovado pero sigue saliendo el viejo.** El servicio no recargó. Recarga
(no hace falta reiniciar) nginx/apache y vuelve a mirar desde fuera. Y ojo
con el segundo servicio olvidado que también usa ese certificado: correo
(dovecot/postfix/exim), paneles, FTP. Con certbot, sirve siempre las
rutas de `/etc/letsencrypt/live/` — son enlaces simbólicos que la
renovación actualiza sola. Copiar los archivos a otra carpeta «para
ordenar» congela el certificado en la versión de ese día. Un
`grep -r ssl_certificate /etc/nginx/` dice qué archivo carga de verdad
cada sitio.

**«No es válido AÚN», o falla solo en una máquina.** Reloj desajustado en
el CLIENTE: un certificado recién emitido parece «del futuro» para un
equipo con la hora atrasada. `timedatectl` en el que falla — se arregla
con NTP, no reemitiendo nada.

**«¿Este certificado y esta clave son pareja?»** Antes de instalar nada a
mano:

```sh
openssl x509 -noout -pubkey -in cert.pem | sha256sum
openssl pkey -pubout -in clave.pem | sha256sum
```

Si los dos hashes no coinciden, no son pareja y el servicio no arrancará
(o servirá el error más confuso del catálogo). Es la comprobación de 10
segundos que ahorra la tarde.

**La validación pasa y aun así no emite.** `dig +short CAA example.com` —
un registro CAA que no autoriza a la CA bloquea la emisión en silencio, y
el CAA del dominio padre manda sobre los subdominios sin CAA propio (los
detalles, en la habilidad de DNS). Es el sospechoso cuando http-01 valida
bien y la emisión falla igual.

**Wildcard y dns-01.** Un certificado `*.example.com` cubre un nivel de
subdominios (no `a.b.example.com` y tampoco el ápex, que se añade como
SAN). Let's Encrypt solo lo emite con validación **dns-01** (un TXT en
`_acme-challenge`): eso exige que el cliente ACME pueda tocar el DNS — si
la renovación automática de un wildcard falla, el sospechoso es la API del
DNS, no el servidor web.

**Formatos.** PEM es el texto con `BEGIN CERTIFICATE` (lo que usan nginx y
apache). Un `.pfx`/`.p12` (Windows, paneles) se descompone con
`openssl pkcs12 -in archivo.pfx -nodes`. Un `.der`/`.cer` binario se
convierte con `openssl x509 -inform der -in x.cer`. La mitad de los «no me
acepta el certificado» son un formato equivocado, no un certificado malo.

## En los paneles

Plesk y cPanel llevan su propio Let's Encrypt integrado y guardan los
certificados a su manera: renueva DESDE el panel, no con certbot por
fuera, o acabarás con dos gestores pisándose el mismo dominio.

## Reglas

- Reemitir o cambiar un certificado en producción va en `propose_plan` con
  el paso de verificación incluido (el `openssl` de arriba, desde fuera).
- Nunca pegues una clave privada en el chat. Si aparece en un log o
  archivo, el harness la tapa — no la reproduzcas tú.
- Al terminar, verifica TODOS los servicios que usan ese certificado, no
  solo el 443.
- Qué gestiona los certificados de cada servidor (panel, certbot, otro
  cliente ACME) y qué servicios los comparten se apunta con `learn`: es la
  primera duda de la próxima renovación.
