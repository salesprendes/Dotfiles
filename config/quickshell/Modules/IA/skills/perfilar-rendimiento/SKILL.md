---
name: Perfilar rendimiento
description: Perfila el código antes de optimizar y demuestra la mejora con mediciones. Úsala cuando algo «va lento», «tarda mucho», «se come la CPU», haya que perfilar un script Python o un proceso, comparar tiempos con hyperfine, o decidir si una optimización merece la pena.
---

# Perfilar antes de optimizar

**Regla madre: la intuición sobre dónde se va el tiempo falla sistemáticamente — se mide primero, se optimiza lo que la medición señala, y se vuelve a medir para demostrar la mejora.** Casi todo el tiempo vive en un puñado de sitios: el perfil los encuentra en minutos, la intuición los busca durante días y suele acusar al inocente.

## Medir bien

- **Comparar comandos: `hyperfine`**, nunca una ejecución suelta.

  ```sh
  hyperfine --warmup 3 'comando_a' 'comando_b'
  ```

  El calentamiento absorbe la caché fría de disco y las repeticiones dan media y desviación. Una sola ejecución mide el estado del sistema en ese instante, no el comando.

- **`time` y su desglose**: `real` es reloj de pared, `user` es CPU en tu código, `sys` es CPU en el núcleo. **`real` alto con `user` bajo significa que el proceso ESPERA** (disco, red, otro proceso), y optimizar la CPU ahí es inútil: hay que ir a buscar la E/S.

- **Python en vivo: `py-spy`**, sin tocar el código ni reiniciar el proceso.

  ```sh
  py-spy top --pid 1234
  py-spy record -o llama.svg --pid 1234
  ```

  `top` enseña en qué funciones está el tiempo ahora mismo y `record` genera el gráfico de llama para ver el reparto entero. Es solo lectura del proceso, aunque acoplarse a uno ajeno puede pedir privilegios.

- **Código nativo en Linux: `perf top`**, para ver en qué símbolos arde la CPU de la máquina.

Medir es lectura y no necesita aprobación. Las manías de cada máquina (qué herramienta está instalada, qué proceso es el sensible) se guardan con `learn`.

## El número de ANTES

Antes de tocar nada se apunta el comando exacto de medición y su tiempo. «Va más rápido» sin número es una sensación, y las sensaciones mejoran solas cuando uno acaba de trabajar en algo. La demostración es siempre la misma: mismo comando, mismos datos, número de antes contra número de después.

## La jerarquía de las optimizaciones

En este orden, porque cada nivel rinde un orden de magnitud más que el siguiente:

1. **El algoritmo.** Un bucle N² sobre datos que crecen gana a cualquier microoptimización: buscar en una lista dentro de un bucle contra buscar en un conjunto o diccionario, ordenar una vez fuera contra ordenar en cada vuelta. Si los datos van a crecer, este nivel es el único que importa.
2. **No repetir trabajo.** Cachear lo caro que no cambia, con la pregunta obligatoria ANTES de escribir la caché: ¿cuándo se invalida? Una caché sin plan de invalidación es un bug futuro con fecha aleatoria.
3. **La E/S.** Agrupar llamadas (una consulta de mil filas y no mil de una), no leer el mismo archivo mil veces, escribir por lotes.
4. **Microoptimizar**, solo al final y solo si el perfil, vuelto a pasar, sigue señalando ese punto.

## Cuándo parar

Cuando ya es suficientemente rápido para su uso real. Un informe nocturno que tarda dos minutos no necesita bajar a diez segundos: nadie lo está mirando. El último 20 % de mejora suele costar el 80 % de la legibilidad, y esa deuda la paga el siguiente que lea el código, que probablemente serás tú.

## Lo que no se hace

- **Optimizar sin medir.** Es la regla madre al revés y falla por la misma razón: se optimiza el sitio equivocado y se complica el código a cambio de nada.
- **Cachear sin plan de invalidación.** Se acaba sirviendo dato viejo y nadie sabe por qué ese usuario ve otra cosa.
- **Sacrificar claridad por una mejora que ningún usuario notará.** Un 3 % en un camino frío no compra un archivo ilegible.
- **Perfilar producción sin avisar.** `py-spy` y `perf` son de bajo impacto, pero en una máquina cargada de un panel se avisa antes, y si hay que instalar herramientas o subir privilegios, va en `propose_plan`.

## Verificación final

- Número de antes y número de después, con el mismo comando y los mismos datos, y la mejora dicha en cifras.
- Los tests siguen en verde: una optimización que cambia el resultado no es una optimización, es un bug rápido.
- El perfil de después ya no señala el punto optimizado. Si señala el siguiente cuello, se anota — no se persigue hoy.
