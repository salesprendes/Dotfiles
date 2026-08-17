---
name: "cPanel y WHM"
description: "Administrar y diagnosticar un servidor cPanel/WHM por SSH: APIs whmapi1 y uapi, dónde está cada log, scripts de servicio e incidencias típicas (correo, disco, cuotas, error 500). Úsala si se habla de cPanel, WHM o una cuenta de hosting."
triggers: "whm, whmapi1, uapi, cpsrvd, easyapache, cphulk, cuota, hosting compartido, addon domain, scripts de cpanel"
---

# cPanel y WHM

Como en Plesk, aquí **el panel manda sobre los archivos**: cPanel reconstruye
la configuración de Apache y de las cuentas. Editar `httpd.conf` a mano es
tirar el trabajo a la basura en la próxima reconstrucción. Se hace por API o
por WHM. Los añadidos que sí sobreviven van en los directorios de includes:
`/etc/apache2/conf.d/userdata/std/2_4/<cuenta>/<dominio>/*.conf` (y
`ssl/2_4/…` para el vhost seguro), aplicados con
`/scripts/rebuildhttpdconf` y el reinicio de Apache.

## Las tres APIs

```sh
# WHM (nivel servidor, como root)
whmapi1 listaccts --output=jsonpretty
whmapi1 accountsummary user=cuenta
whmapi1 getdiskusage

# Nivel CUENTA: siempre con --user
uapi --user=cuenta --output=jsonpretty Email list_pops
uapi --user=cuenta DomainInfo domains_data

# Antigua, aún viva en algunos sitios
cpapi2 --user=cuenta Module::function

# La zona DNS tal como la sirve ESTE servidor
whmapi1 dumpzone domain=example.com
```

**Entrar sin contraseña**: `whmapi1 create_user_session user=cuenta
service=cpaneld` genera una URL de sesión temporal como esa cuenta (con
`service=webmaild`, a su webmail). Es el `plesk login` de cPanel: la salida
limpia cuando «se perdió la contraseña», sin cambiarla ni tocarla.

`--output=jsonpretty` para leerlo tú y `--output=json` si vas a procesarlo.
En **CloudLinux** hay que usar la ruta completa: `/usr/local/cpanel/bin/whmapi1`
y `/usr/local/cpanel/bin/uapi`.

**No te inventes funciones de la API.** Si no estás seguro de que existe,
consúltalo en `https://api.docs.cpanel.net` con `fetch_url` antes de
ejecutar nada. Una función mal escrita no es grave. Una acertada por
casualidad sobre la cuenta equivocada, sí.

Lo más común ya lo trae el harness: `hosting_query {panel:"cpanel", op:…}`
con `version`, `accounts`, `account_info`, `domains` y `disk`.

## Una llamada, muchas lecturas

Agrupa las consultas en un solo comando separado por `;`: cada llamada
remota cuesta una tarjeta de aprobación y una espera.

```sh
/usr/local/cpanel/cpanel -V; whmapi1 servicestatus | head -40; df -h /home; exim -bpc
```

Las escrituras (crear cuentas, tocar cuotas, `/scripts/*` que instalan o
reparan) van siempre solas.

## Dónde está cada log

| Qué | Dónde |
|---|---|
| cPanel/WHM | `/usr/local/cpanel/logs/error_log` |
| Accesos al panel | `/usr/local/cpanel/logs/access_log`, `login_log` |
| Vigilancia de servicios | `/usr/local/cpanel/logs/chkservd.log` |
| Correo (todo) | `/var/log/exim_mainlog` |
| Correo rechazado | `/var/log/exim_rejectlog` |
| Apache | `/etc/apache2/logs/error_log` (EA4) |
| Del dominio | `/home/<cuenta>/logs/<dominio>-error_log` |
| MySQL | `/var/lib/mysql/<hostname>.err` |

`chkservd.log` es el primero que hay que mirar cuando "algo se cae y vuelve
solo": es el vigilante de servicios de cPanel contándote qué reinició.

