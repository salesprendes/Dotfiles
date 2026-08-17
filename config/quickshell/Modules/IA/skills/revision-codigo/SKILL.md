---
name: "Revisión de código"
description: "Cómo revisar código por orden de importancia (corrección, seguridad y luego lo demás) dando cada hallazgo con su caso concreto de fallo. Úsala si piden revisar o auditar código, y antes de dar por buenos tus propios cambios."
triggers: "revisar el codigo, revision de codigo, auditar, auditoria, code review, pull request, hallazgos, dame tu opinion del codigo"
---

# Revisión de código

**Una revisión útil no es una lista de gustos.** Es un puñado de cosas que
se van a romper, dichas de forma que se puedan comprobar.

## Orden de prioridad

Revisa en este orden y no lo inviertas. Un comentario de estilo por encima
de un fallo de corrección entierra lo que importa.

1. **Corrección** — ¿hace lo que dice? Casos límite: vacío, cero, negativo,
   nulo, una sola entrada, entrada gigante, duplicados, Unicode,
   concurrencia.
2. **Seguridad** — entradas sin validar, rutas sin acotar, credenciales en
   claro, comandos construidos por concatenación, permisos de más.
3. **Errores** — ¿qué pasa cuando falla? ¿Se traga la excepción? ¿Deja algo
   a medias? ¿Se puede repetir la operación sin duplicar efectos?
4. **Recursos** — archivos y conexiones que no se cierran, bucles que crecen
   sin tope, trabajo en el camino caliente.
5. **Legibilidad** — nombres, duplicación, funciones que hacen tres cosas.
6. **Estilo** — lo último, y solo si el proyecto no tiene formateador.

En un diff grande, además, no leas en orden alfabético: empieza por lo que
más daño hace si está mal — autenticación y permisos, dinero, borrados,
migraciones de datos, análisis de entrada externa, todo lo que corra con
privilegios. El resto puede esperar a la segunda pasada.

## Cada hallazgo: severidad, caso de fallo y arreglo

No vale "esto podría dar problemas". Di **con qué entrada concreta** falla,
**qué pasa** y **cómo lo arreglarías** en una o dos líneas:

> **Importante** — `parse(path)` con `path=""` entra en el `else` y escribe
> en el directorio actual en vez de fallar. Con `--out ""` te sobrescribe
> `./config`. Arreglo: rechazar ruta vacía al principio con error claro.

Si no eres capaz de construir el caso, probablemente no es un hallazgo:
márcalo como duda, no como defecto.

| Severidad | Significa | Ejemplo |
|---|---|---|
| **Bloqueante** | pérdida de datos, corrupción o agujero de seguridad | inyección de comandos, borrado sin acotar |
| **Importante** | fallo real con una entrada plausible | carrera al escribir el mismo archivo |
| **Menor** | funciona, pero costará caro mantenerlo | duplicación, nombre que miente |
| **Duda** | no consigues construir el caso de fallo | «¿puede llegar nulo aquí?» |

Ordena el informe por severidad y resume arriba: cuántos hallazgos de cada
nivel y si el cambio es aceptable con arreglos o necesita otra vuelta.

## Concurrencia y carreras: mirada explícita

Esta familia se escapa siempre si no se busca a propósito:

- **Comprobar y luego usar (TOCTOU)**: mirar si el archivo existe y abrirlo
  después deja un hueco en el que otro lo cambia. Se abre UNA vez y se
  decide sobre lo abierto (y al crear, con exclusividad tipo `O_EXCL` o
  `mktemp`).
- **Leer-modificar-escribir sin candado**: dos procesos leen 5 y ambos
  escriben 6. Vale para contadores, archivos de estado y columnas de base
  de datos por igual.
- **Escritura no atómica**: quien lea a mitad ve el archivo a medias. Se
  escribe a un temporal en el mismo sistema de archivos y se renombra
  encima, que el renombrado sí es atómico.
- **Modificar una colección mientras se recorre**, y estado compartido
  entre hilos «porque solo es un contador».

## Seguridad: la pregunta de fondo

Siempre la misma: **¿puede un dato convertirse en código o en una ruta?**

- Datos que llegan a un intérprete: SQL, shell, HTML, expresiones
  regulares. Concatenar es el pecado, los parámetros son la virtud.
- Rutas construidas con entrada del usuario sin normalizar: `../../` se
  sale del directorio previsto.
- Temporales con nombre fijo en `/tmp` y permisos de creación demasiado
  abiertos.
- Secretos en el código, en los logs o dentro de mensajes de error que
  viajan al cliente.

## Tests del cambio

Si el diff toca lógica y ningún test cambió, o los tests no existían o no
cubren lo tocado. Es hallazgo, no duda. Y mira lo que los tests afirman:
un test que no puede fallar (sin aserciones reales, o afirmando lo que el
propio código devuelve) es peor que no tener ninguno, porque da confianza
falsa.

## Antes de opinar, lee lo suficiente

- El archivo entero, no el trozo pegado: la mitad de los "esto está mal"
  desaparecen al ver el contexto.
- Quién más lo usa: `grep_files` por el nombre de la función — un cambio de
  comportamiento rompe a los que llaman, no al archivo.
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
- Léete tu propio diff entero como si fuera de otro: es donde aparecen el
  archivo colado y el cambio que no venía a cuento.

## Lo que no es una revisión

Reescribirlo a tu gusto. Si hay una forma mejor, proponla en dos líneas con
el porqué. No entregues una refactorización que nadie ha pedido dentro de
una revisión. Y no infles la severidad para que te hagan caso: un
«bloqueante» que no lo era devalúa el siguiente.
