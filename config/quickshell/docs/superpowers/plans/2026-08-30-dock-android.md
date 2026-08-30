# Dock con diseño de Android — Plan de implementación

> **Para quien ejecute esto:** cada tarea acaba en algo comprobable por sí solo.
> Los pasos van con casilla (`- [ ]`) para ir marcándolos.

**Objetivo:** un dock por monitor en el borde inferior, con dos formas
(pastilla de tableta Android y hotseat del Pixel), que enseña las apps fijadas
y las abiertas, con todo configurable desde Ajustes.

**Arquitectura:** tres capas. `Config/DockCatalog.qml` son funciones puras
sobre arrays (probables sin pantalla); `Services/Dock.qml` es lo vivo
(toplevels de Wayland, datos de Hyprland, resolución de iconos);
`Modules/Dock/` es lo visual. La partición existe porque la fusión de listas
—fijadas + abiertas sin duplicar— es lo único que se equivoca de forma
invisible.

**Tecnología:** Quickshell 0.3.1, Qt 6.11.2, QML/QtQuick, layer-shell de
Wayland, Hyprland 0.56.2.

**Spec:** `docs/superpowers/specs/2026-08-30-dock-android-design.md`

## Restricciones globales

- **Este directorio NO es un repositorio git.** No hay pasos de commit. La
  puerta de cada tarea es `sh tests/correr.sh`, que corre `qmllint`,
  `qmlcarga`, `imports`, `t_busqueda.js`, `logica` y `jit`.
- **`Config/` no importa `qs.Services`.** Es la regla que mantiene cortado el
  ciclo de importaciones (ver la cabecera de `Config/Globals.qml`).
  `DockCatalog` no puede tocar `Services/Dock.qml` ni `NotifService`.
- **Comentarios y cadenas de interfaz en español.** El código sigue el estilo
  del resto: comentarios que explican *por qué*, no *qué*.
- **Toda cadena visible pasa por `I18n.tr()`**, con su entrada en español y
  catalán en `Config/I18n.qml`.
- **Nada de `visible: false` para apagar un subsistema.** `LazyLoader`, como
  hacen la isla y los popups.
- **Se respeta `Theme.animNormal === 0`**: sin `Behavior`, salto seco.
- **Tope de 32 apps fijadas**, constante `DockCatalog.maxPinned`.
- Quickshell **reutiliza los singletons cuya fuente no ha cambiado** al
  recargar: para forzar uno nuevo hay que cambiar bytes del archivo, no
  `touch`.

---

## Estructura de archivos

| archivo | responsabilidad |
|---|---|
| `Config/DockCatalog.qml` | funciones puras: sanear, normalizar claves, fusionar, mover |
| `Services/Dock.qml` | toplevels vivos, claves de app, iconos, avisos, acciones |
| `Modules/Dock/DockWindow.qml` | superficie por monitor: capa, máscara, geometría, revelado |
| `Modules/Dock/Dock.qml` | la pastilla o barra: fondo, fila desplazable, separador |
| `Modules/Dock/DockSeparator.qml` | la rayita entre fijadas y abiertas |
| `Modules/Dock/DockButton.qml` | un icono: lupa, pulsación, indicador, globo, arrastre |
| `Modules/Dock/DockPreview.qml` | globo con las ventanas abiertas de una app |
| `Modules/Dock/DockMenu.qml` | menú contextual |
| `Panels/SettingsPages/DockPage.qml` | la página de Ajustes |
| `Panels/SettingsPages/DockPinEditor.qml` | lista arrastrable de fijadas + buscador |

---

## Tarea 1 · `DockCatalog`, con sus pruebas primero

Es la base de todo lo demás y lo único probable sin pantalla. Va primero y va
por TDD de verdad: las pruebas antes que el archivo.

**Archivos:**
- Crear: `Config/DockCatalog.qml`
- Modificar: `tests/logica.qml` (nueva `pruebaDock()`, registrada en
  `Component.onCompleted` tras `pruebaSwitchPanel()`)

**Interfaces que produce** (las usan las tareas 2, 3, 8 y 9):

