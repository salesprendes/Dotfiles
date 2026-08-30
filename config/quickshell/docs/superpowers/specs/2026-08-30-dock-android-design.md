# Dock con diseño de Android

Fecha: 2026-08-30
Estado: implementado (2026-08-30). Ver docs/superpowers/plans/2026-08-30-dock-android.md

Referencias leídas antes de escribir esto:

- **nandoroid** (`na-ive/nandoroid-shell`) — `panels/Dock/`, 1.070 líneas en 7
  archivos QML. Es la referencia de *estructura*: pastilla centrada, lupa al
  posarse, puntitos por ventana, globo de avisos, vista previa, menú
  contextual, autoocultar con dos modos.
- **noctalia** (`noctalia-dev/noctalia`) — ya no es QML; lo reescribieron en
  C++ (`src/shell/dock/`). No sirve como referencia de código, pero su
  `DockConfig` (`src/config/config_types.h:614`) es la mejor lista de opciones
  disponible: 40 ajustes. Es la referencia de *configurabilidad*.

## 1. Qué se construye

Un dock por monitor, en el borde inferior, con dos formas intercambiables
desde Ajustes:

- **`pill`** — la barra de tareas de tableta Android (12L+): pastilla
  flotante, centrada, de ancho variable según el contenido.
- **`hotseat`** — el hotseat del Pixel Launcher: barra ancha pegada al borde,
  con las esquinas de arriba redondeadas.

Enseña las apps **fijadas** por el usuario y, detrás de un separador, las que
estén **abiertas** y no estén fijadas. Viene encendido de fábrica, con
autoocultar inteligente.

### Decisiones tomadas y su motivo

| Decisión | Motivo |
|---|---|
| Solo borde inferior | Android no tiene dock lateral. Los laterales obligan a disposición vertical, separador girado, globos por el costado y otro eje de animación: un caso más que probar sin uso real detrás. |
| Dos estilos, no uno | Es como está hecho el resto del shell (la isla, la posición de la barra): reversible, y el usuario elige. El coste es bajo porque lo único que cambia entre estilos es la geometría (§4). |
| Fijadas + abiertas | Lo que hacen Android, nandoroid y noctalia. Solo fijadas es un lanzador, no un dock; solo abiertas desaparece con el escritorio vacío. |
| Encendido de fábrica | Petición explícita. Obliga a sembrar `dockPinned` (§3.3), porque con autoocultar inteligente el dock se ve justo cuando no hay nada abierto. |

## 2. Arquitectura: tres capas

La partición no es purismo. Responde a una pregunta concreta: **¿qué parte de
esto se puede equivocar de una forma que no se vea a simple vista?** La
respuesta es la fusión de listas —una app fijada que además está abierta
saliendo dos veces, el orden perdido al cerrar una ventana, un `settings.json`
editado a mano con basura dentro— y esa parte tiene que poder probarse sin
pantalla ni compositor.

### 2.1 `Config/DockCatalog.qml` — funciones puras

Singleton. **No importa `qs.Services`**, igual que el resto de `Config/` (ver
la nota del ciclo de importaciones en `Config/Globals.qml`). Entra un array,
sale un array; ninguna función lee estado global.

```
sanitize(fijadas) → [id]
    Descarta lo que no sea cadena no vacía, quita duplicados conservando la
    primera aparición, y corta en 32. Protege de un settings.json a mano.

normalizeId(raw) → id
    Minúsculas, sin sufijo ".desktop", sin espacios en los extremos.
    LA función clave: ver §2.2.

merge(fijadas, abiertas, verAbiertas) → [ranura]
    ranura = { id, fijada: bool, ventanas: [obj], activa: bool }
    Primero las fijadas en su orden, cada una con las ventanas que le
    correspondan (o ninguna). Luego, si verAbiertas, las abiertas cuyo id no
    esté ya entre las fijadas. Nunca dos ranuras con el mismo id.

move(fijadas, desde, hasta) → [id]
    Devuelve un array NUEVO. Índices fuera de rango: devuelve el original.

add(fijadas, id) / remove(fijadas, id) / has(fijadas, id)
    add ignora duplicados y respeta el tope de 32.

separatorIndex(ranuras) → int
    Dónde va el separador: el número de ranuras fijadas, o -1 si no hay
    ninguna abierta que enseñar detrás.
```

