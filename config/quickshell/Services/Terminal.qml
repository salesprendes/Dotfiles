pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Terminal: detecta los emuladores instalados y, para el seleccionado
// (Settings.terminalApp), genera su config. La paleta viene del tema de
// Quickshell; el resto (fuente, tamaño, opacidad, padding, cursor…) de
// Ajustes → Terminal. Sabe kitty, alacritty y foot. Se regenera al cambiar
// parámetros o tema y recarga la terminal en caliente.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") ?? ""

    // Terminales detectados (instalados) como [{text, value}].
    property var available: []
    // Para cuáles sabemos generar configuración.
    readonly property var configurable: ["kitty", "alacritty", "foot"]

    function installed(app) { return root.available.some(t => t.value === app) }
    function canConfigure(app) { return root.configurable.indexOf(app) !== -1 }

    // La detección de binarios viene de Deps (un solo proceso compartido al
    // arrancar). Si Deps aún no terminó, available queda [] y apply() no hace
    // nada; al dispararse Deps.loaded se recomputa y se aplica una vez.
    Component.onCompleted: refresh()
    function refresh() {
        root.available = root.configurable
            .filter(t => Deps.has(t))
            .map(t => ({ text: t, value: t }))
        root.apply()
    }

    Connections {
        target: Deps
        function onLoaded() { root.refresh() }
    }

    // Helpers de color (desde el tema) y parámetros
    function _pal()      { return Settings.currentPalette }
    function hx(c)       { return Settings.colorHex(c) }
    function lit(c, f)   { return Settings.colorHex(Qt.lighter(c, f)) }
    function accent()    { return Settings.resolvedAccent }
    function font()      { return Settings.terminalFont !== "" ? Settings.terminalFont : Settings.fontFamily }

    // Generadores por terminal
    function kittyTheme() {
        const p = _pal(), a = accent()
        return [
            "# Generado por Quickshell (Ajustes → Tema). No editar a mano.",
            "foreground            " + hx(p.fg),
            "background            " + hx(p.bg),
            "selection_foreground  " + hx(p.bg),
            "selection_background  " + hx(p.fgDim),
            "cursor                " + hx(p.fg),
            "cursor_text_color     " + hx(p.bg),
            "url_color             " + hx(p.cyan),
            "active_border_color   " + hx(a),
            "inactive_border_color " + hx(p.surfaceHi),
            "bell_border_color     " + hx(p.red),
            "tab_bar_background        " + hx(p.bg),
            "active_tab_foreground     " + hx(p.bg),
            "active_tab_background     " + hx(a),
            "active_tab_font_style     bold",
            "inactive_tab_foreground   " + hx(p.fgMuted),
            "inactive_tab_background   " + hx(p.surface),
            "color0  " + hx(p.surface) + "\ncolor8  " + hx(p.overlay),
            "color1  " + hx(p.red) + "\ncolor9  " + lit(p.red, 1.2),
            "color2  " + hx(p.green) + "\ncolor10 " + lit(p.green, 1.2),
            "color3  " + hx(p.yellow) + "\ncolor11 " + lit(p.yellow, 1.15),
            "color4  " + hx(a) + "\ncolor12 " + lit(a, 1.2),
            "color5  " + hx(p.magenta) + "\ncolor13 " + lit(p.magenta, 1.15),
            "color6  " + hx(p.cyan) + "\ncolor14 " + lit(p.cyan, 1.15),
            "color7  " + hx(p.fg) + "\ncolor15 " + lit(p.fg, 1.1),
            ""
        ].join("\n")
    }
    function kittyConf() {
        const blink = Settings.terminalCursorBlink ? "0.5" : "0"
        const lig = Settings.terminalLigatures ? "never" : "always"
        const op = Settings.terminalOpacity
        return [
            "# Generado por Quickshell (Ajustes → Terminal). No editar a mano.",
            "font_family        " + root.font(),
            "bold_font          auto",
            "italic_font        auto",
            "bold_italic_font   auto",
            "font_size          " + Settings.terminalFontSize,
            "disable_ligatures  " + lig,
            "modify_font        cell_height " + Settings.terminalLineHeight + "px",
            "",
            "window_padding_width        " + Settings.terminalPadding,
            "hide_window_decorations     yes",
            "confirm_os_window_close     0",
            "placement_strategy          center",
            "background_opacity          " + op.toFixed(2),
            "dynamic_background_opacity  yes",
            "cursor_shape                " + Settings.terminalCursorShape,
            "cursor_blink_interval       " + blink,
            "scrollback_lines            10000",
            "enable_audio_bell           no",
            "tab_bar_edge                top",
            "tab_bar_style               " + Settings.terminalTabStyle,
            "tab_powerline_style         slanted",
            "shell_integration           enabled",
            "",
            "include theme.conf",
            ""
        ].join("\n")
    }

    function alacrittyToml() {
        const p = _pal(), a = accent()
        const cur = ({ beam: "Beam", block: "Block", underline: "Underline" })[Settings.terminalCursorShape] || "Beam"
        const blink = Settings.terminalCursorBlink ? "On" : "Off"
        return [
            "# Generado por Quickshell (Ajustes → Terminal). No editar a mano.",
            "[font]",
            'normal = { family = "' + root.font() + '" }',
            "size = " + Settings.terminalFontSize,
            "",
            "[window]",
            "opacity = " + Settings.terminalOpacity.toFixed(2),
            "padding = { x = " + Settings.terminalPadding + ", y = " + Settings.terminalPadding + " }",
            'decorations = "None"',
            "",
            "[cursor]",
            'style = { shape = "' + cur + '", blinking = "' + blink + '" }',
            "",
            "[colors.primary]",
            'background = "' + hx(p.bg) + '"',
            'foreground = "' + hx(p.fg) + '"',
            "",
            "[colors.normal]",
            'black = "'   + hx(p.surface) + '"',
            'red = "'     + hx(p.red) + '"',
            'green = "'   + hx(p.green) + '"',
            'yellow = "'  + hx(p.yellow) + '"',
            'blue = "'    + hx(a) + '"',
            'magenta = "' + hx(p.magenta) + '"',
            'cyan = "'    + hx(p.cyan) + '"',
            'white = "'   + hx(p.fg) + '"',
            "",
            "[colors.bright]",
            'black = "'   + hx(p.overlay) + '"',
            'red = "'     + lit(p.red, 1.2) + '"',
            'green = "'   + lit(p.green, 1.2) + '"',
            'yellow = "'  + lit(p.yellow, 1.15) + '"',
            'blue = "'    + lit(a, 1.2) + '"',
            'magenta = "' + lit(p.magenta, 1.15) + '"',
            'cyan = "'    + lit(p.cyan, 1.15) + '"',
            'white = "'   + lit(p.fg, 1.1) + '"',
            ""
        ].join("\n")
    }

    function footIni() {
        const p = _pal(), a = accent()
        const c  = (x) => hx(x).replace("#", "")
        const cl = (x, f) => lit(x, f).replace("#", "")
        const cur = ({ beam: "beam", block: "block", underline: "underline" })[Settings.terminalCursorShape] || "beam"
        return [
            "# Generado por Quickshell (Ajustes → Terminal). No editar a mano.",
            "font=" + root.font() + ":size=" + Settings.terminalFontSize,
            "pad=" + Settings.terminalPadding + "x" + Settings.terminalPadding,
            "",
            "[cursor]",
            "style=" + cur,
            "blink=" + (Settings.terminalCursorBlink ? "yes" : "no"),
            "",
            "[colors]",
            "alpha=" + Settings.terminalOpacity.toFixed(2),
            "background=" + c(p.bg),
            "foreground=" + c(p.fg),
            "regular0=" + c(p.surface), "regular1=" + c(p.red), "regular2=" + c(p.green), "regular3=" + c(p.yellow),
            "regular4=" + c(a),         "regular5=" + c(p.magenta), "regular6=" + c(p.cyan), "regular7=" + c(p.fg),
            "bright0=" + c(p.overlay),  "bright1=" + cl(p.red, 1.2), "bright2=" + cl(p.green, 1.2), "bright3=" + cl(p.yellow, 1.15),
            "bright4=" + cl(a, 1.2),    "bright5=" + cl(p.magenta, 1.15), "bright6=" + cl(p.cyan, 1.15), "bright7=" + cl(p.fg, 1.1),
            ""
        ].join("\n")
    }

    // Aplicar
    // Escribe solo si el contenido cambió de verdad: así evitamos reescribir
    // las configs y lanzar pkill -USR1 (recarga con parpadeo de las kitty
    // abiertas) en cada arranque cuando nada ha cambiado.
    function _writeIfChanged(view, txt) {
        if ((view.text() || "") === txt)
            return false
        view.setText(txt)
        return true
    }
    function apply() {
        const app = Settings.terminalApp
        if (!installed(app) || !canConfigure(app))
            return
        if (app === "kitty") {
            const themeChanged = _writeIfChanged(kittyThemeFile, kittyTheme())
            const confChanged  = _writeIfChanged(kittyConfFile, kittyConf())
            if (themeChanged || confChanged)
                reloadKitty.running = true
        } else if (app === "alacritty") {
            _writeIfChanged(alacrittyFile, alacrittyToml())   // alacritty recarga sola
        } else if (app === "foot") {
            if (_writeIfChanged(footFile, footIni()))
                reloadFoot.running = true
        }
    }

    // Regenera (debounce) al cambiar parámetros o el tema/acento.
    readonly property var _watch: [
        Settings.terminalApp, Settings.terminalFont, Settings.terminalFontSize, Settings.terminalOpacity,
        Settings.terminalPadding, Settings.terminalCursorShape, Settings.terminalCursorBlink,
        Settings.terminalLineHeight, Settings.terminalTabStyle, Settings.terminalLigatures,
        Settings.themeName, Settings.accentColor, Settings.darkMode
    ]
    on_WatchChanged: applyDebounce.restart()
    Timer { id: applyDebounce; interval: 250; onTriggered: root.apply() }

    // Archivos y recargas
    //  blockLoading: necesario para que text() tenga el contenido actual en el
    //  primer apply() y la comparación "solo si cambió" funcione (son archivos
    //  pequeños leídos una vez al crear el singleton).
    FileView { id: kittyConfFile;  path: root.home + "/.config/kitty/kitty.conf";        blockLoading: true; printErrors: false; atomicWrites: true }
    FileView { id: kittyThemeFile; path: root.home + "/.config/kitty/theme.conf";        blockLoading: true; printErrors: false; atomicWrites: true }
    FileView { id: alacrittyFile;  path: root.home + "/.config/alacritty/alacritty.toml"; blockLoading: true; printErrors: false; atomicWrites: true }
    FileView { id: footFile;       path: root.home + "/.config/foot/foot.ini";            blockLoading: true; printErrors: false; atomicWrites: true }
    Process  { id: reloadKitty;    command: ["sh", "-c", "pkill -USR1 -x kitty >/dev/null 2>&1 || true"] }
    Process  { id: reloadFoot;     command: ["sh", "-c", "pkill -USR1 -x foot  >/dev/null 2>&1 || true"] }
}
