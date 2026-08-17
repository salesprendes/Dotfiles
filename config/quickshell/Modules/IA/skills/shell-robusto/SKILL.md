---
name: "Shell y scripts robustos"
description: "Cómo escribir comandos y scripts de shell que no destrocen nada por un espacio en un nombre o una variable vacía, y que se puedan repetir sin duplicar efectos. Úsala al escribir cualquier script, cron, unidad de systemd o comando destructivo."
triggers: "bash, script, cron, crontab, set -euo, comillas, borrado accidental, idempotente, xargs, sed, trap, here-doc, comando destructivo, peligroso, sin querer, me da miedo, espacios en el nombre"
---

# Shell y scripts robustos

**Casi todos los desastres de shell salen de tres cosas: una variable vacía,
un nombre con espacios y un comando que se ejecutó dos veces.**

## La cabecera

```sh
#!/usr/bin/env bash
set -euo pipefail          # falla pronto, variables sin definir son error
IFS=$'\n\t'                # sin partir por espacios
```

En `sh` puro no hay `pipefail`: usa `set -eu` y comprueba a mano lo que
importe.

## Las trampas de `set -e` (te van a pasar)

- Dentro de la condición de un `if`, de un `while`, o a la izquierda de
  `&&` y `||`, `-e` está **desactivado** — también dentro de cualquier
  función llamada desde ahí. Un fallo interno no para nada: no confíes en
  `-e` dentro de condiciones.
- `local var=$(cmd)` se traga el código de salida de `cmd` (manda el del
  `local`, que es 0). Declara y asigna en dos líneas:

```sh
local var
var=$(cmd) || return 1
```

- Con `pipefail`, `grep` sin coincidencias devuelve 1 y mata el script. Si
  «cero resultados» es un caso normal, dilo explícito:

```sh
coincidencias=$(grep patrón archivo || true)
```

- También con `pipefail`: `cmd | head -n1` puede acabar en 141 porque
  `head` cierra la tubería y `cmd` muere por SIGPIPE. Si solo te interesa
  el principio, plantéate leer a un archivo temporal primero.
- `(( contador++ ))` devuelve fallo cuando el valor era 0, y con `-e` el
  script muere justo ahí. Usa `contador=$((contador+1))`.
- La sustitución `$(cmd)` no hereda `-e` por defecto: en bash, actívalo con
  `shopt -s inherit_errexit`.

## Subshells que se tragan variables

```sh
total=0
cat archivo | while read -r linea; do total=$((total+1)); done
echo "$total"    # imprime 0: el while corrió en una subshell
```

La tubería crea una subshell y todo lo asignado dentro se evapora al
terminar. En bash, alimenta el bucle por redirección:

```sh
while read -r linea; do total=$((total+1)); done < archivo
while read -r linea; do …; done < <(cmd)    # si la fuente es un comando
```

## Comillas, siempre

`"$var"`, `"$@"`, `"$(cmd)"`. Sin comillas, un archivo llamado
`copia de seguridad.txt` son tres argumentos.

```sh
rm -rf "$dir"/*     # con $dir vacío, esto borra /*  ← MAL
[ -n "${dir:-}" ] && [ -d "$dir" ] || { echo "dir inválido" >&2; exit 1; }
```

Y en rutas y patrones: `--` antes de los argumentos que vengan de fuera, o
un archivo llamado `-rf` te arruina el día. Dos primas de esta familia:

- `printf '%s\n' "$var"` en vez de `echo "$var"` — con `var` valiendo `-n`
  o conteniendo barras invertidas, `echo` hace lo que le da la gana.
- En `[[ $a == $b ]]`, el lado derecho sin comillas es un PATRÓN glob, no
  un texto: `[[ $a == "$b" ]]` para comparar literal.

## `read` bien hecho

Siempre `read -r` (sin `-r` se come las barras invertidas). Y para
conservar espacios al principio y al final de cada línea:

```sh
while IFS= read -r linea; do …; done < archivo
```

## Antes de lo destructivo

- Enseña primero lo que se va a borrar (`find … -print`) y borra en un
  segundo paso, con lo mismo.
- `rsync --delete`: pruébalo antes con `--dry-run`. Siempre.
- Redirigir a un archivo (`>`) es destructivo: `>>` para añadir.
- `mv` sobrescribe sin avisar: `mv -n` si no quieres eso.

## Idempotencia

Un script bueno se puede ejecutar dos veces sin estropear nada:
`mkdir -p`, `ln -sfn`, comprobar antes de añadir una línea a un archivo,
`grep -q … || echo … >>`.

## Errores que se ven

```sh
log() { printf '%s %s\n' "$(date +%F\ %T)" "$*" >&2; }
trap 'log "falló en la línea $LINENO"' ERR
```

Un script silencioso que falla a las 3 de la mañana en un cron es un
problema que descubres el martes.

## Ver qué hace de verdad

Cuando un script miente, `bash -x script.sh` enseña cada comando ya
expandido. Con esta variable, cada línea sale con su archivo y número:

```sh
PS4='+ ${BASH_SOURCE##*/}:${LINENO}: ' bash -x script.sh
```

## Temporales

```sh
tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT
```

Para un directorio, `mktemp -d` y el mismo trap con `rm -rf "$tmp"`. Nunca
un nombre fijo en `/tmp`: es predecible y lo puede ocupar otro.

## Cron es otro planeta

- PATH mínimo y sin tu perfil ni tus alias: declara `PATH` explícito en la
  primera línea del script y usa rutas absolutas para lo dudoso.
- En un crontab, `%` es carácter especial (corta la línea): escápalo
  como `\%`.
- No hay terminal: nada interactivo, y `$HOME` puede no ser el que crees.
- La salida sin redirigir se pierde o acaba en un correo local que nadie
  lee: redirige a un log con fecha.

## Cron sin solapes

Un cron que tarda más que su intervalo acaba corriendo dos veces a la vez
(y las copias dobles corrompen). Un candado lo evita:

```sh
exec 9>/run/lock/mi-tarea.lock
flock -n 9 || exit 0        # ya hay uno corriendo: salir sin drama
```

## Nombres raros de verdad

Al encadenar find con otra cosa, siempre por NUL:
`find … -print0 | xargs -0 …`. Con `-print` a secas, un archivo con salto
de línea en el nombre parte la tubería en dos rutas falsas. Y si hay
`shellcheck` instalado, pásalo: caza justo esta familia de fallos (las
trampas de `-e`, las comillas, los subshells) antes que ningún humano.

## En este harness

- `run_command` corre con `sh -c` y **20 segundos de tope**: para algo largo,
  lánzalo con `nohup`/`systemd-run` y consulta el resultado después.
- Un comando con `;`, `|`, `>` o `` ` `` vuelve a pedir aprobación aunque la
  herramienta esté en automático. Es a propósito: encadenar convierte un
  permiso en otro. No intentes esquivarlo.
- Los datos que vengan del usuario o de un archivo **no se interpolan** en el
  comando: van por variable de entorno y se leen con `"$VAR"`.
- Para un servidor remoto, `ssh_exec` — y ahí las mismas reglas, pero sin
  deshacer.
