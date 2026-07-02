-- ── Aspecto general (Look & Feel) ───────────────────────────
-- https://wiki.hypr.land/Configuring/Basics/Variables/

local theme = require("conf.theme")

hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 10,

        border_size = 2,

        col = {
            active_border   = theme.active_border,
            inactive_border = theme.inactive_border,
        },

        resize_on_border = true,
        allow_tearing    = false,

        layout = "dwindle",

        -- Imán entre ventanas flotantes al acercarlas.
        snap = {
            enabled       = true,
            window_gap    = 10,
            monitor_gap   = 10,
        },
    },

    decoration = {
        rounding       = 8,
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 0.98,

        -- Oscurece levemente la ventana sin foco (complementa la opacidad).
        dim_inactive  = true,
        dim_strength  = 0.08,

        shadow = {
            enabled      = true,
            -- range 6 (antes 10) y render_power 2 (antes 3): la sombra se
            -- redibuja al mover ventanas; reducirla baja ese coste de GPU
            -- (gratis en batería) sin un cambio visual apreciable.
            range        = 6,
            render_power = 2,
            color        = theme.shadow,
        },

        -- Blur contenido, al estilo Omarchy: suficiente para paneles translúcidos
        -- sin convertir los popups en masas borrosas.
        blur = {
            enabled     = true,
            size        = 3,
            -- 1 pase (antes 2): el blur es lo que más cuesta en la APU;
            -- bajar a 1 casi lo divide a la mitad sin diferencia visible.
            passes      = 1,
            new_optimizations = true,
            vibrancy    = 0.08,
            brightness  = 0.60,
            contrast    = 0.75,
            popups      = true,
            -- Sube el umbral: el blur ignora los márgenes semitransparentes
            -- de la sombra de los menús (Brave/Chromium) → sombra suave en vez
            -- del recuadro gris borroso. Antes 0.2 (demasiado bajo).
            popups_ignorealpha = 0.6,
            xray        = true,   -- el blur solo muestrea el fondo, no las
                                  -- ventanas detrás → más barato en la 780M
        },
    },

    animations = {
        enabled = true,
    },

    group = {
        col = {
            border_active = theme.active_border,
            border_inactive = theme.inactive_border,
        },

        groupbar = {
            font_size = 12,
            font_family = "monospace",
            font_weight_active = "ultraheavy",
            font_weight_inactive = "normal",
            indicator_height = 0,
            indicator_gap = 5,
            height = 22,
            gaps_in = 5,
            gaps_out = 0,
            text_color = "rgb(cacccc)",
            text_color_inactive = "rgba(cacccc90)",
            col = {
                active = "rgba(79818640)",
                inactive = "rgba(10131520)",
            },
            gradients = true,
            gradient_rounding = 8,
            gradient_round_only_edges = false,
        },
    },
})

-- Layout dwindle
hl.config({
    dwindle = {
        preserve_split = true,
    },
})

-- Layout master
hl.config({
    master = {
        new_status = "master",
    },
})

-- Layout scrolling
hl.config({
    scrolling = {
        fullscreen_on_one_column = true,
    },
})

-- Misc
hl.config({
    misc = {
        force_default_wallpaper = 0,     -- sin mascota anime
        disable_hyprland_logo   = true,

        -- Arrastrar/redimensionar con animación → sensación más fluida.
        animate_manual_resizes      = true,
        animate_mouse_windowdragging = true,

        -- VRR (FreeSync) solo en pantalla completa: sincroniza el refresco
        -- del monitor con lo que dibuja Hyprland → sin micro-tirones en
        -- juegos/vídeo. Modo 2 (y no 1) para evitar el parpadeo que la iGPU
        -- puede dar al aplicar VRR en el escritorio/navegador.
        vrr = 2,
    },
})

-- Cursor: se auto-oculta al escribir y tras unos segundos quieto.
hl.config({
    cursor = {
        inactive_timeout   = 3,      -- segundos quieto → ocultar
        hide_on_key_press  = true,   -- ocultar al teclear
    },
})

-- Render: scanout directo en pantalla completa (vídeo/juegos saltan el
-- compositor → menos GPU/consumo en la APU). 1 = activado.
hl.config({
    render = {
        direct_scanout = 1,

        -- Planificación de render nueva: triple búfer solo cuando hace
        -- falta. La wiki lo describe como "mejora los FPS en equipos
        -- modestos": si un frame llega justo, no se pierde el vsync entero.
        new_render_scheduling = true,
    },
})
