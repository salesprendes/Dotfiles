---
name: Discos, RAID y SMART
description: Salud de discos y arrays: leer SMART sin alarmismo, mdadm y ZFS degradados, sustituir un disco sin perder datos y qué hacer ante sectores reubicados o errores de E/S. Úsala si se habla de un disco que falla, SMART, RAID, mdadm, un pool ZFS o errores de E/S.
---

# Discos, RAID y SMART

La pregunta detrás de casi todo aquí es «¿me está avisando o ya es tarde?».
El método: leer lo que dice el disco (SMART), leer lo que dice el kernel
(journal), y decidir con los dos. Uno solo miente por omisión.

## Leer SMART sin alarmismo

```sh
smartctl -a /dev/sda          # todo
smartctl -H /dev/sda          # el veredicto corto
```

Del listado de atributos, los que predicen fallo de verdad (en RAW_VALUE):

| Atributo | Qué significa |
|---|---|
| `Reallocated_Sector_Ct` (5) | sectores ya reubicados |
| `Current_Pending_Sector` (197) | sectores en duda, esperando veredicto |
| `Offline_Uncorrectable` (198) | ilegibles confirmados |
| `UDMA_CRC_Error_Count` (199) | ojo: esto es el CABLE, no el disco |

Cero en los tres primeros: disco sano por viejo que sea. Un valor pequeño y
**estable**: vigilar (apúntalo con `learn` y compara en unos días). Un valor
que **crece**: el disco se está muriendo, y el plan es copia + sustitución,
no esperar. El 199 subiendo se arregla cambiando el cable SATA.

En NVMe: `smartctl -a /dev/nvme0` — mira `Percentage Used`, `Media Errors`
y las entradas del log de errores. Un NVMe que va a tirones sin errores
puede estar simplemente ardiendo: la temperatura está en esa misma salida
y el throttling térmico empieza sin avisar.

Cuando SMART está limpio pero la sospecha sigue, el test largo la
resuelve: `smartctl -t long /dev/sda` (tarda horas, el disco sigue
usable) y el veredicto en `smartctl -l selftest`. Un `read failure` con
el LBA apuntado es la confirmación que faltaba.

Para no equivocarse de disco JAMÁS: `lsblk -o NAME,SIZE,MODEL,SERIAL` —
el serial es el único nombre que no baila entre arranques.

El otro testigo: `journalctl -k | grep -i "ata\|nvme\|i/o error"`. Errores
de E/S en el kernel con SMART limpio apuntan a cable, controladora o
alimentación antes que al plato.

## mdadm (RAID por software)

```sh
cat /proc/mdstat              # el estado real, en una pantalla
mdadm --detail /dev/md0
```

`[UU]` bien, `[U_]` degradado. Degradado significa **sin red de seguridad**:
otra pérdida y se acabó — a partir de ahí todo es urgente pero con cabeza.

Sustituir el disco malo, en este orden y cada paso en el plan:

1. Identifica FÍSICAMENTE el disco (por serial: `smartctl -i`), no por
   /dev/sdX — las letras bailan entre arranques.
2. `mdadm --fail` y `--remove` del miembro malo.
3. Disco nuevo, misma tabla de particiones que un miembro sano
   (`sgdisk -R` para copiarla y `-G` para regenerar el GUID).
4. `mdadm --add` y a vigilar `/proc/mdstat` hasta el final del rebuild.

Durante el rebuild el array está en su momento más frágil (horas de lectura
intensiva sobre los discos que quedan): no es el día de hacer también la
migración pendiente.

El equivalente del scrub de ZFS existe en mdadm y casi nadie lo mira:
`echo check > /sys/block/md0/md/sync_action` recorre el array buscando
discrepancias (`mismatch_cnt` al terminar). Las distros suelen traerlo
mensual por systemd timer — comprobar que corre vale más que confiar.

## ZFS

```sh
zpool status -v               # salud y QUÉ archivos están dañados
zfs list -o space             # quién ocupa, snapshots incluidos
```

`DEGRADED` con un disco `FAULTED`: `zpool replace pool disco-viejo
disco-nuevo` y vigilar el resilver. `zpool status -v` con errores
permanentes lista los archivos afectados con nombre — restaurar esos de
copia, no adivinar. Y el clásico silencioso: **un pool por encima del ~85 %
se degrada en rendimiento** y la fragmentación no se deshace — el aviso de
espacio en ZFS es antes que en otros sistemas.

`scrub` mensual (`zpool scrub`) es lo que convierte los errores latentes en
avisos tempranos. Si no hay cron de scrub, proponlo.

## Reglas

- SMART que empeora = **primero copia de seguridad, después diagnóstico**.
  Todo lo que se haga con un disco moribundo acelera su muerte.
- `badblocks` de escritura, `dd` sobre el disco o rehacer particiones son
  DESTRUCTIVOS: plan aprobado, con el serial del disco escrito en el plan.
- Nunca quites el disco equivocado de un array degradado: verifica serial
  contra bahía dos veces. Es el error clásico que convierte una avería en
  una pérdida.
