---
name: Git como herramienta de investigación
description: Usar la historia del repositorio para averiguar cuándo y por qué algo dejó de funcionar, y para preparar cambios en commits limpios. Úsala cuando algo "antes iba", al entender código ajeno, o al preparar un commit.
---

# Git como herramienta de investigación

La historia de un repositorio contesta preguntas que el código no contesta:
cuándo se rompió, quién lo sabía y qué se intentó antes. Las herramientas
`git_*` de este harness son de **solo lectura**: mirar es gratis.

## "Antes funcionaba"

Es la mejor pista que te pueden dar. Deja de leer código y mira qué cambió:

1. `git_status` — ¿hay cambios sin confirmar? A veces el culpable aún no
   está en ningún commit.
2. `git_diff` — qué han tocado desde el último commit bueno.
3. `git_log {path}` acotado al archivo o carpeta sospechosa.
4. `git_show {ref}` del commit que más pinta tenga.

Si el rango de commits es grande, `git bisect` es la respuesta: díselo al
usuario con los dos extremos (bueno y malo) y el comando de prueba, porque
esa parte la conduce él. Con una prueba automatizable,
`git bisect run <comando>` lo hace entero solo.

Dos búsquedas que el grep normal no sabe hacer:

- `git log -S "texto"` (la pickaxe) encuentra el commit que AÑADIÓ o QUITÓ
  ese texto — responde «¿cuándo desapareció esta línea?» directamente.
- `git log --follow <archivo>` sigue la historia a través de renombrados,
  que es donde `git_file_history` normal se corta.

Y cuando «se ha perdido» un commit o una rama: `git reflog` guarda por
dónde pasó HEAD las últimas semanas. Casi nada está perdido de verdad —
está sin nombre.

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
- Antes de proponer el commit, `git_diff` y léelo entero: es la última
  oportunidad de ver la sonda que te dejaste puesta.

## Lo que este harness NO hace por ti

Confirmar, cambiar de rama, hacer push o reescribir historia. Eso son
comandos con consecuencias: van por `run_command` con su tarjeta, y los
irreversibles (`push --force`, `reset --hard`, `clean -fd`) en un
`propose_plan` donde se vea exactamente qué se pierde.

Nunca hagas un commit "de paso" mientras haces otra cosa: el commit se hace
cuando el usuario lo pide.
