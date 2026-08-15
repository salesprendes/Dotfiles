---
name: Shell y scripts robustos
description: Cómo escribir comandos y scripts de shell que no destrocen nada por un espacio en un nombre o una variable vacía, y que se puedan repetir sin duplicar efectos. Úsala al escribir cualquier script, cron, unidad de systemd o comando destructivo.
---

# Shell y scripts robustos

Casi todos los desastres de shell salen de tres cosas: una variable vacía,
un nombre con espacios y un comando que se ejecutó dos veces.

## La cabecera

```sh
#!/usr/bin/env bash
set -euo pipefail          # falla pronto, variables sin definir son error
IFS=$'\n\t'                # sin partir por espacios
```

En `sh` puro no hay `pipefail`: usa `set -eu` y comprueba a mano lo que
importe.

## Comillas, siempre

`"$var"`, `"$@"`, `"$(cmd)"`. Sin comillas, un archivo llamado
`copia de seguridad.txt` son tres argumentos.

```sh
rm -rf "$dir"/*     # con $dir vacío, esto borra /*  ← MAL
[ -n "${dir:-}" ] && [ -d "$dir" ] || { echo "dir inválido" >&2; exit 1; }
```

Y en rutas y patrones: `--` antes de los argumentos que vengan de fuera, o
un archivo llamado `-rf` te arruina el día.

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

## Temporales

```sh
tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT
```

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
`shellcheck` instalado, pásalo: caza justo esta familia de fallos.

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
