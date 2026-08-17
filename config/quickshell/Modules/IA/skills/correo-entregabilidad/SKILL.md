---
name: "Correo y entregabilidad"
description: "Por qué el correo de un dominio rebota o cae en spam y cómo arreglarlo: SPF, DKIM, DMARC, listas negras, colas de Exim/Postfix y lectura de rebotes. Úsala si se habla de correos que no llegan, spam, rebotes, blacklists o un buzón que no envía."
triggers: "spf, dkim, dmarc, postfix, exim, dovecot, mailq, rebote, rebotes, bounce, spam, blacklist, buzon, smtp, imap, entregabilidad, no llegan los correos"
---

# Correo y entregabilidad

Hay dos problemas distintos que se cuentan igual («el correo no llega»):
**no sale o rebota** (problema técnico, se ve en los logs) y **llega a
spam** (problema de reputación, se ve en las cabeceras del receptor).
Averigua primero cuál de los dos es, porque no comparten arreglo.

## Si rebota: el log tiene la respuesta literal

El servidor receptor DICE por qué rechaza, y esa frase está en el log del
emisor. Búscala por la dirección:

- Exim (cPanel): `/var/log/exim_mainlog`.
- Postfix (Plesk): `/usr/local/psa/var/log/maillog`.

Con el harness: `server_logs {path, grep:"la-direccion"}`. Lee el código
SMTP del rebote: 4xx es temporal (reintenta solo), 5xx es definitivo (algo
hay que cambiar). Un «550 5.7.1» con una URL casi siempre trae el enlace
exacto que explica el bloqueo — síguelo con `fetch_url`.

## Operar la cola sin destruir pruebas

```sh
# Postfix
postqueue -p                        # listar la cola
postcat -vq IDMENSAJE               # ver un mensaje concreto
postsuper -d IDMENSAJE              # borrar uno
postsuper -d ALL deferred           # vaciar los diferidos (solo tras aprobación)

# Exim
exim -bpc                           # contar la cola
exim -bp | exiqsumm                 # resumida por dominio
exim -Mvh IDMENSAJE                 # cabeceras de un mensaje en cola
exiqgrep -i -f 'remite@' | xargs exim -Mrm    # borrar por remitente
exim -bt usuario@dominio            # cómo se enrutaría, sin enviar nada
```

**Cola disparada** (miles de mensajes) casi siempre es una cuenta o un
formulario comprometido enviando spam. Identifica el origen ANTES de vaciar
nada, porque vaciar primero destruye la prueba. Las dos pistas con nombre:
en cPanel, las líneas de `exim_mainlog` con `cwd=/home/…` apuntan al
directorio del script que envía, y en Plesk/Postfix, `sasl_username=` en el
maillog dice qué buzón autenticado es el comprometido. Se cierra ese grifo
(contraseña, formulario) y solo entonces se vacía.

## Si cae en spam: los tres apellidos del dominio

Se comprueban con `dig TXT` (y existen los tres o la reputación cojea):

```sh
dig +short TXT example.com                      # SPF
dig +short TXT selector._domainkey.example.com  # DKIM (el selector varía)
dig +short TXT _dmarc.example.com               # DMARC
```

- **SPF** dice qué servidores pueden enviar como el dominio. Solo puede
  haber UN registro que empiece por `v=spf1` — dos registros lo invalidan
  entero, y es el error más común tras añadir un servicio de mailing.
  Máximo 10 consultas DNS (`include` cuenta): pasarse también lo invalida.
  Del final: `-all` rechaza, `~all` marca, y `+all` autoriza al mundo
  entero — parece protección y es lo contrario.
- **DKIM** firma los mensajes. El selector lo pone el panel o el servicio
  (`default`, `mail`, etc.) — si no sabes cuál es, está en las cabeceras de
  un correo enviado (`DKIM-Signature: s=…`). Selectores habituales por
  servicio: `google` (Google Workspace), `selector1`/`selector2`
  (Microsoft 365), `s1`/`s2` (SendGrid), `k1` (Mailchimp).
- **DMARC** dice qué hacer cuando SPF y DKIM fallan y a quién avisar.
  Empezar con `p=none` y un `rua=` para recibir informes, y endurecer a
  `quarantine`/`reject` cuando los informes salgan limpios.

