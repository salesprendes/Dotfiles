---
name: "Ubiquiti UniFi (WiFi)"
description: "Desplegar y diagnosticar WiFi con puntos de acceso Ubiquiti UniFi: adopción de un AP, set-inform por SSH, estados raros (adopting, isolated, managed by other), canales y potencia, roaming, VLANs por SSID y copias del controlador. Úsala si se habla de UniFi, Ubiquiti, un AP, WiFi lento o que va mal, cobertura o un punto de acceso que no adopta."
---

# Ubiquiti UniFi

UniFi no se configura en el AP: se configura en el **controlador** (una
aplicación en un servidor propio, un Cloud Key o una consola UDM) y este
empuja la configuración a los equipos. De ahí sale casi toda la operativa
y casi todos los líos: un AP «mal configurado» casi siempre es un AP que
no habla con su controlador.

## Cómo se hablan AP y controlador

El AP busca al controlador por el **inform**: una URL
`http://<controlador>:8080/inform`. La descubre por DHCP (opción 43), por
DNS (el nombre `unifi` en el dominio local) o porque alguien se la dijo
por SSH. Puertos del controlador que deben estar abiertos: **8080**
(inform), **8443** (interfaz web), **3478/UDP** (STUN) y 10001/UDP
(descubrimiento).

**El síntoma de STUN cerrado tiene nombre propio**: el AP sale conectado
pero los cambios tardan o no llegan y la interfaz avisa de STUN. No es el
AP: es el 3478/UDP.

Para que los APs de otra subred encuentren solos al controlador: opción
43 de DHCP con la sub-opción 01 y la IP del controlador en hexadecimal
(para 192.168.10.10 es `0104C0A80A0A`), o el registro DNS `unifi`
apuntando a él. Sin eso, `set-inform` a mano en cada AP.

## Adoptar un AP (y arreglar una adopción rota)

Camino feliz: el AP aparece en la interfaz como «Pending adoption» y se
adopta con un clic. Cuando no aparece, SSH al AP (usuario y contraseña
`ubnt`/`ubnt` si está de fábrica, o las credenciales SSH del site si ya
fue adoptado):

```sh
info                                            # estado, versión, inform actual
set-inform http://IP-DEL-CONTROLADOR:8080/inform
```

Tras el `set-inform`, el AP pasa a «Pending» en el controlador, se adopta
ahí, y el estado del `info` debe acabar en «Connected».

Estados con nombre y su remedio:

- **Adopting eterno**: el controlador no alcanza al AP de vuelta o las
  credenciales del site no entran. Repetir `set-inform` tras darle a
  adoptar suele cerrarlo.
- **Managed by other**: el AP pertenece a OTRO controlador (o a una
  instalación anterior). Se libera desde el controlador antiguo
  («Forget») o, sin acceso a él, reset de fábrica del AP.
- **Isolated** (en mallas): el AP no tiene camino cableado ni de malla al
  controlador. Es de red o de uplink, no del AP. Los APs de malla se
  adoptan mejor por cable la primera vez.
- **Reset físico**: botón mantenido ~10 s con el AP encendido hasta que el
  LED cambie. Sin escalera: por SSH, `syswrapper.sh restore-default` hace
  lo mismo. De fábrica, vuelve a `ubnt/ubnt` y a buscar inform.

Un AP recién adoptado que reinicia en bucle con firmware antiguo suele
necesitar actualización de firmware ANTES de aprovisionarse del todo: el
controlador lo ofrece, y en el AP `upgrade <url-del-firmware>` lo fuerza.

## Averías con nombre y apellidos

**«El WiFi va lento» con todas las barras**: mirar primero el uplink del
AP en el controlador — un AP negociado a 100 Mbps por un cable o un
conector malo reparte miseria con señal perfecta. Se confirma en el
puerto del switch (velocidad negociada) y se arregla con el cable, no
tocando la radio.

**Los cacharros IoT no conectan tras un cambio de seguridad**: WPA3 o el
modo mixto WPA2/WPA3 en el SSID rompe clientes antiguos sin mensaje
claro, igual que activar 802.11r. La solución estable es un SSID solo
para IoT, en 2,4 GHz y con WPA2.

**«No veo el Chromecast / la impresora»**: los descubrimientos van por
mDNS, que no cruza VLANs por sí solo, y el aislamiento de la red de
invitados los bloquea a propósito. No es la radio: es multidifusión
entre VLANs (reflector de mDNS) o la política de aislamiento.

**Media oficina se cae de 5 GHz a la vez, de tarde en tarde**: canal DFS
y un radar cerca — el AP debe abandonar el canal por normativa y
arrastra a todos sus clientes. Si se repite, sacar ese AP de canales DFS.