Es el gemelo de `Config/BarCatalog.qml`, que resuelve exactamente el mismo
problema para los tres carriles de la barra.

### 2.2 `Services/Dock.qml` — lo vivo

Singleton. Recorre `ToplevelManager.toplevels`, agrupa por app, cruza con
`Hyprland.toplevels` para monitor y espacio de trabajo, y le pasa la foto de
ahora mismo al catálogo.

**El problema central de este archivo**: fijar guarda el id de un `.desktop`,
pero una ventana de Wayland solo trae su `appId`. Sin llevar ambos a la misma
clave, un Firefox fijado y una ventana de Firefox salen como **dos iconos
distintos**. La normalización pasa por `DesktopEntries.heuristicLookup()`, que
ya es lo que usa `Bar/ActiveWindow.qml` para el mismo problema:

```
claveDe(appId):
    entrada = DesktopEntries.heuristicLookup(appId)
    si entrada  → DockCatalog.normalizeId(entrada.id)
    si no       → DockCatalog.normalizeId(appId)
```

Superficie pública:

```
ranuras            → DockCatalog.merge(...) con los datos de ahora
entradaDe(id)      → la DesktopEntry, o null
iconoDe(id)        → ruta de icono resuelta, con respaldo
ventanasEn(monitor, workspace) → para el autoocultar inteligente
avisosDe(id)       → recuento de notificaciones (§5.3), 0 si no hay match
enSuMonitor(nombre) → ¿toca dock en este monitor? (dockOnlyMonitors vacío = sí)

activar(ranura)    → si no hay ventanas, lanza; si hay una, la enfoca;
                     si hay varias, rota entre ellas (índice recordado)
lanzarNueva(id)    → siempre una instancia nueva
cerrarTodas(ranura)
fijar(id) / soltar(id) / reordenar(desde, hasta)
```

**Degradación sin Hyprland**: `Hyprland.toplevels` da monitor y espacio de
trabajo. Sin Hyprland (`Settings.hyprlandAvailable === false`), esos datos no
existen: el dock se enseña en todos los monitores y el modo inteligente se
comporta como «siempre visible». No es un error, es el comportamiento
razonable cuando falta la información.

### 2.3 `Modules/Dock/`

| archivo | qué es |
|---|---|
| `DockWindow.qml` | la `PanelWindow` por monitor: capa, máscara, geometría, revelado |
| `DockRow.qml` | la pastilla o la barra: fondo, fila desplazable, separador |
| `DockButton.qml` | un icono: lupa, pulsación, indicador de ventanas, globo, arrastre |
| `DockPreview.qml` | globo con las ventanas abiertas de una app |
| `DockMenu.qml` | menú contextual |
| `DockSeparator.qml` | la rayita entre fijadas y abiertas |

## 3. Datos

### 3.1 Claves en `settings.json`

Todas con su valor por defecto, sus límites y su saneado en
`Config/Settings.qml`, como el resto.

```
dockEnabled           bool     true
dockStyle             enum     "pill"      ["pill", "hotseat"]
dockPinned            [string] sembrado    ← ver §3.3
dockShowRunning       bool     true
dockAutoHide          enum     "smart"     ["smart", "always", "never"]
dockReserveSpace      bool     false       ← solo aplica con autoHide "never"
dockOnlyMonitors      [string] []          ← vacío = todos
dockIconSize          int      48          [24, 96]
dockSpacing           int      8           [0, 32]
dockPadding           int      8           [0, 32]
dockOpacity           real     0.78        [0.0, 1.0]
dockRadius            int      -1          [-1, 40]  ← -1 = automático por estilo
dockMagnify           real     1.12        [1.0, 1.6]  ← 1.0 = sin lupa
dockRunningIndicator  enum     "line"      ["line", "dots", "count", "none"]
dockNotifBadges       bool     true
dockPreviews          bool     true
```

