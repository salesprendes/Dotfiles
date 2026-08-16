---
name: "Crear habilidades"
description: "Cómo escribir una habilidad (SKILL.md) para este asistente que se active cuando toca: la descripción es el disparador, el cuerpo son instrucciones. Úsala para enseñarle algo nuevo al asistente o arreglar una habilidad que no se usa nunca."
source: "adaptada de anthropics/skills (skill-creator), Apache-2.0"
---

# Crear habilidades

Adaptada del `skill-creator` de Anthropic (Apache-2.0) a este harness.

Una habilidad es una carpeta en `Modules/IA/skills/<id>/` con un `SKILL.md`
dentro. Nada más es obligatorio.

## Cómo se carga (y por qué importa)

Al prompt de sistema va el **catálogo**: nombre y descripción de cada
habilidad, ordenado por lo que encaje con el último mensaje del usuario. El
cuerpo entero llega cuando el modelo la pide con `use_skill` — o cuando el
propio harness la carga solo, si una encaja claramente con lo que se acaba
de pedir. Eso significa dos cosas:

1. **La descripción es el disparador, por partida doble.** La lee el modelo
   para decidir, y la puntúa el harness para cargarla sola. Si está mal
   escrita, la habilidad no se usará jamás por buena que sea.
2. **Cada habilidad instalada cuesta contexto en cada mensaje.** Con un
   modelo local de 32k, veinte habilidades mediocres hacen daño. Pocas y
   buenas.

## La descripción

Fórmula: **qué hace + CUÁNDO usarla**, con las palabras que el usuario diría.

```
mal:  "Ayuda con bases de datos."
bien: "Diagnosticar y consultar PostgreSQL: consultas lentas, bloqueos,
       índices que faltan, conexiones agotadas. Úsala cuando el usuario
       hable de Postgres, de una consulta lenta o de un bloqueo."
```

Incluye los sinónimos que usaría de verdad («la web se cae», «da 502»), no
solo el término técnico. Si dos habilidades pueden solaparse, di en la
descripción qué las separa.

Dos lecciones medidas en este harness: el puntuador recorta las palabras a
su raíz de SEIS letras, así que «caducidad» NO casa con «caducado» — usa
la forma que el usuario diría, no el sustantivo abstracto. Las tildes sí se
pliegan: «código» y «codigo» casan igual.

## Cómo puntúa el cargador (medido, no supuesto)

El harness compara el último mensaje del usuario con el nombre y la
descripción de cada habilidad. Pesos por palabra que casa:

| dónde casa        | palabra rara | palabra común (está en 3+ habilidades) |
|-------------------|--------------|----------------------------------------|
| en el NOMBRE      | 4            | 1                                      |
| en la descripción | 1            | 0                                      |

La primera del ranking se carga sola si puntúa 2 o más Y le saca 2 o más a
la segunda. Ante un empate no se carga nada: cargar la equivocada cuesta
más que no cargar. Consecuencias prácticas:

- **Las palabras fuertes van al NOMBRE**, que pesa el cuádruple: «SQL
  lento e índices» dispara con «índice», «Refactorizar sin romper» con
  «refactoriza».
- Caso real: «refactoriza» dejó de disparar porque «refactor» aparecía en
  TRES descripciones y el descuento de palabra común la anulaba. Se
  arregló quitándola de las otras dos, no repitiéndola más fuerte.
- El `name:` del frontmatter debe ser legible y con las palabras clave
  dentro, no el id de la carpeta repetido.
- Con muchas habilidades el catálogo tiene presupuesto: la cola se anuncia
  solo por nombre. Otra razón para que el nombre se defienda solo.

## El cuerpo

Instrucciones **operativas**, no un manual:

- Una **regla madre** en negrita al principio: la frase que salva la tarea
  aunque no se lea nada más.
- El orden en que se hacen las cosas, que es lo que un modelo no sabe.
- Los comandos exactos, con sus trampas.
- Lo que NO se hace nunca, y por qué.
- Qué verificar al terminar.

Reglas de estilo aquí: en castellano, con tablas cuando hay rutas o
equivalencias, y sin relleno motivacional. Entre 2 y 5 KB para un tema
acotado, hasta unos 10 KB si el tema lo llena con sustancia. Si pasa de
24 kB se recorta al leerla.