**El análisis de espectro deja el AP fuera de servicio**: lanzar un
escaneo RF desde el controlador corta el servicio de ese AP varios
minutos. Es una acción de ventana acordada, no de mediodía.

## Radio: los ajustes que de verdad cambian el WiFi

- **2,4 GHz: solo canales 1, 6 y 11, y ancho de 20 MHz.** Cualquier otra
  cosa solapa con el vecino y empeora a todos. Con varios APs, repartir
  1/6/11 como un tablero.
- **5 GHz**: anchos de 40 u 80 MHz según densidad de APs (80 en casa, 40
  en despliegues densos). Los canales **DFS** dan espectro limpio pero con
  el riesgo del radar ya contado.
- **Potencia: bajarla, no subirla.** El error clásico es todo a máxima:
  los clientes se aferran a un AP lejano que oyen fuerte pero al que no
  llegan de vuelta. En despliegues con varios APs, potencia media o baja
  en 2,4 GHz hace que los clientes cambien antes al AP cercano.
- **Minimum RSSI** (por AP): expulsa al cliente que se oye por debajo del
  umbral y le obliga a irse al AP bueno. Empezar suave (−75 dBm) y solo si
  hay APs de sobra donde caer.
- **Roaming**: «Fast roaming» del SSID es 802.11r. Ayuda a los clientes
  que cambian mal de AP (móviles con VoIP), pero los IoT viejos no lo
  entienden y directamente no conectan — si tras activarlo desaparecen
  cacharros, es eso. BSS transition (802.11v) es la opción inocua.
- Un SSID por uso, no diez: cada SSID emite balizas que consumen aire en
  TODOS los APs. Dos o tres SSIDs (gente, invitados, IoT) es el máximo
  sano.

## VLANs por SSID

Cada SSID puede etiquetar su tráfico a una VLAN (la red de invitados a la
130, IoT a la 140). Para que funcione, **el puerto de switch donde cuelga
el AP debe ser un trunk** que lleve la VLAN nativa de gestión sin
etiquetar y las VLANs de los SSIDs etiquetadas. El fallo típico: el SSID
de invitados «no da IP» — el trunk del switch no lleva esa VLAN, o el
DHCP de esa VLAN no existe. Se diagnostica en el switch (habilidades de
Cisco/Huawei/MikroTik), no en el AP.

## PoE: el detalle que quema

Los UniFi modernos son **802.3af/at** (PoE estándar). Los Ubiquiti
antiguos y los airMAX usan **PoE pasivo de 24 V**, que NO es estándar:
alimentar un equipo de 24 V pasivo desde un switch 802.3at no funciona, y
enchufar pasivo donde no toca puede dañar. Ante un AP «muerto», confirmar
qué PoE pide el modelo y qué da el puerto antes de dar por muerta la
electrónica. Un AP que se reinicia bajo carga huele a presupuesto PoE del
switch agotado.

## El controlador: cuidarlo

- **Copia de seguridad**: Settings → Backup (archivo `.unf`) descargada y
  fuera del propio equipo. Sin ella, perder el controlador significa
  resetear y readoptar todo el despliegue. Auto-backup activado.
- El controlador autoalojado corre sobre **MongoDB**: los síntomas de «la
  interfaz no carga» tras un corte suelen ser la base corrupta o el disco
  lleno (los logs y la base viven en `/usr/lib/unifi/` o `/var/lib/unifi`).
  El journal del servicio `unifi` lo cuenta.
- Migrar APs a un controlador nuevo: exportar el site o restaurar el
  backup y los APs siguen adoptados (misma identidad). Sin backup:
  `set-inform` de cada AP y readopción a mano.
- En el AP, los logs viven en `/var/log/messages` (por SSH): ahí se ve el
  motivo real de una desconexión o un reinicio.

## Verificar tras cada cambio

- El AP vuelve a «Connected» tras aprovisionar (no se queda clavado en
  «Provisioning») y el número de clientes recupera el nivel de antes.
- Canal o potencia tocados: comprobar en la lista de clientes que nadie
  quedó colgado de un AP lejano con señal mala.
- VLAN por SSID: un cliente de prueba en ese SSID coge IP de la subred
  correcta y sale a donde debe.
- En el AP, `info` por SSH: estado «Connected» y el inform apuntando al
  controlador bueno.

## Reglas

- Cambios de radio (canal, potencia, minimum RSSI) reconectan a los
  clientes de ese AP: son de ventana acordada, no de mediodía.
- «Forget» de un AP en el controlador borra su configuración: es el último
  recurso, no el primer intento.
- Actualizaciones de controlador: copia `.unf` ANTES, siempre — los saltos
  de versión grandes migran la base de datos y no hay vuelta sin copia.
- Anota con `learn` el plano del sitio: qué AP está dónde, qué VLANs
  llevan los SSIDs, dónde vive el controlador y dónde su copia.
