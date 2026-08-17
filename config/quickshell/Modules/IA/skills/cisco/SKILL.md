---
name: "Cisco IOS"
description: "Operar switches y routers Cisco (IOS, IOS-XE) por SSH o consola: comandos show, VLANs y trunks, spanning-tree, EtherChannel, puertos err-disabled, guardar la configuración y cambiar cosas sin quedarte fuera. Úsala si se habla de un Cisco, un Catalyst, IOS, un switch o router Cisco, o comandos como show run."
triggers: "catalyst, nexus, switchport, err-disabled, errdisable, portfast, etherchannel, spanning, show running, enable secret, ios-xe, vtp, cdp, wr mem"
---

# Cisco IOS / IOS-XE

La regla madre de Cisco: **la configuración en marcha (running-config) y la
guardada (startup-config) son dos cosas distintas**. Todo lo que cambias
vive solo en RAM hasta que guardas. Eso es un peligro (un reinicio te borra
el trabajo) y una red de seguridad (si te has quedado fuera, cortar la luz
devuelve el equipo al último guardado). La mitad del oficio es usar bien
esa dualidad.

## Los tres modos

```
Switch>            modo usuario: solo mirar poco
Switch#            privilegiado (con "enable"): mirar todo, reiniciar
Switch(config)#    configuración (con "configure terminal"): tocar
```

`exit` sube un nivel, `end` (o Ctrl-Z) vuelve directo al `#`. Los comandos
se pueden abreviar mientras no sean ambiguos (`sh ip int br`) y `?` en
cualquier punto lista lo que se puede escribir — es la documentación que
siempre está instalada.

## Primer vistazo (todo lectura)

```
show version                    ← modelo, IOS, uptime y POR QUÉ reinició
show ip interface brief         ← todas las IPs y estados en una pantalla
show interfaces status          ← puertos: conectado, VLAN, dúplex, velocidad
show vlan brief                 ← qué VLANs existen y qué puertos tienen
show cdp neighbors detail       ← qué hay enchufado a cada puerto (oro)
show mac address-table          ← dónde está cada MAC (localizar un equipo)
show spanning-tree              ← quién es root y qué puertos bloquea
show power inline               ← PoE: consumo por puerto y presupuesto
show logging                    ← el log interno
show running-config             ← la configuración entera en marcha
```

`show run | include <texto>` y `| section <bloque>` filtran (por ejemplo
`show run | section interface Gi1/0/12`). Para localizar un equipo: su MAC
en `show mac address-table address xxxx.xxxx.xxxx` da el puerto, y `show
cdp neighbors` dice si ese puerto va a otro switch (entonces se sigue por
ahí) o al equipo final.

## Una sesión, muchos comandos

**No abras una conexión por `show`.** Cada llamada es una tarjeta que el
usuario aprueba y un veredicto del supervisor: diez `show` sueltos son diez
esperas que cabían en una. Todos los de arriba son lectura pura y van juntos
en una sola sesión:

```sh
ssh -T admin@switch <<'EOF'
terminal length 0
show version
show ip interface brief
show interfaces status
show vlan brief
EOF
```

`terminal length 0` primero, o el equipo pagina y la sesión se queda
esperando un espacio que nadie va a pulsar. La CONFIGURACIÓN no se agrupa
con las lecturas: quien aprueba tiene que poder leer qué cambia.

## Averías con nombre y apellidos

**Dúplex mal negociado**: red «lenta» solo contra un equipo y pérdida que
crece con la carga. En `show interfaces Gi1/0/12`, `late collisions`
subiendo lo delata (un extremo en auto y el otro fijo). El arreglo es
igualar los dos lados, nunca dejar la mezcla. Si lo que sube son `CRC` e
`input errors` sin colisiones tardías, es cable o SFP: se cambia, se hace
`clear counters Gi1/0/12` y se comprueba que el contador se queda quieto.

**Tormenta de difusión / bucle**: TODA una VLAN a rastras y la CPU del
switch disparada (`show processes cpu sorted`). La firma del bucle es
`%SW_MATM-4-MACFLAP_NOTIF` en `show logging`: una MAC bailando entre dos
puertos, y esos dos puertos son los extremos del bucle. Se corta con
`shutdown` en uno y después se averigua quién enchufó qué. Vacuna:
`spanning-tree portfast` más `spanning-tree bpduguard enable` en cada
puerto de acceso, y `storm-control broadcast level 1.00` de cinturón.

**Spanning-tree inestable**: microcortes en toda la red cada pocos
minutos. `show spanning-tree detail | include ieee|occurr|from` dice
cuándo fue el último cambio de topología y por qué puerto entró:
siguiendo ese puerto de switch en switch se llega al origen (típico: un
puerto de acceso sin portfast donde algo se conecta y desconecta).

**VTP borra las VLANs del sitio**: se enchufa un switch de segunda mano y
en minutos desaparecen VLANs de toda la red. Un switch en modo servidor
VTP con número de revisión más alto sobrescribe la base de VLANs del
dominio entero. `show vtp status` ANTES de enchufar nada usado y `vtp
mode transparent` como norma de la casa. Es la avería más destructiva que
se puede causar sin escribir un solo comando.

**DHCP snooping recién activado y nadie coge IP**: snooping descarta los
OFFER que llegan por puertos no confiables, y por defecto ninguno lo es.
El uplink hacia el servidor DHCP necesita `ip dhcp snooping trust`. Se
comprueba con `show ip dhcp snooping` (qué puertos son de confianza) y
`show ip dhcp snooping binding` (quién tiene concesión).

