---
name: Correo y entregabilidad
description: Por qué el correo de un dominio rebota o cae en spam y cómo arreglarlo: SPF, DKIM, DMARC, listas negras, colas de Exim/Postfix y lectura de rebotes. Úsala si se habla de correos que no llegan, spam, rebotes, blacklists o un buzón que no envía.
---

# Correo y entregabilidad

Hay dos problemas distintos que se cuentan igual («el correo no llega»):
**no sale o rebota** (problema técnico, se ve en los logs) y **llega a
spam** (problema de reputación, se ve en las cabeceras del receptor).
Averigua primero cuál de los dos es, porque no comparten arreglo.

## Si rebota: el log tiene la respuesta literal

El servidor receptor DICE por qué rechaza, y esa frase está en el log del
emisor. Búscala por la dirección:

- Exim (cPanel): `/var/log/exim_mainlog`. La cola se cuenta con `exim -bpc`
  y se lista con `exim -bp`.
- Postfix (Plesk): `/usr/local/psa/var/log/maillog`. La cola, con
  `postqueue -p`.

Con el harness: `server_logs {path, grep:"la-direccion"}`. Lee el código
SMTP del rebote: 4xx es temporal (reintenta solo), 5xx es definitivo (algo
hay que cambiar). Un «550 5.7.1» con una URL casi siempre trae el enlace
exacto que explica el bloqueo — síguelo con `fetch_url`.

**Cola disparada** (miles de mensajes) casi siempre es una cuenta o un
formulario comprometido enviando spam. Identifica el origen ANTES de vaciar
nada: el remitente más repetido de la cola es la pista, y vaciar primero
destruye la prueba.

## Si cae en spam: los tres apellidos del dominio

Se comprueban con `dig TXT` (y existen los tres o la reputación cojea):

```sh
dig +short TXT example.com                      # SPF
dig +short TXT selector._domainkey.example.com  # DKIM (el selector varía)
dig +short TXT _dmarc.example.com               # DMARC
```

- **SPF** dice qué servidores pueden enviar como el dominio. Solo puede
  haber UN registro SPF — dos registros lo invalidan entero, y es el error
  más común tras añadir un servicio de mailing. Máximo 10 consultas DNS
  (`include` cuenta): pasarse también lo invalida.
- **DKIM** firma los mensajes. El selector lo pone el panel o el servicio
  (`default`, `mail`, etc.) — si no sabes cuál es, está en las cabeceras de
  un correo enviado (`DKIM-Signature: s=…`).
- **DMARC** dice qué hacer cuando SPF y DKIM fallan y a quién avisar.
  Empezar con `p=none` y un `rua=` para recibir informes, y endurecer a
  `quarantine`/`reject` cuando los informes salgan limpios.

La prueba de fuego sin adivinar: enviar un correo a un buzón de Gmail y
leer «Mostrar original» — trae el veredicto de SPF/DKIM/DMARC uno a uno.

## Lo que la reputación mira además del DNS

- **PTR coherente**: la IP del servidor debe resolver inversa
  (`dig -x <ip>`) a un nombre que a su vez resuelva a esa IP, y el HELO
  del servidor debería casar con él. Sin eso, Gmail y Microsoft degradan
  aunque SPF y DKIM estén perfectos. El PTR lo cambia el proveedor de la
  IP.
- **Rechazos 4xx que se repiten sin motivo claro**: greylisting del
  receptor — el reintento automático lo resuelve solo. Solo es problema si
  el emisor no reintenta (formularios que envían directo).
- **Microsoft (outlook/hotmail) rebota y Gmail no** (o al revés): cada
  gigante tiene su reputación propia y su formulario de delisting. El
  código del rebote trae la URL exacta: síguela, no adivines.

## Listas negras

Se consulta si la IP del servidor está listada (mxtoolbox u otro checker
con `fetch_url`, o `dig` contra la zona de la DNSBL). Si lo está: primero
**cerrar el grifo** (la cuenta comprometida, el formulario abierto), después
pedir la baja. Pedir la baja sin cerrar el grifo garantiza volver a entrar,
y la segunda baja siempre cuesta más.

## Reglas

- No vacíes una cola ni borres mensajes sin haber identificado el origen y
  habérselo enseñado al usuario.
- Cambios de SPF/DKIM/DMARC son cambios de DNS: copia de la zona antes, y
  recuerda el TTL — el efecto no es inmediato.
- El puerto 25 saliente está bloqueado en muchos centros de datos y VPS
  nuevos: si nada sale y el log dice timeout hacia todos, es eso, no tu
  configuración. Se pide al proveedor.
