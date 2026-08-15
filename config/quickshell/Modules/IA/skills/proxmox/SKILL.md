---
name: "Proxmox VE"
description: "Administrar y diagnosticar un Proxmox por SSH: VMs con qm, contenedores LXC con pct, almacenamiento, copias vzdump, clúster y quórum, y las averías típicas (VM bloqueada, interfaz caída, nodo en gris, /etc/pve de solo lectura). Úsala si se habla de Proxmox, PVE, un hipervisor, una VM, un contenedor o un nodo."
---

# Proxmox VE

Proxmox es un Debian con KVM (máquinas virtuales) y LXC (contenedores),
gestionado por una interfaz web en el puerto 8006 y un juego de utilidades
de línea de comandos. La regla que ordena todo lo demás: **los servicios de
gestión y las máquinas son independientes**. Reiniciar la interfaz web no
toca ninguna VM. Reiniciar el nodo las toca todas. La mitad del oficio es
saber en cuál de los dos planos estás actuando.

## El mapa

| Utilidad | Gobierna |
|---|---|
| `qm` | máquinas virtuales (KVM) |
| `pct` | contenedores (LXC) |
| `pvesm` | almacenamiento |
| `pvecm` | clúster y quórum |
| `vzdump` | copias de seguridad |
| `pvesh` | toda la API, desde la shell |

Y el dato que explica muchas averías: **`/etc/pve` no es un directorio
normal**. Es pmxcfs, un sistema de archivos montado sobre una base de datos
que se replica entre los nodos del clúster. Si se pierde el quórum, se
vuelve **de solo lectura** — y de repente "no puedo cambiar nada" sin que
ningún disco esté lleno. Las configuraciones viven ahí
(`/etc/pve/qemu-server/<vmid>.conf` y `/etc/pve/lxc/<vmid>.conf`) y se
cambian con `qm set` / `pct set`, no con el editor.

## Primer vistazo (todo lectura)

```sh
pveversion -v
qm list
pct list
pvesm status
pvecm status      # solo si hay clúster
```

Con el harness: `server_status` del nodo para lo general y `ssh_exec` para
estos. Son consultas — pídelas juntas.

## Diagnóstico por síntoma

**Interfaz web caída pero las VMs funcionan.** Es `pveproxy` o `pvedaemon`,
no el hipervisor. Mira su journal y reinícialos: no afecta a ninguna VM.
Es de las pocas acciones baratas de este mundo.

**Nodo en gris con «?» en la interfaz.** Casi siempre es `pvestatd`
colgado (el recolector de estado). Reiniciarlo es inocuo. Si el nodo gris
es otro miembro del clúster, mira `corosync` antes de tocar nada.

**«can't lock file … got timeout» o VM bloqueada.** Una tarea anterior
—casi siempre una copia— murió dejando el candado puesto. Averigua primero
QUÉ tarea era (journal de `pvedaemon`, historial de tareas). `qm unlock`
solo cuando estés seguro de que no hay una copia en marcha: quitar el
candado con la copia viva la corrompe.

**`/etc/pve` de solo lectura.** Quórum perdido: `pvecm status` lo confirma.
Con dos nodos y uno caído es lo esperado — dos nodos sin un tercer voto
(qdevice) no tienen mayoría posible. `pvecm expected 1` lo fuerza, pero
desactiva justo la protección que evita que dos mitades escriban a la vez:
va en un plan aprobado y sabiendo por qué.

**Una VM no arranca.** Lee el error de `qm start` ENTERO: casi siempre
nombra la causa — un volumen que no existe, un almacenamiento inactivo o
lleno, memoria insuficiente. `qm config <id>` dice qué discos referencia y
`pvesm status` si ese almacenamiento está activo.

**VM en pausa con estado «io-error».** El almacenamiento de debajo no
acepta escrituras: thin pool lleno o un NFS caído. `lvs` y `pvesm status`
señalan al culpable. Se libera espacio y `qm resume <id>` — reiniciarla
sin arreglar el almacenamiento la devuelve al mismo sitio en minutos.

**«El nodo se reinició solo».** Si hay HA configurado, un nodo con
recursos HA que pierde el quórum se autorreinicia por watchdog en cosa de
un minuto — es el fencing, y es por diseño. El journal justo anterior al
reinicio y `ha-manager status` lo confirman. Corolario: con HA, el gestor
puede rearrancar una VM que acabas de parar con `qm stop` — su estado se
gobierna con `ha-manager set vm:<id> --state stopped`.

**El nodo perdió la red tras actualizar.** Un kernel nuevo o un cambio de
hardware pueden renombrar las interfaces (enp3s0 pasa a enp4s0) y el
puente de `/etc/network/interfaces` sigue apuntando al nombre viejo. Se ve
comparando `ip -br link` con ese archivo, se corrige el nombre y se aplica
con `ifreload -a` sin reiniciar el nodo.

**Copia colgada y la VM congelada con ella.** vzdump con guest agent hace
fsfreeze dentro del invitado antes del snapshot, y a veces algo ahí dentro
(una base de datos, un NFS interno) no suelta. La VM entera queda helada
hasta el timeout. El task log de la copia lo cuenta: la solución va por el
invitado, no por repetir la copia.