```
readonly property int maxPinned: 32

normalizeId(bruto) → string
    Minúsculas, sin sufijo ".desktop", recortado. "" si no es cadena.

sanitize(fijadas) → [string]
    Array → array de ids normalizados, no vacíos, únicos, tope maxPinned.
    Lo que no sea array devuelve [].

has(fijadas, id) → bool
add(fijadas, id) → [string]        nuevo array; ignora duplicado y tope
remove(fijadas, id) → [string]     nuevo array
move(fijadas, desde, hasta) → [string]
    Nuevo array. Índices fuera de rango → devuelve una copia intacta.

merge(fijadas, abiertas, verAbiertas) → [ranura]
    abiertas: [{ id, ventanas: [obj], activa: bool }]
    ranura:   { id, fijada: bool, ventanas: [obj], activa: bool }
    Fijadas primero en su orden, con las ventanas que les toquen.
    Luego, si verAbiertas, las abiertas cuyo id no esté ya fijado.
    Nunca dos ranuras con el mismo id.

separatorIndex(ranuras) → int
    Número de ranuras fijadas, o -1 si detrás no hay ninguna abierta.
```

- [ ] **Paso 1 · Escribir `pruebaDock()` en `tests/logica.qml`**

```qml
    // ── Dock ─────────────────────────────────────────────────────────────────
    function pruebaDock() {
        // normalizeId: las tres formas de nombrar lo mismo tienen que caer en
        // la misma clave, o una app fijada y su ventana abierta saldrían como
        // dos iconos distintos. Es EL fallo del dock.
        igual("normalizeId quita el sufijo .desktop",
              DockCatalog.normalizeId("Firefox.desktop"), "firefox")
        igual("normalizeId recorta y baja a minúsculas",
              DockCatalog.normalizeId("  Firefox  "), "firefox")
        igual("normalizeId con lo que no es cadena da vacío",
              DockCatalog.normalizeId(null), "")

        // sanitize: settings.json es un archivo que el usuario puede editar.
        const sucio = ["kitty", "kitty", "", null, 7, "Firefox.desktop", "  "]
        igual("sanitize quita duplicados, basura y normaliza",
              DockCatalog.sanitize(sucio), ["kitty", "firefox"])
        igual("sanitize de lo que no es array da array vacío",
              DockCatalog.sanitize("kitty"), [])
        const muchas = []
        for (let i = 0; i < 50; i++) muchas.push("app" + i)
        ok("sanitize corta en el tope",
           DockCatalog.sanitize(muchas).length === DockCatalog.maxPinned)

        // add / remove / move devuelven arrays NUEVOS: si mutaran el original,
        // el binding de Settings no se enteraría del cambio.
        const base = ["a", "b", "c"]
        igual("add pone al final", DockCatalog.add(base, "d"), ["a","b","c","d"])
        igual("add no duplica", DockCatalog.add(base, "b"), ["a","b","c"])
        ok("add no toca el original", base.length === 3)
        igual("remove quita", DockCatalog.remove(base, "b"), ["a","c"])
        igual("remove de lo que no está no cambia nada",
              DockCatalog.remove(base, "z"), ["a","b","c"])

        igual("move al principio", DockCatalog.move(base, 2, 0), ["c","a","b"])
        igual("move al final", DockCatalog.move(base, 0, 2), ["b","c","a"])
        igual("move con origen fuera de rango no rompe",
              DockCatalog.move(base, 9, 0), ["a","b","c"])
        igual("move con destino fuera de rango no rompe",
              DockCatalog.move(base, 0, 9), ["a","b","c"])
        ok("move no toca el original", base[0] === "a")

        // merge: el corazón. Una app fijada QUE ADEMÁS está abierta es UNA
        // ranura, no dos.
        const abiertas = [
            { id: "firefox", ventanas: [{ t: "w1" }, { t: "w2" }], activa: true },
            { id: "kitty",   ventanas: [{ t: "w3" }], activa: false }
        ]
        const r1 = DockCatalog.merge(["firefox"], abiertas, true)
        igual("merge: una fijada y abierta sale UNA vez",
              r1.map(x => x.id), ["firefox", "kitty"])
        ok("merge: la fijada conserva sus ventanas", r1[0].ventanas.length === 2)
        ok("merge: la fijada se marca como fijada", r1[0].fijada === true)
        ok("merge: la abierta no fijada no se marca", r1[1].fijada === false)
        ok("merge: el foco viaja", r1[0].activa === true)

        const r2 = DockCatalog.merge(["firefox"], abiertas, false)
        igual("merge sin verAbiertas deja solo las fijadas",
              r2.map(x => x.id), ["firefox"])

        // Una app fijada que se desinstala NO se descarta: el usuario la puso
        // a propósito y quitársela sola sería perderle el ajuste.
        const r3 = DockCatalog.merge(["noexiste"], [], true)
        igual("merge conserva una fijada sin ventanas",
              r3.map(x => x.id), ["noexiste"])
        ok("y sin ventanas", r3[0].ventanas.length === 0)

        igual("merge respeta el orden de las fijadas",
              DockCatalog.merge(["kitty", "firefox"], abiertas, true)
                         .map(x => x.id), ["kitty", "firefox"])

        // separatorIndex: dónde va la rayita.
        ok("separator: sin abiertas detrás, no hay rayita",
           DockCatalog.separatorIndex(r2) === -1)
        ok("separator: con una abierta detrás, va tras las fijadas",
           DockCatalog.separatorIndex(r1) === 1)
        ok("separator: sin ninguna fijada tampoco hay rayita",
           DockCatalog.separatorIndex(
               DockCatalog.merge([], abiertas, true)) === -1)
    }
```

