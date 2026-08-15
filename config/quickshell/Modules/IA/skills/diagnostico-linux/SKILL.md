---
name: Diagnóstico de Linux
description: Método para diagnosticar un equipo Arch/systemd que va lento, no arranca un servicio, se queda sin disco o falla al actualizar. Úsala en cuanto el usuario describa un síntoma del sistema, ANTES de tocar nada.
---

# Diagnóstico de Linux

Un síntoma no es una causa. El error más caro es arreglar lo primero que
parece raro. Aquí se mide, se acota y luego se toca.

## 1. Foto general antes que nada

Empieza SIEMPRE por `system_status`: carga, memoria, discos, unidades
fallidas y temperatura en una sola llamada. La mitad de los problemas se ven
ahí (disco al 100 %, una unidad en failed, la máquina con swap a tope).

Si el usuario ya te ha dicho el servicio, pide en el MISMO turno
`system_status` y `service_query` de esa unidad: son lecturas, van en
paralelo, y tener las dos evita un segundo viaje.

## 2. Del síntoma al sitio

- **Servicio caído o que no arranca** → `service_query {name}` para ver el
  estado y sus últimas líneas, y luego `journal_query {unit, priority:"err"}`.
  El error casi nunca está en la última línea: está en la PRIMERA que falló,
  arriba del todo de la cascada.
- **Lento** → `process_query {sort:"cpu"}` y `{sort:"mem"}`. Si nada
  destaca, mira E/S y disco (`disk_query`) antes de culpar a la CPU.
- **Sin espacio** → `disk_query {path:"/"}` y luego baja por las carpetas
  que más pesan. Sospechosos habituales: `/var/log`, `/var/cache/pacman/pkg`,
  `~/.cache`, journals sin rotar.
- **Red** → `network_query {kind:"interfaces"}` → `{kind:"routes"}` →
  `{kind:"ports"}`. Un `ping` que falla no distingue DNS de ruta: comprueba
  ambos antes de concluir.
- **Un proceso "desapareció" solo** → casi siempre lo mató el OOM killer:
  `journal_query {grep:"oom"}` o el kernel (`journalctl -k`). Si es eso, el
  problema no es el proceso muerto sino quién se comió la memoria.
- **Tras actualizar** → `package_query {op:"info"}` del paquete y
  `journal_query {since:"-2h"}`. Busca `.pacnew` sin fusionar.
- **Arranque lento** → `systemd-analyze blame` y `critical-chain` dicen
  QUÉ unidad se come el tiempo, con número. Sin eso, todo son sospechas.
- **Algo crashea** → `coredumpctl list` y `coredumpctl info <pid>`: el
  volcado con su traza suele estar guardado aunque nadie lo pidiera.
- **Qué hace un proceso colgado** → `cat /proc/<pid>/status` (estado, si
  espera E/S) y `ls -l /proc/<pid>/fd` (qué tiene abierto) responden sin
  herramientas extra. `strace -p <pid>` es el siguiente paso, ya con más
  ruido.

## 3. Antes de proponer un arreglo

Di en una frase **qué crees que pasa y en qué te basas**. Si no puedes
señalar la línea del log que lo demuestra, aún estás adivinando: sigue
mirando.

## 4. Al tocar

- Lo irreversible (parar servicios, borrar, `pacman -R`) va en un
  `propose_plan`, nunca directo.
- `service_ctl` antes que `run_command`: es la herramienta acotada y deja
  claro en la tarjeta qué unidad y qué acción.
- Tras actuar, **verifica**: vuelve a pedir `service_query` o
  `journal_query` y enseña que el error ya no aparece. Un arreglo sin
  comprobación es una hipótesis con buena prensa.

## 5. Lo que aprendas, guárdalo

Si descubres una particularidad de ESTE equipo —que una unidad necesita
autenticación, que un disco se llena por un log concreto, que un servicio
tarda en levantar— guárdala con `learn`. La próxima vez empiezas donde hoy
terminaste.
