---
name: "Redes en el centro de datos"
description: "Diagnosticar red de servidor con método: enlace, IP, ruta, DNS y puerto por capas, más VLANs, bonding/LACP, bridges, MTU y medir ancho de banda con iperf3. Úsala si se habla de red caída, latencia, paquetes perdidos, VLAN, bonding o un puerto que no conecta."
triggers: "iperf3, mtu, bonding, lacp, latencia, paquetes perdidos, traceroute, mtr, ethtool, tcpdump, ping, gateway, arp, puerto cerrado, ancho de banda"
---

# Redes en el centro de datos

La red se diagnostica **por capas y en orden**, porque cada capa solo tiene
sentido si la de abajo funciona. Saltar directo a «será el DNS» es la forma
lenta de acertar a veces.

## La escalera (de abajo arriba)

```sh
ip -br link            # 1. ¿el enlace está UP y con portadora?
ip -br addr            # 2. ¿tengo IP y en la subred correcta?
ip route               # 3. ¿tengo puerta de enlace? ¿la ruta esperada?
ping -c3 <gateway>     # 4. ¿llego al primer salto?
ping -c3 1.1.1.1       # 5. ¿salgo a internet POR IP?
resolvectl query example.com   # 6. ¿resuelve el DNS?
ss -tulpn              # 7. ¿el servicio escucha donde crees?
```

El punto donde se rompe la escalera ES el diagnóstico. 4 falla y 1-3 no:
problema de switch, VLAN o cable. 5 va y 6 no: es DNS, no la red. 6 va y el
servicio no: firewall o el servicio escuchando solo en localhost (el
clásico `127.0.0.1:3306` cuando esperabas `0.0.0.0`).

Con el harness: `network_query` cubre interfaces, rutas, puertos y ping.
Para lo demás, `ssh_exec` con lo de arriba.

**«Se pierde de vez en cuando»** es el caso difícil: `ping -c 100` y mira
el porcentaje, y `mtr -n --report -c 100 <destino>` señala EN QUÉ salto se
pierde. Pérdida intermitente con el enlace UP huele a duplex mismatch,
cable malo o un puerto de switch saturado.

## Una llamada, muchas lecturas

Los peldaños de la escalera son todos lectura: pídelos en UN comando y ten la
foto entera de una vez, en lugar de una tarjeta de aprobación por peldaño.

```sh
ip -br link; ip -br addr; ip route; cat /etc/resolv.conf; ss -tulpn | head -30
```

Lo que MIDE (iperf3, un ping largo, un tcpdump) va aparte y con su plazo: son
las que tardan, y una lectura rápida atrapada detrás de una lenta se pierde
si el harness corta a los 90 s.

## Averías con nombre y apellidos

**IP duplicada**: conectividad que va y viene con todo bien configurado.
`ip neigh` con la MAC del gateway (o de un vecino) cambiando entre dos
valores, o `arping -I eth0 <ip>` devolviendo respuestas de dos MACs
distintas, lo confirma. Al intruso se le caza por su MAC en el switch.

**El gateway en FAILED**: `ip neigh` con la puerta de enlace en `FAILED`
o `INCOMPLETE` significa que el ARP no obtiene respuesta — problema de
capa 2 (VLAN, puerto, cable) por perfecta que esté la configuración IP.

**Pérdidas bajo carga con la red «bien»**: en `dmesg`, el mensaje
`nf_conntrack: table full, dropping packet` explica cortes aleatorios en
máquinas con muchas conexiones (NAT, proxies, balanceadores). Se compara
`sysctl net.netfilter.nf_conntrack_count` con `nf_conntrack_max` y se
sube el máximo.

**Rutas asimétricas que «no van»**: el tráfico entra por una interfaz y
respondería por otra, y el kernel lo tira en silencio por `rp_filter`
estricto (`sysctl net.ipv4.conf.all.rp_filter` a 1). Con varias
interfaces con rutas propias, valor 2 (holgado) o rutas por tabla.
Activar `log_martians` saca esos descartes en el registro del kernel para
verlos en vez de suponerlos.

**La tarjeta pierde paquetes en picos**: `ethtool -S eth0 | grep -iE
'drop|miss|err'` con `rx_missed_errors` o similares subiendo — el anillo
de recepción se queda corto. `ethtool -g eth0` enseña el tamaño actual y
el máximo, y `ethtool -G eth0 rx 4096` lo amplía.

**tcpdump enseña paquetes «imposibles» de 60 KB**: no es un error, es la
tarjeta agregando segmentos (GRO/TSO) — la captura ve el tráfico antes o
después de que el hardware lo trocee. No perseguir ese fantasma.