Y registrarla en `Component.onCompleted`, tras `pruebaSwitchPanel()`:

```qml
        pruebaSwitchPanel()
        pruebaDock()
```

- [ ] **Paso 2 · Correr y ver que falla**

```
sh tests/correr.sh
```

Esperado: falla. `DockCatalog is not defined` — el singleton no existe.

- [ ] **Paso 3 · Escribir `Config/DockCatalog.qml`**

Singleton con `pragma Singleton`, `import QtQuick`, `import Quickshell`. Nada
más: ni `qs.Services`, ni `qs.Config`. Cada función devuelve estructuras
nuevas, nunca muta lo que recibe.

`merge` construye primero un índice `id → abierta` para no hacer una búsqueda
lineal por cada fijada (con 32 fijadas y 30 ventanas eso son 960 comparaciones
en un binding que se reevalúa cada vez que se abre o cierra una ventana).

- [ ] **Paso 4 · Correr y ver que pasa**

```
sh tests/correr.sh
```

Esperado: pasa, con 25 comprobaciones más que antes.

- [ ] **Paso 5 · Validar las pruebas rompiéndolas**

Una a una, y devolviendo el código después:

1. En `merge`, dejar de excluir las abiertas ya fijadas → debe fallar
   «merge: una fijada y abierta sale UNA vez».
2. En `normalizeId`, quitar el `.replace(/\.desktop$/, "")` → debe fallar
   «normalizeId quita el sufijo .desktop».
3. En `move`, quitar la copia del array (mutar el original) → debe fallar
   «move no toca el original».

Si alguna no falla, la prueba no vale y hay que reescribirla.

---

## Tarea 2 · Las claves en `settings.json`

**Archivos:**
- Modificar: `Config/Settings.qml`
- Modificar: `tests/logica.qml` (ampliar `pruebaDock()`)

**Consume:** `DockCatalog.sanitize` de la tarea 1.
**Produce:** las 15 claves que leen las tareas 3–9.

- [ ] **Paso 1 · Declarar las propiedades**

Junto a las de la isla (`Config/Settings.qml:436`), con su bloque de
comentario explicando el porqué de `dockRadius: -1` y de que
`dockReserveSpace` solo aplique sin autoocultar:

```qml
    property bool   dockEnabled: true
    property string dockStyle: "pill"            // pill | hotseat
    property var    dockPinned: []
    property bool   dockShowRunning: true
    property string dockAutoHide: "smart"        // smart | always | never
    property bool   dockReserveSpace: false
    property var    dockOnlyMonitors: []
    property int    dockIconSize: 48
    property int    dockSpacing: 8
    property int    dockPadding: 8
    property real   dockOpacity: 0.78
    property int    dockRadius: -1               // -1 = lo decide el estilo
    property real   dockMagnify: 1.12            // 1.0 = sin lupa
    property string dockRunningIndicator: "line" // line | dots | count | none
    property bool   dockNotifBadges: true
    property bool   dockPreviews: true
```

