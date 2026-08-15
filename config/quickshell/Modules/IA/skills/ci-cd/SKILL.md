---
name: "Pipelines de CI que fallan o van lentos"
description: "Depurar y acelerar pipelines de CI (GitHub Actions, GitLab CI, Jenkins): encontrar el fallo real en el log, cachés envenenadas, secretos que no llegan, tests flaky, y medir antes de optimizar. Úsala cuando el pipeline falla, el build se rompe en CI pero va en local, un job se cuelga o tarda demasiado, o un workflow da error a veces sí y a veces no."
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

**Caché que restaura pero nunca se actualiza.** En GitHub Actions una caché
es inmutable: si la clave exacta ya existe, el guardado al final del job se
omite. Síntoma: la clave es fija (`key: deps`) y las dependencias añadidas
la semana pasada se descargan de la red en cada build. Arreglo: clave por
hash del lockfile con `restore-keys` de red de seguridad.

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: npm-${{ hashFiles('**/package-lock.json') }}
    restore-keys: npm-
```

Con `restore-keys` se restaura la más reciente que empiece por ese prefijo
y, si la clave exacta no existía, al acabar el job se guarda una nueva con
ella. Detalle que despista: una rama solo ve cachés creadas en ella misma,
en la rama por defecto o en la base del PR, así que la primera ejecución de
cada rama nueva «no encuentra» nada y eso no es un fallo. Y hay desalojo:
unos 10 GB por repositorio y las cachés sin uso en una semana se borran
solas.

**Matriz que se cancela en cascada.** En `strategy.matrix`, `fail-fast`
vale `true` por defecto: la primera combinación que falla cancela a todas
las demás a medias. Síntoma: un job rojo y quince «cancelados», sin saber
si el fallo era de una versión concreta o de todas. Para diagnosticar,
una pasada con `fail-fast: false` y la matriz entera hasta el final: la
foto completa dice si el problema es una combinación o el código.

**Dos pushes seguidos que se pisan.** Sin grupo de concurrencia cada push
lanza su ejecución y ambas tocan lo mismo a la vez. Arreglo:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

Ojo: `cancel-in-progress` en un workflow de despliegue puede cortarlo a la
mitad y dejar el entorno en un estado intermedio. Para desplegar, grupo sí
y cancelación no: que las ejecuciones hagan cola. El equivalente en GitLab
es `interruptible: true` en el job.

**Archivos que no aparecen en el siguiente job.** Cada job estrena runner:
nada del disco sobrevive de un job a otro. Lo construido viaja con
`actions/upload-artifact` y `actions/download-artifact`, y el orden se
declara con `needs:` (sin él los jobs corren en paralelo y el consumidor
arranca antes de que el artefacto exista). En la v4 el nombre de artefacto
es único por ejecución: dos patas de una matriz subiendo al mismo nombre
fallan, mete la variable de la matriz en el nombre. En GitLab es al revés:
los artefactos de etapas anteriores se descargan solos en las siguientes.

**El pipe que esconde el fallo.** El shell por defecto de un paso `run` en
Linux es `bash -e` SIN `pipefail`: en `cmd | tee build.log` el paso hereda
el código de `tee` y queda en verde aunque `cmd` reviente. Declarar
`shell: bash` en el paso activa además `pipefail`. Síntoma clásico: build
«en verde» con artefacto vacío.

**El job colgado que cobra por horas.** GitHub Actions no corta un job
hasta los 360 minutos por defecto (GitLab, 60). Un proceso esperando una
entrada que nunca llega son seis horas de facturación y de cola bloqueada.
Póliza barata: `timeout-minutes` a nivel de job, ajustado a la duración
real con margen.

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

## 4. GitHub Actions y GitLab CI no hablan el mismo idioma

| Tema | GitHub Actions | GitLab CI |
|---|---|---|
| Archivos entre jobs | Artefactos explícitos, subir y bajar | Automáticos entre etapas |
| Caché | Central e inmutable por clave, ámbito de rama | En runners propios vive en cada máquina: sin caché distribuida, «a veces está» según qué runner toque |
| Tiempo máximo por defecto | 360 min por job | 60 min |
| Ejecuciones duplicadas | `concurrency` + `cancel-in-progress` | `interruptible: true` |
| Vida de los artefactos | Configurable por workflow | Caducan solos pasado el plazo por defecto |

La fila de la caché explica un clásico de GitLab con runners propios: el
build «recuerda» las dependencias unas veces sí y otras no, y la única
diferencia es qué máquina ejecutó el job.

## 5. Acelerar: medir primero

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
- **Editar el YAML a ojo y hacer push como método de depuración.** Cada
  intento son minutos de cola: reproduce en local primero.

## Herramientas del harness

Leer logs, YAML y lockfiles es gratis: hazlo sin pedir permiso. Relanzar
jobs, borrar cachés o tocar secretos del CI afecta a todo el equipo: va en
`propose_plan`. Y las particularidades del CI de este sitio (qué runner se
usa, qué job es flaky conocido, dónde viven los secretos) se guardan con
`learn` para no redescubrirlas.

## Verificación final

El pipeline en verde una vez no basta si el fallo era intermitente:
relánzalo dos o tres veces seguidas. Si el arreglo era de caché, el log lo
confirma: la línea de restauración nombra la clave exacta y el paso de
instalación baja de minutos a segundos. Y comprueba que el arreglo no ha
alargado el pipeline: la duración total antes y después, en la misma vista
donde mediste al principio.
