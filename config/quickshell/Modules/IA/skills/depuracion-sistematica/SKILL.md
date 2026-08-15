---
name: Depuración sistemática
description: Método para encontrar la causa REAL de un fallo en vez de parchear síntomas: reproducir, acotar, formular una hipótesis que se pueda falsar y comprobarla. Úsala siempre que algo "no funciona", falla, se cuelga o da un resultado raro.
---

# Depuración sistemática

La tentación es cambiar algo que parezca sospechoso y volver a probar. Eso
no es depurar: es barajar. A veces sale, y entonces es peor, porque el fallo
vuelve la semana que viene con otra cara.

## 1. Reproducir antes que entender

Si no puedes provocar el fallo a voluntad, no puedes saber si lo has
arreglado. Consigue **el comando exacto, la entrada exacta y el error
exacto** — pídelos al usuario con `ask_user` si no los tienes. Adivinarlos
cuesta más que preguntarlos.

## 2. Leer el error entero

El mensaje útil casi nunca es la última línea. En una cascada, la causa está
ARRIBA: el resto son consecuencias. Lee la traza completa y localiza la
primera cosa que ya no era como debía.

## 3. Acotar por mitades

Divide el camino en dos y averigua en cuál de las mitades vive el fallo.
Repite. En cuatro o cinco cortes se pasa de "algo en el proyecto" a "esta
línea". Herramientas: `grep_files` para encontrar el sitio, `read_file` con
`offset`/`limit` para leer alrededor, y la historia (`git_log`,
`git_file_history`, `git_blame`) para saber cuándo dejó de funcionar.

Si el fallo es reciente y antes iba: la pregunta correcta es **qué cambió**,
no qué está mal. `git_diff` y `git_log` contestan eso en un minuto.

## 4. Hipótesis falsable

Escríbela como una frase que se pueda demostrar FALSA:

> "Falla porque la ruta llega vacía cuando el usuario no pasa `--config`."

Y ahora diseña la comprobación más barata que la mate. Si tu hipótesis no se
puede refutar con una prueba, todavía no es una hipótesis: es una corazonada.

## 5. Confirmar la causa ANTES de arreglar

Demuéstralo: el valor que imprimes, la línea del log, el `git_show` del
commit que lo introdujo. Solo entonces toca código.

## 6. Arreglar la causa, no el síntoma

Un `if` que esquiva el caso malo no arregla nada: lo esconde. Si de verdad
hace falta un parche temporal, dilo con esas palabras y explica cuál sería
el arreglo de verdad.

## 7. Verificar y dejar rastro

Vuelve a ejecutar la reproducción del paso 1 y **enseña la salida**. Si el
fallo venía de una particularidad del equipo o del proyecto, guárdala con
`learn`: es exactamente lo que no quieres volver a descubrir.

## El truco del entorno que funciona

Cuando existe un sitio donde SÍ va (otra máquina, otro usuario, ayer), la
depuración cambia de forma: deja de buscarse «qué está mal» y se busca
**qué es distinto**. Diff de versiones, de configuración, de variables de
entorno (`env | sort` en ambos lados y comparar). Es el atajo más
infravalorado: la diferencia ES la lista corta de sospechosos.

## Señales de que estás barajando

- Llevas tres cambios y sigues sin saber por qué fallaba.
- Has dicho "probemos a ver si con esto".
- Arreglaste algo y no sabes explicar por qué funcionaba antes.

En cualquiera de los tres casos: para, vuelve al paso 1 y reproduce.
