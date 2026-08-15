---
name: "Plesk"
description: "Administrar y diagnosticar un servidor Plesk por SSH: utilidades plesk bin, plesk repair, dónde está cada log e incidencias típicas (web caída, correo, certificados, disco). Úsala si se habla de Plesk, de una suscripción o de un dominio alojado."
---

# Plesk (Linux)

Plesk **regenera** sus archivos de configuración. Esa es la regla que gobierna
todo lo demás: si editas a mano un `.conf` de un dominio, el panel te lo
sobrescribe en la siguiente reconfiguración y el cambio desaparece sin dejar
rastro. Se toca por utilidad o por panel, no por editor.

## Por dónde empezar

1. `hosting_query {panel:"plesk", op:"version"}` — confirma que hay Plesk y
   qué versión (las utilidades cambian entre Onyx y Obsidian).
2. `hosting_query` con `domains`, `subscriptions`, `databases` o
   `domain_info` (con `name` = el dominio). Son lecturas ya escritas y
   acotadas: úsalas antes que `ssh_exec`.
3. Para lo que no cubran, `ssh_exec` — y ahí ya eres tú el responsable.

**Si no estás seguro de una opción, pregúntasela a la utilidad:**
`plesk bin <utilidad> --help`. Plesk tiene decenas de utilidades y sus flags
cambian entre versiones: inventarse uno es la forma más rápida de romper algo.

## Utilidades que se usan a diario

```sh
plesk version                       # versión y componentes
plesk bin domain --list             # dominios
plesk bin domain --info example.com
plesk bin subscription --list       # suscripciones
plesk bin database --list
plesk bin site --help               # sitios (alojamiento web)
plesk bin mail --help               # buzones
plesk bin ipmanage --help           # direcciones IP
plesk bin pleskbackup --help        # copias de seguridad
plesk bin extension --list          # extensiones instaladas
plesk bin php_handler --list        # versiones de PHP disponibles
plesk bin service --status          # servicios que gestiona el panel
plesk bin dns --info example.com    # la zona DNS que sirve este Plesk
plesk login                         # URL de acceso con sesión de root
```

`plesk login` genera un enlace de un solo uso para entrar al panel como
administrador: es la salida cuando «se perdió la contraseña del panel»,
sin tocar la base de datos. Y `plesk installer` gestiona componentes y
actualizaciones del propio Plesk (es SU gestor, apt/yum no actualizan el
panel).

## La base de datos del panel (psa)

```sh
plesk db "SELECT id, name FROM domains WHERE name='example.com'"
```

Sirve para **consultar** cuando el panel no cuadra con la realidad. Escribir
en `psa` a mano corrompe el panel: no lo hagas nunca, ni aunque parezca la
solución rápida. Si el dato está mal, se arregla con la utilidad
correspondiente o con `plesk repair`.

## plesk repair: primero mirar, luego tocar

```sh
plesk repair all -n                 # DIAGNÓSTICO: informa, no cambia nada
plesk repair mail -n
plesk repair web example.com -n
```

Aspectos: `all`, `web`, `mail`, `dns`, `ftp`, `db`, `fs`, `mysql`,
`installation`.

El modo reparación (`-y`) **reconfigura servicios aunque no encuentre
problemas**: eso puede reiniciar cosas y afectar a los sitios. Va siempre en
un `propose_plan`, con `-n` enseñado antes y la ventana acordada.

## La excepción a «no editar a mano»

Las directivas propias de un dominio van en archivos que Plesk respeta e
incluye: `/var/www/vhosts/system/<dominio>/conf/vhost.conf` (Apache),
`vhost_nginx.conf` (nginx) y `vhost_ssl.conf` (el vhost seguro de Apache).
Tras crearlos o cambiarlos se aplican con:

```sh
plesk sbin httpdmng --reconfigure-domain example.com
```

