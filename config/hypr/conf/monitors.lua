-- ── Monitores ───────────────────────────────────────────────
-- https://wiki.hypr.land/Configuring/Basics/Monitors/

hl.monitor({
    output   = "",
    -- "highres": máxima resolución nativa (2560x1440). NO se usa "highrr"
    -- porque este panel solo alcanza 75 Hz a 1024x768; a 1440p va a ~60 Hz,
    -- así que "highrr" sacrificaría la resolución por Hz que no merecen la pena.
    mode     = "highres",
    position = "auto",
    scale    = "auto",
})