- [ ] **Paso 2 · Darlas de alta en los tres mapas**

En `_defaults` (junto a `"islandEnabled"`), en `_numBounds`:

```
"dockIconSize": [24, 96], "dockSpacing": [0, 32], "dockPadding": [0, 32],
"dockOpacity": [0.0, 1.0], "dockRadius": [-1, 40], "dockMagnify": [1.0, 1.6]
```

en `_enums`:

```
"dockStyle": ["pill", "hotseat"],
"dockAutoHide": ["smart", "always", "never"],
"dockRunningIndicator": ["line", "dots", "count", "none"]
```

y en `_intKeys`: `"dockIconSize"`, `"dockSpacing"`, `"dockPadding"`,
`"dockRadius"`.

- [ ] **Paso 3 · Los dos casos propios en `sanitize()`**

Junto al de `barLayout`, que hace exactamente lo mismo delegando en su
catálogo:

```qml
        if (k === "dockPinned")
            return Array.isArray(val) ? DockCatalog.sanitize(val) : undefined
        if (k === "dockOnlyMonitors") {
            if (!Array.isArray(val)) return undefined
            return val.filter(x => typeof x === "string" && x !== "")
        }
```

- [ ] **Paso 4 · La siembra inicial**

Una función `_sembrarDock()` que corre **una sola vez**, cuando la clave
`dockPinned` no venía en el archivo cargado. La marca es la ausencia de la
clave, no un booleano aparte: quien vacíe la lista a propósito no debe
encontrársela repoblada al reiniciar.

Busca en `DesktopEntries` el primero que exista de cada lista y lo fija:

```
terminal   → Settings.terminalApp
navegador  → firefox, zen, librewolf, chromium, google-chrome, brave-browser
archivos   → org.gnome.Nautilus, org.kde.dolphin, thunar, nemo, pcmanfm
editor     → code, codium, org.gnome.TextEditor, org.kde.kate, nvim
```

Lo que no esté instalado, no se fija. Si no se encuentra ninguno, la clave se
escribe vacía — el dock enseñará solo las abiertas.

- [ ] **Paso 5 · Pruebas del saneado**

Añadir a `pruebaDock()`:

```qml
        ok("sanitize('dockPinned') rechaza lo que no es array",
           Settings.sanitize("dockPinned", "kitty") === undefined)
        igual("sanitize('dockPinned') limpia la lista",
              Settings.sanitize("dockPinned", ["a", "a", ""]), ["a"])
        ok("sanitize('dockStyle') rechaza un estilo inventado",
           Settings.sanitize("dockStyle", "cubo") === undefined)
        igual("sanitize('dockStyle') acepta hotseat",
              Settings.sanitize("dockStyle", "hotseat"), "hotseat")
        ok("sanitize('dockIconSize') recorta por arriba",
           Settings.sanitize("dockIconSize", 500) === 96)
        ok("sanitize('dockAutoHide') rechaza lo que no es de la lista",
           Settings.sanitize("dockAutoHide", "quizás") === undefined)
        ok("sanitize('dockOnlyMonitors') filtra lo que no es cadena",
           Settings.sanitize("dockOnlyMonitors", ["DP-1", 3, ""]).length === 1)
```

- [ ] **Paso 6 · Correr la batería**

```
sh tests/correr.sh
```

Esperado: pasa. Y **comprobar a mano que `settings.json` sigue entero**: leer
el archivo y verificar que las claves de antes siguen con su valor, no solo
que el shell arranque.

---

## Tarea 3 · `Services/Dock.qml`

**Archivos:**
- Crear: `Services/Dock.qml`

**Consume:** `DockCatalog.*` (tarea 1), las claves de `Settings` (tarea 2).
**Produce:** lo que consumen las tareas 4–9:

```
ranuras             → [ranura]  ya fusionadas
entradaDe(id)       → DesktopEntry | null
iconoDe(id)         → string     ruta resuelta, "" si no hay
nombreDe(id)        → string     nombre legible, con respaldo
avisosDe(id)        → int        0 si no hay coincidencia
enSuMonitor(nombre) → bool
hayVentanasEn(nombre) → bool     workspace activo de ESE monitor
activar(ranura)     → void
lanzarNueva(id)     → void
cerrarTodas(ranura) → void
fijar(id) / soltar(id) / reordenar(desde, hasta) → void
```

- [ ] **Paso 1 · Las claves de app**

```qml
    function claveDe(appId) {
        if (!appId) return ""
        const e = DesktopEntries.heuristicLookup(appId)
        return DockCatalog.normalizeId(e ? e.id : appId)
    }
```

Es el mismo `heuristicLookup` que ya usa `Bar/ActiveWindow.qml`. Sin esto, un
Firefox fijado y una ventana de Firefox son dos iconos.

- [ ] **Paso 2 · Agrupar los toplevels**

Recorrer `ToplevelManager.toplevels.values`, agrupar por `claveDe(appId)`,
marcar `activa` si alguna es `ToplevelManager.activeToplevel`. El resultado es
el array `abiertas` que espera `DockCatalog.merge`.

- [ ] **Paso 3 · Los datos de Hyprland**

`hayVentanasEn(monitor)` cruza `Hyprland.toplevels` (que trae
`lastIpcObject.monitor` y `workspace`) con el workspace activo de ese monitor.
**Sin Hyprland** (`!Settings.hyprlandAvailable`) devuelve `false`: el modo
inteligente pasa a comportarse como «siempre visible», que es lo razonable
cuando falta la información, no un error.

- [ ] **Paso 4 · Las acciones**

`activar(ranura)`: sin ventanas → `entradaDe(id).execute()`; con una → la
enfoca; con varias → rota (índice recordado por ranura). Enfocar reusa el
patrón de `Bar/Tray.qml:openApplication`, que ya resuelve traer una ventana de
otro espacio de trabajo sin robarle el foco a la que estabas usando, y que
distingue el modo Lua de Hyprland del clásico.

- [ ] **Paso 5 · El recuento de avisos**

```qml
    function avisosDe(id) {
        if (!Settings.dockNotifBadges) return 0
        const e = root.entradaDe(id)
        if (!e) return 0
        const clave = SettingsFilter.fold(e.name || "")
        if (clave === "") return 0
        let n = 0
        for (const notif of (NotifService.list?.values ?? []))
            if (SettingsFilter.fold(NotifService.appNameFor(notif)) === clave)
                n++
        return n
    }
```

**Sin coincidencia, 0.** Nunca un número adivinado sobre el icono equivocado:
un globo que falta es una función ausente, un globo mal puesto es información
falsa.

- [ ] **Paso 6 · Comprobar que carga**

```
sh tests/correr.sh
```

`qmlcarga` e `imports` tienen que pasar. La lógica viva de este archivo no es
probable sin sesión gráfica y eso se dice, no se disimula.

---

## Tarea 4 · La ventana y la forma

Primera tarea con algo en pantalla. Al acabar tiene que verse un dock, aunque
los iconos aún no hagan nada.

**Archivos:**
- Crear: `Modules/Dock/DockWindow.qml`, `Modules/Dock/Dock.qml`,
  `Modules/Dock/DockSeparator.qml`
- Modificar: `shell.qml`

- [ ] **Paso 1 · `DockWindow.qml`**

`PanelWindow` anclada abajo, `WlrLayershell.layer: WlrLayer.Top` (no
`Overlay`: los paneles del shell van en `Overlay` y tienen que quedar
delante), `namespace: "qs-dock"`, `implicitHeight: Theme.dp(420)`.

`exclusiveZone`: la altura del dock solo si
`dockAutoHide === "never" && dockReserveSpace`; si no, 0.

Margen inferior: `Theme.dp(10)` en `pill`, 0 en `hotseat`, **más
`Theme.barHeight + Theme.barTopMargin` si `Settings.barPosition === "bottom"`**.

`revelado` con las razones del spec §4.3, en ese orden. Sin condición de
bloqueo de sesión: `WlSessionLock` ya esconde toda superficie normal.

