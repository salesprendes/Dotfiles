-- Aspecto general (look & feel)
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
            -- Sombra pequeña: se redibuja al mover ventanas, así que un range y
            -- render_power bajos ahorran GPU (y batería) sin cambio visual apreciable.
            range        = 6,
            render_power = 2,
            color        = theme.shadow,
        },

        -- Blur del contenido: suficiente para paneles translúcidos sin convertir
        -- los popups en masas borrosas.
        blur = {
            enabled     = true,
            -- Radio pequeño: el blur es lo que más cuesta en la APU (780M); bajarlo
            -- ahorra sin cambio visible y el esmerilado se mantiene en todas las capas.
            size        = 2,
            -- Un solo pase: con dos el blur casi dobla su coste en la APU y no se nota.
            passes      = 1,
            new_optimizations = true,
            vibrancy    = 0.08,
            brightness  = 0.60,
            contrast    = 0.75,
            popups      = true,
            -- Umbral alto: el blur ignora los márgenes semitransparentes de la sombra
            -- de los menús (Brave/Chromium), así sale sombra suave y no un recuadro gris.
            popups_ignorealpha = 0.6,
            xray        = true,   -- el blur solo muestrea el fondo, no las
                                  -- ventanas detrás: más barato en la 780M
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

        -- Primer frame del compositor con el color del tema (#101315) en vez de
        -- negro puro, para que el arranque de sesión no dé un salto de color.
        background_color = "rgb(101315)",

        -- Arrastrar/redimensionar con animación, se siente más fluido.
        animate_manual_resizes      = true,
        animate_mouse_windowdragging = true,

        -- VRR (FreeSync) solo en pantalla completa: sincroniza el refresco del
        -- monitor con Hyprland y quita micro-tirones en juegos/vídeo. Modo 2 y no 1
        -- para evitar el parpadeo que da la iGPU al aplicar VRR en el escritorio.
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
-- compositor, menos GPU y consumo en la APU). 1 = activado.
hl.config({
    render = {
        direct_scanout = 1,

        -- Planificación de render nueva: triple búfer solo cuando hace falta, así
        -- un frame que llega justo no pierde el vsync entero (mejora FPS en equipos modestos).
        new_render_scheduling = true,
    },
})
