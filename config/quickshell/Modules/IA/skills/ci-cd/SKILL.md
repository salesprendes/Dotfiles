---
name: Pipelines de CI que fallan o van lentos
description: Depurar y acelerar pipelines de CI (GitHub Actions, GitLab CI, Jenkins): encontrar el fallo real en el log, cachés envenenadas, secretos que no llegan, tests flaky, y medir antes de optimizar. Úsala cuando el pipeline falla, el build se rompe en CI pero va en local, un job se cuelga o tarda demasiado, o un workflow da error a veces sí y a veces no.
---

# Pipelines de CI que fallan o van lentos

**El error real casi nunca está en la última línea del log.** Lo que sale al
final son consecuencias: el paso que abortó, el resumen en rojo. Se busca el
PRIMER fallo, leyendo el log de arriba abajo desde donde el pipeline aún iba
bien. Y un pipeline que falla «a veces» no es mala suerte: es un test flaky
o una dependencia de red, y tiene arreglo con nombre.

## 1. Leer el log entero, no el resumen

Descarga el log crudo del job (el raw, no la vista plegada de la web: la
interfaz colapsa justo las secciones donde vive el error). Busca la primera
aparición de `error`, `fatal`, `denied`, `ENOENT`, `No space` o un código de
salida distinto de cero. Todo lo que venga después es ruido derivado.

## 2. Reproducir en local antes de tocar el YAML

Editar el YAML a ciegas y hacer push para «probar» es el ciclo más caro que
existe: cada iteración son minutos de cola. Antes de tocar nada, ejecuta en
local **el mismo comando que corre el runner, con la misma versión** de la
herramienta (el log dice cuál usa: míralo, no lo supongas). Si el paso corre
dentro de una imagen, `docker run` con esa imagen exacta reproduce el
entorno casi entero. Solo cuando el fallo se reproduce en local merece la
pena arreglarlo, y solo cuando está arreglado en local merece la pena
subirlo.

## 3. Fallos con nombre y apellidos

**Caché envenenada.** Una dependencia a medio escribir o de otra versión
quedó cacheada y ahora todos los builds la heredan. La caché **se invalida
por clave, no se borra a ciegas**: cambia la clave (súbele un sufijo de
versión) y el sistema genera una caché limpia sin destruir las de otras
ramas. Borrarlo todo castiga a todos los pipelines por el pecado de uno.

**Secretos que no llegan.** Los PR desde forks NO reciben secretos (es una
protección deliberada: un fork podría exfiltrarlos), así que el job falla
solo en PRs externos. Y una variable enmascarada sale como `***` en el log:
si sospechas que llega vacía, imprime su longitud o su hash, nunca su valor.

**Runner sin recursos.** `No space left on device` o un proceso matado sin
mensaje (el OOM killer no se despide) a mitad de un paso pesado. Un
`df -h` y un `free -m` como primer paso del job lo diagnostican en la
siguiente ejecución.

**Runner distinto de local.** Imagen con otras utilidades, zona horaria UTC,
locale C (el orden de `sort` cambia y los tests que comparan listas caen), y
CRLF si algo pasó por Windows. Si el test falla solo en CI, la diferencia de
entorno es la primera sospechosa, no el código.

**Test flaky.** Falla sin que nadie haya tocado nada relacionado. Depende de
la hora, del orden de ejecución, de un `sleep` optimista o de la red. Se
arregla o se marca en cuarentena con un issue: nunca se tapa.

## 4. Acelerar: medir primero

La mayoría del tiempo de un pipeline vive en uno o dos pasos. Mira la
duración por paso en la interfaz del CI antes de optimizar nada, porque
optimizar el paso equivocado es tiempo perdido con sensación de trabajo.
Después, en este orden de rentabilidad:

1. **Caché de dependencias** con clave por hash del lockfile
   (`package-lock.json`, `poetry.lock`, `go.sum`): si el lockfile no cambió,
   la instalación es una restauración.
2. **No reconstruir lo que no cambió**: en monorepos, filtros por ruta para
   que tocar la documentación no recompile el backend.
3. **Paralelizar tests** solo tras medir que los tests son el cuello: partir
   una suite de dos minutos en cuatro trozos añade más arranque del que
   ahorra.

## Lo que no se hace nunca

- **Relanzar en bucle sin leer el log.** Si pasa al tercer intento no está
  arreglado: está incubando, y volverá el día del release.
- **`retry` automático como tirita permanente** sobre un test flaky. El
  retry compra tiempo para arreglar la causa, no la sustituye: cada retry
  duplica la duración del pipeline y esconde una regresión real cuando
  llegue.

## Herramientas del harness

Leer logs, YAML y lockfiles es gratis: hazlo sin pedir permiso. Relanzar
jobs, borrar cachés o tocar secretos del CI afecta a todo el equipo: va en
`propose_plan`. Y las particularidades del CI de este sitio (qué runner se
usa, qué job es flaky conocido, dónde viven los secretos) se guardan con
`learn` para no redescubrirlas.

## Verificación final

El pipeline en verde una vez no basta si el fallo era intermitente:
relánzalo dos o tres veces seguidas. Y comprueba que tu arreglo no ha
alargado el pipeline: la duración total antes y después, en la misma vista
donde mediste al principio.