**Escribe el porqué, no solo el qué.** «No edites los .conf a mano *porque
Plesk los regenera*» se recuerda y se generaliza. «No edites los .conf», a
secas, se desobedece en cuanto parezca práctico.

**Solo comandos contrastados.** Cada comando del cuerpo se ejecuta UNA vez
antes de escribirlo, con sus banderas exactas. Un comando inventado es
peor que ninguno: el modelo se fía, falla, y pierde la confianza en el
resto del archivo. Bandera sin confirmar: se reformula la línea u omite.

## Material largo: archivos al lado

`use_skill` solo trae el SKILL.md, pero el modelo tiene `read_file`: el
material de consulta largo (una tabla de códigos, una plantilla, un
ejemplo extenso) se deja en un archivo en la misma carpeta y el cuerpo lo
enlaza con su ruta completa y la orden de leerlo solo cuando haga falta.
Así el cuerpo se queda en el tamaño que se lee bien y el detalle no cuesta
contexto salvo el día que se usa. Los scripts empaquetados al estilo de
otros ecosistemas NO valen aquí: el harness no los ejecuta por su cuenta.

## allowed-tools (opcional)

```yaml
allowed-tools: read_file, grep_files, glob_files, list_dir
```

Mientras esa habilidad esté en uso, el modelo **solo** verá esas
herramientas (más preguntar, planificar y cambiar de habilidad). Sirve para
una habilidad de análisis que no debe tocar nada. Úsalo con cuidado: si te
dejas fuera algo necesario, el agente se queda sin salida a mitad de tarea.

## Probarla

1. Guarda la carpeta y pulsa **Actualizar** en Ajustes avanzados (o el
   propio harness reescanea si el modelo pide una que no encuentra).
   Recuerda que editar un SKILL.md no recarga el shell: el watcher solo
   mira `.qml` y `.js`.
2. Comprueba que aparece en la lista y está activada.
3. Y la prueba de verdad: **escribe tres frases como las escribiría el
   usuario** y mira si el modelo llama a `use_skill` por su cuenta. Si no lo
   hace, el problema está en la descripción, no en el cuerpo.

## Fallos con nombre y apellidos

- **No salta nunca.** Casi siempre es la descripción: no comparte palabras
  con lo que el usuario escribe de verdad. Repasar las raíces de seis
  letras y las palabras comunes que no puntúan, y mover lo fuerte al
  nombre.
- **Salta cuando no toca.** Descripción demasiado ancha que pisa el
  territorio de otra. Arreglo doble: palabras propias, y una frase de
  frontera («para consultas lentas usa sql-lento, esta es para…»).
- **Se carga y el modelo la ignora.** El cuerpo es un manual y no un
  método: la regla importante está enterrada en el cuarto párrafo. La
  regla madre va en negrita en la primera línea del cuerpo, y el resto en
  imperativo operativo («haz X, comprueba Y»), no en descriptivo («X es
  una técnica que…»).
- **Instrucciones que se desobedecen.** Falta el porqué o falta el comando
  exacto: «revisa los permisos» se ignora, una línea concreta con su ruta
  se ejecuta. Cuanto menos margen de interpretación, más obediencia.

## Mantenerla viva

Cada vez que el modelo use la habilidad y haga algo mal, el arreglo va al
SKILL.md, no a regañarle en el chat: la sesión siguiente no habrá leído la
regañina, pero sí la habilidad. Es el mismo bucle que un test de
regresión: fallo observado → frase nueva con su porqué → repetir las tres
frases de prueba.

## Cuándo NO hacer una habilidad

- Si es un dato del usuario → eso es `remember`.
- Si es una particularidad de este equipo → eso es `learn` (instintos).
- Si es una instrucción para SIEMPRE → eso son las «Instrucciones extra» de
  los ajustes, que van en todos los mensajes.

Una habilidad es para un **tipo de tarea** que aparece de vez en cuando y
tiene método propio.

## Verificación final

- `wc -c SKILL.md` dentro del tamaño previsto (tope duro del harness:
  24 kB).
- Las tres frases de usuario disparan `use_skill` o la carga automática.
- Cada comando del cuerpo se ha ejecutado una vez tal cual está escrito.
- La prosa sin puntos y coma y sin spanglish, como el resto de la casa.