`dockRadius: -1` significa «lo decide el estilo» (pastilla completa para
`pill`, `shapeXl` arriba para `hotseat`). Un valor explícito lo sobrescribe.
Se hace así y no con dos claves para que cambiar de estilo no arrastre un
radio pensado para el otro.

### 3.2 Saneado

- `dockStyle`, `dockAutoHide`, `dockRunningIndicator` → `_enums`
- `dockIconSize`, `dockSpacing`, `dockPadding`, `dockRadius` → `_numBounds` + `_intKeys`
- `dockOpacity`, `dockMagnify` → `_numBounds`
- `dockPinned` y `dockOnlyMonitors` → caso propio en `sanitize()`, delegando
  en `DockCatalog.sanitize()` el primero (mismo patrón que `barLayout` con
  `BarCatalog.sanitize`).

### 3.3 Siembra inicial

Con `dockPinned` vacío y autoocultar inteligente, el dock se vería por primera
vez **exactamente cuando no hay nada abierto que enseñar**: una pastilla vacía.

Así que la primera vez —y solo la primera, escrito a `settings.json` como un
valor más, **no como binding**— se siembra con lo que de verdad esté
instalado:

1. `Settings.terminalApp` si su `.desktop` existe
2. el primer navegador que exista, entre `firefox`, `zen`, `librewolf`,
   `chromium`, `google-chrome`, `brave-browser`
3. el primer gestor de archivos, entre `org.gnome.Nautilus`, `org.kde.dolphin`,
   `thunar`, `nemo`, `pcmanfm`
4. el primer editor, entre `code`, `codium`, `org.gnome.TextEditor`,
   `org.kde.kate`, `nvim`

La existencia se comprueba contra `DesktopEntries`, no contra el disco.
Lo que no esté instalado, no se fija. Nada de una lista fija de ids que en una
máquina concreta serían iconos rotos. Si no se encuentra ninguno, `dockPinned`
queda vacío y el dock enseña solo las abiertas — degradado, pero no roto.

La marca de «ya sembrado» es la presencia de la clave `dockPinned` en el
archivo, no un booleano aparte: quien la vacíe a propósito no debe encontrársela
repoblada en el siguiente arranque.

## 4. La ventana

### 4.1 Una sola superficie, alta y enmascarada

`PanelWindow` por monitor, anclada abajo, `WlrLayershell.layer: Top`,
`WlrLayershell.namespace: "qs-dock"`.

**Más alta que el dock** (unos 420 dp) con `mask: Region` recortando lo que
recibe clics. El motivo: la vista previa y el menú salen *hacia arriba* desde
el icono. Con una ventana de la altura del dock harían falta dos superficies
de layer-shell más por monitor, cada una con su agarre de foco y su
coordinación de cierre. Alta y enmascarada, viven dentro. Es el truco de
nandoroid (`Dock.qml:73`, `implicitHeight: 500`) y es el correcto.

La máscara cambia sola:

```
escondido        → tira de 6 dp pegada al borde inferior
revelado         → el rectángulo de la pastilla/barra
+ vista previa   → y ADEMÁS el rectángulo del globo, sumado con una Region hija
menú abierto     → la ventana entera, para poder cerrarlo pulsando fuera
```

Fuera de eso el clic atraviesa al escritorio.

**Corrección hecha al implementar**: la primera versión agrandaba la máscara a
la ventana entera con *cualquiera* de los dos globos. Con la vista previa eso
deja 2560×420 dp del tercio inferior de la pantalla sin recibir clics solo por
posar el ratón en un icono. Un menú sí puede cobrarse la ventana entera —lo
abre el usuario y pulsar fuera es como se cierra—, pero un globo que sale al
pasar por encima no. Las dos zonas se suman ahora con una `Region` hija.