Todo lo demás de ese directorio (`httpd.conf`, `nginx.conf` generados) se
regenera y no se toca.

## WordPress Toolkit desde la consola

En un Plesk típico la mitad de los sitios son WordPress, y la extensión
WP Toolkit los conoce todos. Su CLI trae además el `wp-cli` oficial
integrado, sin instalar nada en cada sitio:

```sh
plesk ext wp-toolkit --list                                # instancias con su ID
plesk ext wp-toolkit --wp-cli -instance-id 11 -- core version
plesk ext wp-toolkit --wp-cli -instance-id 11 -- plugin list
plesk ext wp-toolkit --wp-cli -instance-id 11 -- user list
```

Con eso se diagnostica un WordPress roto sin tocar FTP: versión, plugins
activos y usuarios en tres comandos. Desactivar un plugin sospechoso
(`-- plugin deactivate <nombre>`) es la primera maniobra ante un sitio
caído tras «actualizar algo» — reversible y quirúrgica. Actualizar
plugins o el núcleo en masa toca sitios de terceros: eso va con plan.

## Copias de seguridad

Las del panel caen en `/var/lib/psa/dumps` (por eso ese directorio es
sospechoso habitual del disco lleno). Se gestionan mejor desde el panel,
pero por consola existen las dos mitades: `plesk bin pleskbackup` crea
(server entero, suscripción o dominio) y `plesk bin pleskrestore
--restore <archivo>` restaura, con niveles para no restaurar de más
(sus opciones exactas, con `--help`, que cambian entre versiones).
Restaurar pisa lo que hay: siempre con plan aprobado. Y **migrar
suscripciones entre servidores** es trabajo de la extensión oficial
Plesk Migrator, que se lleva web, correo, DNS y bases de datos de una
vez — nunca un rsync del docroot a pelo, que deja atrás todo lo demás.

## Dónde está cada log

| Qué | Dónde |
|---|---|
| Panel | `/var/log/plesk/panel.log` |
| Interfaz del panel | `/var/log/sw-cp-server/error_log` |
| Correo | `/usr/local/psa/var/log/maillog` |
| Del dominio | `/var/www/vhosts/system/<dominio>/logs/` |
| nginx | `/var/log/nginx/error.log` |
| Apache | `/var/log/httpd/error_log` o `/var/log/apache2/error.log` |

En el directorio del dominio están `error_log`, `proxy_error_log` (nginx
delante de Apache) y los de acceso. **El útil casi siempre es
`proxy_error_log` o `error_log`, no el de acceso.**

Con el harness: `server_logs {host, path:"/var/www/vhosts/system/…/logs/error_log", grep:"…"}`.

## Incidencias típicas

**Sitio caído / 502 / 504.** Suele ser PHP-FPM, no el servidor web: mira el
`proxy_error_log` del dominio. Comprueba qué versión de PHP tiene asignada
(`plesk bin domain --info`) y si su pool está vivo. Cada versión de PHP de
Plesk es un servicio FPM independiente (`plesk-php83-fpm` y similares):
`systemctl list-units 'plesk-php*'` dice cuáles corren, y reiniciar uno
toca a TODOS los dominios que usan esa versión.

**El sitio no puede escribir tras subir archivos como root.** Propiedad
equivocada: los archivos del dominio deben pertenecer al usuario de sistema
de su suscripción. `plesk repair fs example.com -n` lo enseña y con `-y`
(en plan aprobado) lo corrige sin tocar nada más.

**Dominio que enseña la página por defecto de Plesk.** Antes de buscar
fantasmas en nginx: suscripción suspendida o vencida, o alojamiento
desactivado. `plesk bin subscription --info <nombre>` y
`plesk bin domain --info` lo dicen en dos líneas.