Dos vigilantes más con nombre: **cPHulk** banea IPs por intentos de login
fallidos — si «no se puede entrar desde la oficina», mira primero
`whmapi1 flush_cphulk_login_history_for_ips ip=…` tras confirmarlo en su
log. Y **AutoSSL** renueva los certificados solo: si un dominio se quedó
sin HTTPS, su porqué está en `/var/log/cpanel/autossl` (dominio que ya no
apunta aquí, o límite del proveedor) — se fuerza con
`/usr/local/cpanel/bin/autossl_check --user=cuenta`, no instalando un
certbot paralelo.

## Servicios

```sh
/scripts/restartsrv_httpd
/scripts/restartsrv_exim
/scripts/restartsrv_mysql
/scripts/restartsrv_cpsrvd
```

Hay uno por servicio (`ls /scripts/restartsrv_*` enseña los del equipo:
dovecot, named o pdns, ftpd…). Usa estos y no `systemctl` directamente:
cPanel envuelve los servicios y `chkservd` puede pelearse contigo. De
hecho, **el servicio que pares a mano vuelve solo en minutos**: chkservd lo
rearranca. Para mantener algo parado adrede se desactiva antes su
monitorización en WHM (Service Manager) o con
`whmapi1 configureservice service=<svc> enabled=1 monitored=0`.
Reiniciar afecta a todas las cuentas del servidor: va con aprobación.

## Correo: la caja de herramientas de Exim

```sh
exigrep 'usuario@dominio' /var/log/exim_mainlog  # historia completa de una dirección
exim -bpc                                        # tamaño de la cola
exim -bp | exiqsumm                              # cola resumida por dominio
exiqgrep -i -f 'remite@' | xargs exim -Mrm       # borrar de la cola por remitente
exim -bt usuario@dominio                         # cómo se enrutaría, sin enviar nada
```

Y el truco que encuentra al script que envía spam: cPanel apunta en
`exim_mainlog` el directorio de trabajo del proceso que generó cada
mensaje. `grep 'cwd=/home' /var/log/exim_mainlog` y el directorio más
repetido es el comprometido — casi siempre un plugin o un formulario sin
proteger.

Los mensajes **congelados** (frozen) son los que Exim ya no intenta
entregar: `exiqgrep -z -i` los lista y con `| xargs exim -Mrm` se purgan
(tras la investigación, no antes). Lo de listas negras, SPF, DKIM y
reputación de la IP vive en la habilidad de correo y entregabilidad:
pídela si el problema es «llega a spam» y no «no sale».

## Si está instalado CSF

Medio mundo cPanel lleva el cortafuegos ConfigServer (csf) además de
cPHulk. Cuando «no se puede entrar desde tal sitio» y cPHulk está limpio:

```sh
csf -g 1.2.3.4        # ¿está esta IP bloqueada y por qué regla?
csf -tr 1.2.3.4       # quitar un bloqueo temporal
csf -dr 1.2.3.4       # quitar un bloqueo permanente
```

Su configuración vive en `/etc/csf/csf.conf` y sus motivos en
`/var/log/lfd.log` — el demonio lfd es quien banea (logins fallidos,
scripts sospechosos), así que ese log explica cada bloqueo.

## Incidencias típicas

**Cuenta suspendida o sobre cuota.** `whmapi1 accountsummary user=…` da
estado y uso, y `quota -v -u <cuenta>` da la cuota real del sistema. Ojo: un
buzón lleno y una cuota de disco llena se parecen y no se arreglan igual.

**Cuotas que mienten tras una migración.** Cuentas recién restauradas
enseñando 0 o cifras imposibles: `/scripts/fixquotas` las recalcula.

**Correo que no llega.** `exim_mainlog` es la fuente de verdad. Búscalo por
la dirección con `server_logs {path:"/var/log/exim_mainlog", grep:"…"}`.
Cola disparada casi siempre = cuenta comprometida enviando spam: identifica
el origen ANTES de vaciar (el `cwd=` de arriba), o borrarás la prueba.