**Capa `Top`, no `Overlay`**: los paneles del shell (que van en `Overlay`)
tienen que quedar por delante del dock, no detrás.

### 4.2 Geometría por estilo

Es lo único que cambia entre `pill` y `hotseat`. `Dock`, `DockButton`,
`DockPreview` y `DockMenu` no saben en qué estilo están.

```
                    pill                      hotseat
margen inferior     dp(10)                    0
ancho               contenido, tope 90 %      pantalla completa
radio               alto / 2                  shapeXl solo arriba
alto                icono + 2×padding         igual
```

**Con la barra abajo** (`Settings.barPosition === "bottom"`) el margen inferior
suma `Theme.barHeight + Theme.barTopMargin`: el dock se apoya justo encima. La
barra ya reserva su zona exclusiva, así que no hay que negociar nada más.

**Zona exclusiva**: `dockReserveSpace` solo tiene efecto con
`dockAutoHide === "never"`. En los modos de autoocultar es siempre 0 — reservar
un hueco para algo que está escondido dejaría una franja vacía permanente.

### 4.3 Revelado

Una sola propiedad `revelado`, con las razones en este orden:

```
menú o vista previa      → visible
ratón dentro             → visible
dockAutoHide "never"     → visible
dockAutoHide "always"    → oculto
dockAutoHide "smart"     → visible si el espacio de trabajo activo
                           de ESTE monitor no tiene ventanas
```

**No hay condición de bloqueo de sesión**, y es deliberado: nandoroid la lleva
(`GlobalStates.screenLocked`), pero este shell bloquea con `WlSessionLock`
(`Panels/LockScreen.qml`, protocolo ext-session-lock), y ese protocolo hace que
el compositor esconda **todas** las superficies normales, layer-shell incluida.
Añadir la condición no escondería nada que no esté ya escondido, y a cambio
destruiría y reconstruiría una ventana por monitor en cada bloqueo.

Que sea *de este monitor* importa: con dos pantallas, un navegador a pantalla
completa en la principal no debe esconder el dock de la secundaria vacía.

La animación es de margen inferior + opacidad, con `Theme.animNormal`. Se
respeta `Theme.animNormal === 0` (animaciones desactivadas): salto seco, sin
`Behavior`.

## 5. El botón

```
   ╭─────────╮
   │    ▣  ③ │   ← globo de avisos, arriba a la derecha (CountBadge)
   │         │
   ╰────▁────╯   ← indicador de ventanas
```

- Icono `dockIconSize`, resuelto vía `Quickshell.iconPath(icono, true)` con
  respaldo a `application-x-executable`.
- Lupa al posarse: escala `dockMagnify` (1.12 por defecto; 1.0 lo apaga).
- Pulsación: escala 0.92 y `Components/Ripple.qml`, que ya existe.
- Clic izquierdo → `Dock.activar(ranura)`. Clic central → `lanzarNueva`.
  Clic derecho → menú.

### 5.1 Indicador de ventanas

Ajuste `dockRunningIndicator`:

| valor | qué dibuja |
|---|---|
| `line` | una rayita de 12×3 dp si la app tiene alguna ventana |
| `dots` | un puntito de 4×3 dp por ventana, hasta 3 |
| `count` | el número de ventanas, si son 2 o más |
| `none` | nada |

Color `Theme.accent` si alguna de sus ventanas tiene el foco;
`Theme.withAlpha(Theme.fg, 0.4)` si no.

### 5.2 Arrastrar para reordenar

El patrón de `Panels/SettingsPages/BarLayoutEditor.qml`: el icono arrastrado
**no se reparenta**; se queda atenuado en su sitio haciendo de hueco de origen,
y lo que sigue al ratón es un fantasma dibujado en una capa por encima. El
destino lo deciden `DropArea` entre iconos.

