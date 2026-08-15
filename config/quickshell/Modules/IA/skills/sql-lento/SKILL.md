---
name: SQL lento e índices
description: Diagnostica consultas SQL lentas con EXPLAIN y el registro de consultas lentas, y diseña índices en MySQL/MariaDB o PostgreSQL. Úsala cuando «la consulta tarda», «MySQL va lento», «la base de datos carga el servidor», haga falta crear un índice en una tabla o un panel Plesk/cPanel se arrastre.
---

# Consultas lentas e índices

**Regla madre: no se adivina por qué una consulta es lenta — se le pregunta al planificador con `EXPLAIN`, y lo que diga manda.** Toda hipótesis sin un EXPLAIN delante es una corazonada, y las corazonadas sobre SQL fallan más que aciertan.

## Leer un EXPLAIN de MySQL/MariaDB

```sql
EXPLAIN SELECT ... \G
```

- **`type: ALL`** es recorrido completo de tabla: el sospechoso número uno. Lo sano es `const`, `ref` o `range` sobre un índice.
- **`rows`** es cuántas filas ESTIMA tocar. Una consulta que devuelve 10 filas con `rows: 2000000` está leyendo dos millones para tirar casi todo.
- **`Extra: Using filesort`** y **`Using temporary`** explican los picos: ordenación aparte o tabla temporal, casi siempre por un `ORDER BY` o `GROUP BY` que ningún índice sirve.
- En MySQL 8 y MariaDB, `EXPLAIN ANALYZE` ejecuta de verdad y da tiempos reales por paso. Ojo: EJECUTA la consulta, no lo lances sobre un UPDATE.

En PostgreSQL el equivalente es `EXPLAIN (ANALYZE, BUFFERS)`, con `Seq Scan` en el papel de `type: ALL` y `pg_stat_statements` como agregador de culpables.

## Qué optimizar: el registro de consultas lentas

Optimizar una consulta que no aparece en el registro es perder el tiempo. Primero la lista de culpables reales:

```sql
SET GLOBAL slow_query_log = ON;
SET GLOBAL long_query_time = 1;
SHOW VARIABLES LIKE 'slow_query_log_file';
```

Se agrega con `mysqldumpslow -s t archivo.log` o, mejor, con `pt-query-digest archivo.log` (Percona Toolkit), que ordena por tiempo total consumido: una consulta de 50 ms ejecutada cien mil veces pesa más que una de 10 segundos que corre una vez al día.

## Índices: cómo funcionan de verdad

- **Prefijo izquierdo.** Un índice compuesto `(a, b)` sirve para `WHERE a = ?` y para `WHERE a = ? AND b = ?`, pero NO para `WHERE b = ?` solo. El orden de las columnas se elige mirando las consultas reales, no por intuición.
- **Una función sobre la columna anula el índice.** `WHERE YEAR(fecha) = 2026` recorre toda la tabla. Se reescribe como rango: `WHERE fecha >= '2026-01-01' AND fecha < '2027-01-01'`.
- **`LIKE '%texto'`** con comodín delante tampoco puede usar el índice. Con el comodín solo detrás (`LIKE 'texto%'`), sí.
- **Cada índice encarece cada escritura**: INSERT, UPDATE y DELETE mantienen todos los índices de la tabla. No se añaden a ciegas «por si acaso»: se añade uno para una consulta concreta y se comprueba con EXPLAIN que de verdad lo usa. Un índice que ningún EXPLAIN usa es coste puro.

## Trampas con nombre y apellidos

- **El N+1**: mil consultas de una fila en vez de una consulta de mil filas. No se ve en el EXPLAIN, porque cada consulta individual es rápida. Se ve en el registro o en `SHOW PROCESSLIST` como ráfagas de consultas idénticas con distinto identificador. El arreglo está en el código que llama: un JOIN o un `WHERE id IN (...)`.
- **`SELECT *`** arrastra columnas gordas (TEXT, BLOB) que impiden que un índice cubriente resuelva la consulta sin tocar la tabla. Se piden las columnas que se usan y ninguna más.
- **`OFFSET` grande para paginar**: la página 1000 con `LIMIT 50 OFFSET 50000` lee y tira 50 000 filas. Se pagina por cursor: `WHERE id > ultima_clave_vista ORDER BY id LIMIT 50`.

## En producción de un panel (Plesk/cPanel)

Mirar es gratis y no necesita aprobación: `EXPLAIN`, `SHOW PROCESSLIST`, `SHOW INDEX FROM tabla` y el registro de lentas. Pero **crear o borrar un índice en una tabla grande bloquea o carga el servidor**: incluso con `ALGORITHM=INPLACE, LOCK=NONE` en InnoDB la carga de E/S es real, y en MyISAM el bloqueo de escrituras es total. Eso va en `propose_plan` con ventana horaria, tabla afectada, tamaño estimado y marcha atrás. Las particularidades del servidor (versión, motor de las tablas grandes, franja de menor carga) se guardan con `learn`.

## Cuando el EXPLAIN miente

Si la estimación de filas es disparatada (dice 100 donde hay millones, o al revés), las estadísticas de la tabla están viejas y el planificador decide con datos falsos: `ANALYZE TABLE tabla` las recalcula. Es rápido y casi siempre inocuo, pero en un servidor cargado también se anuncia antes de lanzarlo.

## Verificación final

- El EXPLAIN de después usa el índice esperado y `rows` bajó de forma drástica, no marginal.
- El tiempo real de la consulta, medido antes y después, con números y no con sensaciones.
- Al cabo de un rato, la consulta desaparece de las primeras posiciones del registro de lentas. Si sigue ahí, el diagnóstico era otro.
