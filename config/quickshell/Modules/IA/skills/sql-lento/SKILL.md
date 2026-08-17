---
name: "SQL lento e índices"
description: "Diagnostica consultas SQL lentas con EXPLAIN y el registro de consultas lentas, y diseña índices en MySQL/MariaDB o PostgreSQL. Úsala cuando «la consulta tarda», «MySQL va lento», «la base de datos carga el servidor», haga falta crear un índice en una tabla o el panel de un hosting se arrastre."
triggers: "explain, indice, indices, mysql, mariadb, postgres, postgresql, consulta lenta, slow query, innodb, join, cardinalidad, analyze, tabla enorme"
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
- **`Extra: Using index`** es la buena noticia: índice cubriente, la consulta se resuelve sin tocar la tabla.
- En MySQL 8 y MariaDB, `EXPLAIN ANALYZE` ejecuta de verdad y da tiempos reales por paso. Ojo: EJECUTA la consulta, no lo lances sobre un UPDATE.

## Leer un EXPLAIN ANALYZE de PostgreSQL

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;
```

- **`actual time` es POR VUELTA**: en un nodo con `loops=8000`, el coste real es tiempo × vueltas. El clásico que engaña es un Nested Loop con un Seq Scan interior «barato» de 0.2 ms… ejecutado ocho mil veces.
- **`Rows Removed by Filter`** alto es el índice que falta: se leyeron miles de filas para tirarlas después.
- **`Buffers: shared read`** es disco de verdad y `shared hit` es caché. Una consulta lenta la primera vez y rápida la segunda vive ahí, y esa mejora «mágica» al repetirla no es mejora.
- **Estimado contra real**: si donde estimaba `rows=100` aparecen 2 millones reales, el planificador decide con datos falsos. `ANALYZE tabla;` (así, a secas, en PostgreSQL) recalcula las estadísticas.
- **`Index Only Scan` con `Heap Fetches` altos** no es «only» de nada: el mapa de visibilidad está viejo y sigue yendo a la tabla. Lo arregla el autovacuum o un `VACUUM tabla;`.

El agregador de culpables es `pg_stat_statements`:

```sql
SELECT calls, round(total_exec_time) AS ms, left(query, 60) AS q
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;
```

(antes de la versión 13 la columna se llama `total_time`).

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
- **Igualdades primero, el rango al final.** Para `WHERE cliente = ? AND fecha > ?` el índice bueno es `(cliente, fecha)`: tras saltar al cliente, las fechas quedan ordenadas y el rango es un tramo contiguo. `(fecha, cliente)` obliga a recorrer todo el rango de fechas filtrando a mano.
- **Índice cubriente**: si contiene TODAS las columnas que la consulta usa, no se toca la tabla. Se reconoce en `Extra: Using index` (MySQL) o en `Index Only Scan` (PostgreSQL, donde además `CREATE INDEX ... INCLUDE (columna)` cuelga columnas de solo lectura sin engordar la clave).
- **Una función sobre la columna anula el índice.** `WHERE YEAR(fecha) = 2026` recorre toda la tabla. Se reescribe como rango: `WHERE fecha >= '2026-01-01' AND fecha < '2027-01-01'`.
- **`LIKE '%texto'`** con comodín delante tampoco puede usar el índice. Con el comodín solo detrás (`LIKE 'texto%'`), sí.
- **Cada índice encarece cada escritura**: INSERT, UPDATE y DELETE mantienen todos los índices de la tabla. No se añaden a ciegas «por si acaso»: se añade uno para una consulta concreta y se comprueba con EXPLAIN que de verdad lo usa. Un índice que ningún EXPLAIN usa es coste puro.

## Trampas con nombre y apellidos

- **El N+1**: mil consultas de una fila en vez de una consulta de mil filas. No se ve en el EXPLAIN, porque cada consulta individual es rápida. Se ve en el registro o en `SHOW PROCESSLIST` como ráfagas de consultas idénticas con distinto identificador. El arreglo está en el código que llama: un JOIN o un `WHERE id IN (...)`.
- **`SELECT *`** arrastra columnas gordas (TEXT, BLOB) que impiden que un índice cubriente resuelva la consulta sin tocar la tabla. Se piden las columnas que se usan y ninguna más.
- **`OFFSET` grande para paginar**: la página 1000 con `LIMIT 50 OFFSET 50000` lee y tira 50 000 filas. Se pagina por cursor: `WHERE id > ultima_clave_vista ORDER BY id LIMIT 50`.
- **`OR` entre columnas distintas** suele descartar los índices de las dos. Se reescribe como dos consultas unidas con `UNION`, cada una con su índice.
- **Comparar tipos distintos anula el índice sin avisar**: `WHERE telefono = 612345678` sobre una columna VARCHAR obliga a MySQL a convertir fila a fila. Con comillas (`'612345678'`) el índice vuelve. La variante sorda: dos tablas unidas por columnas de collation distinta (`utf8mb4_general_ci` contra `utf8mb4_unicode_ci`) hacen el JOIN sin índice y ningún mensaje lo dice.

## Bloqueos y deadlocks

Síntoma: una consulta normalmente instantánea se queda colgada a ratos, o la aplicación registra `Deadlock found when trying to get lock`.

- **MySQL/InnoDB**: `SHOW ENGINE INNODB STATUS \G` y leer la sección `LATEST DETECTED DEADLOCK`: las dos transacciones, sus consultas y qué bloqueo esperaba cada una. Las transacciones abiertas y desde cuándo:

  ```sql
  SELECT trx_id, trx_started, trx_query
  FROM information_schema.innodb_trx ORDER BY trx_started;
  ```

  Una transacción abierta hace horas suele ser un proceso que abrió, llamó a algo externo y nunca confirmó: además de bloquear, impide purgar el histórico.
- **PostgreSQL**: `pg_blocking_pids(pid)` da directamente quién bloquea a un proceso, y `pg_stat_activity` con `wait_event_type = 'Lock'` lista a los que esperan.

Los arreglos reales son de diseño, no de configuración: transacciones CORTAS (el patrón mortal es abrir transacción, llamar a una API externa y confirmar al volver), tocar las tablas en el MISMO orden desde todos los caminos del código, y en PostgreSQL indexar las columnas de clave foránea — borrar o modificar un padre sin índice en la columna del hijo recorre la tabla hija entera con el bloqueo cogido.

## En producción de un panel (Plesk/cPanel)

Mirar es gratis y no necesita aprobación: `EXPLAIN`, `SHOW PROCESSLIST`, `SHOW INDEX FROM tabla` y el registro de lentas. Pero **crear o borrar un índice en una tabla grande bloquea o carga el servidor**: incluso con `ALGORITHM=INPLACE, LOCK=NONE` en InnoDB la carga de E/S es real, y en MyISAM el bloqueo de escrituras es total. En PostgreSQL, `CREATE INDEX CONCURRENTLY` construye sin bloquear escrituras a cambio de tardar más: no puede ir dentro de una transacción y, si falla a medias, deja un índice marcado INVALID que hay que borrar y relanzar. Todo esto va en `propose_plan` con ventana horaria, tabla afectada, tamaño estimado y marcha atrás. Las particularidades del servidor (versión, motor de las tablas grandes, franja de menor carga) se guardan con `learn`.

## Cuando el EXPLAIN miente

Si la estimación de filas es disparatada (dice 100 donde hay millones, o al revés), las estadísticas de la tabla están viejas y el planificador decide con datos falsos: `ANALYZE TABLE tabla` en MySQL/MariaDB, `ANALYZE tabla;` en PostgreSQL. Es rápido y casi siempre inocuo, pero en un servidor cargado también se anuncia antes de lanzarlo.

## Verificación final

- El EXPLAIN de después usa el índice esperado y `rows` bajó de forma drástica, no marginal.
- El tiempo real de la consulta, medido antes y después, con números y no con sensaciones. Un arreglo bueno se cuenta con las dos cifras: «`rows` de 1 900 000 a 42, tiempo de 3,8 s a 12 ms, mismo `EXPLAIN ANALYZE`». Una mejora del 15 % probablemente es ruido o el índice equivocado.
- Al cabo de un rato, la consulta desaparece de las primeras posiciones del registro de lentas. Si sigue ahí, el diagnóstico era otro.
