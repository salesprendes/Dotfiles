---
name: Quickshell y QML
description: Cómo trabajar en la configuración de Quickshell del usuario (~/.config/quickshell) sin romperla: cómo verificar un cambio, y las trampas de QML que ya han costado un fallo real aquí. Úsala antes de editar cualquier .qml o .js de este shell.
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
