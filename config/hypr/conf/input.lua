-- ── Entrada (teclado, ratón, touchpad, gestos) ──────────────
-- https://wiki.hypr.land/Configuring/Variables/#input

hl.config({
    input = {
        kb_layout  = "es",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 a 1.0, 0 = sin modificar.

        touchpad = {
            natural_scroll = false,
        },
    },
})

-- Gesto de 3 dedos para cambiar de workspace.
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

-- Ejemplo de configuración por dispositivo.
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})