El comentario de cabecera de ese archivo explica por qué reparentar el
delegate de un `Repeater` se rompe en cuanto cambia el modelo. Aquí el modelo
cambia **más** que en la barra (cada ventana que se abre o se cierra lo
altera), así que el patrón no es opcional.

Solo se reordenan las **fijadas**. Arrastrar una abierta a la zona de fijadas
la fija en esa posición.

### 5.3 Globo de avisos — limitación conocida

`Services/NotifService.qml` agrupa por `appName`: **el nombre que la app se
pone a sí misma** al enviar la notificación. El dock indexa por id de
`.desktop`. No son la misma cosa y no hay forma general de convertir una en
otra.

El emparejamiento compara ambos plegados (`SettingsFilter.fold`, sin
diacríticos y en minúsculas) contra el `name` y el `id` de la entrada
`.desktop`. Acertará con Firefox, Signal o Thunderbird; fallará con apps que
se anuncien con un nombre sin parecido con su `.desktop`.

**Sin coincidencia, sin globo.** Nunca un número adivinado sobre el icono
equivocado: un globo ausente es una función que falta, un globo mal puesto es
información falsa.

## 6. Vista previa

Globo de 320 dp sobre el icono, dentro de la ventana alta (§4.1). Una fila por
ventana con su título; clic salta a esa ventana.

Histéresis, que es lo que hace que se pueda usar:

- aparece a los **500 ms** de posarse sobre el icono
- se retira a los **250 ms** de salir

Ese retardo de salida es lo que deja mover el ratón del icono al globo sin que
se cierre en el camino. Al pasar de un icono a otro con el globo ya abierto,
se recoloca sin desaparecer.

Se apaga con `dockPreviews: false`, y entonces no se construye (`LazyLoader`),
no se esconde.

## 7. Menú contextual

Clic derecho sobre un icono:

```
Fijar al dock / Quitar del dock
Abrir ventana nueva
──────────────────────
(acciones del .desktop: "Ventana privada", "Componer correo"…)
──────────────────────
Cerrar todas                    ← solo si tiene ventanas
```

Se dibuja dentro de la ventana alta, no como superficie aparte.

## 8. Ajustes

Categoría nueva **Dock**, en el grupo «Barra y widgets», junto a Widgets y
Shell. Tres sitios que tocar:

1. `Panels/Settings.qml` → `groups` (glifo nf-md, plano y sin contenedor de
   color, como los demás)
2. `Panels/Settings.qml` → el `switch` del cargador de páginas
3. `Config/SettingsSearchIndex.qml` → `pageSources`

El índice del buscador se construye solo recorriendo el árbol en busca de
`skey` + `label`; no hay lista aparte que mantener.

`Panels/SettingsPages/DockPage.qml`, en tarjetas:

| tarjeta | filas |
|---|---|
| **General** | `dockEnabled` · `dockStyle` (`SegRow`) · `dockOnlyMonitors` |
| **Comportamiento** | `dockAutoHide` · `dockReserveSpace` · `dockShowRunning` · `dockRunningIndicator` · `dockNotifBadges` · `dockPreviews` |
| **Aspecto** | `dockIconSize` · `dockSpacing` · `dockPadding` · `dockOpacity` · `dockRadius` · `dockMagnify` |
| **Apps fijadas** | `DockPinEditor.qml` |

`dockReserveSpace` se atenúa (no se esconde) cuando `dockAutoHide !== "never"`:
esconder una fila hace que el usuario la busque; atenuarla explica por qué no
aplica.

**`Panels/SettingsPages/DockPinEditor.qml`** — la lista de fijadas, arrastrable
para reordenar, con aspa para quitar, y debajo un buscador sobre
`Services/AppCatalog.qml` para añadir. Mismo patrón de arrastre que
`BarLayoutEditor`, y **escribe a través de `DockCatalog.move/add/remove`**: es
el segundo sitio que edita `dockPinned`, y la única forma de que no diverja del
arrastre dentro del propio dock es que ambos pasen por las mismas funciones.