**Sitio con error 500.** El log del dominio en `/home/<cuenta>/logs/`, no el
de Apache global. Mira también permisos: cPanel es estricto y un 500 suele
ser un `.htaccess` o unos permisos 777 que suPHP rechaza.

**403 o 406 sin motivo aparente** (guardar una entrada en WordPress, subir
un archivo). ModSecurity: el detalle y el número de regla están en
`/etc/apache2/logs/modsec_audit.log`. Se desactiva ESA regla para ESE
dominio desde WHM (ModSecurity Tools), no el módulo entero.

**«Cambié el DNS y no pasa nada».** La zona local solo manda si los NS del
dominio apuntan a este servidor: `dig +short NS <dominio>` desde fuera. Si
no, el cambio va donde de verdad se sirve la zona.

**Disco lleno.** `whmapi1 getdiskusage`, y luego los sospechosos:
`/home/*/mail` (buzones), `/backup`, `/var/log`, y las copias de cPanel.

**Actualizaciones.** El propio cPanel se actualiza con `upcp`
(`/scripts/upcp`, su log en `/var/log/cpanel/updatelog`) y Apache/PHP con
**EasyApache 4** (perfiles de paquetes ea-*): un fallo tras «actualizar el
servidor» se acota mirando cuál de los dos corrió y cuándo. **Migrar
cuentas** entre servidores es la Transfer Tool de WHM (o
`/scripts/pkgacct` + `/scripts/restorepkg` a mano) — nunca rsync del
/home a pelo, que deja fuera base de datos, DNS y correo.

**«Licencia inválida» al entrar a WHM.** Suele ser que cambió la IP del
servidor y la licencia sigue atada a la vieja: se refresca con
`/usr/local/cpanel/cpkeyclt` y se comprueba qué IP tiene licenciada el
proveedor. Mientras la licencia no valide, el panel no deja entrar pero
**las webs y el correo siguen funcionando** — no es una caída, no
reinicies nada.

## PHP por dominio (MultiPHP)

Cada dominio puede llevar su versión de PHP (paquetes `ea-php81`,
`ea-php83`…) y su gestor (FPM o no). El mapa completo lo da
`whmapi1 php_get_vhost_versions` (versión, FPM y estado por vhost) y el
cambio se hace desde MultiPHP Manager en WHM o con
`whmapi1 php_set_vhost_versions version=ea-php83 vhost-0=example.com`.
Cambiar la versión puede tumbar un sitio viejo en el acto (funciones
retiradas): es un cambio con plan, dominio a dominio, y con el error 500
de arriba como síntoma si sale mal.

## Copias de seguridad

Se configuran en WHM (Backup Configuration) y caen en `/backup` por fecha.
Forzar una pasada ahora: `/usr/local/cpanel/bin/backup --force`, con su
log en `/usr/local/cpanel/logs/cpbackup/`. Restaurar una cuenta concreta:
Backup Restoration en WHM o `/scripts/restorepkg cuenta`. La regla de
siempre aplica también aquí: una copia que nunca se ha restaurado de
prueba no es una copia, es una esperanza — y si `/backup` vive en el mismo
disco que `/home`, un disco muerto se lleva las dos cosas.

## Comprobar que quedó arreglado

`whmapi1 servicestatus service=httpd` (o exim, mysql) dice lo que chkservd
opina del servicio, que es lo que cuenta. La web se comprueba desde fuera
con el dominio real, no con localhost. Un arreglo de correo se remata con
un envío de prueba y su línea de entrega en `exim_mainlog`. Y si el
síntoma era «se cae a ratos», vigilar `chkservd.log` un rato: si el
vigilante sigue reiniciando, no está arreglado.

## Lo que NO se hace sin un plan aprobado

`removeacct` (borra la cuenta entera y sus datos), `suspendacct`, cambios de
versión de PHP o de EasyApache, `upcp`, restaurar cuentas encima de
existentes, vaciar colas de correo, y cualquier reinicio. Todo eso va en
`propose_plan` diciendo a quién afecta.

Si el servidor tiene una particularidad (CloudLinux, rutas distintas, una
versión antigua de la API), guárdala con `learn`.
