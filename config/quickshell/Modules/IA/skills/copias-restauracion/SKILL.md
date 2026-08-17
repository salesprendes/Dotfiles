---
name: "Copias y restauración"
description: "Diseñar y comprobar copias de seguridad que restauran de verdad: regla 3-2-1, rsync/borg/vzdump, restauraciones de prueba y cómo actuar cuando hay que restaurar en caliente. Úsala si se habla de backups, copias, restaurar algo borrado o un plan de recuperación."
triggers: "backup, backups, borg, restic, rsync, vzdump, snapshot, restaurar, restauracion, retencion, incremental, plan de recuperacion, borrado por error, punto de restauracion"
---

# Copias y restauración

**Nadie quiere copias: todo el mundo quiere restauraciones.** Toda esta
habilidad se reduce a esa frase. Una copia que nunca se ha restaurado de
prueba es un deseo con cron.

## La regla 3-2-1, aplicada

Tres copias de lo que importa, en dos soportes distintos, una fuera del
edificio. En la práctica de un servidor pequeño: los datos vivos, una copia
local (rápida de restaurar) y una remota (la que sobrevive al desastre).
Un RAID **no es una copia** — replica al instante también los borrados y el
ransomware. Un snapshot tampoco: vive en el mismo disco que protege. Y la
copia remota en la que el servidor puede escribir Y borrar cae con él: si
un ransomware entra con las llaves del servidor, cifra también la copia.
Modo de solo añadir (borg lo trae) o copia tirada DESDE el destino, no
empujada desde el origen.

## Qué preguntar antes de diseñar nada

1. ¿Qué duele perder? (datos, configuraciones, bases de datos, correo)
2. ¿Cuánto vale una hora de ese dato? — eso fija cada cuánto copiar (RPO).
3. ¿Cuánto puede estar caído? — eso fija el método de restaurar (RTO).

Con esas tres respuestas el diseño casi se escribe solo. Sin ellas, todo
plan de copias es decoración.

## Herramientas, por caso

- **rsync**: espejo de archivos. Con `--dry-run` SIEMPRE antes del primer
  `--delete`. La barra final cambia el significado — `rsync -a origen/
  destino/` copia el contenido, y sin barra crea `destino/origen/` — la
  mitad de los espejos duplicados nacen ahí. Para un sistema entero `-a`
  no basta: `-aHAX` conserva también enlaces duros, ACL y atributos
  extendidos. Barato y universal, pero un espejo hereda los borrados: sin
  versiones no protege del «lo borré ayer».
- **borg / restic**: copias con historial, deduplicadas y cifradas — el
  «lo borré hace dos semanas» que el espejo no cubre. `borg list` para ver
  qué hay y `borg extract` restaura fino. `borg check` y `restic check`
  verifican el repositorio entero: una pasada mensual detecta la
  corrupción antes que el día de la restauración. Si una copia
  interrumpida deja el repositorio bloqueado, `borg break-lock` lo
  libera — SOLO tras confirmar que no queda ningún proceso de borg vivo.
- **vzdump / PBS** en Proxmox: la copia de la VM entera. Modo snapshot no
  corta la máquina. Copiar a mano la imagen de disco de una VM encendida
  da lo mismo que copiar una base de datos en caliente: basura con buen
  aspecto.
- **Bases de datos**: NUNCA copiar los archivos en caliente y ya —
  `mysqldump --single-transaction` (InnoDB sin bloquear) o `pg_dump`
  producen un volcado consistente. Copiar `/var/lib/mysql` con el motor
  encendido da una copia corrupta que parece buena hasta el día que hace
  falta.
- **Retención**: borg y restic la automatizan (`borg prune` con
  `--keep-daily 7 --keep-weekly 4 --keep-monthly 6` y `borg compact` para
  recuperar el espacio, `restic forget --prune`). Sin política de
  retención, toda copia acaba en «disco lleno» y alguien borrando a mano
  lo que no debía.
- Paneles: Plesk y cPanel traen su sistema de copias — usarlo antes que
  inventar uno en paralelo, y comprobar A DÓNDE guarda (una copia en el
  mismo disco que muere no cuenta para el 3-2-1).

## El cron que falla en silencio

El fallo más común no es técnico: la copia dejó de correr hace meses y
nadie lo supo. Dos defensas. La primera, saber que el cron tiene un PATH
más corto que tu sesión — sus «command not found» solo se ven redirigiendo
su salida a un archivo o al correo, no probando el guion a mano. La
segunda y principal: **vigilar la EDAD de la última copia, no si el cron
corrió**. `borg list --last 1` o `restic snapshots --latest 1` dan la
fecha de la última copia real — una alerta cuando esa fecha envejece caza
cualquier causa de fallo, conocida o por conocer.

## La prueba de restauración

Periódica y pequeña basta: restaurar UN archivo y UNA base de datos a un
directorio temporal, y comparar. Eso caza el 90 % de los desastres
silenciosos — la copia vacía, la clave de cifrado perdida, el cron que
lleva tres meses fallando y nadie leyó el aviso. Si hay hueco, propón
programarla con su verificación automática.

Con los volcados de base de datos, dos comprobaciones de un minuto: que no
esté truncado (la última línea de un volcado de mysqldump dice `-- Dump
completed`, y un volcado cortado a mitad no) y que el comprimido esté
íntegro (`gzip -t volcado.sql.gz`). El tamaño «parecido al de ayer» no
demuestra nada: un volcado puede pesar lo mismo y venir sin la tabla que
importa.

Para tener la línea a mano al restaurar fino:

```sh
borg extract /ruta/repo::copia-2026-08-14 etc/nginx    # esa ruta, en el directorio actual
restic -r /ruta/repo restore latest --target /tmp/prueba --include /etc/nginx
```

## Restaurar en caliente (cuando ya ha pasado)

1. **Para el daño primero**: si algo sigue borrando o cifrando, se aísla
   antes de restaurar nada.
2. Restaura **a un lado**, nunca encima: lo que queda del original puede
   ser lo único que hay si la copia resulta peor de lo esperado.
3. Verifica lo restaurado (abre el archivo, consulta la base) ANTES de
   ponerlo en su sitio.
4. El paso final de mover lo restaurado a producción va en `propose_plan`.

## Reglas

- Borrar copias viejas para hacer sitio va en un plan, con la lista de lo
  que se borra: es el único momento en que borrar copias parece buena idea.
- Cifrado sin custodia de clave = copia perdida con extra de vergüenza.
  Pregunta dónde está la clave y quién más la tiene — y con borg y restic,
  que esté guardada FUERA del servidor que se copia, porque la copia
  cifrada del servidor muerto no se abre con la clave que ardió con él.
- Anota con `learn` dónde están las copias de cada servidor y cada cuánto
  corren: es la primera pregunta de cualquier incidente futuro.
