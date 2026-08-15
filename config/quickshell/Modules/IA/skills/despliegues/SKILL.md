---
name: "Desplegar sin sustos (deploy, canary, rollback)"
description: "Preparar y ejecutar despliegues con lista go/no-go, migraciones compatibles hacia atrás, canary o blue-green según el caso, y rollback probado. Úsala cuando haya que desplegar, subir a producción, hacer un release, migrar la base de datos, hacer rollback o revertir un despliegue que ha salido mal."
---

# Desplegar sin sustos

**Un despliegue sin plan de vuelta atrás PROBADO no es un despliegue: es una
apuesta.** «Probado» significa que la vuelta atrás se ha ejecutado alguna
vez, no que existe un documento que la describe. Todo lo demás de esta
habilidad ordena las cosas para que, si algo sale mal, volver sea un
comando aburrido y no una noche heroica.

## 1. Lista go/no-go antes de empezar

Se repasa entera y en voz alta. Un «no» en cualquier punto para el
despliegue sin discusión:

- **Qué cambia exactamente.** El diff entre lo desplegado y lo que se va a
  desplegar, leído. «Solo un fix pequeño» sin diff delante es la frase que
  precede a las sorpresas.
- **Migraciones compatibles hacia atrás.** Ver la sección siguiente: si la
  migración rompe la versión anterior, el rollback ya no existe.
- **Salud del entorno destino.** Disco, memoria, réplicas en verde,
  alertas activas. Desplegar sobre un entorno tocado convierte un problema
  en dos y hace imposible saber cuál causó qué.
- **Ventana acordada y quién está al teléfono.** Con nombre. «Alguien del
  equipo» no coge el teléfono.
- **Congelaciones.** Viernes por la tarde y vísperas de festivo: no. No
  porque el despliegue vaya a fallar, sino porque si falla no habrá nadie
  mirando durante horas.

## 2. Migraciones: expandir-contraer

Nunca se despliega un cambio de esquema destructivo junto al código que
deja de usarlo. El orden es **primero añadir, luego desplegar, y solo
después quitar**:

1. Migración que AÑADE (columna nueva, tabla nueva) sin tocar lo viejo.
   Las dos versiones del código conviven con este esquema.
2. Desplegar el código nuevo. Si hay que volver atrás, la versión vieja
   sigue funcionando porque no le falta nada.
3. Días después, con el despliegue asentado, la migración que QUITA lo que
   ya nadie lee.

Un renombrado o cambio de tipo hecho con red se ve así:

```sql
-- Fase 1 (expandir): la columna nueva llega opcional
ALTER TABLE pedidos ADD COLUMN importe_centimos BIGINT;

-- Fase 2: el código nuevo escribe en LAS DOS columnas y lee la nueva.
-- Relleno del histórico por lotes, nunca de una tacada:
UPDATE pedidos SET importe_centimos = importe * 100
WHERE importe_centimos IS NULL AND id BETWEEN 1 AND 10000;
-- (repetir por tramos: un UPDATE de toda la tabla retiene bloqueos
--  durante minutos y dispara el retraso de las réplicas)

-- Fase 3 (contraer): días después y en OTRO despliegue
ALTER TABLE pedidos DROP COLUMN importe;
```

La columna jamás se borra en el mismo despliegue que deja de usarla: ese
atajo es exactamente el que convierte un rollback de un minuto en una
restauración de copia de seguridad. Dos trampas más del mismo barrio:

- **Índices sobre tablas grandes.** En PostgreSQL,
  `CREATE INDEX CONCURRENTLY` construye el índice sin bloquear las
  escrituras. No puede ejecutarse dentro de una transacción, así que va
  fuera del bloque transaccional de la herramienta de migraciones.
- **`NOT NULL` sobre columna nueva.** Primero opcional, luego relleno por
  lotes, y la restricción se aprieta al final, cuando ya no queda ningún
  nulo. Exigirla de entrada obliga a un valor por defecto y en PostgreSQL
  anterior a la versión 11 reescribía la tabla entera con bloqueo.

## 3. Feature flags: separar desplegar de activar

Un flag convierte «volver atrás» en apagar un interruptor, sin tocar
infraestructura: el código llega apagado, se activa para un grupo pequeño
y, si algo huele mal, se apaga en segundos. Reglas para que no se vuelva
en contra:

- **Apagado por defecto**, y el camino con el flag apagado es exactamente
  el comportamiento de ayer, cubierto por los tests de siempre.
