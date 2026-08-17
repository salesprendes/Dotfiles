---
name: "Planificar cambios"
description: "Convierte un encargo en un plan por fases verificables antes de escribir código. Úsala cuando el encargo sea grande o ambiguo, cuando el usuario diga «planifica esto», «cómo lo harías», «diseña el cambio», o antes de tocar varios archivos a la vez."
triggers: "planifica, planificar, plan, fases, hoja de ruta, disena, como lo harias, alcance, requisitos, antes de escribir codigo, por donde empiezo"
---

# Del encargo al plan

**Regla madre: el código más barato de arreglar es el que no se ha escrito — media hora de plan ahorra una tarde de deshacer.**

## Primero, entender el encargo de verdad

- **El problema detrás de la petición.** Muchas veces se pide una solución concreta («añade un botón») cuando el problema real («no encuentro X») tiene una salida mejor. Se pregunta por el problema, no solo por la petición recibida.
- **Qué NO pide.** El alcance se respeta en las dos direcciones: ni recortarlo en silencio ni inflarlo con mejoras que nadie pidió. Cada «ya que estoy» es riesgo gratis y revisión más cara.
- **Las preguntas que separan dos diseños distintos se hacen ANTES**, con `ask_user`. Si la respuesta cambia la arquitectura (¿esto es por usuario o global?, ¿tiene que sobrevivir a un reinicio?), descubrirla a mitad de faena cuesta rehacer. Las dudas menores que no cambian el diseño se anotan y se deciden sobre la marcha, sin interrumpir.
- **Puertas de un solo sentido.** Lo reversible (un nombre interno, un texto, la forma de un componente) se decide rápido y se cambia si molesta. Lo difícil de deshacer (un formato de datos que se persiste, un contrato de API que otros consumen, un esquema de base de datos) se piensa dos veces, porque una vez hay datos escritos o clientes enganchados ya no hay tecla de deshacer. Las preguntas de `ask_user` se gastan ahí, no en los colores.

## Explorar lo existente antes de diseñar

Leer es gratis: antes de inventar, mira cómo resuelve ya el proyecto los problemas parecidos. La mitad de los «diseños nuevos» son un componente existente sin descubrir: un patrón de panel, un servicio, una utilidad que ya hace el 80 %. Seguir la convención de la casa vale más que una idea mejor que desentona, porque el que mantenga esto mañana conoce la convención, no tu idea. Lo que descubras del proyecto y vaya a servir otra vez (dónde viven las cosas, qué patrón siguen), guárdalo con `learn`.

**Medir el radio de la onda expansiva** antes de decidir el enfoque: un `grep_files` del símbolo que se quiere cambiar y contar los puntos de uso. Cambiar una firma usada en 3 sitios se hace del tirón. Usada en 40, pide otra estrategia: la función nueva convive con la vieja, los usos migran por tandas con el proyecto funcionando entre tanda y tanda, y la vieja se borra al llegar a cero. El número decide el plan, y averiguarlo cuesta un minuto de lectura.

**Cuando una incógnita técnica bloquea el diseño** («¿esta biblioteca soporta streaming?», «¿aguanta este formato acentos?»), la respuesta no sale de debatir: sale de un spike, un prototipo desechable con caja de tiempo de media hora que responde la pregunta. El código del spike se tira sin pena, porque su producto es la respuesta, no el código.

## El plan por fases

- **Cada fase deja el proyecto FUNCIONANDO.** Nada de «fase 1: romperlo todo, fase 3: recomponerlo». Si algo interrumpe el trabajo entre fases, lo que haya en el disco tiene que arrancar y pasar sus pruebas.
- **Cada fase lleva su criterio de verificación escrito**: un comando concreto y qué debe decir, no una sensación. «La fase 2 está hecha cuando `pytest tests/api` pasa y el panel abre sin errores en consola» es verificable. «La fase 2 está hecha cuando quede bien» no lo es.
- **La primera fase, vertical si se puede**: el caso más simple atravesando todas las capas de punta a punta (un esqueleto que anda), antes que una capa entera perfecta. Los problemas de integración son los caros, y una fase vertical los destapa el primer día en vez de esconderlos detrás del «ya lo juntaremos al final».
- **De menos a más riesgo** cuando el orden lo permita: primero lo reversible y barato, lo delicado al final, cuando ya hay más información y más red.
- En este harness el plan se propone con `propose_plan` y nada gordo se ejecuta sin aprobación. Las lecturas exploratorias no la necesitan: explorar primero, proponer después.

## YAGNI

Lo que «quizá haga falta luego» no se construye hoy: se anota en el plan como extensión posible y se deja el diseño abierto a ella si sale gratis, pero no se paga por adelantado. La abstracción prematura es más cara de deshacer que la duplicación que pretendía evitar, porque la duplicación se ve y la abstracción equivocada se hereda.

## Señales de que el plan es malo

- Una fase sin forma de verificarse. Si no puedes escribir el comando que la da por buena, no sabes qué estás construyendo en ella.
- Una fase cuyo resultado es una lista de archivos tocados y no un comportamiento observable: «modificar A, B y C» no es un objetivo, es un diff sin motivo.
- Un «y de paso» dentro de cualquier fase.
- Más de cinco o seis fases: casi siempre son dos encargos con un solo título, y partirlos da dos planes que sí caben en la cabeza.
- No poder explicar el cambio entero en dos frases: o no está entendido, o en realidad son dos cambios y hay que partirlos.
- Empezar a escribir código en la fase 1 sin haber leído el código existente que toca.
- Una migración de datos que aparece de pasada dentro de una fase de código. Los datos persistidos merecen fase propia, con su vuelta atrás pensada, porque el código se revierte con git y los datos no.

## Verificación final

- El plan responde a la petición original releída palabra por palabra: es fácil acabar resolviendo un problema adyacente al pedido.
- Cada fase tiene su comando de verificación escrito.
- Las preguntas de diseño están respondidas o formuladas con `ask_user`, no enterradas en un supuesto silencioso.
- Si el plan sustituye algo, la última fase incluye el criterio numérico de terminado: el `grep_files` del símbolo viejo devolviendo cero usos, no la memoria de haberlos migrado todos.
- El plan cabe en `propose_plan` tal cual: fases, comandos y qué toca cada una.