**dig resuelve pero la aplicación no**: `dig` habla directo con el
servidor DNS y la aplicación pasa por NSS (`/etc/nsswitch.conf` y
`/etc/hosts`). La prueba honesta de lo que ve la aplicación es
`getent hosts <nombre>` — si difiere de `dig`, el problema es local.

**El bond de 2×10G solo da 10G**: normal con UN flujo — LACP asigna cada
conexión a una sola pata según el hash (`xmit_hash_policy`, con
`layer3+4` repartiendo mejor entre conexiones). Se mide con `iperf3 -P 8`
(varios flujos), nunca con uno solo.

## VLANs, bonding y bridges

- **VLAN**: `ip -d link show` enseña la etiqueta. Si el servidor está bien
  configurado y no pasa tráfico, el puerto del switch no lleva esa VLAN
  (trunk mal declarado) — eso se arregla en el switch, no en el servidor.
- **Bonding/LACP**: `cat /proc/net/bonding/bond0` dice el modo, qué patas
  están arriba y los fallos por pata. LACP (802.3ad) exige configuración a
  AMBOS lados: un bond en LACP contra un switch sin LAG da un enlace que
  «funciona a ratos», que es peor que no funcionar.
- **Bridge** (típico en hipervisores): `bridge link` enseña qué cuelga de
  él. Una VM sin red con el host bien suele ser la pata de la VM fuera del
  bridge o una VLAN que el bridge no filtra como esperas.
- **MTU/jumbo frames**: si el ping normal va y las transferencias grandes o
  el almacenamiento por red se atascan, prueba
  `ping -M do -s 8972 <destino>` (para MTU 9000) o `-s 1472` para la MTU
  estándar. Los jumbo frames deben estar en TODO el camino — un solo salto
  a 1500 y aparecen los cuelgues raros. La MTU se mira con `ip link`, y
  `tracepath <destino>` descubre la MTU real del camino completo. La firma
  del agujero negro de MTU: el ping pequeño va, el grande con `-M do` no,
  y las conexiones TCP se quedan colgadas justo al transferir datos.

## Medir de verdad

Las sensaciones no son datos. `iperf3 -s` en un extremo y
`iperf3 -c <ip>` en el otro miden el ancho de banda real del camino
(`-R` para el sentido contrario, `-P 8` para varios flujos en paralelo).
Si iperf3 da lo esperado y la aplicación va lenta, la red queda descartada
y se ahorra una semana de culparla.

Tres testigos más que resuelven casos concretos:

- `ethtool eth0` — velocidad y dúplex NEGOCIADOS de verdad (un enlace de
  10G sincronizado a 1G por un cable malo se ve aquí y en ningún otro
  sitio), y `ethtool -S eth0` los contadores de error de la tarjeta.
- `tcpdump -ni eth0 host <ip> and port <p>` — cuando hay que ver si los
  paquetes LLEGAN o no. Acotado siempre con filtro y `-c 100`: un tcpdump
  sin filtro en un servidor cargado es un problema nuevo.
- **Firewall local**: `nft list ruleset` (o `iptables -L -n -v` en lo
  viejo) con los CONTADORES — la regla que come los paquetes tiene el
  contador subiendo. Un servicio que escucha pero no recibe casi siempre
  muere aquí o en el firewall del proveedor (cloud: security groups).

## Si el problema está en el switch o el router

Desde el servidor solo se ve la mitad. Cuando el diagnóstico apunta al
otro lado del cable (VLAN que no llega, puerto que negocia mal, trunk sin
la VLAN), sigue en el equipo de red con su habilidad: **Cisco IOS**,
**Huawei VRP**, **MikroTik RouterOS** o **Ubiquiti UniFi** según lo que
haya en el sitio — ahí están sus comandos y sus trampas.

## Verificar tras cada cambio

Repetir la escalera desde el peldaño 1: un cambio de red se da por bueno
cuando el enlace, la IP, la ruta, el ping a la puerta de enlace y el
servicio (`ss -tulpn` más una conexión real) están donde deben. Y a los
cinco minutos, `ip -s link` sin errores ni descartes nuevos. Si el cambio
venía a arreglar pérdida intermitente, la prueba es un `ping -c 300` o un
`mtr --report -c 100`, no tres pings con suerte.

## Reglas

- **Cambiar la red de un servidor remoto puede dejarte fuera.** Cualquier
  cambio de IP, ruta, VLAN o firewall por SSH va en `propose_plan` y con
  red de seguridad: un `sleep 180 && <revertir>` lanzado ANTES del cambio,
  que se cancela solo si sigues dentro.
- Anota con `learn` lo que descubras del sitio: qué VLAN es cuál, MTU del
  almacenamiento, qué bond va a qué switch. Es el mapa que nadie documenta.
- Los cortes intermitentes se cazan con datos acumulados (ping largo, mtr,
  contadores de error de `ip -s link`), no reiniciando interfaces a ver si
  se arregla.