**Port-security apaga un puerto legítimo**: `show port-security
interface Gi1/0/12` enseña la MAC que violó y el máximo configurado (con
`maximum 1`, un teléfono con PC detrás ya son dos MACs). El puerto acaba
en err-disabled — sigue abajo.

## Puertos que se apagan solos: err-disabled

`show interfaces status err-disabled` los lista y la razón (port-security,
bpduguard, un flap). El puerto NO vuelve solo salvo que haya recovery
configurado: se investiga la causa, se arregla, y se rearma con
`shutdown` + `no shutdown` en la interfaz. Rearmar sin arreglar la causa
es un bucle. Para causas concretas puede automatizarse el rearme:
`errdisable recovery cause bpduguard` con `errdisable recovery interval
300` en configuración global (`show errdisable recovery` enseña lo
activo) — útil en accesos, jamás la excusa para no investigar.

BPDU Guard apagando un puerto significa que por ahí llegó otro switch (o
un cable en bucle): eso es una protección funcionando, no una avería.

## VLANs y trunks

```
conf t
vlan 30
 name servidores
interface Gi1/0/12
 switchport mode access
 switchport access vlan 30
```

Un trunk lleva varias VLANs etiquetadas:

```
interface Gi1/0/24
 switchport mode trunk
 switchport trunk allowed vlan 10,20,30
```

**La trampa clásica de Cisco, la que tira redes enteras:**
`switchport trunk allowed vlan 30` **REEMPLAZA** la lista entera — acabas
de quitar del trunk todas las demás VLANs. Para añadir sin destruir es
`switchport trunk allowed vlan add 30`. Antes de tocar un trunk, SIEMPRE
`show interfaces trunk` para ver la lista actual, y en el plan se escribe
el comando con `add`.

Otras dos con nombre: la **native VLAN** (la que viaja sin etiqueta) debe
coincidir en ambos extremos del trunk o el propio switch lo cantará
(`%CDP-4-NATIVE_VLAN_MISMATCH`). Y una VLAN que no existe en el switch no
pasa aunque el trunk la permita: `show vlan brief` primero.

## EtherChannel (agregación)

```
interface range Gi1/0/23-24
 channel-group 1 mode active      ← LACP (active = negocia)
```

`show etherchannel summary`: las patas en `(P)` están agrupadas, `(s)` o
`(D)` no. Un canal a medias (una pata dentro y otra fuera) da esa red que
«funciona a ratos». La configuración de las patas debe ser IDÉNTICA
(VLANs, modo, velocidad) o el canal las expulsa.

## Cambiar sin quedarte fuera

El paracaídas de Cisco para cambios remotos arriesgados:

```
reload in 10                    ← programa un reinicio en 10 min
(haces el cambio)
(compruebas que sigues dentro)
reload cancel                   ← todo bien: se cancela
```

Como lo cambiado no está guardado, si el cambio te cortó el acceso, el
reinicio programado devuelve el equipo a la configuración guardada. Es el
`sleep && revertir` de los switches. Cualquier cambio de VLAN, trunk o IP
por SSH va en `propose_plan` y con este paracaídas puesto ANTES del cambio.

**Guardar** (cuando ya está verificado): `copy running-config
startup-config` (o `write memory`, el veterano `wr`). Y antes de una sesión
de cambios, copia de la configuración: `show run` completo pegado a un
archivo local (con paginación quitada: `terminal length 0` en la sesión,
que no toca configuración).

## Verificar tras cada cambio

- Trunk tocado: `show interfaces trunk` en AMBOS extremos y la lista de
  VLANs exactamente la esperada.
- VLAN de acceso cambiada: el equipo coge IP y su MAC aparece en la VLAN
  nueva (`show mac address-table interface Gi1/0/12`).
- EtherChannel: `show etherchannel summary` con todas las patas en `(P)`.
- Siempre: ping a la puerta de enlace de la VLAN afectada y un vistazo a
  `show logging` sin mensajes nuevos. Solo entonces se guarda.

## Detalles de familia

- **IOS-XE** (Catalyst 9k, ISR 4k) se opera igual que IOS clásico. Trae
  además `archive` (histórico de configs con diff:
  `show archive config differences`) — si está configurado, úsalo para ver
  qué cambió.
- **NX-OS** (Nexus, centro de datos) se parece pero no es igual: hay que
  activar `feature` antes de usar cada cosa, y `show run` solo enseña lo
  que difiere del defecto. Si `show version` dice NX-OS, no des por hechos
  los reflejos de IOS.
- Los equipos viejos solo hablan SSH con algoritmos antiguos: si el ssh
  moderno se niega, se añaden `-oKexAlgorithms=+diffie-hellman-group14-sha1
  -oHostKeyAlgorithms=+ssh-rsa` — al comando, no a la configuración global.

## Reglas

- Nunca `write memory` de un cambio sin verificar: la configuración sin
  guardar ES la vuelta atrás.
- `shutdown` de una interfaz o VLAN por la que entras = quedarte fuera.
  Antes de tocar una interfaz, `show users` y saber por dónde entraste.
- `reload` sin `in` ni plan aprobado, jamás: reinicia el equipo entero con
  todo lo que cuelga de él.
- Anota con `learn` el mapa que descubras: qué puerto va a qué sitio, la
  native VLAN del sitio, qué switch es el root de spanning-tree.
