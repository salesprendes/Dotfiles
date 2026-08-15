---
name: Huawei VRP
description: Operar switches y routers Huawei (VRP: series S, CE, AR) por SSH o consola: comandos display, system-view, VLANs con port trunk, eth-trunk, guardar con save, y el commit de los CloudEngine. Úsala si se habla de un Huawei, VRP, un switch S5700 o similar, un CloudEngine o comandos display.
---

# Huawei VRP

VRP es el sistema de los switches y routers Huawei. Quien viene de Cisco
tiene el 80 % del mapa con tres traducciones: se **mira** con `display`
(no `show`), se **niega** con `undo` (no `no`), y se entra a configurar
con `system-view` (no `configure terminal`). El resto del oficio son las
diferencias que no se traducen — y ahí es donde se rompe.

## Traducción de reflejos

| Cisco | Huawei VRP |
|---|---|
| `enable` + `conf t` | `system-view` |
| `show …` | `display …` |
| `no <orden>` | `undo <orden>` |
| `exit` / `end` | `quit` / `return` |
| `copy run start` / `wr` | `save` (confirma con `y`) |
| `show run` | `display current-configuration` |
| `show start` | `display saved-configuration` |
| `terminal length 0` | `screen-length 0 temporary` |

`display current-configuration | include <texto>` filtra igual que en
Cisco. La paginación se quita con `screen-length 0 temporary` (el
`temporary` la limita a la sesión: sin él quedaría configurado).

## Primer vistazo (todo lectura)

```
display version                     ← modelo, VRP, uptime
display device                      ← tarjetas, fuentes, estado del hardware
display ip interface brief
display interface brief             ← puertos: estado, uso, errores
display vlan                        ← VLANs y qué puertos tiene cada una
display mac-address                 ← dónde está cada MAC
display lldp neighbor brief         ← qué hay enchufado a cada puerto
display stp brief
display eth-trunk                   ← agregaciones y estado de las patas
display logbuffer                   ← el log
display alarm active                ← alarmas activas (en CE)
```

En `display interface brief` la columna de errores y el `InUti/OutUti`
(uso del puerto) responden rápido a «va lento»: un puerto al 99 % o con
errores subiendo es el diagnóstico.

## VLANs y trunks

Las VLANs se crean ANTES de usarse, y `vlan batch` crea varias de golpe:

```
system-view
vlan batch 10 20 30
interface GigabitEthernet0/0/12
 port link-type access
 port default vlan 30
```

Trunk:

```
interface GigabitEthernet0/0/24
 port link-type trunk
 port trunk allow-pass vlan 10 20 30
```

Dos diferencias con Cisco que muerden:

- `port trunk allow-pass vlan 40` **AÑADE** la 40 a la lista (al revés que
  Cisco, donde reemplaza). Para dejar la lista exacta hay que quitar antes
  lo que sobre con `undo port trunk allow-pass vlan …`. En ambos mundos la
  respuesta es la misma: mirar la lista actual antes de tocar
  (`display this` dentro de la interfaz enseña su configuración).
- Por defecto un trunk solo deja pasar la VLAN 1: todo lo demás se declara.
  Una VLAN declarada en el `allow-pass` pero no creada con `vlan batch`
  tampoco pasa.

Un puerto de acceso mal cambiado se limpia con `undo port default vlan` y
`undo port link-type` antes de darle el tipo nuevo: VRP se queja si se
cambia el tipo con restos de la configuración anterior.

## Eth-Trunk (agregación)

```
interface Eth-Trunk1
 mode lacp
interface GigabitEthernet0/0/23
 eth-trunk 1
```

`display eth-trunk 1` enseña las patas y si están `Up` y seleccionadas.
Igual que en todos los fabricantes: LACP a ambos lados y patas idénticas,
o el enlace «funciona a ratos».

## Guardar, y el caso CloudEngine

En las series S y AR es como Cisco: los cambios aplican al momento y
`save` los hace permanentes. **Sin `save`, un reinicio los borra** — que
es también la vuelta atrás si un cambio te dejó fuera.

Los **CloudEngine (CE, centro de datos) usan commit**: los cambios en
system-view van a una configuración candidata y NO aplican hasta escribir
`commit`. Quien opera un CE con reflejos de serie S se queda mirando un
cambio que «no funciona» — solo está sin confirmar. `display
configuration candidate` (o el aviso del prompt) lo delata. Y el propio
commit tiene paracaídas: `commit trial <minutos>` aplica de prueba y
revierte solo si no se confirma — el equivalente al `reload in` de Cisco,
úsalo en cambios remotos arriesgados.

## Paracaídas en series sin commit

En un S o AR el paracaídas es el de Cisco pero con sus nombres: programar
un reinicio con `schedule reboot delay 10` ANTES del cambio arriesgado
(sin `save`, el reinicio vuelve a lo guardado), verificar que sigues
dentro, y cancelarlo con `undo schedule reboot`.

## Detalles del mundo real

- El usuario de SSH necesita nivel de privilegio suficiente: si todo
  parece de solo lectura, `display users` y el nivel del usuario son la
  pista (los niveles van de 0 a 15, gestión completa a partir de 3 en la
  configuración típica).
- Equipos con años solo hablan cifrados viejos de SSH: mismas opciones
  `-oKexAlgorithms=+…` que con Cisco antiguo, en el comando y no en la
  configuración global.
- `display this` dentro de cualquier contexto enseña solo la configuración
  de ese contexto: es la forma rápida de revisar una interfaz sin bucear
  por la configuración entera.
- Los mensajes y la documentación mezclan inglés y traducciones: el texto
  exacto del log (`display logbuffer`) pegado en una búsqueda encuentra el
  caso — el código de alarma (`%%01…`) es el identificador bueno.

## Reglas

- En serie S/AR: nunca `save` sin verificar — lo no guardado es la vuelta
  atrás. En CE: nunca `commit` a ciegas — `commit trial` para lo remoto.
- Antes de una sesión de cambios: `display current-configuration` completo
  guardado en un archivo local.
- `reboot` y los cambios de VLAN o IP de la interfaz de gestión van en
  `propose_plan`, con el paracaídas escrito en el plan.
- Anota con `learn` la serie y versión de cada equipo del sitio (S de
  campus, CE con commit, AR de sucursal): cambia qué comandos valen.
