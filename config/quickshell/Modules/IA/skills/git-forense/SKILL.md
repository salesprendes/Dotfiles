---
name: "Git como herramienta de investigación"
description: 'Usar la historia del repositorio para averiguar cuándo y por qué algo dejó de funcionar, y para preparar cambios en commits ordenados. Úsala cuando algo "antes iba", al entender código ajeno, o al preparar un commit.'
triggers: "commit, commits, bisect, blame, reflog, historial, rebase, stash, cherry-pick, antes iba, quien toco, cuando se rompio, commits limpios, commits ordenados"
---

# Git como herramienta de investigación

**La historia de un repositorio contesta preguntas que el código no
contesta**: cuándo se rompió, quién lo sabía y qué se intentó antes. Las
herramientas `git_*` de este harness son de **solo lectura**: mirar es
gratis.

## "Antes funcionaba"

Es la mejor pista que te pueden dar. Deja de leer código y mira qué cambió:

1. `git_status` — ¿hay cambios sin confirmar? A veces el culpable aún no
   está en ningún commit.
2. `git_diff` — qué han tocado desde el último commit bueno.
3. `git_log {path}` acotado al archivo o carpeta sospechosa.
4. `git_show {ref}` del commit que más pinta tenga.

## `git bisect`, con piloto automático si se puede

Si el rango de commits es grande, bisect encuentra el commit culpable en
log₂(n) pruebas. Díselo al usuario con los dos extremos y la prueba, porque
esa parte la conduce él:

```sh
git bisect start
git bisect bad HEAD          # primero el malo
git bisect good v2.1         # luego el último bueno conocido
git bisect run ./prueba.sh   # con prueba automatizable, va solo
git bisect reset             # SIEMPRE al terminar
```

Reglas de `bisect run`: la prueba sale con 0 si ese commit está bien, con
1–127 si está mal, y con **125** si no se puede evaluar (no compila, falta
una dependencia) para que git lo salte. La prueba puede ser tan simple como
un `grep -q` sobre un archivo generado.

Trampa: si al acabar el repositorio está «raro» y HEAD suelto, es que el
bisect sigue abierto — `git bisect reset` lo cura y te devuelve a donde
estabas.

## Recetas de búsqueda que el grep normal no sabe hacer

| Pregunta | Comando |
|---|---|
| ¿Cuándo apareció o desapareció este texto? | `git log -S "texto" --oneline` |
| ¿Qué commits tocaron líneas que casan con este patrón? | `git log -G "patrón" --oneline` |
| ¿La historia de ESTA función? | `git log -L :nombre_funcion:archivo` |
| ¿Quién escribió esto de verdad, no quién lo reformateó? | `git blame -w -M -C archivo` |
| ¿Cómo era este archivo hace tres commits? | `git show HEAD~3:ruta/archivo` |
| ¿Su historia a través de renombrados? | `git log --follow -p archivo` |

`-S` (la pickaxe) cuenta apariciones: encuentra el commit que AÑADIÓ o
QUITÓ el texto. `-G` casa el patrón contra las líneas del diff: para
«¿cuándo cambió el valor de este parámetro?» suele ser `-G`.

## Rescatar lo «perdido»

`git reflog` guarda por dónde pasó HEAD las últimas semanas. Casi nada está
perdido de verdad — está sin nombre:

```sh
git reflog                        # localizar el estado bueno
git branch rescate HEAD@{3}       # ponerle nombre antes de que caduque
git fsck --lost-found             # commits colgantes que ni el reflog nombra
```

Tras un `reset --hard` equivocado, todo lo CONFIRMADO se recupera así. Lo
que nunca vuelve: cambios sin confirmar pisados por `checkout -- archivo` o
por ese mismo reset. Esa asimetría es la razón de que esos comandos vayan
en `propose_plan`.

## Dos sitios a la vez: `git worktree`

```sh
git worktree add ../urgente rama-estable
git worktree list
git worktree remove ../urgente
```

Un segundo directorio de trabajo del MISMO repositorio: reproduces un fallo
en otra rama o compilas una versión vieja sin guardar ni pisar lo que
tienes a medias. Ideal durante un bisect largo o un arreglo urgente en
mitad de otra cosa.

## Conflictos repetidos: `rerere`

Con `git config rerere.enabled true`, git recuerda cómo resolviste cada
conflicto y reaplica esa resolución la próxima vez que aparezca. En rebases
largos o ramas que se reintegran a menudo ahorra una tarde entera.

## Entender código ajeno (o tuyo de hace un año)

- `git_blame` sobre las líneas raras, y luego `git_show` de ese commit: el
  mensaje suele explicar la rareza. **Una línea rara suele ser la cicatriz
  de un fallo real** — quitarla lo reabre.
- `git_file_history {diff:true}` para ver cómo evolucionó un archivo.
- `git_grep` en vez de `grep_files` cuando estés dentro de un repo: busca
  solo en lo que git sigue, así no te trae `node_modules` ni artefactos.

## Preparar cambios

- Un commit = una idea. Si el mensaje necesita un "y además", son dos
  commits.
- El mensaje dice **por qué**, no qué (el diff ya dice qué). En imperativo y
  en el idioma del repositorio — mira `git_log` antes de elegirlo.
- Antes de proponer el commit, léete el diff ENTERO — y ojo: `git_diff` a
  secas no enseña lo ya preparado, lo preparado se ve con
  `git diff --staged`. Mira los dos o la sonda que dejaste puesta viaja en
  el commit.
- `git stash pop` con conflicto NO borra la entrada del stash: tras
  resolver, comprueba con `git stash list` y limpia con `git stash drop`,
  o el stash «resucita» semanas después.

## Lo que este harness NO hace por ti

Confirmar, cambiar de rama, hacer push o reescribir historia. Eso son
comandos con consecuencias: van por `run_command` con su tarjeta, y los
irreversibles (`push --force`, `reset --hard`, `clean -fd`) en un
`propose_plan` donde se vea exactamente qué se pierde. Para `clean`,
primero `git clean -n` (enseña sin borrar) y solo después la versión real.

Nunca hagas un commit "de paso" mientras haces otra cosa: el commit se hace
cuando el usuario lo pide.