- [ ] **Paso 2 · La máscara**

```
escondido               → tira de Theme.dp(6) pegada al borde inferior
visible, sin globos     → el rectángulo de la pastilla
con vista previa o menú → la ventana entera
```

**Esto es lo primero que hay que comprobar a ojo**: una máscara mal calculada
deja el escritorio sin poder recibir clics en una franja del ancho de la
pantalla. Antes de seguir a la tarea 5: recargar, hacer clic en el escritorio
por encima del dock y confirmar que llega.

- [ ] **Paso 3 · `Dock.qml` y `DockSeparator.qml`**

Fondo `Theme.withAlpha(Theme.bg, Settings.dockOpacity)`, borde
`Theme.withAlpha(Theme.overlay, 0.35)` — el mismo tratamiento que la isla, que
es la otra superficie flotante del shell.

Radio: `Settings.dockRadius >= 0 ? Theme.dp(dockRadius) : (estilo === "pill"
? alto/2 : solo Theme.shapeXl arriba)`.

Ancho: contenido con tope del 90 % en `pill`; pantalla completa en `hotseat`.
Si se pasa, `ListView` horizontal con rueda y desvanecido por los bordes.

El separador es un `Rectangle` de 1 dp en `Theme.outlineVariant`, colocado en
el índice que dice `DockCatalog.separatorIndex`.

- [ ] **Paso 4 · Enganchar en `shell.qml`**

Dentro del `Variants` de pantallas, junto a la isla:

```qml
            LazyLoader {
                active: Settings.dockEnabled && Dock.enSuMonitor(scr.modelData.name)
                DockWindow { modelData: scr.modelData }
            }
```

Con su comentario explicando por qué `LazyLoader` y por qué el filtro de
monitor va aquí y no dentro de la ventana.

Y añadir la regla de Hyprland para que el compositor no anime la capa por
encima de la animación de QML, junto a las dos que ya hay en
`Component.onCompleted`:

```
hl.layer_rule({ name = "qs-noanim-dock", match = { namespace = "qs-dock" }, no_anim = true })
```

- [ ] **Paso 5 · Ver que se ve**

```
sh tests/correr.sh
qs kill; qs &
grim -g "..." /tmp/.../dock-1.png
```

Comprobar con capturas: la pastilla sale, se esconde al abrir una ventana
(modo inteligente), vuelve al llevar el ratón al borde, y el clic atraviesa
donde debe. Cambiar `dockStyle` a `hotseat` y volver a mirar.

---

## Tarea 5 · `DockButton`

**Archivos:**
- Crear: `Modules/Dock/DockButton.qml`

**Consume:** `Dock.iconoDe`, `Dock.avisosDe`, `Dock.activar`,
`Dock.lanzarNueva` (tarea 3).

- [ ] **Paso 1 · Icono y estados**

`Image` de `Settings.dockIconSize` con `Quickshell.iconPath(icono, true)` y
respaldo a `application-x-executable`. Lupa al posarse
(`scale: Settings.dockMagnify`), pulsación a 0.92, y `Components/Ripple.qml`,
que ya existe.

- [ ] **Paso 2 · El indicador de ventanas**

Los cuatro modos de `dockRunningIndicator`:

| valor | dibujo |
|---|---|
| `line` | rayita de 12×3 dp si hay alguna ventana |
| `dots` | puntito de 4×3 dp por ventana, hasta 3 |
| `count` | el número, si son 2 o más |
| `none` | nada |

Color `Theme.accent` con el foco, `Theme.withAlpha(Theme.fg, 0.4)` sin él.

- [ ] **Paso 3 · El globo de avisos**

`Components/CountBadge.qml`, que ya existe, anclado arriba a la derecha.
`visible` cuando `Dock.avisosDe(id) > 0`.

- [ ] **Paso 4 · Los clics**

Izquierdo → `Dock.activar(ranura)`. Central → `Dock.lanzarNueva(id)`.
Derecho → señal `pideMenu(ranura, x, y)`, que la tarea 7 recogerá.

- [ ] **Paso 5 · Comprobar**

