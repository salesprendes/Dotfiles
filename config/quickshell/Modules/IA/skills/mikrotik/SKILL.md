---
name: MikroTik RouterOS
description: Operar routers y switches MikroTik (RouterOS) por SSH o WinBox: safe mode, firewall, NAT, bridge con VLANs, colas, copias con /export y las trampas que te dejan fuera del equipo. Úsala si se habla de MikroTik, RouterOS, WinBox, un hAP, un CRS o un CCR.
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
- **Reset físico**: botón pulsado ANTES de enchufar y mantenido ~5 s hasta
  que el LED parpadee — configuración de fábrica (192.168.88.1, admin sin
  contraseña o la de la pegatina en equipos nuevos). Mantenerlo más tiempo
  entra en Netinstall (reinstalación total).

## Versiones y actualización

`/system package update check-for-updates` y `install` — reinicia el
equipo, así que es un cambio con plan y ventana. Tras actualizar el SO,
el firmware de la placa va aparte: `/system routerboard upgrade` y OTRO
reinicio. **v6 y v7 difieren de verdad** (v7 cambió el enrutado — tablas,
BGP/OSPF con otra sintaxis — y consolidó las VLANs en el bridge): antes de
recomendar comandos de rutas, `/system resource print` para saber en cuál
estás. El salto v6→v7 en un equipo en producción no es una actualización
más: es un plan.

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
