---
name: Incidentes en producción
description: Cómo actuar cuando algo está CAÍDO y hay presión: estabilizar antes que explicar, no destruir pruebas, comunicar estado y hacer el análisis después. Úsala si algo está caído en producción, hay clientes afectados o el usuario tiene prisa y nervios.
---

# Incidentes en producción

Cuando algo está caído, el orden de prioridades cambia: primero **volver a
dar servicio**, después entender por qué. Es el único contexto donde un
parche feo con hora de caducidad es la decisión correcta — siempre que se
declare como tal.

## Primero: el tamaño del agujero

Tres preguntas antes de tocar nada, y se responden con lecturas
(`server_status`, `server_logs`, `network_query`):

1. **¿Qué está caído exactamente?** «La web» puede ser el servidor, el
   servicio, un dominio o solo el HTTPS. Un minuto de acotar ahorra media
   hora de arreglar lo que funcionaba.
2. **¿Desde cuándo?** El journal con `since` lo dice. La hora del primer
   error apunta directa a la causa (un deploy, una renovación, un cron).
3. **¿Qué cambió justo antes?** La mayoría de los incidentes son un cambio
   reciente. Historial de tareas, `git_log` si hay repo, actualizaciones.

## Estabilizar sin quemar las naves

- **Lo reversible primero.** Reiniciar un servicio, revertir el último
  cambio o desactivar la función nueva son movimientos que se deshacen.
  Borrar, migrar o «reinstalar ya» no — esos van con plan aunque haya
  prisa.
- **No destruyas las pruebas.** Antes de reiniciar algo colgado, captura
  su estado: los últimos cientos de líneas de su log a un archivo, la lista
  de procesos, `ss -tulpn`. Treinta segundos que valen el análisis entero.
  La captura de un tiro, para no pensarla bajo presión:

  ```sh
  d=/root/incidente-$(date +%F-%H%M) && mkdir -p "$d" && \
  journalctl -n 500 > "$d/journal.txt" && ps auxf > "$d/ps.txt" && \
  ss -tulpn > "$d/ss.txt" && df -h > "$d/df.txt" && free -m > "$d/free.txt"
  ```
  Reiniciar borra la escena del crimen y a veces también el síntoma — hasta
  la próxima, ya sin pistas.
- **Un cambio cada vez, y anotado.** Dos cambios a la vez y ya no sabes
  cuál arregló (o cuál rompió más). Ve apuntando hora y acción con
  `todo_write` — es el borrador de la cronología.
- Si el arreglo es un parche temporal, dilo con esas palabras y apunta el
  arreglo de verdad como pendiente. Los parches temporales sin fecha se
  vuelven permanentes solos.

## Comunicar (aunque el usuario sea uno)

Tras estabilizar, o cada pocos minutos si va largo: **qué está afectado,
qué se sabe, qué se está haciendo y cuándo el próximo aviso**. Sin culpas y
sin promesas de tiempo que no controlas. Es exactamente lo que quien espera
necesita, y es lo que evita las interrupciones de «¿cómo va?» a mitad de
maniobra.

## Después: los cinco porqués sin culpables

Con el servicio en pie, la cronología ya casi está escrita (los todo_write
y los logs). El análisis pregunta «por qué» hasta llegar a una causa que se
pueda arreglar de verdad:

> Se cayó la web → el disco se llenó → los logs no rotaban → el paquete de
> rotación se desinstaló en una limpieza → nadie monitoriza el disco.

El arreglo de verdad es el último eslabón (monitorizar + rotar), no el
primero (borrar logs a mano hoy). Cierra el incidente con dos cosas:
la lección del sistema con `learn`, y los pendientes que salieron, dichos
al usuario — un incidente sin pendientes anotados es un incidente que
volverá.

## Reglas

- La prisa del usuario no cambia las reglas del harness: lo destructivo
  sigue yendo en `propose_plan` — un plan de dos líneas se aprueba en diez
  segundos y evita el segundo incidente, el causado por el arreglo.
- Si hay dos hipótesis y una prueba barata las separa, la prueba va antes
  que el arreglo de cualquiera de las dos.
- Nunca digas «arreglado» sin la verificación delante: el mismo comando o
  petición que fallaba, ahora funcionando.
