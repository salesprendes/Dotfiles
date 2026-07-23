pragma ComponentBehavior: Bound
pragma Singleton

import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config
import qs.Services

// Plantillas de apps (Ajustes → Plantillas): una parrilla de apps con
// casillas, cada una vuelca los colores del tema en el archivo de
// configuración de esa app. Todo en QML (FileView para leer/escribir,
// Process solo para comandos sueltos como 'pkill'/'mkdir'/'dbus-send' con
// argv directo) — nada de scripts .sh.
//
// Ajustes → Plantillas solo LISTA las apps detectadas en el sistema
// (vía Services/Deps.qml, ver 'isInstalled' más abajo) — con 15 apps casi ninguna
// instalada a la vez, mostrarlas todas era más ruido que utilidad. GTK e
// Hyprland son la excepción: GTK porque no hay un binario que comprobar (es
// una librería, no un programa); Hyprland porque su detección real es "es
// el compositor activo ahora mismo" (Settings.hyprlandAvailable, por
// variable de entorno), no un binario instalado. Ambos se dan por
// disponibles según ese criterio propio, no 'which'.
//
// GTK e Hyprland viven aparte, en Config/Settings.qml
// (gtkThemingEnabled/gtkTokens/applyGtkTheme y
// hyprlandThemingEnabled/hyprThemeLua/applyHyprlandThemeNow): ya tenían su
// propio mecanismo antes de que existiera este registro genérico — más
// profundo que una plantilla de texto (Hyprland: recarga en vivo con
// hyprctl reload; GTK: sincroniza modo claro/oscuro con gsettings). Aquí
// solo aparecen como una entrada más de la lista para que la página se vea
// unificada, pero delegan en Settings.
//
// 'category' agrupa la lista por tipo de app (sistema/terminal/editor/
// compositor/audio/otros).
//
// Kitty/Alacritty/Foot quedan excluidos (a diferencia de Hyprland, sin
// entrada siquiera): Services/Terminal.qml ya los regenera enteros (fuente,
// opacidad, cursor...) en Ajustes → Terminal; meterlos aquí también pisaría
// ese archivo cada vez que cambie cualquier ajuste de terminal, perdiendo
// el include que añadiéramos nosotros.
//
// Nombre del tema que se escribe en cada app: 'quickshell' — es el nombre
// de este shell (el generador), no el de la paleta de color elegida
// (Settings.themeName); mismo criterio que ya se siguió en GTK
// (quickshell.css).
Singleton {
    id: root

    readonly property string home: Settings.home
    readonly property string tplDir: home + "/.config/quickshell/Templates"

    readonly property var registry: [
        { id: "gtk",       label: "GTK",          glyph: "󰆧", bin: "",          category: "system" },
        { id: "qt",        label: "Qt",           glyph: "󰐡", bin: "qt6ct",     category: "system" },
        { id: "kde",       label: "KColorScheme", glyph: "󰣇", bin: "plasmashell", category: "system" },
        { id: "ghostty",   label: "Ghostty",      glyph: "󰆍", bin: "ghostty",   category: "terminal" },
        { id: "wezterm",   label: "WezTerm",      glyph: "󰆍", bin: "wezterm",   category: "terminal" },
        { id: "starship",  label: "Starship",     glyph: "󰝤", bin: "starship",  category: "terminal" },
        { id: "helix",     label: "Helix",        glyph: "󰈮", bin: "hx",        category: "editor" },
        { id: "emacs",     label: "Emacs",        glyph: "󰚗", bin: "emacs",     category: "editor" },
        { id: "hyprland",  label: "Hyprland",     glyph: "󱂬", bin: "",          category: "compositor" },
        { id: "labwc",     label: "Labwc",        glyph: "󱂬", bin: "labwc",     category: "compositor" },
        { id: "niri",      label: "Niri",         glyph: "󱂬", bin: "niri",      category: "compositor" },
        { id: "mango",     label: "Mango",        glyph: "󱂬", bin: "mango",     category: "compositor" },
        { id: "scroll",    label: "Scroll",       glyph: "󱂬", bin: "scroll",    category: "compositor" },
        { id: "sway",      label: "Sway",         glyph: "󱂬", bin: "sway",      category: "compositor" },
        { id: "cava",      label: "Cava",         glyph: "󰎄", bin: "cava",      category: "audio" },
        { id: "btop",      label: "Btop",         glyph: "󰘚", bin: "btop",      category: "misc" }
    ]

    // Detección vía Deps (un único 'which' compartido al arrancar, ver
    // Services/Deps.qml). gtk/hyprland no se detectan así: siempre usan su
    // propio criterio. Solo decide qué se LISTA en Ajustes; activar/aplicar
    // sigue funcionando igual sin más comprobación. Reactivo: Deps.has() lee
    // Deps._found, así que los bindings se re-evalúan al acabar la detección.
    function isInstalled(id) {
        if (id === "gtk") return true
        if (id === "hyprland") return Settings.hyprlandAvailable
        const r = registry.find(e => e.id === id)
        return r ? Deps.has(r.bin) : false
    }

    // Marca real, guardada en el archivo — independiente del interruptor
    // maestro (Settings.templatesOn). Pausar el maestro NO toca esto: al
    // reactivarlo vuelve a aplicarse exactamente lo que ya estaba marcado.
    // Sin preferencia guardada, las apps DETECTADAS vienen activadas por
    // defecto (mismo criterio que GTK/Hyprland, que nacen a true); un
    // desmarcado explícito del usuario queda guardado y se respeta.
    function isEnabled(id) {
        if (id === "gtk") return Settings.gtkThemingEnabled
        if (id === "hyprland") return Settings.hyprlandThemingEnabled
        const map = Settings.templatesEnabled || {}
        if (map[id] === undefined) return isInstalled(id)
        return !!map[id]
    }
    function setEnabled(id, val) {
        if (id === "gtk") { Settings.gtkThemingEnabled = val; return }
        if (id === "hyprland") { Settings.hyprlandThemingEnabled = val; return }
        const cur = Object.assign({}, Settings.templatesEnabled || {})
        cur[id] = val
        Settings.templatesEnabled = cur
    }
    // Estado visual: la casilla solo se ve "marcada" si además el maestro
    // está encendido — con el maestro apagado, todas se ven sin marcar aunque
    // su preferencia real siga guardada.
    function isActive(id) {
        return Settings.templatesOn && isEnabled(id)
    }

    // ── Orquestación: reaplica lo activo cuando cambia tema/acento/modo ────
    Timer {
        id: applyTimer
        interval: 400
        onTriggered: root.applyAll()
    }
    function scheduleApplyAll() {
        if (Settings._loaded)
            applyTimer.restart()
    }
    Connections {
        target: Settings
        function onAccentColorChanged() { root.scheduleApplyAll() }
        function onDarkModeChanged() { root.scheduleApplyAll() }
        function onThemeNameChanged() { root.scheduleApplyAll() }
        function onTemplatesEnabledChanged() { root.scheduleApplyAll() }
        function onTemplatesOnChanged() { root.scheduleApplyAll() }
    }
    Component.onCompleted: scheduleApplyAll()

    function applyAll() {
        if (!Settings.templatesOn)
            return
        const ids = []
        for (let i = 0; i < registry.length; i++) {
            const r = registry[i]
            if (r.id !== "gtk" && r.id !== "hyprland" && isEnabled(r.id))
                ids.push(r.id)
        }
        if (ids.length === 0)
            return
        const dirs = []
        for (let i = 0; i < ids.length; i++)
            dirs.push.apply(dirs, outputDirsFor(ids[i]))
        mkdirProc.pendingIds = ids
        mkdirProc.command = ["mkdir", "-p"].concat(dirs)
        if (!mkdirProc.running)
            mkdirProc.running = true
    }
    Process {
        id: mkdirProc
        property var pendingIds: []
        onExited: (code, status) => {
            for (let i = 0; i < pendingIds.length; i++)
                root.applyOne(pendingIds[i])
        }
    }

    function outputDirsFor(id) {
        switch (id) {
        case "ghostty":   return [home + "/.config/ghostty/themes"]
        case "wezterm":   return [home + "/.config/wezterm/colors"]
        case "starship":  return [home + "/.config"]
        case "btop":      return [home + "/.config/btop/themes"]
        case "cava":      return [home + "/.config/cava/themes"]
        case "helix":     return [home + "/.config/helix/themes"]
        case "emacs":     return [home + "/.emacs.d/themes"]
        case "qt":        return [home + "/.config/qt5ct/colors", home + "/.config/qt6ct/colors"]
        case "kde":       return [home + "/.local/share/color-schemes"]
        case "labwc":     return [home + "/.config/labwc", home + "/.local/share/themes/quickshell/openbox-3"]
        case "niri":      return [home + "/.config/niri"]
        case "mango":     return [home + "/.config/mango"]
        case "scroll":    return [home + "/.config/scroll"]
        case "sway":      return [home + "/.config/sway"]
        default:          return []
        }
    }

    function applyOne(id) {
        switch (id) {
        case "ghostty":   applyGhostty(); break
        case "wezterm":   applyWezterm(); break
        case "starship":  applyStarship(); break
        case "btop":      applyBtop(); break
        case "cava":      applyCava(); break
        case "helix":     applyHelix(); break
        case "emacs":     applyEmacs(); break
        case "qt":        applyQt(); break
        case "kde":       applyKde(); break
        case "labwc":     applyLabwc(); break
        case "niri":      applyNiri(); break
        case "mango":     applyMango(); break
        case "scroll":    applyScroll(); break
        case "sway":      applySway(); break
        }
    }

    // ── Ayudas de texto compartidas (sin shell) ─────────────────────────────
    // reload() antes de leer: sin esto, un FileView cuyo archivo todavía no
    // existe se queda con el 'setText' posterior sin efecto (no llega a
    // escribir a disco) — hace falta forzar el (re)enganche con el archivo
    // real antes de poder crearlo. De paso, recoge ediciones externas del
    // usuario hechas entre una aplicación y la siguiente.
    function readText(view) {
        view.reload()
        return view.text() || ""
    }
    function render(text) { return Settings.renderTemplate(text, Settings.materialTokens()) }

    // Escribe solo si el contenido cambió de verdad (mismo patrón que
    // Services/Terminal.qml): evita reescribir los archivos y mandar señales
    // de recarga (pkill) a las apps en cada arranque del shell cuando nada
    // ha cambiado. Devuelve si hubo escritura.
    function _writeIfChanged(view, txt) {
        if (readText(view) === txt)
            return false
        view.setText(txt)
        return true
    }

    // Si 'hasFn(contenido)' ya es verdad, no toca el archivo. Si el archivo
    // está vacío/no existe, lo crea con 'createContent'. Si no, añade
    // 'appendLine' al final (con una línea en blanco delante). Devuelve si
    // hubo escritura.
    function ensureLine(view, hasFn, appendLine, createContent) {
        const content = readText(view)
        if (content.length === 0) {
            view.setText(createContent)
            return true
        }
        if (hasFn(content))
            return false
        const trimmed = content.replace(/\s+$/, "")
        view.setText(trimmed + "\n\n" + appendLine + "\n")
        return true
    }

    // ═══════════════════════════════ ghostty ════════════════════════════════
    FileView { id: ghosttyTpl; path: root.tplDir + "/ghostty/ghostty"; blockLoading: true; printErrors: false }
    FileView { id: ghosttyOut; path: root.home + "/.config/ghostty/themes/quickshell"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: ghosttyCfgA; path: root.home + "/.config/ghostty/config"; blockLoading: true; printErrors: false; atomicWrites: true }
    FileView { id: ghosttyCfgB; path: root.home + "/.config/ghostty/config.ghostty"; blockLoading: true; printErrors: false }
    Process { id: ghosttyReload; command: ["pkill", "-SIGUSR2", "ghostty"] }
    function applyGhostty() {
        let changed = _writeIfChanged(ghosttyOut, render(ghosttyTpl.text()))
        const target = readText(ghosttyCfgB).length > 0 ? ghosttyCfgB : ghosttyCfgA
        const content = readText(target)
        const line = "theme = quickshell"
        if (content.length === 0) {
            ghosttyCfgA.setText(line + "\n")
            changed = true
        } else if (/^theme\s*=\s*quickshell\s*$/m.test(content)) {
            // ya correcto
        } else if (/^theme\s*=/m.test(content)) {
            target.setText(content.replace(/^theme\s*=.*/m, line))
            changed = true
        } else {
            target.setText(content.replace(/\s+$/, "") + "\n" + line + "\n")
            changed = true
        }
        if (changed)
            ghosttyReload.running = true
    }

    // ═══════════════════════════════ wezterm ════════════════════════════════
    FileView { id: weztermTpl; path: root.tplDir + "/wezterm/wezterm.toml"; blockLoading: true; printErrors: false }
    FileView { id: weztermOut; path: root.home + "/.config/wezterm/colors/Quickshell.toml"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: weztermCfg; path: root.home + "/.config/wezterm/wezterm.lua"; blockLoading: true; printErrors: false; atomicWrites: true }
    // Si no hay wezterm.lua, se fabrica uno mínimo (en vez de no hacer nada:
    // es Lua del usuario y podría preferirse no tocarlo, pero así activar la
    // plantilla no exige ningún paso a mano). Si ya existe, se edita sin
    // tocar el resto.
    function applyWezterm() {
        _writeIfChanged(weztermOut, render(weztermTpl.text()))
        const content = readText(weztermCfg)
        const line = 'config.color_scheme = "Quickshell"'
        if (content.length === 0) {
            weztermCfg.setText('local wezterm = require("wezterm")\nlocal config = wezterm.config_builder()\n\n'
                + line + '\n\nreturn config\n')
            return
        }
        if (/config\.color_scheme\s*=\s*['"]Quickshell['"]/.test(content))
            return
        if (/^\s*config\.color_scheme\s*=/m.test(content))
            weztermCfg.setText(content.replace(/^\s*config\.color_scheme\s*=.*/m, line))
        else if (/^\s*return\s+config/m.test(content))
            weztermCfg.setText(content.replace(/^\s*return\s+config/m, line + "\nreturn config"))
        else
            weztermCfg.setText(content.replace(/\s+$/, "") + "\n" + line + "\n")
    }

    // ═══════════════════════════════ starship ═══════════════════════════════
    FileView { id: starshipTpl; path: root.tplDir + "/starship/starship.toml"; blockLoading: true; printErrors: false }
    FileView { id: starshipCfg; path: root.home + "/.config/starship.toml"; blockLoading: true; printErrors: false; atomicWrites: true }
    // Usamos siempre ~/.config/starship.toml, sin rastrear STARSHIP_CONFIG
    // en /proc/*/environ por si estuviera en otra ruta.
    function applyStarship() {
        const markerBegin = "# >>> QUICKSHELL STARSHIP PALETTE >>>"
        const markerEnd = "# <<< QUICKSHELL STARSHIP PALETTE <<<"
        const palette = render(starshipTpl.text())
        const original = readText(starshipCfg)
        let content = original

        if (content.indexOf(markerBegin) !== -1) {
            const re = new RegExp(markerBegin.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
                + "[\\s\\S]*?" + markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g")
            content = content.replace(re, "").replace(/\n{3,}/g, "\n\n")
        }
        if (/^palette\s*=/m.test(content))
            content = content.replace(/^palette\s*=.*/m, 'palette = "quickshell"')
        else
            content = 'palette = "quickshell"\n' + content

        const next = content.replace(/\s+$/, "") + "\n\n" + markerBegin + "\n" + palette.trim() + "\n" + markerEnd + "\n"
        if (next !== original)
            starshipCfg.setText(next)
    }

    // ═══════════════════════════════ btop ═══════════════════════════════════
    FileView { id: btopTpl; path: root.tplDir + "/btop/btop.theme"; blockLoading: true; printErrors: false }
    FileView { id: btopOut; path: root.home + "/.config/btop/themes/quickshell.theme"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: btopCfg; path: root.home + "/.config/btop/btop.conf"; blockLoading: true; printErrors: false; atomicWrites: true }
    Process { id: btopReload; command: ["pkill", "-SIGUSR2", "-x", "btop"] }
    // Si btop.conf no existe todavía (no se ha arrancado btop ni una vez),
    // no lo fabricamos.
    function applyBtop() {
        let changed = _writeIfChanged(btopOut, render(btopTpl.text()))
        const content = readText(btopCfg)
        if (content.length === 0)
            return
        if (/^color_theme\s*=\s*"quickshell"/m.test(content)) {
            // ya correcto
        } else if (/^color_theme\s*=/m.test(content)) {
            btopCfg.setText(content.replace(/^color_theme\s*=.*/m, 'color_theme = "quickshell"'))
            changed = true
        } else {
            btopCfg.setText(content.replace(/\s+$/, "") + "\ncolor_theme = \"quickshell\"\n")
            changed = true
        }
        if (changed)
            btopReload.running = true
    }

    // ═══════════════════════════════ cava ═══════════════════════════════════
    FileView { id: cavaTpl; path: root.tplDir + "/cava/cava.ini"; blockLoading: true; printErrors: false }
    FileView { id: cavaOut; path: root.home + "/.config/cava/themes/quickshell"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: cavaCfg; path: root.home + "/.config/cava/config"; blockLoading: true; printErrors: false; atomicWrites: true }
    Process { id: cavaReload; command: ["pkill", "-USR1", "-x", "cava"] }
    function applyCava() {
        let changed = _writeIfChanged(cavaOut, render(cavaTpl.text()))
        const content = readText(cavaCfg)
        if (content.length === 0)
            return
        const sectionRe = /(\[color\][^[]*)/
        const m = content.match(sectionRe)
        if (m && /^theme\s*=\s*"quickshell"/m.test(m[1])) {
            // ya correcto
        } else if (m && /^theme\s*=/m.test(m[1])) {
            cavaCfg.setText(content.replace(sectionRe, m[1].replace(/^theme\s*=.*/m, 'theme = "quickshell"')))
            changed = true
        } else if (m) {
            cavaCfg.setText(content.replace(sectionRe, m[1].replace(/\s*$/, "") + '\ntheme = "quickshell"\n'))
            changed = true
        } else {
            cavaCfg.setText(content.replace(/\s+$/, "") + '\n\n[color]\ntheme = "quickshell"\n')
            changed = true
        }
        if (changed)
            cavaReload.running = true
    }

    // ═══════════════════════════════ helix ══════════════════════════════════
    FileView { id: helixTpl; path: root.tplDir + "/helix/helix.toml"; blockLoading: true; printErrors: false }
    FileView { id: helixOut; path: root.home + "/.config/helix/themes/quickshell.toml"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: helixCfg; path: root.home + "/.config/helix/config.toml"; blockLoading: true; printErrors: false; atomicWrites: true }
    // Además de dejar el archivo de tema, edita config.toml para que quede
    // activo sin pasos extra (en vez de dejar que el usuario lo active a mano).
    function applyHelix() {
        _writeIfChanged(helixOut, render(helixTpl.text()))
        const content = readText(helixCfg)
        const line = 'theme = "quickshell"'
        if (content.length === 0) {
            helixCfg.setText(line + "\n")
        } else if (/^theme\s*=\s*"quickshell"\s*$/m.test(content)) {
            // ya correcto
        } else if (/^theme\s*=/m.test(content)) {
            helixCfg.setText(content.replace(/^theme\s*=.*/m, line))
        } else {
            helixCfg.setText(line + "\n" + content)
        }
    }

    // ═══════════════════════════════ emacs ══════════════════════════════════
    FileView { id: emacsTpl; path: root.tplDir + "/emacs/quickshell-theme.el"; blockLoading: true; printErrors: false }
    FileView { id: emacsOut; path: root.home + "/.emacs.d/themes/quickshell-theme.el"; blockLoading: true; atomicWrites: true; printErrors: false }
    Process { id: emacsReload; command: ["emacsclient", "-e", "(load-theme 'quickshell t)"] }
    // Siempre ~/.emacs.d/themes, sin probar ~/.config/doom o ~/.config/emacs
    // antes.
    function applyEmacs() {
        if (_writeIfChanged(emacsOut, render(emacsTpl.text())))
            emacsReload.running = true
    }

    // ═══════════════════════════════ qt ═════════════════════════════════════
    FileView { id: qtTpl; path: root.tplDir + "/qt/qtct.conf"; blockLoading: true; printErrors: false }
    FileView { id: qt5Out; path: root.home + "/.config/qt5ct/colors/quickshell.conf"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: qt6Out; path: root.home + "/.config/qt6ct/colors/quickshell.conf"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: qt5Cfg; path: root.home + "/.config/qt5ct/qt5ct.conf"; blockLoading: true; printErrors: false; atomicWrites: true }
    FileView { id: qt6Cfg; path: root.home + "/.config/qt6ct/qt6ct.conf"; blockLoading: true; printErrors: false; atomicWrites: true }
    // Crea o actualiza la sección [Appearance] de qt5ct.conf/qt6ct.conf,
    // sin tocar el resto del archivo.
    function ensureQtAppearance(view, colorSchemePath) {
        const content = readText(view)
        let next
        if (content.length === 0) {
            next = "[Appearance]\ncolor_scheme_path=" + colorSchemePath + "\ncustom_palette=true\n"
        } else {
            const sectionRe = /(\[Appearance\][^[]*)/
            const m = content.match(sectionRe)
            if (!m) {
                next = content.replace(/\s+$/, "") + "\n\n[Appearance]\ncolor_scheme_path=" + colorSchemePath + "\ncustom_palette=true\n"
            } else {
                let section = m[1]
                section = /^color_scheme_path\s*=/m.test(section)
                    ? section.replace(/^color_scheme_path\s*=.*/m, "color_scheme_path=" + colorSchemePath)
                    : section.replace(/\s*$/, "") + "\ncolor_scheme_path=" + colorSchemePath + "\n"
                section = /^custom_palette\s*=/m.test(section)
                    ? section.replace(/^custom_palette\s*=.*/m, "custom_palette=true")
                    : section.replace(/\s*$/, "") + "\ncustom_palette=true\n"
                next = content.replace(sectionRe, section)
            }
        }
        if (next !== content)
            view.setText(next)
    }
    // Además de escribir los archivos de esquema, activa "quickshell" en
    // qt5ct/qt6ct directamente (en vez de que el usuario lo elija a mano).
    function applyQt() {
        const rendered = render(qtTpl.text())
        _writeIfChanged(qt5Out, rendered)
        _writeIfChanged(qt6Out, rendered)
        ensureQtAppearance(qt5Cfg, root.home + "/.config/qt5ct/colors/quickshell.conf")
        ensureQtAppearance(qt6Cfg, root.home + "/.config/qt6ct/colors/quickshell.conf")
    }

    // ═══════════════════════════════ kde / KColorScheme ═════════════════════
    FileView { id: kdeTpl; path: root.tplDir + "/kde/kcolorscheme.colors"; blockLoading: true; printErrors: false }
    FileView { id: kdeOut; path: root.home + "/.local/share/color-schemes/Quickshell.colors"; blockLoading: true; atomicWrites: true; printErrors: false }
    Process { id: kdeNotify; command: ["dbus-send", "/KGlobalSettings", "org.kde.KGlobalSettings.notifyChange", "int32:0", "int32:0"] }
    function applyKde() {
        if (_writeIfChanged(kdeOut, render(kdeTpl.text())))
            kdeNotify.running = true
    }

    // ═══════════════════════════════ labwc ══════════════════════════════════
    FileView { id: labwcTpl; path: root.tplDir + "/labwc/labwc.conf"; blockLoading: true; printErrors: false }
    FileView { id: labwcStaging; path: root.home + "/.config/labwc/quickshell.conf"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: labwcThemerc; path: root.home + "/.local/share/themes/quickshell/openbox-3/themerc"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: labwcRc; path: root.home + "/.config/labwc/rc.xml"; blockLoading: true; printErrors: false; atomicWrites: true }
    function applyLabwc() {
        const rendered = render(labwcTpl.text())
        _writeIfChanged(labwcStaging, rendered)
        _writeIfChanged(labwcThemerc, rendered)

        const content = readText(labwcRc)
        if (content.length === 0) {
            labwcRc.setText('<?xml version="1.0" encoding="UTF-8"?>\n<labwc_config>\n  <theme>\n    <name>quickshell</name>\n  </theme>\n</labwc_config>\n')
            return
        }
        if (/<theme>[\s\S]*?<name>quickshell<\/name>[\s\S]*?<\/theme>/.test(content))
            return
        if (/<theme>[\s\S]*?<\/theme>/.test(content)) {
            if (/<theme>[\s\S]*?<name>[\s\S]*?<\/name>[\s\S]*?<\/theme>/.test(content))
                labwcRc.setText(content.replace(/(<theme>[\s\S]*?)<name>[\s\S]*?<\/name>([\s\S]*?<\/theme>)/, "$1<name>quickshell</name>$2"))
            else
                labwcRc.setText(content.replace(/<theme>/, "<theme>\n    <name>quickshell</name>"))
        } else if (/<labwc_config[\s>]/.test(content)) {
            labwcRc.setText(content.replace(/<labwc_config([\s>][^>]*)?>/, "$&\n  <theme>\n    <name>quickshell</name>\n  </theme>"))
        }
    }

    // ═══════════════════════════════ niri ═══════════════════════════════════
    FileView { id: niriTpl; path: root.tplDir + "/niri/niri.kdl"; blockLoading: true; printErrors: false }
    FileView { id: niriOut; path: root.home + "/.config/niri/quickshell.kdl"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: niriCfg; path: root.home + "/.config/niri/config.kdl"; blockLoading: true; printErrors: false; atomicWrites: true }
    function applyNiri() {
        _writeIfChanged(niriOut, render(niriTpl.text()))
        ensureLine(niriCfg,
            c => /include\s+"?quickshell\.kdl"?/.test(c),
            'include "quickshell.kdl"',
            'include "quickshell.kdl"\n')
    }

    // ═══════════════════════════════ mango ══════════════════════════════════
    FileView { id: mangoTpl; path: root.tplDir + "/mango/mango.conf"; blockLoading: true; printErrors: false }
    FileView { id: mangoOut; path: root.home + "/.config/mango/quickshell.conf"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: mangoCfg; path: root.home + "/.config/mango/config.conf"; blockLoading: true; printErrors: false; atomicWrites: true }
    Process { id: mangoReload; command: ["mmsg", "dispatch", "reload_config"] }
    function applyMango() {
        let changed = _writeIfChanged(mangoOut, render(mangoTpl.text()))
        if (ensureLine(mangoCfg,
                c => /source\s*=.*quickshell\.conf/.test(c),
                "source=~/.config/mango/quickshell.conf",
                "source=~/.config/mango/quickshell.conf\n"))
            changed = true
        if (changed)
            mangoReload.running = true
    }

    // ═══════════════════════════════ scroll ═════════════════════════════════
    FileView { id: scrollTpl; path: root.tplDir + "/scroll/scroll"; blockLoading: true; printErrors: false }
    FileView { id: scrollOut; path: root.home + "/.config/scroll/quickshell"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: scrollCfg; path: root.home + "/.config/scroll/config"; blockLoading: true; printErrors: false; atomicWrites: true }
    function applyScroll() {
        _writeIfChanged(scrollOut, render(scrollTpl.text()))
        ensureLine(scrollCfg,
            c => /^include\s+.*quickshell/m.test(c),
            "include ~/.config/scroll/quickshell",
            "include ~/.config/scroll/quickshell\n")
    }

    // ═══════════════════════════════ sway ═══════════════════════════════════
    FileView { id: swayTpl; path: root.tplDir + "/sway/sway"; blockLoading: true; printErrors: false }
    FileView { id: swayOut; path: root.home + "/.config/sway/quickshell"; blockLoading: true; atomicWrites: true; printErrors: false }
    FileView { id: swayCfg; path: root.home + "/.config/sway/config"; blockLoading: true; printErrors: false; atomicWrites: true }
    function applySway() {
        _writeIfChanged(swayOut, render(swayTpl.text()))
        ensureLine(swayCfg,
            c => /^include\s+.*quickshell/m.test(c),
            "include ~/.config/sway/quickshell",
            "include ~/.config/sway/quickshell\n")
    }
}