## 9. Cadenas nuevas (`Config/I18n.qml`)

Español y catalán, siguiendo lo que ya hay. Aproximadamente 30 cadenas:
"Dock", "Pastilla", "Hotseat", "Autoocultar", "Inteligente", "Siempre",
"Nunca", "Reservar espacio", "Enseñar apps abiertas", "Indicador de ventanas",
"Rayita", "Puntos", "Número", "Tamaño de icono", "Separación", "Relleno",
"Opacidad", "Radio", "Automático", "Lupa", "Apps fijadas", "Añadir app",
"Fijar al dock", "Quitar del dock", "Abrir ventana nueva", "Cerrar todas",
"Globos de notificación", "Vistas previas", "Monitores", "Todos".

## 10. Enganche en `shell.qml`

Dentro del recorrido `Variants` de pantallas, junto a la isla:

```qml
LazyLoader {
    active: Settings.dockEnabled && Dock.enSuMonitor(scr.modelData.name)
    DockWindow { modelData: scr.modelData }
}
```

`LazyLoader` y no `visible: false`, por la misma razón que la isla: una
superficie de layer-shell escondida sigue existiendo, con sus temporizadores y
sus bindings, por monitor. Quien apague el dock no debe pagar nada por él.

El filtro por monitor (`dockOnlyMonitors`) va **dentro** de `active`, no en la
ventana: un monitor excluido no construye nada.

## 11. Pruebas

`pruebaDock()` en `tests/logica.qml`, sobre `DockCatalog` (puro, sin pantalla):

1. `sanitize` con basura: números, `null`, cadenas vacías, duplicados, 40
   elementos → array limpio de ≤32 cadenas únicas
2. `normalizeId`: `"Firefox.desktop"`, `" firefox "`, `"firefox"` → la misma
   clave
3. `merge`: una app fijada **que además está abierta** aparece **una sola vez**,
   con sus ventanas
4. `merge`: las abiertas no fijadas van detrás, en orden estable
5. `merge` con `verAbiertas: false`: solo las fijadas
6. `merge` con una fijada desinstalada: la ranura sigue, sin ventanas (el
   icono se resolverá a respaldo; no se descarta la fijada, que el usuario la
   puso a propósito)
7. `move` al principio, al final, e índices fuera de rango → array original
8. `add` duplicado → sin cambios; `add` en el tope 32 → sin cambios
9. `separatorIndex` con 0 fijadas, 0 abiertas, y ambas

Cada prueba se valida **rompiendo a propósito** el código que protege, como
las de la isla.

Cubre además la batería que ya existe: `qmllint`, `qmlcarga`, `imports`.

**Lo que no se puede probar aquí**, y se dice desde ya: la geometría de
layer-shell, la máscara de clics y el hover. Ya se comprobó al hacer el vistazo
de la isla que `hyprctl dispatch movecursor` mueve el cursor **sin** entregar
un enter de puntero de Wayland, así que el hover no es automatizable en este
entorno. Se verifica a ojo, con capturas de `grim`, y se dice qué se comprobó y
qué no.

## 12. Archivos

**Nuevos (11)**

```
Config/DockCatalog.qml
Services/Dock.qml
Modules/Dock/DockWindow.qml
Modules/Dock/DockRow.qml            ← se llamaba Dock.qml; ver abajo
Modules/Dock/DockButton.qml
Modules/Dock/DockPreview.qml
Modules/Dock/DockMenu.qml
Modules/Dock/DockSeparator.qml
Panels/SettingsPages/DockPage.qml
Panels/SettingsPages/DockPinEditor.qml
Panels/SettingsPages/DockPinChip.qml       ← una ficha del editor
Panels/SettingsPages/DockPinDropGap.qml    ← un hueco de suelta
Panels/SettingsPages/DockMonitorPicker.qml ← la fila de monitores
docs/superpowers/specs/2026-08-30-dock-android-design.md   (este)
```

