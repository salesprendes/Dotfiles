---
name: Redes en el centro de datos
description: Diagnosticar red de servidor con método: enlace, IP, ruta, DNS y puerto por capas, más VLANs, bonding/LACP, bridges, MTU y medir ancho de banda con iperf3. Úsala si se habla de red caída, latencia, paquetes perdidos, VLAN, bonding o un puerto que no conecta.
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
el porcentaje, y `mtr <destino>` señala EN QUÉ salto se pierde. Pérdida
intermitente con el enlace UP huele a duplex mismatch, cable malo o un
puerto de switch saturado.

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
  `ping -M do -s 8972 <destino>` (para MTU 9000). Los jumbo frames deben
  estar en TODO el camino — un solo salto a 1500 y aparecen los cuelgues
  raros. La MTU se mira con `ip link`.

## Medir de verdad

Las sensaciones no son datos. `iperf3 -s` en un extremo y
`iperf3 -c <ip>` en el otro miden el ancho de banda real del camino
(`-R` para el sentido contrario). Si iperf3 da lo esperado y la aplicación
va lenta, la red queda descartada y se ahorra una semana de culparla.

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
