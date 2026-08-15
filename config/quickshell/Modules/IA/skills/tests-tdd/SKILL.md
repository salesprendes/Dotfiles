---
name: "Tests y TDD"
description: "Escribe tests que demuestran comportamiento y guía el ciclo TDD: rojo, verde, limpiar. Úsala cuando el usuario diga «escribe los tests», «haz TDD», «testea esto», «este test es flaky», «sube la cobertura» o al arreglar un bug que necesita test de regresión."
---

# Tests que valen y TDD pragmático

**Regla madre: un test que nunca has visto fallar no demuestra nada, porque puede estar pasando por accidente.** Todo lo demás es consecuencia de esa frase: cada test se ejecuta en rojo antes de dar por bueno su verde.

## El ciclo, en orden y sin saltarse pasos

1. **Escribe el test primero** y ejecútalo. Tiene que fallar **con el mensaje esperado**: la aserción concreta que describe el comportamiento que falta. Si falla por otra cosa (una importación rota, un nombre mal escrito, un fallo al montar el entorno), el test está mal y no vigila nada. Se corrige hasta que el rojo sea el rojo correcto.
2. **Escribe el mínimo código que lo pone en verde.** Mínimo de verdad, sin adelantar casos que ningún test pide todavía.
3. **Refactoriza con la red puesta.** Con el verde en la mano se limpian nombres, duplicación y estructura, ejecutando la suite tras cada retoque.

Para el ciclo corto valen dos banderas de pytest: `-x` para en el primer rojo y `--lf` repite solo lo que falló la última vez. Ejecutar tests es lectura barata: hazlo tantas veces como haga falta sin pedir permiso. Si descubres una manía del proyecto (el ejecutor exacto, una variable de entorno obligatoria, un test que necesita la base de datos local), guárdala con `learn` para la próxima vez.

## Qué se prueba

- **El contrato, no las tripas.** Se afirma lo observable desde fuera: entradas, salidas, efectos visibles y errores. Un test acoplado a la implementación (que espía métodos internos o comprueba el orden de llamadas privadas) se rompe con cada refactor legítimo y acaba borrado o ignorado, que es peor que no tenerlo.
- **Los bordes, siempre.** Vacío, cero, negativo, uno, muchos, Unicode con acentos y emoji, y el error esperado: qué pasa con la entrada inválida tiene que decirlo un test, no la suerte.
- **Un test = una afirmación de comportamiento**, con un nombre que se lee como una frase: `test_rechaza_importe_negativo`, no `test_caso_3`. Cuando falle dentro de seis meses, el nombre es el diagnóstico.

## Fixtures y parametrización

Diez tests clónicos que solo cambian el dato son una tabla disfrazada. Parametrizar los convierte en filas, y cada fila falla por separado con su valor en el nombre:

```python
import pytest

@pytest.mark.parametrize("texto, esperado", [
    ("", 0),
    ("a", 1),
    ("año 🎉", 5),
])
def test_cuenta_caracteres(texto, esperado):
    assert cuenta(texto) == esperado
```

La trampa de parametrizar: meter en la misma tabla entradas que en realidad ejercitan comportamientos distintos. Si dos filas piden aserciones diferentes, son dos tests con nombre propio, no dos filas.

Con las fixtures, la palabra peligrosa es el ámbito. Por defecto es `function` (se reconstruye para cada test) y eso es lo correcto casi siempre. Subir a `session` para acelerar solo vale con recursos de solo lectura: **una fixture de sesión mutable es la fábrica número uno de tests dependientes del orden**, porque el test A deja migas que el test B se encuentra. Síntoma inconfundible: el test pasa ejecutado solo y falla dentro de la suite, o al revés. Diagnóstico: ejecutarlo aislado (`pytest tests/test_x.py::test_y`) y comparar resultados con la suite completa.

## Propiedades además de ejemplos

Un test de ejemplo fija un caso concreto. Un test de propiedad afirma una ley para TODAS las entradas y deja que la biblioteca (Hypothesis en Python) busque el contraejemplo:

```python
from hypothesis import given, strategies as st

@given(st.text())
def test_ida_y_vuelta(s):
    assert descodifica(codifica(s)) == s
```

Leyes que suelen pagar el billete: ida y vuelta (serializar y recuperar lo mismo), invariantes (la salida ordenada conserva la longitud y los elementos), y equivalencia con una implementación tonta pero obviamente correcta. Cuando la herramienta encuentra un fallo lo encoge hasta el contraejemplo mínimo: ese valor exacto se fija después como test de ejemplo normal, para que quede de regresión aunque la generación aleatoria no vuelva a pisarlo. Dónde rinden: analizadores, serializadores, cálculo, cualquier función con una ley enunciable. Dónde no: código pegamento de una rama por caso, donde la propiedad acaba reimplementando la función que prueba.

## Dobles de prueba con mesura

Simular la red y el reloj: sí, porque son lentos, no deterministas y ajenos al código que se prueba. Casi todo lo demás se usa de verdad. Cuando se simula cada colaborador, el test deja de comprobar comportamiento y pasa a ser un espejo de la implementación que asiente a todo: cambias el código, cambias los dobles para que cuadren, y ese verde ya no significa nada.

## Tests flaky

Un test intermitente depende de la hora, del orden de ejecución o de un `sleep`. Confirmarlo y medir cómo de grave es cuesta un minuto:

```sh
for i in $(seq 20); do pytest tests/test_sospechoso.py -q || break; done
```

Si de veinte pasadas falla alguna, es flaky confirmado, y la proporción dice cuánto. El arreglo por causa:

- **Depende del tiempo**: nunca subir el `sleep`. Se **espera una condición, no un plazo** (reintentar hasta que el archivo exista o el puerto responda, con tope), porque el `sleep` que va en tu máquina falla en el runner cargado del CI.
- **Depende del orden**: comparte estado con otro test (fixture mutable de sesión, base de datos sin limpiar, variable global). Se aísla el estado, no se fija el orden.
- **Depende de la hora o del azar**: el reloj se inyecta y se congela, la semilla del generador aleatorio se fija.

Un flaky tolerado entrena a todo el mundo a ignorar el rojo, y ese hábito se acaba cobrando un bug real.

## La trampa de la cobertura

El 100 % de líneas con aserciones vacías es cero cobertura real: ejecutar una línea no es comprobarla. La cobertura sirve para encontrar lo que NO está probado, nunca como objetivo en sí. Un test sin aserción (o con un `assert True` de adorno) se completa o se borra, pero no se cuenta.

## Al arreglar un bug

Primero el test que lo reproduce, ejecutado para verlo fallar exactamente como falla el bug. Luego el arreglo, y el test pasa. En ese orden y no al revés: así el bug no puede volver sin que un test avise, y el rojo inicial demuestra que el test de verdad captura el problema y no un vecino suyo. Si el bug lo encontró una herramienta de propiedades, el contraejemplo mínimo que escupió es literalmente el test de regresión: se copia tal cual.

## Verificación final

- La suite entera en verde, no solo el test nuevo.
- Retira el arreglo un momento (con `git stash` vale): el test nuevo tiene que volver al rojo. Si no vuelve, no vigila nada.
- Si hubo arreglo de flaky, el bucle de veinte pasadas otra vez: veinte de veinte en verde, no «ya no me ha fallado».
- Ningún test quedó marcado como omitido «temporalmente»: eso es un agujero en la red con fecha de olvido.
