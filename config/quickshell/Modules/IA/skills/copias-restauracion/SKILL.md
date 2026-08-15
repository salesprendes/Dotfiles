---
name: Copias y restauración
description: Diseñar y comprobar copias de seguridad que restauran de verdad: regla 3-2-1, rsync/borg/vzdump, restauraciones de prueba y cómo actuar cuando hay que restaurar en caliente. Úsala si se habla de backups, copias, restaurar algo borrado o un plan de recuperación.
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
ransomware. Un snapshot tampoco: vive en el mismo disco que protege.

## Qué preguntar antes de diseñar nada

1. ¿Qué duele perder? (datos, configuraciones, bases de datos, correo)
2. ¿Cuánto vale una hora de ese dato? — eso fija cada cuánto copiar (RPO).
3. ¿Cuánto puede estar caído? — eso fija el método de restaurar (RTO).

Con esas tres respuestas el diseño casi se escribe solo. Sin ellas, todo
plan de copias es decoración.

## Herramientas, por caso

- **rsync**: espejo de archivos. Con `--dry-run` SIEMPRE antes del primer
  `--delete`. Barato y universal, pero un espejo hereda los borrados: sin
  versiones no protege del «lo borré ayer».
- **borg / restic**: copias con historial, deduplicadas y cifradas — el
  «lo borré hace dos semanas» que el espejo no cubre. `borg list` para ver
  qué hay y `borg extract` restaura fino.
- **vzdump / PBS** en Proxmox: la copia de la VM entera. Modo snapshot no
  corta la máquina.
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

## La prueba de restauración

Periódica y pequeña basta: restaurar UN archivo y UNA base de datos a un
directorio temporal, y comparar. Eso caza el 90 % de los desastres
silenciosos — la copia vacía, la clave de cifrado perdida, el cron que
lleva tres meses fallando y nadie leyó el aviso. Si hay hueco, propón
programarla con su verificación automática.

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
  Pregunta dónde está la clave y quién más la tiene.
- Anota con `learn` dónde están las copias de cada servidor y cada cuánto
  corren: es la primera pregunta de cualquier incidente futuro.
