---
name: "Diagnóstico de Linux"
description: "Método para diagnosticar un equipo Arch/systemd que va lento, no arranca un servicio, se queda sin disco o falla al actualizar. Úsala en cuanto el usuario describa un síntoma del sistema, ANTES de tocar nada."
triggers: "systemd, systemctl, journalctl, dmesg, pacman, arch, no arranca, disco lleno, sin espacio, carga alta, uptime, fstab, kernel, unidad en fallo, actualizar el sistema"
---

# Diagnóstico de Linux

**Un síntoma no es una causa.** El error más caro es arreglar lo primero que
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
  `~/.cache`, journals sin rotar (`journalctl --disk-usage` lo dice en un
  segundo).
- **Red** → `network_query {kind:"interfaces"}` → `{kind:"routes"}` →
  `{kind:"ports"}`. Un `ping` que falla no distingue DNS de ruta: comprueba
  ambos antes de concluir.
- **Un proceso "desapareció" solo** → casi siempre lo mató el OOM killer:
  `journal_query {grep:"oom"}` o el kernel (`journalctl -k`). Si es eso, el
  problema no es el proceso muerto sino quién se comió la memoria.
- **La máquina se reinició sola** → `journalctl -b -1 -p err` lee los
  errores del arranque ANTERIOR, que es donde está la historia
  (`journalctl --list-boots` para orientarse entre arranques).
- **Tras actualizar** → `package_query {op:"info"}` del paquete y
  `journal_query {since:"-2h"}`. Busca `.pacnew` sin fusionar: `pacdiff -o`
  los lista sin tocar nada.
- **Arranque lento** → `systemd-analyze blame` y
  `systemd-analyze critical-chain` dicen QUÉ unidad se come el tiempo, con
  número. Sin eso, todo son sospechas.
- **Algo crashea** → `coredumpctl list` y `coredumpctl info <pid>`: el
  volcado con su traza suele estar guardado aunque nadie lo pidiera.
- **Qué hace un proceso colgado** → `cat /proc/<pid>/status` (estado, si
  espera E/S) y `ls -l /proc/<pid>/fd` (qué tiene abierto) responden sin
  herramientas extra. `strace -p <pid>` es el siguiente paso, ya con más
  ruido.

## 3. Fallos con nombre y apellidos

| Síntoma | Causa | Confírmalo con | Arreglo |
|---|---|---|---|
| «Too many open files» | límite de descriptores | `cat /proc/<pid>/limits` y contar `/proc/<pid>/fd` | subir `LimitNOFILE=` en la unidad y `daemon-reload` |
| «No space left on device» con `df -h` holgado | inodos agotados | `df -i` | vaciar la carpeta con millones de archivos pequeños |
| Lo mismo, pero al vigilar archivos (editor, sincronizador) | inotify agotado | `sysctl fs.inotify.max_user_watches` | subirlo en `/etc/sysctl.d/` y aplicar con `sysctl --system` |
| `df` dice lleno y `du` no encuentra el culpable | archivo borrado que un proceso mantiene abierto | `lsof +L1` | reiniciar el proceso que lo retiene (el espacio vuelve solo) |
| Proceso en estado `D` inmune a `kill -9` | espera E/S ininterrumpible (disco o NFS caídos) | `ps -o stat,wchan,cmd -p <pid>` | arreglar el almacenamiento, no el proceso |
| Proceso `<defunct>` (zombi) | el padre no recoge a sus hijos | `ps -o ppid= -p <pid>` | el problema es el PADRE: reiniciarlo |
| TLS falla de repente en todas partes | reloj desviado | `timedatectl` | `timedatectl set-ntp true` |
| Resuelve con `dig` pero la aplicación no | las apps resuelven por NSS, no por DNS directo | comparar `getent hosts nombre` con `resolvectl query nombre` | mirar `/etc/nsswitch.conf` y `resolvectl status` |
| El servicio se comporta como la versión VIEJA tras actualizar | sigue corriendo el binario borrado | `ls -l /proc/<pid>/exe` acaba en `(deleted)` | reiniciar el servicio |

## 4. strace, ltrace y lsof sin ahogarse

- `strace -f -p <pid> -e trace=%file` — solo llamadas de archivos: perfecto
  para «¿qué configuración está leyendo DE VERDAD?» o «¿qué ruta le falta?».
  Busca los `ENOENT` y los `EACCES` en la salida.
- `timeout 5 strace -c -p <pid>` — cinco segundos de resumen estadístico de
  llamadas al sistema. Si domina `futex`, pelea de hilos. Si domina `read` o
  `poll`, espera a otro. El `timeout` es obligado aquí: `run_command` corta
  a los 20 segundos.
- `ltrace -p <pid>` hace lo mismo con llamadas a bibliotecas: mucho más
  ruidoso, resérvalo para cuando strace no cuenta la historia.
- `lsof -p <pid>` (qué tiene abierto), `lsof /ruta` (quién lo tiene
  abierto), y para puertos `ss -tlnp` antes que lsof, que es más barato.
- En `/proc/<pid>/` hay más oro: `cwd` (desde dónde corre), `environ`
  (con qué entorno, pásalo por `tr '\0' '\n'`), `exe` (qué binario es).

## 5. Trampas que cuestan horas

- `active (running)` solo dice que el proceso vive, no que responda:
  compruébalo con una petición real antes de dar nada por sano.
- Tras editar una unidad, `systemctl daemon-reload` o systemd seguirá usando
  la versión vieja SIN avisar. `systemd-analyze verify unidad.service` caza
  erratas antes de arrancarla.
- `systemctl status` trunca líneas y solo enseña el final: la verdad
  completa está en `journalctl -u unidad -n 100 --no-pager`.
- `dmesg -T` da hora humana, pero tras una suspensión esa hora puede venir
  desviada: para lo fino, contrasta con el journal.
- En Arch no existe la actualización parcial: `pacman -Sy paquete` sin `-u`
  deja bibliotecas desparejadas y fallos aleatorios («error while loading
  shared libraries»). O todo con `-Syu` o nada.
- `systemctl list-timers` enseña las tareas programadas de systemd: si algo
  pasa «solo a ciertas horas», empieza por ahí y por el crontab.
- Si el journal es lo que llena el disco, `journalctl --vacuum-size=500M`
  recorta los viejos — borra historia: dilo antes de ejecutarlo.

## 6. Antes de proponer un arreglo

Di en una frase **qué crees que pasa y en qué te basas**. Si no puedes
señalar la línea del log que lo demuestra, aún estás adivinando: sigue
mirando.

## 7. Al tocar

- Lo irreversible (parar servicios, borrar, `pacman -R`) va en un
  `propose_plan`, nunca directo.
- `service_ctl` antes que `run_command`: es la herramienta acotada y deja
  claro en la tarjeta qué unidad y qué acción.
- Tras actuar, **verifica**: vuelve a pedir `service_query` o
  `journal_query` y enseña que el error ya no aparece. Un arreglo sin
  comprobación es una hipótesis con buena prensa.

## 8. Lo que aprendas, guárdalo

Si descubres una particularidad de ESTE equipo —que una unidad necesita
autenticación, que un disco se llena por un log concreto, que un servicio
tarda en levantar— guárdala con `learn`. La próxima vez empiezas donde hoy
terminaste.
