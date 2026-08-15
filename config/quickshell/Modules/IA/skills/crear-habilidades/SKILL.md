---
name: Crear habilidades
description: Cómo escribir una habilidad (SKILL.md) para este asistente que se active cuando toca: la descripción es el disparador, el cuerpo son instrucciones. Úsala para enseñarle algo nuevo al asistente o arreglar una habilidad que no se usa nunca.
source: adaptada de anthropics/skills (skill-creator), Apache-2.0
---

# Crear habilidades

Adaptada del `skill-creator` de Anthropic (Apache-2.0) a este harness.

Una habilidad es una carpeta en `Modules/IA/skills/<id>/` con un `SKILL.md`
dentro. Nada más.

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
la forma que el usuario diría, no el sustantivo abstracto. Y las palabras
que aparecen en tres o más descripciones («servidor», «dominio») dejan de
puntuar: lo que dispara una habilidad son sus palabras PROPIAS (plesk,
proxmox, mikrotik), ponlas en el nombre y en la descripción.

## El cuerpo

Instrucciones **operativas**, no un manual:

- El orden en que se hacen las cosas, que es lo que un modelo no sabe.
- Los comandos exactos, con sus trampas.
- Lo que NO se hace nunca, y por qué.
- Qué verificar al terminar.

Reglas de estilo aquí: en castellano, con tablas cuando hay rutas o
equivalencias, y sin relleno motivacional. Entre 2 y 5 KB. Si pasa de 24 kB
se recorta al leerla.

**Escribe el porqué, no solo el qué.** «No edites los .conf a mano *porque
Plesk los regenera*» se recuerda y se generaliza. «No edites los .conf», a
secas, se desobedece en cuanto parezca práctico.

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
2. Comprueba que aparece en la lista y está activada.
3. Y la prueba de verdad: **escribe tres frases como las escribiría el
   usuario** y mira si el modelo llama a `use_skill` por su cuenta. Si no lo
   hace, el problema está en la descripción, no en el cuerpo.

## Cuándo NO hacer una habilidad

- Si es un dato del usuario → eso es `remember`.
- Si es una particularidad de este equipo → eso es `learn` (instintos).
- Si es una instrucción para SIEMPRE → eso son las «Instrucciones extra» de
  los ajustes, que van en todos los mensajes.

Una habilidad es para un **tipo de tarea** que aparece de vez en cuando y
tiene método propio.