`sh tests/correr.sh`, y a mano: lanzar una app fijada que no esté abierta,
enfocar una que sí, y rotar entre dos ventanas de la misma app. Capturas de
los cuatro indicadores.

---

## Tarea 6 · `DockPreview`

**Archivos:**
- Crear: `Modules/Dock/DockPreview.qml`
- Modificar: `Modules/Dock/DockWindow.qml` (montarlo, en `LazyLoader`)

- [ ] **Paso 1 · El globo**

320 dp de ancho, dentro de la ventana alta de la tarea 4 —no una superficie
nueva—, colocado sobre el icono y acotado a los bordes de la pantalla. Una
fila por ventana con su título; clic salta a esa ventana.

- [ ] **Paso 2 · La histéresis**

Aparece a los **500 ms** de posarse; se retira a los **250 ms** de salir. Ese
retardo de salida es justo lo que deja mover el ratón del icono al globo sin
que se cierre en el camino — sin él, la vista previa es inusable. Al pasar de
un icono a otro con el globo ya abierto, se recoloca sin desaparecer.

- [ ] **Paso 3 · Que se apague de verdad**

Con `dockPreviews: false` el `LazyLoader` no lo construye. No `visible: false`.

- [ ] **Paso 4 · Comprobar**

`sh tests/correr.sh` y prueba a mano con una app de tres ventanas. El hover
**no es automatizable aquí**: ya se comprobó al hacer el vistazo de la isla que
`hyprctl dispatch movecursor` mueve el cursor sin entregar un enter de puntero
de Wayland. Se prueba a mano y se dice que se probó a mano.

---

## Tarea 7 · `DockMenu`

**Archivos:**
- Crear: `Modules/Dock/DockMenu.qml`
- Modificar: `Modules/Dock/DockWindow.qml`

- [ ] **Paso 1 · Las filas**

```
Fijar al dock / Quitar del dock
Abrir ventana nueva
──────────────────
acciones del .desktop (entry.actions)
──────────────────
Cerrar todas                ← solo si tiene ventanas
```

Dentro de la ventana alta. Se cierra al pulsar fuera, con Escape, y al
ejecutar una fila.

- [ ] **Paso 2 · Que la ventana sepa que está abierto**

`DockWindow.revelado` tiene que dar `true` mientras el menú esté abierto, o el
dock se escondería debajo del menú que él mismo abrió.

- [ ] **Paso 3 · Comprobar**

`sh tests/correr.sh` y a mano: fijar una app abierta, soltarla, y ejecutar una
acción del `.desktop` (Firefox trae «Ventana privada»).

---

## Tarea 8 · Arrastrar para reordenar

**Archivos:**
- Modificar: `Modules/Dock/DockButton.qml`, `Modules/Dock/Dock.qml`

- [ ] **Paso 1 · El patrón del fantasma**

El de `Panels/SettingsPages/BarLayoutEditor.qml`: el icono arrastrado **no se
reparenta**; se queda atenuado en su sitio haciendo de hueco de origen, y lo
que sigue al ratón es un fantasma dibujado en una capa por encima. El destino
lo deciden `DropArea` entre iconos.

Leer la cabecera de ese archivo antes de escribir nada: explica por qué
reparentar el delegate de un `Repeater` se rompe en cuanto cambia el modelo.
Aquí el modelo cambia **más** que en la barra —cada ventana que se abre o se
cierra lo altera—, así que el patrón no es opcional.

- [ ] **Paso 2 · Escribir por el catálogo**

El suelte llama a `Dock.reordenar(desde, hasta)`, que por dentro es
`DockCatalog.move`. Nunca tocar `Settings.dockPinned` directamente: es el
segundo sitio que edita esa lista (el otro es la tarea 9) y la única forma de
que no diverjan es que ambos pasen por las mismas funciones.

Arrastrar una **abierta** a la zona de fijadas la fija en esa posición.

- [ ] **Paso 3 · Comprobar**

`sh tests/correr.sh`, y a mano: reordenar, y luego **abrir y cerrar una app a
mitad de gesto** para confirmar que el fantasma no se queda pegado.

---

## Tarea 9 · Ajustes

