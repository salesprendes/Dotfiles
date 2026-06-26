-- ── Reglas de ventana ───────────────────────────────────────
-- https://wiki.hypr.land/Configuring/Window-Rules/

-- Ignorar peticiones de maximizar de todas las apps.
local suppressMaximizeRule = hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

-- Arreglar problemas de arrastre con XWayland.
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})
