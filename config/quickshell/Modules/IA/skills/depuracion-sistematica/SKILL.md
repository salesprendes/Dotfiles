---
name: "Depuración sistemática"
description: 'Método para encontrar la causa REAL de un fallo en vez de parchear síntomas: reproducir, acotar, formular una hipótesis que se pueda falsar y comprobarla. Úsala siempre que algo "no funciona", falla, se cuelga o da un resultado raro.'
---

# Depuración sistemática

**La tentación es cambiar algo que parezca sospechoso y volver a probar. Eso
no es depurar: es barajar.** A veces sale, y entonces es peor, porque el
fallo vuelve la semana que viene con otra cara.

## 1. Reproducir antes que entender

Si no puedes provocar el fallo a voluntad, no puedes saber si lo has
arreglado. Consigue **el comando exacto, la entrada exacta y el error
exacto** — pídelos al usuario con `ask_user` si no los tienes. Adivinarlos
cuesta más que preguntarlos.

## 2. Leer el error entero, y de verdad

El mensaje útil casi nunca es la última línea. En una cascada, la causa está
ARRIBA: el resto son consecuencias. Lee la traza completa y localiza la
primera cosa que ya no era como debía. Además:

- Copia el mensaje EXACTO, no lo parafrasees: «no such file» y «permission
  denied» llevan a sitios distintos, y «connection refused» no es
  «connection timed out».
- Busca el texto literal del error en el código (`grep_files` con el trozo
  más raro del mensaje): saber QUIÉN lo emite acota media búsqueda.
- Los números del mensaje son datos, no decorado: la línea, la ruta, el
  código de error. Úsalos.

## 3. Acotar por mitades

Divide el camino en dos y averigua en cuál de las mitades vive el fallo.
Repite. En cuatro o cinco cortes se pasa de "algo en el proyecto" a "esta
línea". Herramientas: `grep_files` para encontrar el sitio, `read_file` con
`offset`/`limit` para leer alrededor, y la historia (`git_log`,
`git_file_history`, `git_blame`) para saber cuándo dejó de funcionar.

El corte por mitades vale para CUALQUIER espacio, no solo commits: comenta
la mitad de la configuración, reduce la entrada a la mitad, desactiva la
mitad de las extensiones. **Reducir la reproducción ya es avanzar** aunque
todavía no entiendas nada: un fallo que se reproduce con cinco líneas de
entrada casi se explica solo.

Si el fallo es reciente y antes iba: la pregunta correcta es **qué cambió**,
no qué está mal. `git_diff` y `git_log` contestan eso en un minuto.

## 4. Hipótesis falsable — y UNA cada vez

Escríbela como una frase que se pueda demostrar FALSA:

> "Falla porque la ruta llega vacía cuando el usuario no pasa `--config`."

Y ahora diseña la comprobación más barata que la mate. Si tu hipótesis no se
puede refutar con una prueba, todavía no es una hipótesis: es una corazonada.

La disciplina del experimento:

- **Un cambio por experimento.** Si tocas dos cosas y mejora, no sabes cuál
  fue, y ya tienes un cambio supersticioso en el código.
- **Escribe la predicción ANTES de mirar** («si es esto, el print saldrá
  vacío»). Si miras primero, cualquier resultado te parecerá compatible.
- **Deshaz el experimento fallido** antes del siguiente. Los restos de
  experimentos son la fuente clásica de «ahora falla distinto».
- **Apunta hipótesis → predicción → resultado.** Con tres experimentos ya
  no te acuerdas de qué descartaste.

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

## Cuando ninguna hipótesis sobrevive

Tras dos o tres hipótesis muertas, deja de proponer causas y cuestiona el
suelo que pisas. Las suposiciones que MÁS veces resultan falsas:

- **No se está ejecutando el código que editas.** Mete un print
  inconfundible (o un error de sintaxis) en la primera línea: si no
  aparece, ahí estaba todo. Causas típicas: compilación vieja, caché, otro
  archivo homónimo, o `command -v programa` apunta a otro binario.
- **El servicio no releyó la configuración.** Editar el archivo no basta:
  recarga o reinicia, y si la herramienta sabe enseñar su configuración
  EFECTIVA, pídesela en vez de suponerla.
- **El entorno no es el que crees.** Versión exacta, directorio de trabajo,
  variables de entorno, usuario con el que corre.
- **Los datos no son los que crees.** Imprime la entrada real justo antes
  del punto que falla, no la que «debería» llegar.

## Fallos intermitentes

- Si añadir un print hace desaparecer el fallo, sospecha de una carrera
  entre hilos o procesos: el print cambió los tiempos.
- Si falla «a veces», mide la frecuencia ANTES de tocar nada, o nunca
  sabrás si tu arreglo la bajó o tuviste suerte:

```sh
for i in $(seq 50); do ./reproducir >/dev/null 2>&1 || echo "fallo $i"; done
```

## Cuándo parar y replantear

Ponte un tope (tres hipótesis muertas o media hora dando vueltas). Al
llegar:

1. Escribe qué sabes SEGURO (con su prueba al lado) y qué estás suponiendo.
2. La causa vive casi siempre en la columna de suposiciones: verifica la
   más barata.
3. Si aun así nada, reduce la reproducción al mínimo, cuenta al usuario lo
   descartado y pide contexto con `ask_user`. Retirarse con un mapa es
   progreso, seguir barajando no.

## Señales de que estás barajando

- Llevas tres cambios y sigues sin saber por qué fallaba.
- Has dicho "probemos a ver si con esto".
- Arreglaste algo y no sabes explicar por qué funcionaba antes.

En cualquiera de los tres casos: para, vuelve al paso 1 y reproduce.