**Correo que no sale o no entra.** `maillog` primero. Cola de Postfix con
`postqueue -p`. Si hay miles de mensajes en cola casi siempre es una cuenta
comprometida enviando spam: en el maillog, las líneas con `sasl_username=`
dicen qué buzón se autenticó para cada envío, y el que más se repite es el
comprometido. Primero cambiar SU contraseña, después vaciar
(`postsuper -d ALL deferred`, solo con aprobación) — al revés, la cola se
rellena sola y se pierde la prueba.

**Certificado caducado.** Comprueba la fecha real desde fuera antes de
tocar Plesk: `echo | openssl s_client -servername <dominio> -connect <dominio>:443 2>/dev/null | openssl x509 -noout -dates`.

**Let's Encrypt no renueva.** Las dos causas de siempre: el dominio ya no
apunta a este servidor, o una redirección se come
`/.well-known/acme-challenge/`. Se comprueba desde fuera:
`curl -sI http://<dominio>/.well-known/acme-challenge/prueba` — un 404
está bien, un 301 hacia otro sitio o un 403 es el problema. El detalle del
fallo queda en `/var/log/plesk/panel.log`.

**«Cambié el DNS en Plesk y no pasa nada».** Plesk puede llevar su propio
BIND, pero solo manda si los NS del dominio apuntan a este servidor:
`dig +short NS <dominio>` desde fuera lo dice. Si apuntan al registrador o
a Cloudflare, la zona de Plesk es decorativa y el cambio hay que hacerlo
donde de verdad se sirve.

**MySQL caído tumba el panel Y los sitios a la vez.** La base `psa` vive
en el mismo MySQL/MariaDB que las webs de los clientes. La causa típica es
un disco lleno que paró el motor: se mira `df -h` y el journal de
mariadb/mysql antes de reiniciar nada.

**Disco lleno.** `df -h` y luego los sospechosos de Plesk: copias de
seguridad en `/var/lib/psa/dumps`, logs de dominios sin rotar, y
`/var/lib/mysql`.

**No se puede entrar al panel.** Si es contraseña, `plesk login`. Si el
panel mismo no carga, su servicio es `sw-cp-server` + `sw-engine` y su log
el `error_log` de sw-cp-server. Muchas IPs bloqueadas a la vez huele a
fail2ban (Plesk lo integra): `plesk bin ip_ban --banned` lista y
`--unban <ip>` libera.

**Un dominio nuevo enseña el contenido de OTRO dominio.** El nombre
apunta al servidor pero ese vhost no existe (todavía) en Plesk, así que
el servidor web sirve el vhost por defecto. `plesk bin domain --list`
dice si de verdad está dado de alta — la causa típica es apuntar el DNS
antes de crear el dominio en el panel, o una errata en el nombre.

**El correo sale pero llega a spam.** Eso no es de Plesk sino de
reputación: SPF, DKIM (se activa por dominio en los ajustes de correo) y
DMARC. La habilidad de correo y entregabilidad lleva ese diagnóstico
entero: pídela.

**«El panel dice una cosa y el sistema otra».** Ese es exactamente el caso
de `plesk repair` con `-n` primero. No se corrige tocando los dos lados a
mano para que cuadren: se deja que el panel regenere.

## Comprobar que quedó arreglado

Desde fuera, no desde el servidor: `curl -sI https://<dominio>` para la
web (código de respuesta y certificado) y un correo real de ida y vuelta
para el buzón, siguiendo su rastro en el maillog hasta el `status=sent`.
Si el arreglo fue de configuración, un `plesk repair web <dominio> -n`
limpio confirma que panel y sistema vuelven a contar lo mismo.

## Reglas

- Lo que cambie configuración, cuentas o servicios va en `propose_plan`.
- Copia antes de tocar cualquier archivo (`cp -a x x.bak-$(date +%F)`).
- Nada de `plesk repair -y`, reinicios ni cambios de PHP sin aprobación: hay
  sitios de terceros detrás.
- Si el servidor tiene una particularidad (versión antigua, utilidad que
  falta, ruta distinta), guárdala con `learn`.