**Archivos:**
- Crear: `Panels/SettingsPages/DockPage.qml`,
  `Panels/SettingsPages/DockPinEditor.qml`
- Modificar: `Panels/Settings.qml`, `Config/SettingsSearchIndex.qml`,
  `Config/I18n.qml`

- [ ] **Paso 1 · Las cuatro tarjetas**

| tarjeta | filas |
|---|---|
| General | `dockEnabled` · `dockStyle` (`SegRow`) · `dockOnlyMonitors` |
| Comportamiento | `dockAutoHide` · `dockReserveSpace` · `dockShowRunning` · `dockRunningIndicator` · `dockNotifBadges` · `dockPreviews` |
| Aspecto | `dockIconSize` · `dockSpacing` · `dockPadding` · `dockOpacity` · `dockRadius` · `dockMagnify` |
| Apps fijadas | `DockPinEditor` |

Cada fila con su `skey` y su `label`, que es lo que recoge solo el índice del
buscador.

`dockReserveSpace` se **atenúa**, no se esconde, cuando
`dockAutoHide !== "never"`: esconder una fila hace que el usuario la busque;
atenuarla explica por qué no aplica.

- [ ] **Paso 2 · `DockPinEditor.qml`**

Lista de fijadas arrastrable (mismo patrón del fantasma), aspa para quitar, y
debajo un buscador sobre `Services/AppCatalog.qml` para añadir. Escribe
**siempre** por `DockCatalog.move/add/remove`.

- [ ] **Paso 3 · Los tres enganches**

1. `Panels/Settings.qml` → `groups`, en «Barra y widgets»:
   `{ key: "dock", glyph: "󰕰", label: I18n.tr("Dock") }` con un glifo nf-md
   distinto del de Widgets.
2. `Panels/Settings.qml` → el `switch` del cargador:
   `case "dock": return "SettingsPages/DockPage.qml"`
3. `Config/SettingsSearchIndex.qml` → `pageSources`:
   `"dock": "../Panels/SettingsPages/DockPage.qml"`

- [ ] **Paso 4 · Las cadenas**

Unas 30 en `Config/I18n.qml`, en español y catalán: "Dock", "Pastilla",
"Hotseat", "Autoocultar", "Inteligente", "Siempre", "Nunca", "Reservar
espacio", "Enseñar apps abiertas", "Indicador de ventanas", "Rayita",
"Puntos", "Número", "Tamaño de icono", "Separación", "Relleno", "Opacidad",
"Radio", "Automático", "Lupa", "Apps fijadas", "Añadir app", "Fijar al dock",
"Quitar del dock", "Abrir ventana nueva", "Cerrar todas", "Globos de
notificación", "Vistas previas", "Monitores", "Todos".

- [ ] **Paso 5 · Comprobar**

`sh tests/correr.sh`, y a mano: abrir Ajustes, ir a Dock, tocar cada control y
ver el efecto en pantalla; buscar "dock" desde Spotlight y confirmar que el
índice encontró las filas.

---

## Tarea 10 · Repaso final

- [ ] **Paso 1 · La batería entera**

```
sh tests/correr.sh
```

Esperado: los 217+ archivos QML compilan, imports OK, 91 del buscador, y las
comprobaciones de lógica con 0 mal.

- [ ] **Paso 2 · `settings.json` intacto**

Comparar clave por clave con la copia de seguridad. Solo deben haber cambiado
las 16 nuevas del dock (y la marca de tiempo de la caché del clima, que cambia
sola).

- [ ] **Paso 3 · El interruptor, en los dos sentidos**

Apagar `dockEnabled` y confirmar en `hyprctl layers` que **no queda ninguna
capa `qs-dock`** — no que esté escondida: que no exista. Volver a encenderlo y
confirmar que vuelve.

- [ ] **Paso 4 · Capturas del antes y el después**

Las dos formas, los cuatro indicadores, la vista previa, el menú y la página
de Ajustes.

- [ ] **Paso 5 · Decir qué no se probó**

En el informe: la geometría de layer-shell, la máscara de clics y el hover se
comprobaron **a ojo**, no con pruebas automáticas, porque en este entorno no
hay forma de entregar un enter de puntero de Wayland. Se dice, no se disimula.
