---
name: Refactorizar sin romper
description: Refactoriza código sin cambiar el comportamiento, en pasos pequeños con verificación entre medias. Úsala cuando el usuario diga «refactoriza», «limpia este código», «extrae la función», «renombra esto», «este archivo es un lío», o quiera migrar de código viejo a nuevo sin romper.
---

# Refactorizar sin romper

**Regla madre: refactorizar es cambiar la FORMA sin cambiar el comportamiento — si no hay manera de demostrar que el comportamiento no cambió, todavía no toca refactorizar: toca construir esa red.** La red son tests que cubran lo que se va a mover o, como mínimo, una prueba de humo reproducible: un comando que ejercita el código y cuya salida se guarda y se compara antes y después.

## Nunca mezclar refactor y funcionalidad

Un cambio es refactor o es funcionalidad, jamás las dos cosas. Si a mitad del refactor aparece un bug, se anota y se arregla APARTE, en su propio cambio con su propio test. Arreglarlo «de paso» convierte el diff en ilegible (¿qué línea es limpieza y cuál es arreglo?) y el fallo en imposible de acotar: si algo se rompe después, no se sabe si fue la forma o el comportamiento. La misma regla al revés: en mitad de una funcionalidad no se «aprovecha para limpiar».

## Pasos pequeños con verificación entre medias

Renombrar, extraer función, mover archivo: cada paso compila y pasa los tests antes del siguiente. El porqué es práctico, no estético: diez pasos verificados se depuran solos, porque el paso que rompió es siempre el último, mientras que un salto grande que rompe obliga a bisecar a mano lo que la disciplina daba gratis. Confirmar cada paso que queda en verde regala puntos de retorno baratos.

## El patrón estrangulador para lo grande

Cuando el refactor no cabe en pasos pequeños (sustituir un módulo entero, cambiar una API con muchos usos), lo nuevo crece AL LADO de lo viejo:

1. La pieza nueva se construye junto a la vieja, con sus tests, sin tocar aún a nadie.
2. Los usos migran de uno en uno, verificando cada migración por separado.
3. Lo viejo se borra al final, cuando ya nadie lo llama — y eso lo confirma `grep` sobre todo el proyecto, no la memoria. El uso olvidado en un archivo que nadie abrió es el fallo clásico de esta técnica.

Durante la convivencia las dos piezas existen y el proyecto funciona en todo momento. Un refactor de este tamaño se propone antes con `propose_plan`: orden de migración y comando de verificación de cada paso.

## Las rarezas del código viejo son cicatrices

Antes de «limpiar» una línea rara (un caso especial inexplicable, un límite arbitrario, un orden de llamadas sospechoso), `git blame` sobre ella y leer la confirmación que la introdujo. Muchas de esas rarezas están arreglando un fallo real que costó encontrar, y borrarlas lo resucita. Si tras investigar sigue sin explicación, se quita, pero con un test que cubra la zona y anotando el motivo en el mensaje de la confirmación. El porqué de una rareza del proyecto, una vez averiguado, se guarda con `learn` para no repetir la arqueología.

## Cuándo NO refactorizar

- **Sin red de pruebas.** Primero la red, luego el refactor. Es la regla madre y no tiene excepciones.
- **Mezclado con un despliegue o un arreglo urgente.** Lo urgente sale limpio y mínimo, para poder revisarlo y revertirlo con facilidad. El refactor espera a mañana.
- **Código que funciona y nadie va a tocar.** Refactorizar tiene un coste cierto y un beneficio que solo se cobra si alguien vuelve a ese código. Feo pero estable y sin visitas previstas: se deja en paz.

## Verificación final

- El diff se lee ENTERO antes de dar el trabajo por terminado: cada línea tiene que ser explicable como cambio de forma, ninguna como cambio de comportamiento.
- Mismos tests verdes antes y después. Mismos, no «los que quedaron»: ningún test borrado, debilitado ni omitido por el camino.
- Ninguna sonda olvidada: ni impresiones de depuración, ni código viejo comentado «por si acaso» — para eso está el historial de git.
- Si hubo estrangulador, `grep` confirma que del nombre viejo no queda ni una referencia.