**`Dock.qml` → `DockRow.qml`**: el componente visual y el singleton
`Services/Dock.qml` resolvían al mismo nombre `Dock`, y QML gana el singleton —
con el error «Composite Singleton Type Dock is not creatable». El servicio se
queda con el nombre bueno; el componente pasa a decir lo que es.

Las tres piezas extra del editor de fijadas salieron de partir un archivo que
se iba a 400 líneas: la ficha y el hueco de suelta se entienden solos, y
mantenerlos dentro del editor obligaba a leerlo entero para cambiar un borde.

**Tocados (6)**

```
Config/Settings.qml            claves, defaults, saneado, siembra
Config/SettingsSearchIndex.qml pageSources
Config/I18n.qml                ~30 cadenas × 2 idiomas
Panels/Settings.qml            groups + switch del cargador
shell.qml                      el LazyLoader del dock
tests/logica.qml               pruebaDock()
```

## 12b. Estilo de nandoroid (añadido después)

Petición posterior: «pon el estilo y diseño del dock que nandroid». Nota
factual: **nandoroid usa la pastilla, no el hotseat** — su `backgroundStyle`
por defecto es `1`, radio completo (`core/Config.qml:456`). Su `2` sí es el
pegado al borde con esquinas de 24 dp arriba, que es nuestro `hotseat`, pero no
viene de fábrica.

Lo que de verdad lo distingue no es la forma, sino el tratamiento de los
iconos. Añadido:

| pieza | cómo |
|---|---|
| iconos monocromos | círculo de acento al 14 % detrás, icono teñido con `MultiEffect.colorization` |
| sombra | `RectangularShadow` de `QtQuick.Effects`, bajo el fondo y fuera de él |
| desvanecido | dos degradados horizontales del color del fondo, solo al desbordar |
| botones finales | lanzador y Spotlight, tras un filete, con la misma caja |
| proporción | icono por defecto 48 → **32**: nandoroid deja más aire que icono |
| indicador `auto` | rayita con una ventana, puntos con varias — lo que hace nandoroid |

**`Qt5Compat` no está instalado en este equipo**, y nandoroid lo usa para
`ColorOverlay` y `OpacityMask`. `QtQuick.Effects` (Qt 6) sí está y ya se usa en
`Panels/LockContent.qml`: `MultiEffect.colorization` sustituye a `ColorOverlay`,
y el desvanecido sale más barato con dos degradados que con una máscara de
opacidad, que montaría una capa de composición sobre la fila entera.

Claves nuevas: `dockIconStyle` (`mono` | `color`, de fábrica `mono`),
`dockShadow`, `dockShowLauncher`, `dockShowSpotlight`. Y
`dockRunningIndicator` gana el valor `auto`, que pasa a ser el de fábrica.

Archivo nuevo: `Modules/Dock/DockActionButton.qml`.

## 13. Riesgos

| Riesgo | Mitigación |
|---|---|
| El emparejamiento `appId` ↔ `.desktop` falla con apps raras | `heuristicLookup` primero; si no resuelve, el `appId` crudo es la clave. Se agrupa mal en el peor caso, no se rompe. |
| La máscara de clics deja el escritorio inservible si se calcula mal | Es lo primero que se comprueba a ojo tras la primera versión que arranque, antes de seguir. |
| Un dock con 30 apps abiertas se sale de la pantalla | Tope del 90 % del ancho, desplazamiento con rueda y desvanecido por los bordes. |
| El arrastre se rompe al cambiar el modelo a mitad de gesto | El patrón del fantasma de `BarLayoutEditor`, no reparentar. |
| Colisión con la barra abajo | Margen inferior += `barHeight + barTopMargin`. |
| Este directorio **no está versionado** (`~/Documentos/dotfiles` es una copia) | Fuera del alcance de este spec, pero se vuelve a dejar dicho: no hay a qué volver si algo sale mal. |
