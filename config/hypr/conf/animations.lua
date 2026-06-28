-- ── Animaciones ─────────────────────────────────────────────
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/

-- Curvas bezier
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

-- Muelle (spring) suave
hl.curve("easy", { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

-- Curvas de ventana: apertura con deceleración suave y cierre sin corte lineal.
-- El popin parte cerca del tamaño final para que se note fluido, no elástico.
hl.curve("smoothOpen",  { type = "bezier", points = { {0.16, 1},    {0.30, 1}    } })
hl.curve("smoothClose", { type = "bezier", points = { {0.40, 0},    {0.20, 1}    } })
hl.curve("smoothFade",  { type = "bezier", points = { {0.25, 0.46}, {0.45, 0.94} } })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
-- Borde con gradiente acento que ROTA en bucle (eye-candy). Redibuja el
-- borde continuamente → enciéndelo solo con corriente; déjalo off en batería.
hl.animation({ leaf = "borderangle",   enabled = false, speed = 30,   bezier = "linear", style = "loop" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 5.2,  spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 5.8,  bezier = "smoothOpen",   style = "popin 86%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 4.2,  bezier = "smoothClose",  style = "popin 88%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 3.8,  bezier = "smoothFade" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 3.2,  bezier = "smoothClose" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 4.0,  bezier = "smoothFade" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })
