---
name: "MikroTik RouterOS"
description: "Operar routers y switches MikroTik (RouterOS) por SSH o WinBox: safe mode, firewall, NAT, bridge con VLANs, colas, copias con /export y las trampas que te dejan fuera del equipo. Úsala si se habla de MikroTik, RouterOS, WinBox, un hAP, un CRS o un CCR."
triggers: "routeros, winbox, hap, crs, ccr, chr, safe mode, mangle, srcnat, masquerade, netinstall, export compact, vlan filtering"
---

# MikroTik RouterOS

RouterOS aplica cada comando **al instante**. No hay running/startup como
en Cisco ni commit como en Huawei: lo que escribes ya está en producción y
sobrevive al reinicio. Por eso la herramienta más importante de un MikroTik
no es un comando de configuración: es el **Safe Mode**.

## Safe Mode: la regla madre

En la consola, `Ctrl-X` entra en Safe Mode (el prompt cambia a `<SAFE>`).
Desde ahí, **si la sesión se corta, todo lo hecho en Safe Mode se
revierte solo**. Cortarte el acceso a ti mismo deshace el corte. Se sale
confirmando con otro `Ctrl-X` (los cambios se quedan) o descartando con
`Ctrl-D`.

Todo cambio remoto de firewall, direcciones, bridge o VLANs se hace DENTRO
de Safe Mode, sin excepción. Es el único fabricante que regala esta red de
seguridad: no usarla es elegir el riesgo.

Segunda red, menos conocida: `/system history print` lista los últimos
cambios de configuración con quién y cuándo, y `/undo` deshace el más
reciente (repetible). No sustituye al Safe Mode, pero responde al «¿qué
acabo de tocar?» y al «¿qué tocó el compañero ayer?».

## Leer el equipo

```
/system resource print          ← modelo, versión, CPU, RAM, uptime
/system routerboard print       ← firmware de la placa (va aparte del SO)
/ip address print
/ip route print
/interface print stats
/ip firewall filter print       ← reglas con contadores
/ip firewall nat print
/ip dhcp-server lease print
/log print                      ← el log (follow con /log print follow)
/export                         ← TODA la configuración, legible
```

`/export` es la copia de seguridad buena: texto que se lee, se compara y se
pega. `/system backup save` crea un binario que solo sirve para restaurar
en el MISMO equipo (lleva las claves y la identidad) — útil, pero no
sustituye al export. Antes de una sesión de cambios: `/export
file=antes-YYYYMMDD` y bajárselo.

Herramientas de diagnóstico propias que conviene conocer:

- `/tool torch interface=ether1` — quién consume ancho de banda AHORA, en
  vivo. La respuesta a «la red va lenta» en un minuto.
- `/ping 1.1.1.1 count=10`, `/tool traceroute`.
- `/ip neighbor print` — otros MikroTik y equipos con descubrimiento
  visibles, con IP y MAC (así se encuentra el equipo mal configurado).
- `/tool profile` — qué se come la CPU del router (¿el firewall? ¿colas?).
- `/interface ethernet monitor ether1 once` — velocidad y dúplex
  negociados de verdad, y `/interface ethernet print stats` los
  contadores finos por puerto.

## Una llamada, muchas lecturas

**RouterOS encadena con `;`**, así que todo el vistazo de arriba es UNA
llamada en vez de seis tarjetas de aprobación:

```sh
ssh admin@router "/system resource print; /system identity print; /interface print; /ip address print; /ip route print"
```

Las escrituras van solas y bajo Safe Mode, que es justo lo contrario: ahí lo
que quieres es ver una por una qué cambia.

## Firewall: las dos cadenas que importan

- **input**: tráfico HACIA el router (WinBox, SSH, DNS del propio equipo).
- **forward**: tráfico QUE LO ATRAVIESA (la LAN saliendo a internet).

Las reglas se evalúan en orden y la primera que casa gana. El patrón sano:
aceptar `established,related` arriba del todo, aceptar lo que se necesita,
tirar el resto al final. **La trampa que deja fuera**: un `drop` en input
sin haber aceptado antes tu propio acceso. Con Safe Mode es un susto, sin
él es un viaje al sitio. Los contadores de `/ip firewall filter print
stats` dicen qué regla está comiendo el tráfico — con eso se depura, no
adivinando.

NAT de salida típico: `/ip firewall nat` cadena `srcnat` acción
`masquerade` en la interfaz WAN. Redirigir un puerto hacia dentro:
`dstnat` + `dst-port` + `to-addresses`. Si un dstnat no funciona desde la
propia LAN, es el clásico hairpin NAT: falta la regla de masquerade para
el tráfico LAN→LAN.

## Blindar la gestión

Los servicios de administración se gobiernan en `/ip service`: telnet
(23), ftp (21), www (80), ssh (22), www-ssl (443), api (8728), api-ssl
(8729) y winbox (8291). En un equipo con la WAN a internet:

```
/ip service print
/ip service disable telnet,ftp,www,api
/ip service set winbox address=192.168.88.0/24
/ip service set ssh address=192.168.88.0/24
```

Matiz documentado que importa: `address=` **no descarta el paquete a
nivel de red**, solo niega el servicio — el drop de verdad sigue siendo
cosa del firewall de input. Las dos capas juntas, no una u otra.

## Averías con nombre y apellidos

**Las colas no limitan nada**: hay simple queues y el tráfico las ignora.
Casi siempre es FastTrack: la regla `action=fasttrack-connection` de la
configuración por defecto salta el resto del firewall Y las colas para
las conexiones marcadas. Se ve en los contadores (la regla fasttrack
engorda y las colas no se mueven). Para ese tráfico se elige: o colas o
fasttrack, no ambos.

**CPU alta y la WAN saturada de DNS**: `/ip dns` tiene
`allow-remote-requests=yes` (necesario para servir DNS a la LAN) y el
puerto 53 quedó abierto al mundo — el router hace de amplificador para
terceros. `/tool torch` en la WAN lo enseña en segundos. El arreglo es
tirar udp/53 y tcp/53 en input desde la WAN, no quitar la opción.

**Pusiste la IP en el puerto y lo metiste al bridge**: al añadir ether2
como puerto de un bridge, cualquier IP configurada EN ether2 deja de
atender (el nivel 3 vive ahora en el bridge). Es una forma clásica de
quedarse fuera: la IP de gestión se mueve al bridge ANTES de meter el
puerto.

**Bucle en la LAN**: todo lento y MACs bailando de puerto en
`/interface bridge host print`. El bridge trae RSTP activado por defecto
(`protocol-mode=rstp`) — si alguien lo deshabilitó, un latiguillo en
bucle tumba la red entera.

**La hora está mal tras cada corte de luz**: muchos RouterBOARD no
llevan reloj con pila. Sin cliente NTP (`/system ntp client`), tras un
reinicio los certificados fallan y los registros y programadores viven
en otra fecha. Configurarlo es de lo primero en un equipo nuevo.

**El log no cuenta nada del reinicio**: el registro por defecto vive en
RAM y muere con el equipo. Para cazar reinicios o fallos nocturnos,
mandar los temas importantes a disco: `/system logging add
topics=critical action=disk`.

**La red «se para» a horas punta con CPU normal**: tabla de conexiones
llena (típico con mucho P2P o un escaneo). `/ip firewall connection print
count-only` contra el máximo de `/ip firewall connection tracking` lo
confirma — el remedio de fondo es cortar al causante (torch lo señala),
no solo agrandar la tabla.

## Vigilancia y automatismos

- **Netwatch** vigila un host y reacciona al cambio de estado:
  `/tool netwatch add host=1.1.1.1 interval=30s down-script=":log warning \"WAN caida\""`
  (tipos icmp, tcp-conn, http-get y dns para vigilar servicios, no solo
  ping). Es el detector de «se cayó la VPN o la WAN» que avisa él solo.
- **Programador + correo**: con `/tool e-mail` configurado (servidor,
  remitente), un script que haga `/export file=copia` y después
  `/tool e-mail send` con `file=copia.rsc`, colgado de
  `/system scheduler` a diario, es la copia de seguridad nocturna
  oficial de la casa: el export sale del router cada noche sin que nadie
  se acuerde.
- **DDNS gratuito**: `/ip cloud set ddns-enabled=yes` y en
  `/ip cloud print` aparece un nombre `xxxx.sn.mynetname.net` que sigue
  a la IP pública del equipo (`force-update` para refrescarlo ya). Para
  llegar a un router con IP dinámica sin contratar nada.

## Bridge y VLANs: donde caen los valientes

En RouterOS moderno (v6.41+ y todo v7) los puertos se agrupan en un
**bridge** y las VLANs se hacen con `vlan-filtering` en él:

1. Puertos al bridge (`/interface bridge port add`).
2. Tabla de VLANs: `/interface bridge vlan add` con `tagged=` (trunks) y
   `untagged=` (accesos) por cada VLAN.
3. PVID en cada puerto de acceso.
4. Y SOLO al final, `set bridge vlan-filtering=yes`.

**Activar `vlan-filtering` con la tabla a medias te corta el acceso al
instante**, porque el propio tráfico de gestión deja de estar permitido: el
bridge mismo debe figurar como `tagged` en la VLAN de gestión. Es EL
incidente típico de MikroTik. Orden correcto, Safe Mode puesto, y el
acceso de emergencia de abajo conocido.

En los CRS (switches), el conmutado de VLANs por hardware va también por
el bridge en v7 — configuraciones antiguas con `/interface ethernet
switch` son de v6 y no se mezclan con el método nuevo.

## Acceso de emergencia

- **MAC-Telnet / WinBox por MAC**: WinBox puede entrar por la MAC aunque
  la IP esté mal o no exista, desde la misma red física. Es lo que salva
  cuando el fallo es de IPs o VLANs. Neighbor discovery debe estar
  habilitado en esa interfaz (por eso no se deshabilita en la LAN).
- **RoMON** (`/tool romon set enabled=yes secrets=<clave>`): red de
  gestión propia por capa 2 entre MikroTik vecinos. Con el botón RoMON
  de WinBox se entra a un equipo SIN IP alcanzable atravesando los
  MikroTik intermedios — el salvavidas en redes con varios equipos y
  VLANs rotas. Se habilita ANTES de necesitarlo, con secreto, o no
  existe el día del incidente.
- **Reset físico**: botón pulsado ANTES de enchufar y mantenido ~5 s hasta
  que el LED parpadee — configuración de fábrica (192.168.88.1, admin sin
  contraseña o la de la pegatina en equipos nuevos). Mantenerlo más tiempo
  entra en Netinstall (reinstalación total).

## Versiones y actualización

`/system package update check-for-updates` y `install` — reinicia el
equipo, así que es un cambio con plan y ventana. El canal se elige con
`/system package update set channel=` y en producción se está en el
conservador, no en testing. Tras actualizar el SO,
el firmware de la placa va aparte: `/system routerboard upgrade` y OTRO
reinicio. **v6 y v7 difieren de verdad** (v7 cambió el enrutado — tablas,
BGP/OSPF con otra sintaxis — y consolidó las VLANs en el bridge): antes de
recomendar comandos de rutas, `/system resource print` para saber en cuál
estás. El salto v6→v7 en un equipo en producción no es una actualización
más: es un plan.

## Verificar tras cada cambio

- Firewall tocado: los contadores de la regla nueva suben con tráfico de
  prueba y tu propia sesión sigue viva — ANTES de confirmar el Safe Mode.
- VLANs de bridge: desde un puerto de cada VLAN se coge IP y se alcanza
  su puerta de enlace.
- NAT nuevo: probar desde FUERA (datos móviles), no solo desde la LAN —
  el hairpin engaña.
- Siempre: `/log print` sin quejas nuevas y `/tool torch` con la pinta de
  tráfico esperada.

## Reglas

- Safe Mode para TODO cambio remoto. Sin excusas: es gratis.
- `/export file=` antes de cualquier sesión de cambios, y el archivo
  descargado, no solo dentro del router.
- `/system reset-configuration` borra todo sin ceremonia. Jamás sin plan
  aprobado y copia bajada.
- Las contraseñas de WinBox y los secretos de PPP salen en el export: al
  enseñar un export en el chat, el harness tapa lo que reconoce — no
  pegues tú lo que reconozcas como secreto.
- Anota con `learn` la versión, el modelo y las mañas del sitio (qué
  puerto es la WAN, cuál es la VLAN de gestión, si hay colas configuradas).