**Discos huérfanos.** Tras una migración o una restauración fallida quedan
volúmenes que ninguna configuración referencia. `qm rescan --vmid <id>`
los engancha a la configuración como `unusedX` y desde ahí se borran
sabiendo qué son — nunca borrando a ojo en el almacenamiento.

**Contenedor que no arranca y no dice por qué.** `pct start <id> --debug`
en versiones recientes, o `lxc-start -n <id> -F` para verlo en primer
plano. Un clásico: restaurar la copia de un contenedor privilegiado como
no privilegiado (o al revés) descoloca los UID y todo el sistema de
archivos aparece como «permission denied».

**«Falta» RAM y hay ZFS.** El ARC de ZFS usa hasta la mitad de la RAM por
diseño y la suelta cuando hay presión. No es una fuga: `arc_summary` lo
enseña. Solo si de verdad estorba se limita con `zfs_arc_max` en
`/etc/modprobe.d/zfs.conf`.

**Disco lleno.** `pvesm status` y luego los sospechosos: copias vzdump
viejas en `local`, ISOs olvidadas y snapshots antiguos (`qm listsnapshot`).
Con LVM-thin, además, `lvs`: un thin pool al 100 % **corrompe datos sin
avisar** — es la urgencia real, no el aviso estético de la interfaz.

**«¿Qué pasó anoche?»** Cada operación es una tarea con su log:
`/var/log/pve/tasks/` los guarda y la interfaz los lista en Task History.
Una copia que falla cada noche o una migración a medias se explican ahí,
no en el journal general. `qm status <id>` y `qm config <id>` completan la
foto de una VM concreta.

**La VM va, pero no se puede entrar.** La consola de la interfaz web
funciona sin red dentro del invitado: es la forma de mirar una VM que
perdió su IP. Desde la shell, `qm terminal <id>` da la consola serie si el
invitado la tiene habilitada. Con el guest agent instalado,
`qm guest cmd <id> network-get-interfaces` dice las IPs reales sin entrar.

## Operar sin sustos

- **`shutdown` no es `stop`.** `qm shutdown` avisa al invitado por ACPI y
  espera. `qm stop` es tirar del cable. Siempre primero `shutdown` con
  timeout, y `stop` solo si no responde — y dilo.
- **Snapshot antes de tocar dentro de una VM** (`qm snapshot <id> antes-x`)
  y bórralo al terminar. Un snapshot **no es una copia**: vive en el mismo
  almacenamiento que la VM y, con el tiempo, la frena.
- `pct enter <id>` da una shell dentro de un contenedor sin red ni
  contraseña. Para un comando suelto, `pct exec <id> -- comando`.
- **Copias:** `vzdump` en modo snapshot no corta la VM. Una copia que nunca
  se ha probado a restaurar no es una copia, es un deseo. Si hay un
  **Proxmox Backup Server**, las copias son incrementales y deduplicadas, y
  restaurar UN archivo (file restore) no exige restaurar la VM entera —
  compruébalo antes de proponer una restauración completa.
- **Discos de VM:** agrandar es seguro (`qm resize <id> scsi0 +20G` y luego
  crecer la partición DENTRO del invitado — son dos pasos y la gente olvida
  el segundo). Encoger no existe como operación segura: eso es copia,
  recrear y restaurar.
- **`qm destroy` borra la VM y sus discos**, y con `--purge` también sus
  referencias en trabajos de copia y replicación. No hay papelera.
- **`local` y `local-lvm` no son intercambiables**: `local` es un
  directorio en la raíz del nodo (ahí caen ISOs y copias) y `local-lvm`
  son volúmenes. Llenar `local` llena la raíz del sistema mientras la
  interfaz jura que en `local-lvm` sobra sitio.
- **Actualizar:** nunca `apt upgrade` a secas — Proxmox exige
  `full-upgrade`, y un upgrade parcial puede dejar el nodo cojo. Sin
  suscripción, el repositorio enterprise devuelve 401: se cambia al
  `pve-no-subscription` antes de pelearse con apt.
- **En clúster:** migra las VMs antes de reiniciar un nodo (`qm migrate`,
  con almacenamiento compartido o `--with-local-disks`). Corosync quiere
  latencia baja y red estable. Y jamás reinicies varios nodos a la vez sin
  haber contado los votos del quórum.

## Comprobar que quedó arreglado

`qm status <id>` en running es lo mínimo, no la prueba. Con guest agent,
`qm agent <id> ping` confirma que el invitado vive y
`qm guest cmd <id> network-get-interfaces` que tiene red. Si dentro corre
un servicio, la prueba de verdad es desde fuera (`fetch_url` o el puerto).
Tras liberar disco, `pvesm status` y `lvs` deben enseñar el margen
recuperado, no solo «ya no da error».

## Lo que va en propose_plan

Parar una VM en uso, `qm unlock`, `qm destroy`, `pvecm expected 1`, borrar
snapshots o copias, el `full-upgrade` del nodo y cualquier operación de
clúster o de HA. Un hipervisor multiplica el daño: debajo de cada orden
hay N máquinas de otra gente.

Si el Proxmox del usuario tiene una particularidad (versión, un
almacenamiento con nombre raro, un nodo sin quórum crónico), guárdala con
`learn`.
