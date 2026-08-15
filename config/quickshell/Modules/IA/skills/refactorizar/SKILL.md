---
name: "Refactorizar sin romper"
description: "Refactoriza código sin cambiar el comportamiento, en pasos pequeños con verificación entre medias. Úsala cuando el usuario diga «refactoriza», «limpia este código», «extrae la función», «renombra esto», «este archivo es un lío», o quiera migrar de código viejo a nuevo sin romper."
---

# Refactorizar sin romper

**Regla madre: refactorizar es cambiar la FORMA sin cambiar el comportamiento — si no hay manera de demostrar que el comportamiento no cambió, todavía no toca refactorizar: toca construir esa red.** La red son tests que cubran lo que se va a mover o, como mínimo, una prueba de humo reproducible: un comando que ejercita el código y cuya salida se guarda y se compara antes y después.

## Sin tests: la red se teje con tests de caracterización

Cuando el código no tiene tests, el primer paso no es escribirlos «bien»: es capturar el comportamiento ACTUAL, bugs incluidos, y convertirlo en oráculo.

```sh
python3 informe.py datos_prueba.csv > /tmp/antes.txt    # antes de tocar nada
python3 informe.py datos_prueba.csv > /tmp/despues.txt  # tras cada paso
diff /tmp/antes.txt /tmp/despues.txt                    # vacío, o no hay trato
```

Si la salida lleva fechas, horas o identificadores aleatorios, se normalizan antes de comparar (un `sed` que las sustituya por una marca fija), o el diff dará falsas alarmas y se dejará de mirar, que es peor que no tenerlo. Y antes de fiarse de una suite existente, comprobar que de verdad pisa la zona a mover: en Python, `coverage run -m pytest` y `coverage report` sobre el archivo afectado. Un refactor «cubierto» por tests que no ejecutan la rama movida da una seguridad falsa y carísima.

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

## El cambio paralelo para renombrar lo compartido

Renombrar algo con datos vivos detrás (una columna de base de datos, un campo de un JSON persistido, un parámetro de una API con clientes) no admite el renombrado directo: entre «ya escribo el nombre nuevo» y «ya leo el nuevo» circulan datos viejos. El orden seguro es expandir, migrar, contraer:

1. Se añade el nombre nuevo SIN quitar el viejo, escribiendo en los dos.
2. Los lectores migran al nuevo, de uno en uno y con verificación.
3. Se migran los datos ya guardados con el nombre viejo.
4. Solo entonces se deja de escribir el viejo y se elimina.

Saltarse el paso 3 es el fallo clásico: todo funciona con datos recién creados y revienta con el archivo de un usuario antiguo.

## Trampas que cambian el comportamiento sin querer

- **Renombrar a base de buscar y sustituir** alcanza cadenas, comentarios y símbolos parecidos, y NO alcanza las referencias dinámicas: `getattr`, claves de diccionario, señales invocadas por nombre, plantillas, archivos de configuración. El método: `grep -rn` del nombre viejo, leer CADA aparición y decidirla una a una. Al terminar, el viejo da cero apariciones y las del nuevo cuadran con las migradas — números, no memoria.
- **Cambiar `d["clave"]` por `d.get("clave")`** convierte un KeyError ruidoso en un None silencioso que explota tres funciones más lejos. La forma de fallar TAMBIÉN es comportamiento.
- **Extraer una función puede multiplicar trabajo**: si el trozo extraído consulta base de datos o disco y la extracción acaba dentro de un bucle donde antes se ejecutaba una vez, el refactor «limpio» acaba de fabricar un N+1. Tras extraer, mirar qué hace la función por dentro y desde dónde se la llama ahora.
- **Sustituir una lista por un conjunto** (por velocidad) cambia el orden de recorrido. Si la salida dependía de ese orden, el diff de humo lo cantará: entonces se decide si el orden era contrato o accidente, y si era contrato, se ordena explícitamente.
- **Mover código cambia el orden de inicialización**: imports con efectos, registros al cargar el módulo, singletons. Si un módulo hace algo al importarse, moverlo de sitio cambia el comportamiento sin tocar una línea suya.
- **Los textos de error y de registro son API** cuando alguien los analiza (un grep en un cron, una alerta que busca una frase exacta). Antes de «mejorar» un mensaje, grep de esa frase por el proyecto y por los scripts del sistema.

## Las rarezas del código viejo son cicatrices

Antes de «limpiar» una línea rara (un caso especial inexplicable, un límite arbitrario, un orden de llamadas sospechoso), `git blame` sobre ella y leer la confirmación que la introdujo. Muchas de esas rarezas están arreglando un fallo real que costó encontrar, y borrarlas lo resucita. Si tras investigar sigue sin explicación, se quita, pero con un test que cubra la zona y anotando el motivo en el mensaje de la confirmación. El porqué de una rareza del proyecto, una vez averiguado, se guarda con `learn` para no repetir la arqueología.

## Cuándo NO refactorizar

- **Sin red de pruebas.** Primero la red, luego el refactor. Es la regla madre y no tiene excepciones.
- **Mezclado con un despliegue o un arreglo urgente.** Lo urgente sale limpio y mínimo, para poder revisarlo y revertirlo con facilidad. El refactor espera a mañana.
- **Código que funciona y nadie va a tocar.** Refactorizar tiene un coste cierto y un beneficio que solo se cobra si alguien vuelve a ese código. Feo pero estable y sin visitas previstas: se deja en paz.

## Si aun así algo se rompió

Con cada paso confirmado en verde, encontrar el culpable es mecánico:

```sh
git bisect start
git bisect bad                 # aquí falla
git bisect good abc123        # aquí funcionaba
git bisect run ./humo.sh      # git encuentra la confirmación culpable solo
```

`git bisect run` necesita un comando que salga con 0 en verde y con otro código en rojo: la prueba de humo de la red sirve tal cual. Es el pago diferido de los pasos pequeños — sin ellos, bisect señala «el megacambio» y no dice nada útil.

## Verificación final

- El diff se lee ENTERO antes de dar el trabajo por terminado: cada línea tiene que ser explicable como cambio de forma, ninguna como cambio de comportamiento.
- Mismos tests verdes antes y después. Mismos, no «los que quedaron»: ningún test borrado, debilitado ni omitido por el camino.
- La prueba de humo da diff vacío contra la salida capturada antes de empezar.
- Ninguna sonda olvidada: ni impresiones de depuración, ni código viejo comentado «por si acaso» — para eso está el historial de git.
- Si hubo estrangulador o cambio paralelo, `grep` confirma que del nombre viejo no queda ni una referencia.
