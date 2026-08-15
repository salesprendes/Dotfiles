---
name: cPanel y WHM
description: Administrar y diagnosticar un servidor cPanel/WHM por SSH: APIs whmapi1 y uapi, dónde está cada log, scripts de servicio e incidencias típicas (correo, disco, cuotas, error 500). Úsala si se habla de cPanel, WHM o una cuenta de hosting.
---

# cPanel y WHM

Como en Plesk, aquí **el panel manda sobre los archivos**: cPanel reconstruye
la configuración de Apache y de las cuentas. Editar `httpd.conf` a mano es
tirar el trabajo a la basura en la próxima reconstrucción. Se hace por API o
por WHM. Para añadidos hay directorios de *includes* que sí se respetan.

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
```

`--output=jsonpretty` para leerlo tú y `--output=json` si vas a procesarlo.
En **CloudLinux** hay que usar la ruta completa: `/usr/local/cpanel/bin/whmapi1`
y `/usr/local/cpanel/bin/uapi`.

**No te inventes funciones de la API.** Si no estás seguro de que existe,
consúltalo en `https://api.docs.cpanel.net` con `fetch_url` antes de
ejecutar nada. Una función mal escrita no es grave. Una acertada por
casualidad sobre la cuenta equivocada, sí.

Lo más común ya lo trae el harness: `hosting_query {panel:"cpanel", op:…}`
con `version`, `accounts`, `account_info`, `domains` y `disk`.

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

Usa estos y no `systemctl` directamente: cPanel envuelve los servicios y
`chkservd` puede pelearse contigo. Reiniciar afecta a todas las cuentas del
servidor: va con aprobación.

## Incidencias típicas

**Cuenta suspendida o sobre cuota.** `whmapi1 accountsummary user=…` da
estado y uso, y `quota -v -u <cuenta>` da la cuota real del sistema. Ojo: un
buzón lleno y una cuota de disco llena se parecen y no se arreglan igual.

**Correo que no llega.** `exim_mainlog` es la fuente de verdad. Búscalo por
la dirección con `server_logs {path:"/var/log/exim_mainlog", grep:"…"}`.
`exim -bpc` cuenta la cola y `exim -bp` la lista. Cola disparada casi siempre
= cuenta comprometida enviando spam: identifica el origen ANTES de vaciar,
o borrarás la prueba.

**Sitio con error 500.** El log del dominio en `/home/<cuenta>/logs/`, no el
de Apache global. Mira también permisos: cPanel es estricto y un 500 suele
ser un `.htaccess` o unos permisos 777 que suPHP rechaza.

**Disco lleno.** `whmapi1 getdiskusage`, y luego los sospechosos:
`/home/*/mail` (buzones), `/backup`, `/var/log`, y las copias de cPanel.

**Actualizaciones.** El propio cPanel se actualiza con `upcp`
(`/scripts/upcp`, su log en `/var/log/cpanel/updatelog`) y Apache/PHP con
**EasyApache 4** (perfiles de paquetes ea-*): un fallo tras «actualizar el
servidor» se acota mirando cuál de los dos corrió y cuándo. **Migrar
cuentas** entre servidores es la Transfer Tool de WHM (o
`/scripts/pkgacct` + `/scripts/restorepkg` a mano) — nunca rsync del
/home a pelo, que deja fuera base de datos, DNS y correo.

## Lo que NO se hace sin un plan aprobado

`removeacct` (borra la cuenta entera y sus datos), `suspendacct`, cambios de
versión de PHP o de EasyApache, `upcp`, restaurar cuentas encima de
existentes, y cualquier reinicio. Todo eso va en `propose_plan` diciendo a
quién afecta.

Si el servidor tiene una particularidad (CloudLinux, rutas distintas, una
versión antigua de la API), guárdala con `learn`.