**SPF pasa pero DMARC falla.** DMARC no mira solo el veredicto sino el
**alineamiento**: el dominio del Return-Path (para SPF) o el del firmante
DKIM (`d=`) tiene que coincidir con el del From visible. Con un servicio
de mailing el Return-Path es del servicio, así que SPF nunca alinea — lo
que salva el DMARC es una firma DKIM con TU dominio, la que el servicio
activa al «verificar el dominio». Es la avería más incomprendida de todas.

**Los requisitos de Gmail y Yahoo (desde 2024).** Para quien les envía en
volumen: SPF y DKIM, DMARC publicado (aunque sea `p=none`), baja en un
clic en los boletines y tasa de quejas por debajo del 0,3 % (se vigila en
Google Postmaster Tools). Incumplirlos no siempre rebota: degrada en
silencio, que es peor de diagnosticar.

## Lo que la reputación mira además del DNS

- **PTR coherente**: la IP del servidor debe resolver inversa
  (`dig -x <ip>`) a un nombre que a su vez resuelva a esa IP, y el HELO
  del servidor debería casar con él. Sin eso, Gmail y Microsoft degradan
  aunque SPF y DKIM estén perfectos. El PTR lo cambia el proveedor de la
  IP.
- **El MX debe apuntar a un nombre con registro A**, nunca a un CNAME —
  funciona a ratos y falla con los receptores estrictos.
- **Rechazos 4xx que se repiten sin motivo claro**: greylisting del
  receptor — el reintento automático lo resuelve solo. Solo es problema si
  el emisor no reintenta (formularios que envían directo).
- **Microsoft (outlook/hotmail) rebota y Gmail no** (o al revés): cada
  gigante tiene su reputación propia y su formulario de delisting. El
  código del rebote trae la URL exacta: síguela, no adivines.
- **Tras migrar de servidor, todo cae en spam.** Tres sospechosos en
  orden: el SPF sigue autorizando la IP vieja y no la nueva, la IP nueva
  no tiene PTR, y la IP nueva es «fría» — sin historial, los grandes
  desconfían del volumen súbito. Los dos primeros se arreglan en DNS, el
  tercero solo con envío gradual y paciencia.

## Listas negras

Se consulta con un checker (mxtoolbox u otro, con `fetch_url`) o con `dig`
contra la zona de la DNSBL, invirtiendo la IP:

```sh
# IP 203.0.113.7 → octetos invertidos + zona
dig +short 7.113.0.203.zen.spamhaus.org
```

Sin respuesta = no listada. `127.0.0.x` = listada (el último octeto dice
en qué lista). Y la trampa que pierde horas: una respuesta `127.255.255.x`
no significa «listado», significa «consulta rechazada» — Spamhaus rechaza
los resolutores públicos (8.8.8.8, 1.1.1.1). Se consulta con el resolutor
propio del servidor o por el checker web.

Si la IP está listada: primero **cerrar el grifo** (la cuenta
comprometida, el formulario abierto), después pedir la baja. Pedir la baja
sin cerrar el grifo garantiza volver a entrar, y la segunda baja siempre
cuesta más.

## Comprobar que quedó arreglado

La prueba de fuego sin adivinar: enviar un correo a un buzón de Gmail y
leer «Mostrar original» — trae el veredicto de SPF, DKIM y DMARC uno a
uno, con el dominio que alineó cada cual. En el log del emisor, la línea
del mensaje debe acabar en entrega (`status=sent` en Postfix, la flecha
`=>` y «Completed» en Exim). Y tras un cambio de DNS, verlo desde fuera
con `dig` contra un resolutor público antes de darlo por propagado — el
TTL viejo puede seguir sirviéndose durante horas.

## Reglas

- No vacíes una cola ni borres mensajes sin haber identificado el origen y
  habérselo enseñado al usuario — y el vaciado va en `propose_plan`.
- Cambios de SPF/DKIM/DMARC son cambios de DNS: copia de la zona antes, y
  recuerda el TTL — el efecto no es inmediato.
- El puerto 25 saliente está bloqueado en muchos centros de datos y VPS
  nuevos: si nada sale y el log dice timeout hacia todos, es eso, no tu
  configuración. Se pide al proveedor.
- Si el dominio del usuario tiene una particularidad (su servicio de
  mailing, su selector DKIM, quién sirve su zona), guárdala con `learn`.
