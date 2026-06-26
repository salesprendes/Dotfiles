-- ── Variables de entorno ────────────────────────────────────
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Qt (dolphin y demás apps Qt/KDE): Wayland nativo en vez de XWayland.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")            -- wayland, con respaldo xcb
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")  -- sin doble barra de título
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")          -- escalado HiDPI correcto

-- Electron (VSCode, Discord…): forzar backend Wayland nítido.
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- AMD Radeon 780M: driver VAAPI explícito (decodificación de vídeo HW).
hl.env("LIBVA_DRIVER_NAME", "radeonsi")
