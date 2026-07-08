-- Monitores
-- https://wiki.hypr.land/Configuring/Basics/Monitors/

hl.monitor({
    output   = "",
    -- highres = resolución nativa (2560x1440). No uso highrr porque este panel
    -- solo da 75 Hz a 1024x768 y a 1440p baja a ~60 Hz; no compensa perder resolución.
    mode     = "highres",
    position = "auto",
    scale    = "auto",
})
