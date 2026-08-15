---
name: Revisión de código
description: Cómo revisar código por orden de importancia (corrección, seguridad y luego lo demás) dando cada hallazgo con su caso concreto de fallo. Úsala si piden revisar o auditar código, y antes de dar por buenos tus propios cambios.
---

# Revisión de código

Una revisión útil no es una lista de gustos. Es un puñado de cosas que se
van a romper, dichas de forma que se puedan comprobar.

## Orden de prioridad

Revisa en este orden y no lo inviertas. Un comentario de estilo por encima
de un fallo de corrección entierra lo que importa.

1. **Corrección** — ¿hace lo que dice? Casos límite: vacío, cero, negativo,
   nulo, una sola entrada, entrada gigante, Unicode, concurrencia.
2. **Seguridad** — entradas sin validar, rutas sin acotar, credenciales en
   claro, comandos construidos por concatenación, permisos de más.
3. **Errores** — ¿qué pasa cuando falla? ¿Se traga la excepción? ¿Deja algo
   a medias? ¿Se puede repetir la operación sin duplicar efectos?
4. **Recursos** — archivos y conexiones que no se cierran, bucles que crecen
   sin tope, trabajo en el camino caliente.
5. **Legibilidad** — nombres, duplicación, funciones que hacen tres cosas.
6. **Estilo** — lo último, y solo si el proyecto no tiene formateador.

## Cada hallazgo, con su caso de fallo

No vale "esto podría dar problemas". Di **con qué entrada concreta** falla y
**qué pasa**:

> `parse(path)` con `path=""` entra en el `else` y escribe en el directorio
> actual en vez de fallar. Con `--out ""` te sobrescribe `./config`.

Si no eres capaz de construir el caso, probablemente no es un hallazgo:
márcalo como duda, no como defecto.

Un par de familias que se escapan siempre y merecen mirada explícita:
las **comprobaciones con carrera** (comprobar y luego usar: el archivo
puede cambiar entre medias — se abre y se comprueba lo abierto), y los
**tests del cambio**: si el diff toca lógica y ningún test cambió, o los
tests no existían o no cubren lo tocado. Ambas son hallazgo, no duda.

## Antes de opinar, lee lo suficiente

- El archivo entero, no el trozo pegado: la mitad de los "esto está mal"
  desaparecen al ver el contexto.
- Quién más lo usa: `grep_files` por el nombre de la función.
- Por qué está así: `git_blame` sobre las líneas raras y `git_show` del
  commit. Muchas rarezas son una cicatriz de un fallo real, y quitarlas lo
  reabre.

## Al revisar TU propio trabajo

Antes de decir que algo está hecho:

- ¿Lo has ejecutado? Enseña la salida.
- ¿Has probado el camino que falla, no solo el que funciona?
- ¿Has dejado sondas, prints o archivos temporales? Quítalos.
- ¿Lo que dices que hace coincide con lo que hace? Si el resumen es más
  generoso que el código, corrige el resumen.

## Lo que no es una revisión

Reescribirlo a tu gusto. Si hay una forma mejor, proponla en dos líneas con
el porqué. No entregues una refactorización que nadie ha pedido dentro de
una revisión.
