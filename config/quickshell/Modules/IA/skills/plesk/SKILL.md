---
name: Plesk
description: Administrar y diagnosticar un servidor Plesk por SSH: utilidades plesk bin, plesk repair, dónde está cada log e incidencias típicas (web caída, correo, certificados, disco). Úsala si se habla de Plesk, de una suscripción o de un dominio alojado.
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
(`plesk bin domain --info`) y si su pool está vivo.

**Correo que no sale o no entra.** `maillog` primero. Cola de Postfix con
`postqueue -p`. Si hay miles de mensajes en cola casi siempre es una cuenta
comprometida enviando spam — busca el remitente antes de vaciar nada.

**Certificado caducado.** Comprueba la fecha real desde fuera antes de
tocar Plesk: `echo | openssl s_client -servername <dominio> -connect <dominio>:443 2>/dev/null | openssl x509 -noout -dates`.

**Disco lleno.** `df -h` y luego los sospechosos de Plesk: copias de
seguridad en `/var/lib/psa/dumps`, logs de dominios sin rotar, y
`/var/lib/mysql`.

**No se puede entrar al panel.** Si es contraseña, `plesk login`. Si el
panel mismo no carga, su servicio es `sw-cp-server` + `sw-engine` y su log
el `error_log` de sw-cp-server. Muchas IPs bloqueadas a la vez huele a
fail2ban (Plesk lo integra): `plesk bin ip_ban --banned` lista y
`--unban <ip>` libera.

**«El panel dice una cosa y el sistema otra».** Ese es exactamente el caso
de `plesk repair` con `-n` primero. No se corrige tocando los dos lados a
mano para que cuadren: se deja que el panel regenere.

## Reglas

- Lo que cambie configuración, cuentas o servicios va en `propose_plan`.
- Copia antes de tocar cualquier archivo (`cp -a x x.bak-$(date +%F)`).
- Nada de `plesk repair -y`, reinicios ni cambios de PHP sin aprobación: hay
  sitios de terceros detrás.
- Si el servidor tiene una particularidad (versión antigua, utilidad que
  falta, ruta distinta), guárdala con `learn`.