- **Los dos caminos se prueban** mientras convivan: el flag duplica los
  estados posibles y el camino que nadie ejecuta es el que se pudre.
- **Fecha de defunción.** Un flag que cumple meses ya no es un
  interruptor, es deuda: dos ramas de código vivas y nadie recuerda cuál
  manda. Asentado el cambio, el flag y el camino viejo se borran en un
  despliegue propio.
- **Una variable por vez.** Activar un flag y desplegar otra cosa a la vez
  deja dos sospechosos para cualquier síntoma: si se activa un flag, no se
  despliega nada más en esa ventana.

## 4. Estrategia según el caso

| Estrategia | Cuándo | Precio |
|---|---|---|
| Rolling | Lo normal: cambios rutinarios | Vuelta atrás gradual, conviven versiones un rato |
| Blue-green | Cuando la vuelta atrás debe ser instantánea | Doble infraestructura mientras dura |
| Canary | Cambios con riesgo real o difícil de probar en staging | Necesita métricas por versión y paciencia |

Con canary, la palabra clave es **decidir con datos**: un porcentaje
pequeño de tráfico a la versión nueva, y se comparan errores 5xx y
latencia (mediana y p95) del canary contra el resto **en la misma
ventana de tiempo** y con tráfico suficiente para que el número diga algo.
Números, no sensaciones. Si el canary empeora, se revierte sin discusión y
se investiga en frío: «vamos a dejarlo un rato a ver» es como se convierte
un 5 % de usuarios afectados en un 100 %.

## 5. Healthcheck y readiness no son lo mismo

- **Liveness** contesta «¿el proceso vive?» y su fallo provoca un
  reinicio. Solo debe mirar el proceso mismo: si comprueba la base de
  datos y la base de datos parpadea, el orquestador reinicia TODAS las
  instancias a la vez y una avería pequeña se convierte en tormenta de
  reinicios.
- **Readiness** contesta «¿puedo recibir tráfico?» y su fallo solo saca a
  la instancia del balanceador. Aquí sí caben las dependencias: sin
  conexión a la base de datos, mejor no recibir peticiones.
- **Arranques lentos.** Si la aplicación tarda en calentar más que el
  plazo de la sonda, el orquestador la mata antes de terminar de arrancar.
  Síntoma: bucle de reinicios sin ningún error de aplicación en los logs.
  Se amplía el margen inicial (retardo o sonda de arranque), no se relaja
  la sonda de régimen normal.

Verificación concreta en staging: parar una dependencia y comprobar que la
instancia sale del balanceador (readiness) sin reiniciarse (liveness), y
que vuelve sola cuando la dependencia vuelve.

## 6. Deriva entre entornos

Si staging y producción divergen (versiones de servicios, variables de
entorno, volumen de datos), staging deja de predecir nada y el «en staging
iba» pierde todo su valor. Antes de confiar en una prueba de staging,
comparar: versiones desplegadas, configuración y variables lado a lado. Las
lecturas son gratis en este harness: comparar antes de desplegar no cuesta
nada y desmiente derivas que nadie recordaba.

## 7. Después de desplegar

Terminar de copiar archivos no es terminar el despliegue. Verificación
real, en este orden:

1. **La petición concreta** que motivó el cambio (el bug que se arregla, el
   endpoint nuevo), ejecutada contra producción.
2. **El healthcheck** de cada instancia, no solo del balanceador, y que la
   versión que responde sea la nueva (un endpoint de versión o el hash del
   commit en la respuesta lo zanja).
3. **Los logs los primeros minutos**, comparando la tasa de errores con la
   de la hora anterior: los fallos de despliegue buenos avisan enseguida,
   los malos avisan cuando ya te has ido.

Solo después de las tres cosas se declara victoria. Y si durante el proceso
apareció una particularidad del sitio (el servicio que tarda en arrancar,
la instancia que siempre va rezagada), se guarda con `learn`.

## Herramientas del harness

Todo lo que toca producción — el despliegue mismo, el rollback, las
migraciones, activar un flag global — va en `propose_plan`, con la vuelta
atrás escrita como parte del plan, no como nota al pie. Mirar estado, logs,
diffs y versiones es lectura y no necesita aprobación: agótala antes de
proponer nada.

## Lo que no se hace nunca

- Desplegar algo cuyo diff no se ha leído.
- Migración destructiva y código que la necesita en el mismo despliegue.
- Mantener un canary degradado «a ver si se estabiliza».
- Activar un flag y desplegar otro cambio en la misma ventana.
- Declarar el despliegue terminado sin haber lanzado la petición que
  fallaba.
