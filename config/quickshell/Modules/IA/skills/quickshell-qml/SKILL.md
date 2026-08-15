---
name: "Quickshell y QML"
description: "Cómo trabajar en la configuración de Quickshell del usuario (~/.config/quickshell) sin romperla: cómo verificar un cambio, y las trampas de QML que ya han costado un fallo real aquí. Úsala antes de editar cualquier .qml o .js de este shell."
---

# Quickshell y QML

Esta configuración es el escritorio del usuario **en marcha**. Un error de
sintaxis no da un mensaje amable: deja la barra en negro. Por eso aquí se
verifica siempre.

## Verificar un cambio (en este orden)

1. `qmllint -I . <archivo>` desde `~/.config/quickshell`. Las quejas de
   `qs.Config` / `qs.Components` no se pueden resolver (los módulos son del
   propio shell) y son ruido normal: lo que importa son los errores de
   sintaxis.
2. El shell recarga solo al guardar. Míralo con `qs log`: buscas
   `Configuration Loaded` sin errores detrás.
3. Para comprobar que algo FUNCIONA, no que compila: pon un `console.log`
   temporal con una marca (`SONDA1 …`), recarga, léelo con `qs log`, y
   **quítalo**. Es la única forma fiable de ver el estado interno.

## Trampas que ya han mordido aquí

- **`grep` calla en archivos con líneas larguísimas**: usa `grep -a` con
  `AiService.qml`, o creerás que algo no existe.
- **Un `ListModel` congela sus roles con la PRIMERA fila.** Si un `append`
  no trae todos los campos, ese rol deja de existir para siempre. Por eso
  todos los mensajes se añaden por una sola función.
- **`JsonAdapter` propaga sus escrituras un tick TARDE.** Leer la propiedad
  justo después de asignarla devuelve el valor viejo, y dos escrituras en el
  mismo tick se pisan. Solución ya usada: una copia local que manda, y el
  adaptador solo para persistir.
- **`FileView` no crea la carpeta padre** al escribir.
- Un `.js` con `.pragma library` **no ve** el árbol QML, ni `Settings`, ni
  `Quickshell.env`, ni `Qt.*`. Solo funciones puras.
- En un `Instantiator`, `modelData` llega como propiedad de contexto: NO se
  declara con `required property`.
- Los `Process` son la forma de hablar con el sistema: `SplitParser` para
  leer línea a línea (streaming) y `StdioCollector` para la salida entera.
- **Dos `Component.onCompleted` en el mismo objeto** dan
  `Property value set multiple times` y tumban la carga del archivo entero.
  Las inicializaciones nuevas van DENTRO del que ya existe.
- **El watcher de recarga solo mira `.qml` y `.js`**: editar un `SKILL.md`
  o un `.json` no recarga nada, y `touch` a secas tampoco (vigila
  contenido, no fechas). Para probar una recarga, cambia contenido real.
- **En sesiones largas el watcher puede morir**: el shell responde a
  `qs ipc` pero deja de cargar cambios y `qs log` deja de crecer. La
  comprobación barata es cambiar un texto visible y mirar la pantalla. El
  remedio es reiniciar quickshell — es el escritorio en marcha del
  usuario: preguntar antes.
- Para animar apariciones, la casa ya tiene el patrón: un escalar 0→1 con
  `Behavior` y la geometría derivada de él (ver `ExpandableDetail` y
  `Theme.revealOpacity`) — no se apilan `visible` + animaciones sueltas.

## Trampas de QML en general (muerden en cualquier proyecto)

- **Una asignación imperativa MATA el binding para siempre.** `ancho = 200`
  en un manejador destruye el `ancho: otro.ancho` declarativo, y la
  propiedad deja de seguir a su fuente sin aviso ninguno. Síntoma: «esto
  se actualizaba solo y dejó de hacerlo después de X». Diagnóstico: buscar
  asignaciones `=` a esa propiedad en los manejadores. Arreglo: derivar de
  una propiedad de estado (`ancho: abierto ? 200 : 80`) y cambiar SOLO el
  estado, o un elemento `Binding {}` explícito.
- **`Binding loop detected for property`** en `qs log`: A depende de B y B
  de A, casi siempre con alturas (el contenedor mide a sus hijos y un hijo
  se mide contra el contenedor). La regla que lo corta: un componente
  define su `implicitHeight`/`implicitWidth` (lo que MIDE su contenido) y
  quien lo coloca decide `height`/`width`. Mezclar los dos planos es el
  origen de casi todos los bucles.
- **`property var` no notifica cambios internos**: `lista.push(x)` o
  `obj.n++` no dispara ningún binding. Se reasigna entero:
  `lista = lista.concat([x])`. (Pariente de la trampa del ListModel de
  arriba: el estado compartido cambia por reemplazo, no por mutación.)
- **`Loader`**: mientras `active` es false o con `asynchronous: true` a
  medio cargar, `item` es null — todo acceso lleva guarda
  (`loader.item?.algo`) o va en `onLoaded`. Para pasar valores iniciales,
  `setSource("Cosa.qml", { valor: 3 })` evita el parpadeo de crear con
  valores por defecto y corregir un tick después.
- **Los manejadores `onXChanged` saltan ya durante la construcción**, con
  medio árbol aún sin existir: guarda de null en la primera línea.
- **Dentro de un Layout mandan las `Layout.*`**: anclar un hijo de
  `ColumnLayout` con `anchors` pelea con el layout (aviso en el log y
  geometría errática). `Layout.fillWidth` y compañía, o fuera del layout.
- **Señales que llegan tarde**: un `Process` puede terminar cuando el panel
  que lo lanzó ya no existe, y su manejador toca objetos muertos
  (`TypeError: Cannot read property ... of null` en el log). Los `Process`
  que sobreviven a la vista van en un servicio/Singleton, no en el panel.
- En delegados de `Repeater`/`ListView` los datos del modelo SÍ se
  declaran con `required property` — justo al revés que en `Instantiator`
  (arriba). Copiar un delegado de un contexto al otro sin revisar esto
  acaba en `modelData` indefinido.
- **`console.log(objeto)` enseña `QObject(0x…)`**, no el contenido. Para
  datos planos, `JSON.stringify(obj)`. Para un objeto QML, imprimir las
  propiedades sueltas que interesen.

## Estilo de la casa

- **Comentarios y textos en castellano.** Los comentarios explican POR QUÉ,
  no qué hace la línea siguiente.
- Las duraciones de animación salen de `Theme` (`animFast`, `animNormal`,
  `animLoop`), nunca números sueltos.
- Los tamaños pasan por `Theme.dp()` / `Theme.sp()`, y los colores por
  `Theme.*` y `SettingsPalette.*`.
- Todo texto visible va en `I18n.tr("…")`, con su traducción añadida a
  `Config/I18n.qml` (es y ca).
- Antes de crear un componente, mira `Components/`: casi seguro ya existe
  (`TextField`, `SwitchRow`, `SegRow`, `IconButton`, `Hint`, `EmptyNote`…).

## Antes de tocar

Lee el archivo entero, no solo el trozo. Y si el cambio es grande o toca
algo que el usuario usa a diario (barra, ajustes, asistente), propón el plan
primero: aquí un fallo se nota en la pantalla, no en un test.
