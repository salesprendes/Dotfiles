---
name: "Discos, RAID y SMART"
description: "Salud de discos y arrays: leer SMART sin alarmismo, mdadm y ZFS degradados, sustituir un disco sin perder datos y qué hacer ante sectores reubicados o errores de E/S. Úsala si se habla de un disco que falla, SMART, RAID, mdadm, un pool ZFS o errores de E/S."
triggers: "smart, smartctl, mdadm, zfs, zpool, raid, sectores, reubicados, badblocks, resync, degradado, nvme, sata, scrub, disco fallando, errores de lectura"
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

Ojo con el veredicto corto: el `PASSED` de `-H` es un listón bajísimo y un
disco puede lucirlo mientras reubica sectores a diario. El veredicto útil
está en los atributos, no en esa línea. Los que predicen fallo de verdad
(en RAW_VALUE):

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
y el estrangulamiento térmico empieza sin avisar.

Tras una caja USB, `smartctl` a menudo no ve el disco de serie:
`smartctl -d sat -a /dev/sdX` atraviesa el puente en la mayoría de cajas.

Cuando SMART está limpio pero la sospecha sigue, el test largo la
resuelve: `smartctl -t long /dev/sda` (tarda horas, el disco sigue
usable) y el veredicto en `smartctl -l selftest`. Un `read failure` con
el LBA apuntado es la confirmación que faltaba.

Para no equivocarse de disco JAMÁS: `lsblk -o NAME,SIZE,MODEL,SERIAL` —
el serial es el único nombre que no baila entre arranques.

El otro testigo: `journalctl -k | grep -i "ata\|nvme\|i/o error"`. Errores
de E/S en el kernel con SMART limpio apuntan a cable, controladora o
alimentación antes que al plato.

## Una llamada, muchas lecturas

El inventario es lectura pura y cabe en un solo comando:

```sh
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL; cat /proc/mdstat; zpool status 2>/dev/null; df -h
```

Los SMART largos y un `badblocks` NO se agrupan: tardan de más y arrastrarían
al resto por el plazo. Y nada que escriba en un disco comparte llamada con
nada.

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
4. `mdadm --add` y a vigilar `/proc/mdstat` hasta el final de la
   reconstrucción.
5. Si el array es de arranque, `grub-install` también en el disco NUEVO:
   un array que sobrevive al fallo pero no arranca porque el cargador
   solo vivía en el disco muerto es el final amargo clásico.

Durante la reconstrucción el array está en su momento más frágil (horas de
lectura intensiva sobre los discos que quedan): no es el día de hacer
también la migración pendiente.

Dos trampas finas. Si tras un cambio el array aparece como `/dev/md127`
en vez de con su nombre, falta su definición en `mdadm.conf` dentro del
initramfs: `mdadm --detail --scan` da la línea para el archivo (vigilando
duplicados) y después se regenera el initramfs de la distro — no es
cosmético, hay monturas y configuraciones que apuntan al nombre. Y con
discos de escritorio en RAID: sin límite de recuperación de errores
(`smartctl -l scterc /dev/sda` lo enseña), el disco puede pasarse minutos
reintentando un sector mientras el kernel se cansa a los 30 segundos y lo
expulsa del array estando «sano». `smartctl -l scterc,70,70 /dev/sda`
fija 7 segundos si el modelo lo admite — en muchos se pierde al apagar y
toca aplicarlo en el arranque.

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

La trampa de espacio: **borrar archivos no libera nada si un snapshot los
retiene**. `zfs list -t snapshot` enseña quién guarda cuánto — el espacio
vuelve al destruir los snapshots viejos, no al vaciar más papeleras.

`scrub` mensual (`zpool scrub`) es lo que convierte los errores latentes en
avisos tempranos. Si no hay cron de scrub, proponlo.

## Disco lleno (df, du, ncdu)

Cuando algo «no escribe», tres preguntas en orden:

```sh
df -h && df -i                      # ¿espacio o inodos? (df -i al 100 % = «lleno» con gigas libres)
du -xh --max-depth=1 / | sort -h    # ¿qué directorio? (-x no cruza a otros sistemas de archivos)
ncdu -x /                           # lo mismo, interactivo
```

Las dos discrepancias que vuelven loco a cualquiera:

- **`du` suma mucho menos de lo que `df` da por ocupado**: hay archivos
  borrados que un proceso mantiene abiertos — el log gigante que alguien
  borró «para hacer sitio» sin recargar el servicio. `lsof +L1` los lista
  con su proceso, y el espacio se libera recargando o reiniciando ese
  servicio, no borrando más cosas.
- **`du` no encuentra al culpable por ningún lado**: puede haber archivos
  escondidos DEBAJO de un punto de montaje (se escribió en `/mnt/copia`
  con el disco sin montar y luego se montó encima). Un montaje espejo de
  la raíz (`mount --bind / /mnt/raiz`) deja mirar debajo sin desmontar
  nada.

Y el sospechoso habitual en systemd: `journalctl --disk-usage`, que se
poda con `journalctl --vacuum-size=500M`.

## LVM

`pvs`, `vgs` y `lvs` dan la foto en tres comandos. Para crecer:
`lvextend -r -L +10G /dev/vg/lv` — la `-r` redimensiona también el sistema
de archivos, y olvidarla es el clásico «he ampliado el volumen y `df`
sigue igual». Otra de horas perdidas: un snapshot de LVM que se llena se
invalida solo y sin aviso — se le da tamaño de sobra y vida corta, nunca
se deja olvidado. Encoger un volumen es otra liga: destructivo si se hace
mal, siempre con copia previa y en un plan.

## Reglas

- SMART que empeora = **primero copia de seguridad, después diagnóstico**.
  Todo lo que se haga con un disco moribundo acelera su muerte.
- `badblocks` de escritura, `dd` sobre el disco o rehacer particiones son
  DESTRUCTIVOS: plan aprobado, con el serial del disco escrito en el plan.
- Nunca quites el disco equivocado de un array degradado: verifica serial
  contra bahía dos veces. Es el error clásico que convierte una avería en
  una pérdida.
